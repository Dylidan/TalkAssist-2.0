class Message {
  // global singleton instance
  static final Message instance = Message._internal();

  Message._internal();

  // store latest user input
  String latestUserInput = "";

  // store full conversation history
  final List<String> conversationHistory = [];

  void addUserMessage(String message) {
    latestUserInput = message;
    conversationHistory.add(message);
  }
}
