import 'dart:convert';
enum MsgRole { user, assistant}

//Who/What/When
class ChatMessage {
  final MsgRole role;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
  });

  // convert to JSON
  Map<String, dynamic> toJson() {
  return {
    "role": role.name,
    "text": text,
    "timestamp": timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return "[${timestamp.toIso8601String()}] ${role.name}: $text";
  }
}

class Message {
  // global singleton instance
  static final Message instance = Message._internal();

  Message._internal();

  // store latest user input
  String latestUserInput = "";

  // store full conversation history
  final List<ChatMessage> conversationHistory = [];

  void addUserMessage(String text) {
    latestUserInput = text;
    conversationHistory.add(
      ChatMessage(
        role:MsgRole.user,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
  }

  void addAssistMsg(String text)
  {
    conversationHistory.add(
      ChatMessage(
        role: MsgRole.assistant,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
  }

  String exportHistoryJson() 
  {
    final list = conversationHistory.map((m) => m.toJson()).toList();
    return jsonEncode(list);
  }
}
