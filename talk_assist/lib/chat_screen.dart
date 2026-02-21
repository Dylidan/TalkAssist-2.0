import 'package:flutter/material.dart';
import 'package:talk_assist/message.dart';
import 'widgets/chat_ui.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  const ChatMessage({required this.id, required this.text, required this.isUser});
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final msgId = DateTime.now().microsecondsSinceEpoch.toString();
    Message.instance.addUserMessage(text);

    setState(() {
      _messages.add(ChatMessage(id: "u_$msgId", text: text, isUser: true));
      _messages.add(ChatMessage(id: "a_$msgId", text: "...", isUser: false));
    });

    await Future.delayed(const Duration(milliseconds: 600));
    final reply = await generateReply(text);

    final idx = _messages.indexWhere((m) => m.id == "a_$msgId");
    if (idx != -1) {
      setState(() {
        _messages[idx] = ChatMessage(id: "a_$msgId", text: reply, isUser: false);
      });
    }

    Message.instance.addAssistMsg(reply);

    _controller.clear();
    _scrollToBottom();
  }

  Future<String> generateReply(String userText) async {
    return userText; // replace with LLM later
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatUI(
      title: 'TalkAssist 2.0',
      messages: _messages,
      textController: _controller,
      scrollController: _scrollController,
      onSend: _sendMessage,
    );
  }
}