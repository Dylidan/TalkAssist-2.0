import 'package:flutter/material.dart';

/// UI-facing data for a single chat bubble in the conversation view.
class ChatMessageView {
  const ChatMessageView({
    required this.id,
    required this.text,
    required this.isUser,
    this.origin,
  });

  /// Stable identifier used to track or diff this rendered message.
  final String id;

  /// Message text shown inside the chat bubble.
  final String text;

  /// Whether this message was sent by the user instead of the assistant.
  final bool isUser;
  final String? origin;
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

class LlmStatusView {
  const LlmStatusView({required this.label});

  final String label;

  Color get dotColor {
    switch (label) {
      case 'online':    return const Color(0xFF34D399); // teal
      case 'on-device': return const Color(0xFF4ADE80); // green
      case 'safe mode': return const Color(0xFFFBBF24); // amber
      case 'device':    return const Color(0xFF60A5FA); // blue
      case 'queued':    return const Color(0xFFA78BFA); // purple
      default:          return const Color(0xFF6B7280); // grey
    }
  }
}