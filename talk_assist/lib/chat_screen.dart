import "dart:async";

import "package:flutter/material.dart";
import "package:talk_assist/chat/chat_controller.dart";
import "package:talk_assist/chat/chat_view_models.dart";
import 'package:talk_assist/stt/sherpa_stt_service.dart';
import 'package:talk_assist/stt/wake_word_service.dart';
import "widgets/chat_ui.dart";

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessageView> _messages = <ChatMessageView>[];
  final List<ConversationTabView> _conversations = <ConversationTabView>[];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatController _chatController;
  bool _isVoiceModeActive = false;
  bool _isWakeWordReady = false;
  bool _isListening = false;
  bool _isTranscribing = false;
  String _activeServiceLabel = 'initializing';
  int _recordSessionId = 0;
  late final SherpaSttService _sttService;
  late final WakeWordService _wakeWordService;
  StreamSubscription<String>? _wakeWordSubscription;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));

    _chatController = ChatController();
    _chatController.addListener(_onChatControllerChanged);
    unawaited(_chatController.initialize());
    _sttService = SherpaSttService();
    _wakeWordService = WakeWordService();
    _wakeWordSubscription = _wakeWordService.detections.listen(
      _handleWakeWordDetected,
    );
    unawaited(_initializeAudioServices());
  }

  Future<void> _initializeAudioServices() async {
    try {
      await _sttService.initialize();
      await _wakeWordService.initialize();
      if (!mounted) {
        return;
      }
      _isWakeWordReady = true;
      await _ensureWakeWordListening();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio initialization failed: $e')),
      );
    }
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
            (message) => ChatMessageView(
              id: message.id,
              text: message.text,
              isUser: message.isUser,
            ),
          ),
        );
      _conversations
        ..clear()
        ..addAll(
          _chatController.conversations.map(
            (conversation) => ConversationTabView(
              id: conversation.id,
              title: conversation.title,
              preview: conversation.preview,
              isActive: conversation.isActive,
            ),
          ),
        );
      _activeServiceLabel = _chatController.activeServiceLabel;
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

  Future<void> _createConversation() async {
    _controller.clear();
    await _chatController.createConversation();
    _scrollToBottom();
  }

  Future<void> _selectConversation(String conversationId) async {
    await _chatController.selectConversation(conversationId);
    _scrollToBottom();
  }

  Future<void> _deleteConversation(String conversationId) async {
    final isDeletingActiveConversation = _conversations.any(
      (conversation) => conversation.id == conversationId && conversation.isActive,
    );
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete conversation?"),
          content: const Text(
            "This removes the conversation from saved history on this device.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    if (isDeletingActiveConversation) {
      _controller.clear();
    }
    await _chatController.deleteConversation(conversationId);
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

  Future<void> _submitSpeechTranscript(
    String text, {
    bool speakReply = true,
    bool awaitReplySpeechCompletion = false,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      return;
    }

    _controller.clear();
    await _chatController.sendUserMessage(
      cleaned,
      speakReply: speakReply,
      awaitReplySpeechCompletion: awaitReplySpeechCompletion,
    );
    _scrollToBottom();
  }

  Future<void> _toggleMic() async {
    if (_isVoiceModeActive) {
      await _stopVoiceMode();
      return;
    }

    if (_isTranscribing) {
      return;
    }

    try {
      await _startVoiceMode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Record failed: $e')),
      );
    }
  }

  Future<void> _startVoiceMode() async {
    await _sttService.initialize();
    await _wakeWordService.stopListening();
    await _chatController.stopSpeaking();

    if (!mounted) {
      return;
    }

    final sessionId = ++_recordSessionId;
    setState(() {
      _isVoiceModeActive = true;
      _isListening = true;
      _isTranscribing = false;
    });

    unawaited(_runContinuousSpeechMode(sessionId));
  }

  Future<void> _handleWakeWordDetected(String keyword) async {
    if (!mounted || !_isWakeWordReady) {
      return;
    }
    if (_isVoiceModeActive || _isListening || _isTranscribing) {
      return;
    }

    debugPrint("WAKE WORD: handoff to voice mode for $keyword");
    try {
      await _startVoiceMode();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wake word failed: $e')),
      );
      await _ensureWakeWordListening();
    }
  }

  Future<void> _stopVoiceMode() async {
    _recordSessionId += 1;
    setState(() {
      _isVoiceModeActive = false;
      _isListening = false;
      _isTranscribing = false;
    });

    try {
      await _sttService.cancel();
      await _ensureWakeWordListening();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isVoiceModeActive = false;
      });
    }
  }

  Future<void> _runContinuousSpeechMode(int sessionId) async {
    while (mounted &&
        _isVoiceModeActive &&
        sessionId == _recordSessionId) {
      try {
        if (!mounted || !_isVoiceModeActive || sessionId != _recordSessionId) {
          return;
        }

        setState(() {
          _isListening = true;
          _isTranscribing = false;
        });

        final text = await _sttService.recordUntilSilenceAndTranscribe();

        if (!mounted || !_isVoiceModeActive || sessionId != _recordSessionId) {
          return;
        }

        setState(() {
          _isListening = false;
          _isTranscribing = true;
        });

        if (text != null && text.isNotEmpty) {
          await _submitSpeechTranscript(
            text,
            speakReply: true,
            awaitReplySpeechCompletion: true,
          );
        } else {
          debugPrint("VOICE MODE: No speech detected, re-arming recorder");
        }
      } catch (e) {
        if (!mounted || sessionId != _recordSessionId) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech recognition failed: $e')),
        );
        break;
      }

      if (!mounted || !_isVoiceModeActive || sessionId != _recordSessionId) {
        return;
      }

      setState(() {
        _isListening = false;
        _isTranscribing = false;
      });
    }

    if (mounted && sessionId == _recordSessionId) {
      setState(() {
        _isVoiceModeActive = false;
        _isListening = false;
        _isTranscribing = false;
      });
      await _ensureWakeWordListening();
    }
  }

  Future<void> _ensureWakeWordListening() async {
    if (!_isWakeWordReady || _isVoiceModeActive || _isListening) {
      return;
    }
    if (_wakeWordService.isListening) {
      return;
    }

    try {
      await _wakeWordService.startListening();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wake word unavailable: $e')),
      );
    }
  }

  @override
  void dispose() {
    _recordSessionId += 1;
    _wakeWordSubscription?.cancel();
    _chatController.removeListener(_onChatControllerChanged);
    _chatController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _wakeWordService.dispose();
    _sttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatUI(
      title: "TalkAssist 2.0",
      messages: _messages,
      conversations: _conversations,
      textController: _controller,
      scrollController: _scrollController,
      onSend: _sendMessage,
      onNewConversation: _createConversation,
      onSelectConversation: _selectConversation,
      onDeleteConversation: _deleteConversation,
      onMicTap: _toggleMic,
      isVoiceModeActive: _isVoiceModeActive,
      isListening: _isListening,
      isTranscribing: _isTranscribing,
      llmStatus: LlmStatusView(label: _activeServiceLabel),
    );
  }
}
