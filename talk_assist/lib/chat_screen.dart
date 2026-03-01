import "dart:async";

import "package:flutter/material.dart";
import "package:talk_assist/chat/chat_controller.dart";
import "widgets/chat_ui.dart";

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
  });
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = <ChatMessage>[];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatController _chatController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));

    _chatController = ChatController();
    _chatController.addListener(_onChatControllerChanged);
    unawaited(_chatController.initialize());
  }

  void _onChatControllerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _messages
        ..clear()
        ..addAll(
          _chatController.messages.map(
            (message) => ChatMessage(
              id: message.id,
              text: message.text,
              isUser: message.isUser,
            ),
          ),
        );
    });

    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    _controller.clear();
    await _chatController.sendUserMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _chatController.removeListener(_onChatControllerChanged);
    _chatController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatUI(
      title: "TalkAssist 2.0",
      messages: _messages,
      textController: _controller,
      scrollController: _scrollController,
      onSend: _sendMessage,
    );
  }
}
