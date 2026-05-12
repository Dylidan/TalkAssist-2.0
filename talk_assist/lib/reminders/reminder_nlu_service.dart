import "dart:convert";

import "package:flutter/foundation.dart";
import "package:talk_assist/llm/llm_orchestrator.dart";
import "package:talk_assist/reminders/reminder_command.dart";

class ReminderNluService {
  ReminderNluService({required LlmOrchestrator orchestrator})
    : _orchestrator = orchestrator;

  //backup LLM task if local parse fail
  final LlmOrchestrator _orchestrator;

  //First check if its reminder, then local parse then LLM
  Future<ReminderCommandParseResult> tryParse(String rawInput) async {

    final text = rawInput.trim();
    if (text.isEmpty) {
      return const ReminderCommandParseResult.notReminder();
    }

    if (!_looksLikeReminderIntent(text)) {
      return const ReminderCommandParseResult.notReminder();
    }

    //local parsing
    final relativeParsed = _tryParseRelativeReminder(text);
    if (relativeParsed != null) {
      if (kDebugMode) {
        final startAt = relativeParsed.startAt;
        debugPrint(
          "REMINDER_NLU: Relative-time parser matched title=${relativeParsed.title} datetime=${startAt?.toIso8601String()}",
        );
      }
      return ReminderCommandParseResult.success(relativeParsed);
    }

    //if local failed then try LLM parsing with JSON
    final response = await _orchestrator.runLocalStructuredTask(
      taskPrompt: _buildPrompt(text),
    );
    if (response == null) {
      return const ReminderCommandParseResult.notReminder();
    }

    final parsed = _decodeJsonObject(response);
    if (parsed == null) {
      return const ReminderCommandParseResult.notReminder();
    }

    //if its still not reminder
    final isReminder = parsed["isReminder"] == true;
    if (!isReminder) {
      return const ReminderCommandParseResult.notReminder();
    }

    //Reduce false positives with confidence
    final confidence = _asDouble(parsed["confidence"]);
    if (confidence != null && confidence < 0.60) {
      return const ReminderCommandParseResult.notReminder();
    }

    //Title and time
    final title = (parsed["title"]?.toString() ?? "").trim();
    if (title.isEmpty) {
      return const ReminderCommandParseResult.error(
        "I can help set a reminder, but I could not understand the task.",
      );
    }
    final dateText = (parsed["datetime"]?.toString() ?? "").trim();
    if (dateText.isEmpty) {
      return const ReminderCommandParseResult.error(
        "I can set that reminder. What time should I use?",
      );
    }

    //Parse datetime string
    final dateTime = _parseReminderDateTime(dateText);
    if (dateTime == null) {
      return const ReminderCommandParseResult.error(
        "I understood the reminder task, but not the time. Please say a specific date and time.",
      );
    }

    //Build final reminder request
    return ReminderCommandParseResult.success(
      ReminderRequest(
        title: title,
        startAt: dateTime,
        allDay: false,
      ),
    );
  }

  //detector/trigger
  bool _looksLikeReminderIntent(String text) {
    final lower = text.toLowerCase();
    return lower.contains("remind") ||
        lower.contains("reminder") ||
        lower.contains("dont let me forget") ||
        lower.contains("don't let me forget") ||
        lower.contains("set a reminder") ||
        lower.contains("set reminder");
  }

  // Prompt,which return JSON only.
  String _buildPrompt(String userInput) {
    final now = DateTime.now();
    final nowLocal = _formatDateTime(now);
    return 
    """
        You extract reminder requests.
        Return ONLY a single-line JSON object.
        Schema:
        {"isReminder":true|false,"title":"string or null","datetime":"yyyy-MM-ddTHH:mm:ss or null"}
        Rules:
        - English only.
        - Current local datetime is $nowLocal.
        - Resolve relative dates like today, tomorrow, tonight, next Monday against that current local datetime.
        - If this is not a reminder request, return {"isReminder":false,"title":null,"datetime":null}
        - Title must contain only the task.
        - Datetime must be local time and must not include Z, UTC, timezone, markdown, explanation, or extra fields.
        - If time is missing or unclear, set datetime to null.

        User: $userInput
        JSON:
    """;
  }

