import "package:talk_assist/tts/tts_config.dart";

class TtsTextNormalizer {
  const TtsTextNormalizer._();

  static String normalizeForVoice(String text, TtsVoiceConfig voice) {
    if (!voice.locale.toLowerCase().startsWith("zh")) {
      return text;
    }

    return _normalizeChineseNumbers(text);
  }

  // Regular expressions to identify different number formats in Chinese text
  // 99%, 99.9%, 0.1％, etc.
  static final RegExp _percentPattern = RegExp(
    r"(?<![A-Za-z0-9_])-?\d[\d,]*(?:\.\d+)?[%％]",
  );

  // Matches 2 to 4 digit numbers followed by "年" (year)
  // For example: "2024年", "99年"
  static final RegExp _yearPattern = RegExp(r"\d{2,4}(?=年)");

  // Matches decimal numbers
  // For example: "3.14", "-0.5"
  static final RegExp _decimalPattern = RegExp(
    r"(?<![A-Za-z0-9_])-?\d[\d,]*\.\d+",
  );

  // Matches integer numbers
  // For example: "1000", "-500"
  static final RegExp _integerPattern = RegExp(r"(?<![A-Za-z0-9_])-?\d[\d,]*");

  // 0-9 in Chinese
  static const List<String> _digits = [
    "零",
    "一",
    "二",
    "三",
    "四",
    "五",
    "六",
    "七",
    "八",
    "九",
  ];

  static String _normalizeChineseNumbers(String text) {
    var normalized = text.replaceAllMapped(_percentPattern, (match) {
      final number = match.group(0)!.replaceAll(RegExp(r"[%％]"), "");
      return "百分之${_numberToChinese(number)}";
    });

    normalized = normalized.replaceAllMapped(_yearPattern, (match) {
      return _digitsToChinese(match.group(0)!);
    });

    normalized = normalized.replaceAllMapped(_decimalPattern, (match) {
      return _numberToChinese(match.group(0)!);
    });

    return normalized.replaceAllMapped(_integerPattern, (match) {
      final value = match.group(0)!;
      if (_shouldReadDigitsIndividually(normalized, match)) {
        return _signedDigitsToChinese(value);
      }

      return _numberToChinese(value);
    });
  }

  // Converts a numeric string to its Chinese text representation
  static String _numberToChinese(String rawValue) {
    // Remove commas
    var value = rawValue.replaceAll(",", "");
    // Check for negative numbers
    final isNegative = value.startsWith("-");
    // If negative, remove negative sign for processing
    if (isNegative) {
      value = value.substring(1);
    }

    // Split integer and decimal parts, 1.1 -> ["1", "1"], 100 -> ["100"]
    final parts = value.split(".");
    final integer = parts.first;
    final decimal = parts.length > 1 ? parts[1] : null;

    final prefix = isNegative ? "负" : "";
    final integerText = _integerToChinese(integer);

    // If there's no decimal part, return the integer text with prefix
    // Example: "1000" -> "一千", "-500" -> "负五百"
    if (decimal == null) {
      return "$prefix$integerText";
    }

    // Example: "3.14" -> "三点一四", "-0.5" -> "负零点五"
    // 点 is "."
    return "$prefix$integerText点${_digitsToChinese(decimal)}";
  }

  // Converts a string of digits to Chinese characters, ignoring non-digit characters
  // Example: "12345" -> "一二三四五", "1,000" -> "一零零零"
  static String _digitsToChinese(String value) {
    return value
        .replaceAll(",", "")
        .split("")
        .where((character) => RegExp(r"\d").hasMatch(character))
        .map((character) => _digits[int.parse(character)])
        .join();
  }

  // Handles signed numbers by converting the absolute value and adding "负" prefix if negative
  // Example: "-123" -> "负一二三", "100" -> "一零零"
  static String _signedDigitsToChinese(String rawValue) {
    final value = rawValue.replaceAll(",", "");
    if (value.startsWith("-")) {
      return "负${_digitsToChinese(value.substring(1))}";
    }

    return _digitsToChinese(value);
  }

  // Determines if digits should be read individually based on preceding context
  // So that 验证码是10086 -> 验证码是一零零八六 instead of 验证码是一万零八十六
  static bool _shouldReadDigitsIndividually(String text, Match match) {
    final contextStart = match.start - 12 < 0 ? 0 : match.start - 12;
    final prefix = text.substring(contextStart, match.start);
    return RegExp(
      r"(验证码|校验码|动态码|密码|编号|序号|订单号|单号|账号|帐号|电话|手机号|手机|号码|ID|id|code|Code)\s*(是|为|:|：)?\s*$",
    ).hasMatch(prefix);
  }

