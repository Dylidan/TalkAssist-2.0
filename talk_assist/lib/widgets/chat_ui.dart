import 'dart:ui';
import 'package:flutter/material.dart';

import '../chat_screen.dart';
import 'animated_gradient_background.dart';
import 'message_bubble.dart';
import 'send_button.dart';

class ChatUI extends StatelessWidget {
  final String title;
  final List<ChatMessage> messages;
  final TextEditingController textController;
  final ScrollController scrollController;
  final VoidCallback onSend;

  const ChatUI({
    super.key,
    required this.title,
    required this.messages,
    required this.textController,
    required this.scrollController,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
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
              title: Text(
                title,
                style: const TextStyle(
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
          const AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: messages[index]);
                    },
                  ),
                ),

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
                                controller: textController,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => onSend(),
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
                            SendButton(
                              onPressed: onSend,
                              enabled: textController.text.trim().isNotEmpty,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}