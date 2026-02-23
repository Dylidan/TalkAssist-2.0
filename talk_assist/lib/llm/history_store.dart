import "dart:convert";
import "dart:io";

import "package:path_provider/path_provider.dart";
import "package:talk_assist/message.dart";

/// Reads and writes chat history to disk as JSON.
/// Stores messages in `history.json` in the app documents directory.
/// All operations are resilient to missing or corrupt files.
class HistoryStore {
  static const String _fileName = "history.json";

  /// Loads persisted history from disk.
  /// Returns an empty list if the file is missing, empty, or contains invalid JSON.
  Future<List<ChatMessage>> loadHistory() async {
    final file = await _historyFile();
    if (!await file.exists()) {
      return <ChatMessage>[];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return <ChatMessage>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <ChatMessage>[];
    }

    final result = <ChatMessage>[];
    for (final entry in decoded) {
      if (entry is! Map) {
        continue;
      }
      try {
        result.add(ChatMessage.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        continue;
      }
    }

    return result;
  }

  /// Serializes all messages to JSON and writes to disk.
  /// Uses flush=true for durability. Creates parent directories if needed.
  Future<void> saveHistory(List<ChatMessage> history) async {
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    final payload = jsonEncode(
      history.map((message) => message.toJson()).toList(growable: false),
    );
    await file.writeAsString(payload, flush: true);
  }

  Future<void> clear() async {
    final file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _historyFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File("${appDir.path}/$_fileName");
  }
}