  //JSON decoding
  Map<String, dynamic>? _decodeJsonObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    final start = raw.indexOf("{");
    final end = raw.lastIndexOf("}");
    if (start != -1 && end != -1 && end > start) {
      //Recover for extra text.
      final candidate = raw.substring(start, end + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    //Recover for malformed responses
    final partial = <String, dynamic>{};
    final isReminderMatch = RegExp(
      r'"isReminder"\s*:\s*(true|false)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (isReminderMatch != null) {
      partial["isReminder"] =
          (isReminderMatch.group(1) ?? "false").toLowerCase() == "true";
    }

    final titleMatch = RegExp(
      r'"title"\s*:\s*"([^"\r\n}]*)',
    ).firstMatch(raw);
    if (titleMatch != null) {
      partial["title"] = titleMatch.group(1);
    } else if (RegExp(r'"title"\s*:\s*null').hasMatch(raw)) {
      partial["title"] = null;
    }

    final datetimeMatch = RegExp(
      r'"datetime"\s*:\s*"([^"\r\n}]*)',
    ).firstMatch(raw);
    if (datetimeMatch != null) {
      partial["datetime"] = datetimeMatch.group(1);
    } else if (RegExp(r'"datetime"\s*:\s*null').hasMatch(raw)) {
      partial["datetime"] = null;
    }

    return partial.isEmpty ? null : partial;
  }

  ReminderRequest? _tryParseRelativeReminder(String rawInput) {
    final normalized = _normalizeText(rawInput);

    //resolve date words.
    final baseDate = _extractRelativeDate(normalized);
    if (baseDate == null) {
      return null;
    }

    //resolve AM/PM time.
    final time = _extractTimeOfDay(normalized);
    if (time == null) {
      return null;
    }

    //extract pure task title.
    final title = _extractReminderTitle(rawInput);
    if (title == null || title.isEmpty) {
      return null;
    }

    final scheduledAt = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      time.hour,
      time.minute,
    );

    return ReminderRequest(title: title, startAt: scheduledAt, allDay: false);
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Convert relative date tokens to an absolute local date
  DateTime? _extractRelativeDate(String normalized) {
    final now = DateTime.now();
    if (normalized.contains('day after tomorrow')) {
      return now.add(const Duration(days: 2));
    }
    if (RegExp(r'\btomorrow\b').hasMatch(normalized)) {
      return now.add(const Duration(days: 1));
    }
    if (RegExp(r'\btoday\b').hasMatch(normalized) ||
        RegExp(r'\btonight\b').hasMatch(normalized)) {
      return now;
    }
    return null;
  }

  //parse & convert time
  _ParsedTimeOfDay? _extractTimeOfDay(String normalized) {
    final match = RegExp(
      r'\b(?:at|for|by)?\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final hourText = match.group(1);
    final minuteText = match.group(2);
    final meridiemText = match.group(3);
    final hour = int.tryParse(hourText ?? '');
    final minute = int.tryParse(minuteText ?? '0');
    if (hour == null || minute == null || hour < 1 || hour > 12) {
      return null;
    }

    final meridiem = (meridiemText ?? '').toLowerCase().replaceAll('.', '');
    var normalizedHour = hour % 12;
    if (meridiem == 'pm') {
      normalizedHour += 12;
    }

    return _ParsedTimeOfDay(hour: normalizedHour, minute: minute);
  }

  // Remove command/date/time words to keep only task text
  String? _extractReminderTitle(String rawInput) {
    var title = rawInput.trim();

    title = title.replaceFirst(
      RegExp(
        r'^\s*(?:please\s+)?(?:remind me|set (?:me )?a reminder|set reminder)(?:\s+to)?\s*',
        caseSensitive: false,
      ),
      '',
    );

    title = title.replaceAll(
      RegExp(r'\bday after tomorrow\b', caseSensitive: false),
      ' ',
    );
    title = title.replaceAll(
      RegExp(r'\b(?:today|tomorrow|tonight)\b', caseSensitive: false),
      ' ',
    );
    title = title.replaceAll(
      RegExp(
        r'\b(?:at|for|by)?\s*\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    title = title.replaceAll(
      RegExp(r'^\s*(?:to)\s+', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceAll(RegExp(r'^[,:;\-\s]+|[,:;\-\s.]+$'), '');

    return title.isEmpty ? null : title;
  }

  DateTime? _parseReminderDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.endsWith("Z")
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return DateTime.tryParse(normalized);
  }

  // Accept both numeric and string forms for confidence
  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  // Format local time for prompt context.
  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '${value.year}-$month-$day''T$hour:$minute:$second';
  }
}

class _ParsedTimeOfDay {
  const _ParsedTimeOfDay({required this.hour, required this.minute});
  final int hour;
  final int minute;
}
