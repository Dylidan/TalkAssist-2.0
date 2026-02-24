import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:talk_assist/llm/history_store.dart";
import "package:talk_assist/llm/llm_orchestrator.dart";
import "package:talk_assist/message.dart";
import "package:talk_assist/tts/piper_tts_service.dart";
import "package:talk_assist/tts/tts_service.dart";

/// Lightweight message object for the chat UI layer.
/// Contains: an id for updates, the text content, and direction (user vs assistant).
class ChatUiMessage {
  const ChatUiMessage({
    required this.id,
    required this.text,
    required this.isUser,
  });

  // Unique identifier for this message (used for updates).
  final String id;

  // Message text content.
  final String text;

  // True if from the user, false if from the assistant.
  final bool isUser;
}

/// Bridges the chat UI to the LLM backend.
/// Manages the UI message list, delegates to [LlmOrchestrator] for replies, and handles history persistence with coalescing flushes.
/// Implements [WidgetsBindingObserver] to flush on app lifecycle changes.
/// Also integrates TTS to speak LLM replies aloud.
class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  ChatController({
    HistoryStore? historyStore,
    LlmOrchestrator? orchestrator,
    TtsService? ttsService,
    Duration? historyFlushInterval,
  }) : _historyStore = historyStore ?? HistoryStore(),
       _orchestrator = orchestrator ?? LlmOrchestrator(),
       _ttsService = ttsService ?? PiperTtsService(),
       _historyFlushInterval =
           historyFlushInterval ?? const Duration(seconds: 30);

  final HistoryStore _historyStore;
  final LlmOrchestrator _orchestrator;
  final TtsService _ttsService;
  final Message _messageStore = Message.instance;
  final Duration _historyFlushInterval;

  final List<ChatUiMessage> _messages = <ChatUiMessage>[];

  Future<void>? _initializeFuture;
  Future<void>? _historyFlushFuture;
  Timer? _historyFlushTimer;
  bool _historyDirty = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _isObserverRegistered = false;
  int _idCounter = 0;

  List<ChatUiMessage> get messages =>
      List<ChatUiMessage>.unmodifiable(_messages);

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }

    final existing = _initializeFuture;
    if (existing != null) {
      return existing;
    }

    final future = _initializeInternal();
    _initializeFuture = future;
    return future.whenComplete(() {
      if (identical(_initializeFuture, future)) {
        _initializeFuture = null;
      }
    });
  }

  Future<void> _initializeInternal() async {
    final restoredHistory = await _historyStore.loadHistory();
    _messageStore.replaceHistory(restoredHistory);

    _messages
      ..clear()
      ..addAll(
        restoredHistory.map(
          (historyMessage) => ChatUiMessage(
            id: _newId(historyMessage.role == MsgRole.user ? "u" : "h"),
            text: historyMessage.text,
            isUser: historyMessage.role == MsgRole.user,
          ),
        ),
      );

    _orchestrator.setHistorySnapshot(_messageStore.historySnapshot());

    await _orchestrator.start();

    // Start TTS initialization in background (non-blocking).
    unawaited(_ttsService.init());

    _initialized = true;
    _historyDirty = false;
    _registerLifecycleObserver();
    _startHistoryFlushTimer();
    _notifyIfAlive();
  }

  Future<void> sendUserMessage(String rawInput) async {
    final text = rawInput.trim();
    if (text.isEmpty || _disposed) {
      return;
    }

    if (!_initialized) {
      await initialize();
    }

    final userId = _newId("u");
    final assistantId = _newId("a");

    _messages.add(ChatUiMessage(id: userId, text: text, isUser: true));
    _messages.add(ChatUiMessage(id: assistantId, text: "...", isUser: false));

    _messageStore.addUserMessage(text);
    _orchestrator.setHistorySnapshot(_messageStore.historySnapshot());
    _markHistoryDirty();
    _notifyIfAlive();

    LlmOrchestratorReply reply;
    try {
      reply = await _orchestrator.replyForUserInput(
        userInput: text,
        history: _messageStore.historySnapshot(),
      );
    } catch (_) {
      reply = const LlmOrchestratorReply(
        text:
            "I heard you. I am still preparing the local assistant and will answer as soon as it is ready.",
        origin: AssistantOrigin.safeMode,
      );
    }

    _replaceMessage(
      assistantId,
      ChatUiMessage(id: assistantId, text: reply.text, isUser: false),
    );

    _messageStore.addAssistMsg(reply.text, origin: reply.origin);
    _orchestrator.setHistorySnapshot(_messageStore.historySnapshot());
    _markHistoryDirty();
    _notifyIfAlive();

    // Speak the LLM reply aloud.
    if (kDebugMode) {
      debugPrint("CHAT: Triggering TTS for reply");
    }
    unawaited(_ttsService.speak(reply.text));
  }

  /// Flushes dirty history when the app goes to background/inactive/detached.
  /// Called automatically by the Flutter framework on lifecycle transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized || _disposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_flushHistoryIfDirty(reason: "lifecycle:${state.name}"));
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  Future<void> _flushHistoryIfDirty({required String reason}) {
    if (_disposed || !_initialized || !_historyDirty) {
      return Future<void>.value();
    }

    final existing = _historyFlushFuture;
    if (existing != null) {
      return existing;
    }

    final future = _flushHistoryInternal(reason: reason);
    _historyFlushFuture = future;
    return future.whenComplete(() {
      if (identical(_historyFlushFuture, future)) {
        _historyFlushFuture = null;
      }
      if (_historyDirty && !_disposed) {
        unawaited(_flushHistoryIfDirty(reason: "coalesced"));
      }
    });
  }

  Future<void> _flushHistoryInternal({required String reason}) async {
    final snapshot = _messageStore.historySnapshot();
    _historyDirty = false;
    try {
      await _historyStore.saveHistory(snapshot);
      if (kDebugMode) {
        debugPrint(
          "History flushed (reason=$reason, messages=${snapshot.length}).",
        );
      }
    } catch (_) {
      _historyDirty = true;
      // Keep chat flow alive even if persistence fails.
    }
  }

  void _startHistoryFlushTimer() {
    _historyFlushTimer?.cancel();
    _historyFlushTimer = Timer.periodic(_historyFlushInterval, (_) {
      unawaited(_flushHistoryIfDirty(reason: "timer"));
    });
  }

  void _markHistoryDirty() {
    _historyDirty = true;
  }

  void _registerLifecycleObserver() {
    if (_isObserverRegistered) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _isObserverRegistered = true;
  }

  void _unregisterLifecycleObserver() {
    if (!_isObserverRegistered) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _isObserverRegistered = false;
  }

  void _replaceMessage(String id, ChatUiMessage replacement) {
    final index = _messages.indexWhere((message) => message.id == id);
    if (index == -1) {
      _messages.add(replacement);
      return;
    }
    _messages[index] = replacement;
  }

  String _newId(String prefix) {
    _idCounter += 1;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return "${prefix}_$micros$_idCounter";
  }

  void _notifyIfAlive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _historyFlushTimer?.cancel();
    _unregisterLifecycleObserver();
    unawaited(_flushHistoryIfDirty(reason: "dispose"));

    _disposed = true;
    unawaited(_orchestrator.dispose());
    unawaited(_ttsService.dispose());
    super.dispose();
  }
}
