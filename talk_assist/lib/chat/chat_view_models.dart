/// UI-facing data for a single chat bubble in the conversation view.
class ChatMessageView {
  const ChatMessageView({
    required this.id,
    required this.text,
    required this.isUser,
  });

  /// Stable identifier used to track or diff this rendered message.
  final String id;

  /// Message text shown inside the chat bubble.
  final String text;

  /// Whether this message was sent by the user instead of the assistant.
  final bool isUser;
}

/// UI-facing data for one conversation tab in the chat history/sidebar.
class ConversationTabView {
  const ConversationTabView({
    required this.id,
    required this.title,
    required this.preview,
    required this.isActive,
  });

  /// Stable identifier for the conversation represented by this tab.
  final String id;

  /// Primary label shown as the tab title.
  final String title;

  /// Short snippet used to preview the conversation content.
  final String preview;

  /// Whether this tab is the conversation currently open on screen.
  final bool isActive;
}