  // Converts an integer string to Chinese text with proper grouping and units
  // Example: "12345" -> "一万两千三百四十五", "10005" -> "一万零五", "123456789" -> "一亿两千三百四十五万六千七百八十九"
  static String _integerToChinese(String rawValue) {
    final value = rawValue.replaceFirst(RegExp(r"^0+(?=\d)"), "");
    // If the value is empty after removing leading zeros, or if it's all zeros, return "零"
    if (value.isEmpty || RegExp(r"^0+$").hasMatch(value)) {
      return _digits[0];
    }

    // Split the number into groups of 4 digits from the right
    // For example: "123456789" -> ["6789", "2345", "1"]
    final groups = <String>[];
    for (var end = value.length; end > 0; end -= 4) {
      final start = end - 4 < 0 ? 0 : end - 4;
      groups.insert(0, value.substring(start, end));
    }

    // Units for each group of 4 digits
    // ["", "万", "亿", "兆"]
    const groupUnits = ["", "万", "亿", "兆"];
    final buffer = StringBuffer();
    var needsZero = false;

    // Process each group of digits and append the appropriate unit
    // For example: "123456789" -> "一亿两千三百四十五万六千七百八十九"
    for (var i = 0; i < groups.length; i += 1) {
      final group = groups[i];
      final groupValue = int.tryParse(group) ?? 0;
      final groupUnitIndex = groups.length - i - 1;

      // If the group value is zero, we may need to insert "零" if there are non-zero groups before or after it
      // For example: "10005" -> "一万零五" (we need to insert "零" for the "000" group)
      if (groupValue == 0) {
        if (buffer.isNotEmpty) {
          needsZero = true;
        }
        continue;
      }

      if (buffer.isNotEmpty && (needsZero || groupValue < 1000)) {
        buffer.write(_digits[0]);
      }

      // Convert the current group of digits to Chinese text and append the group unit
      // For example: "2345" -> "两千三百四十五", and if it's the second group from the right, append "万" to get "两千三百四十五万"
      buffer.write(
        _sectionToChinese(groupValue, omitLeadingOneForTen: buffer.isEmpty),
      );
      if (groupUnitIndex < groupUnits.length) {
        buffer.write(groupUnits[groupUnitIndex]);
      }

      needsZero = false;
    }

    return buffer.toString();
  }

  // Converts a section of up to 4 digits to Chinese text, handling special cases for "十" and "两"
  // For example: "10" -> "十" (not "一十"), "20" -> "二十", "200" -> "两百", "1000" -> "一千"
  static String _sectionToChinese(
    int number, {
    required bool omitLeadingOneForTen,
  }) {
    // Units for each digit in the section
    // ["", "tenth", "hundredth", "thousandth"]
    const units = ["", "十", "百", "千"];
    final chars = number.toString().split("");
    final buffer = StringBuffer();
    var pendingZero = false;

    // Process each digit in the section and append the appropriate unit
    for (var i = 0; i < chars.length; i += 1) {
      final digit = int.parse(chars[i]);
      final unitIndex = chars.length - i - 1;

      if (digit == 0) {
        if (buffer.isNotEmpty && unitIndex > 0) {
          pendingZero = true;
        }
        continue;
      }

      if (pendingZero) {
        buffer.write(_digits[0]);
        pendingZero = false;
      }

      // Omit the leading "一" for numbers between 10 and 19 ("10" -> "十", not "一十")
      final shouldOmitLeadingOne =
          omitLeadingOneForTen &&
          digit == 1 &&
          unitIndex == 1 &&
          buffer.isEmpty &&
          chars.length == 2;

      if (!shouldOmitLeadingOne) {
        buffer.write(_digitForUnit(digit, unitIndex));
      }
      buffer.write(units[unitIndex]);
    }

    return buffer.toString();
  }

  // Returns "两" instead of "二" for the digit 2 when it appears in certain unit positions ("两百" instead of "二百")
  static String _digitForUnit(int digit, int unitIndex) {
    if (digit == 2 && unitIndex >= 2) {
      return "两";
    }

    return _digits[digit];
  }
}
