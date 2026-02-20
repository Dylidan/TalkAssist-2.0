import 'package:flutter/material.dart';
import 'dart:ui';
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

<<<<<<< Updated upstream
  void _sendMessage() {
=======
  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  //Pipeline
  void _sendMessage() async {
>>>>>>> Stashed changes
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    Message.instance.addUserMessage(text);

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _messages.add(
        _ChatMessage(text: "Place Holder: ${Message.instance.latestUserInput}", isUser: false),
      );
    });

    debugPrint("Latest input: ${Message.instance.latestUserInput}");
    debugPrint("History: ${Message.instance.conversationHistory}");

    _controller.clear();
    _scrollToBottom();
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
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              elevation: 0,
              backgroundColor: Colors.white.withOpacity(0.08),
              title: const Text(
                'TalkAssist 2.0',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
              centerTitle: false,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background gradient (Apple-style soft glow)
          const _AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              children: [
                // Messages
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _MessageBubble(message: msg);
                    },
                  ),
                ),

                // Input bar (frosted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Message',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SendButton(
                              onPressed: _sendMessage,
                              enabled: _controller.text.trim().isNotEmpty,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    // iMessage-ish colors (soft + modern)
    final bubbleGradient = isUser
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF5B8CFF).withOpacity(0.95),
              const Color(0xFF7A5CFF).withOpacity(0.95),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.14),
              Colors.white.withOpacity(0.08),
            ],
          );

    final textColor = isUser ? Colors.white : Colors.white.withOpacity(0.92);

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          gradient: bubbleGradient,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 18),
          ),
          border: isUser ? null : Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(
            message.text,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool enabled;

  const _SendButton({required this.onPressed, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF66A6FF),
                Color(0xFF7F5CFF),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.45,
              child: const Center(
                child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedGradientBackground extends StatefulWidget {
  const _AnimatedGradientBackground();

  @override
  State<_AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<_AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;

        // Soft shifting gradient stops
        final a = Alignment.lerp(Alignment.topLeft, Alignment.topRight, t)!;
        final b = Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, t)!;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: a,
              end: b,
              colors: const [
                Color(0xFF0B1220), // deep navy
                Color(0xFF101A33),
                Color(0xFF14102A), // subtle purple
              ],
            ),
          ),
          child: Container(
            // Glow blobs overlay
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.lerp(const Alignment(-0.6, -0.6), const Alignment(0.6, 0.2), t)!,
                radius: 1.2,
                colors: [
                  const Color(0xFF7F5CFF).withOpacity(0.22),
                  const Color(0xFF66A6FF).withOpacity(0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.35, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}