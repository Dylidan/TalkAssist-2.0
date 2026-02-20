import 'package:flutter/material.dart';
import 'package:talk_assist/message.dart';


void main() => runApp(const MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  //Pipeline
  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    //locat/replace with corrct loading
    final msgId = DateTime.now().microsecondsSinceEpoch.toString();
    Message.instance.addUserMessage(text);

    setState(() {
      _messages.add(
        _ChatMessage(
          id: "u_$msgId", 
          text: text, 
          isUser: true
        ));
      _messages.add(
        _ChatMessage(
          //text: "Place Holder: ${Message.instance.latestUserInput}",
          id: "a_$msgId",
          text: "...",
          isUser: false
        ),);
      //Message.instance.addAssistMsg("Place Holder: ${Message.instance.latestUserInput}");
    });
    
    await Future.delayed(const Duration(milliseconds: 600));
    //Connect LLM (gen relpy)
    final reply = await generateReply(text);

    final idx = _messages.indexWhere((m) => m.id == "a_$msgId");
    if (idx != -1) {
      setState(() {
        _messages[idx] = _ChatMessage(
          id: "a_$msgId", 
          text: reply, 
          isUser: false);
      });
    }
    Message.instance.addAssistMsg(reply);

    debugPrint("Latest input: ${Message.instance.latestUserInput}");
    debugPrint("History: ${Message.instance.conversationHistory}");
    debugPrint("JSON: ${Message.instance.exportHistoryJson()}");

    _controller.clear();
    _scrollToBottom();
  }

  Future<String> generateReply(String userText) async {
  //Can replace with LLM call
    return userText;
  }

  void _scrollToBottom() {
    // Wait for the list to rebuild, then scroll.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('TalkAssist 2.0'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _MessageBubble(message: msg);
                },
              ),
            ),

            // Input bar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.id, required this.isUser});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final align = message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = message.isUser ? Colors.blue : Colors.grey.shade300;
    final fg = message.isUser ? Colors.white : Colors.black87;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: fg, fontSize: 16),
        ),
      ),
    );
  }
}
