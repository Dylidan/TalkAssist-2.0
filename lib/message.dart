import "dart:convert";

/// Identifies the author of a chat message.
enum MsgRole { user, assistant }

/// Tracks which service produced an assistant reply.
/// Used to filter safe-mode echoes out of LLM context windows.
enum AssistantOrigin { localLlm, safeMode, queuedReplay, deviceAction }

/// A single message in the conversation.
///
/// Immutable value object with role, text, timestamp, and optional origin.
/// Serializable to/from JSON for disk persistence.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.assistantOrigin,
  });

  final MsgRole role;
  final String text;
  final DateTime timestamp;

  /// Which service produced this assistant reply, if known.
  final AssistantOrigin? assistantOrigin;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "role": role.name,
      "text": text,
      "timestamp": timestamp.toIso8601String(),
      if (assistantOrigin != null) "assistantOrigin": assistantOrigin!.name,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: _parseRole(json["role"]?.toString()),
      text: json["text"]?.toString() ?? "",
      timestamp:
          DateTime.tryParse(json["timestamp"]?.toString() ?? "") ??
          DateTime.now(),
      assistantOrigin: _parseAssistantOrigin(
        json["assistantOrigin"]?.toString(),
      ),
    );
  }

  @override
  String toString() {
    return "[${timestamp.toIso8601String()}] ${role.name}: $text";
  }
}

/// Global in-memory conversation store.
///
/// Holds the full conversation history and provides filtered snapshots
/// (e.g., excluding safe-mode replies) for building LLM prompts.
class Message {
  static final Message instance = Message._internal();

  Message._internal();

  /// The most recent user input, used for prompt deduplication.
  String latestUserInput = "";

  /// Complete conversation history, including safe-mode responses.
  final List<ChatMessage> conversationHistory = <ChatMessage>[];

  void addUserMessage(String text) {
    latestUserInput = text;
    conversationHistory.add(
      ChatMessage(role: MsgRole.user, text: text, timestamp: DateTime.now()),
    );
  }

  void addAssistMsg(
    String text, {
    AssistantOrigin origin = AssistantOrigin.localLlm,
  }) {
    conversationHistory.add(
      ChatMessage(
        role: MsgRole.assistant,
        text: text,
        timestamp: DateTime.now(),
        assistantOrigin: origin,
      ),
    );
  }

  void replaceHistory(List<ChatMessage> history) {
    conversationHistory
      ..clear()
      ..addAll(history);

    latestUserInput = "";
    for (var index = history.length - 1; index >= 0; index -= 1) {
      final item = history[index];
      if (item.role == MsgRole.user) {
        latestUserInput = item.text;
        break;
      }
    }
  }

  String exportHistoryJson() {
    final list = conversationHistory
        .map((message) => message.toJson())
        .toList();
    return jsonEncode(list);
  }

  List<ChatMessage> historySnapshot() {
    return List<ChatMessage>.from(conversationHistory);
  }

  /// Returns history with safe-mode assistant messages stripped out.
  ///
  /// The local LLM should never see fallback echo text in its context,
  /// as that would confuse the model's understanding of the conversation.
  List<ChatMessage> historyForLlm({bool includeSafeModeAssistant = false}) {
    return conversationHistory
        .where((message) {
          if (message.role != MsgRole.assistant) {
            return true;
          }
          if (includeSafeModeAssistant) {
            return true;
          }
          if (message.assistantOrigin == AssistantOrigin.safeMode) {
            return false;
          }

          final normalized = message.text.trimLeft().toLowerCase();
          return !normalized.startsWith("safe mode");
        })
        .map(
          (message) => ChatMessage(
            role: message.role,
            text: message.text,
            timestamp: message.timestamp,
            assistantOrigin: message.assistantOrigin,
          ),
        )
        .toList(growable: false);
  }
}

MsgRole _parseRole(String? raw) {
  for (final value in MsgRole.values) {
    if (value.name == raw) {
      return value;
    }
  }
  return MsgRole.user;
}

AssistantOrigin? _parseAssistantOrigin(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  for (final value in AssistantOrigin.values) {
    if (value.name == raw) {
      return value;
    }
  }
  return null;
}