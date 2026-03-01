import "dart:async";
import "dart:io";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";
import "package:talk_assist/llm/fllama_llm_service.dart";
import "package:talk_assist/llm/llm_service.dart";
import "package:talk_assist/llm/model_repository.dart";
import "package:talk_assist/llm/safe_mode_llm_service.dart";
import "package:talk_assist/message.dart";

/// Result from [LlmOrchestrator.replyForUserInput].
/// Pairs the reply text with its origin so the UI can distinguish
/// between local LLM responses and safe-mode fallback replies.
class LlmOrchestratorReply {
  const LlmOrchestratorReply({required this.text, required this.origin});

  // The generated reply text.
  final String text;

  // Which service produced this reply.
  final AssistantOrigin origin;
}

/// Routes user messages to the local LLM or safe-mode fallback.
/// Coordinates the model preparation lifecycle (download + init) as a
/// background task. Tries the local LLM first when ready.
/// On any failure, falls back to safe-mode for immediate response.
class LlmOrchestrator {
  factory LlmOrchestrator({
    ModelRepository? modelRepository,
    LlmService? localLlmService,
    LlmService? safeModeLlmService,
    Connectivity? connectivity,
    Future<List<ConnectivityResult>> Function()? connectivityCheck,
  }) {
    final repository = modelRepository ?? ModelRepository();
    final resolvedConnectivity = connectivity ?? Connectivity();
    return LlmOrchestrator._(
      modelRepository: repository,
      localLlmService:
          localLlmService ?? FllamaLlmService(modelRepository: repository),
      safeModeLlmService: safeModeLlmService ?? SafeModeLlmService(),
      connectivityCheck:
          connectivityCheck ?? resolvedConnectivity.checkConnectivity,
    );
  }

  LlmOrchestrator._({
    required ModelRepository modelRepository,
    required LlmService localLlmService,
    required LlmService safeModeLlmService,
    required Future<List<ConnectivityResult>> Function() connectivityCheck,
  }) : _modelRepository = modelRepository,
       _localLlm = localLlmService,
       _safeModeLlm = safeModeLlmService,
       _connectivityCheck = connectivityCheck;

  final ModelRepository _modelRepository;
  final LlmService _localLlm;
  final LlmService _safeModeLlm;
  final Future<List<ConnectivityResult>> Function() _connectivityCheck;

  Future<void>? _startFuture;
  Future<bool>? _prepareFuture;
  bool _started = false;
  bool _isLocalReady = false;
  bool _disposed = false;

  List<ChatMessage> _latestHistory = <ChatMessage>[];

  /// Idempotent startup.
  /// Initializes the safe-mode service immediately, then kicks off local
  /// model preparation in the background. Safe to call multiple times.
  Future<void> start() {
    if (_disposed) {
      return Future<void>.value();
    }
    if (_started) {
      return Future<void>.value();
    }

    final existing = _startFuture;
    if (existing != null) {
      return existing;
    }

    final future = _startInternal();
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    });
  }

  Future<void> _startInternal() async {
    await _safeModeLlm.init();
    await _cleanupLegacyQueueFile();
    unawaited(_prepareLocalModel(triggerSource: "startup"));
    _started = true;
  }

  void setHistorySnapshot(List<ChatMessage> history) {
    _latestHistory = List<ChatMessage>.from(history);
  }

  /// Main entry point for getting a reply to user input.
  /// Tries the local LLM first if ready. On timeout, empty response, or
  /// any error, falls back to safe-mode. Updates internal history snapshot
  /// so subsequent generations have context.
  Future<LlmOrchestratorReply> replyForUserInput({
    required String userInput,
    required List<ChatMessage> history,
  }) async {
    await start();

    final normalized = userInput.trim();
    if (normalized.isEmpty) {
      final safeReply = await _safeModeLlm.generateReply(
        userInput: normalized,
        history: history,
      );
      return LlmOrchestratorReply(
        text: safeReply,
        origin: AssistantOrigin.safeMode,
      );
    }

    setHistorySnapshot(history);

    final requestStartedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        "LLM request started (source=live, inputChars=${normalized.length}).",
      );
    }

    try {
      final localReady = await _prepareLocalModel(triggerSource: "send");
      if (localReady) {
        try {
          final localReply = await _localLlm.generateReply(
            userInput: normalized,
            history: _historyForLlm(_latestHistory),
          );
          _latestHistory = <ChatMessage>[
            ..._latestHistory,
            ChatMessage(
              role: MsgRole.assistant,
              text: localReply,
              timestamp: DateTime.now(),
              assistantOrigin: AssistantOrigin.localLlm,
            ),
          ];
          return LlmOrchestratorReply(
            text: localReply,
            origin: AssistantOrigin.localLlm,
          );
        } catch (error) {
          if (kDebugMode) {
            debugPrint("Local LLM generation failed (source=live): $error");
          }
          await _refreshLocalReadyFromService();
        }
      }

      final safeReply = await _safeModeLlm.generateReply(
        userInput: normalized,
        history: history,
      );

      return LlmOrchestratorReply(
        text: safeReply,
        origin: AssistantOrigin.safeMode,
      );
    } finally {
      if (kDebugMode) {
        final elapsedMs = DateTime.now()
            .difference(requestStartedAt)
            .inMilliseconds;
        debugPrint("LLM request finished (source=live, elapsedMs=$elapsedMs).");
      }
    }
  }

  Future<bool> _prepareLocalModel({required String triggerSource}) {
    if (_disposed) {
      return Future<bool>.value(false);
    }

    if (_isLocalReady) {
      return Future<bool>.value(true);
    }

    final existing = _prepareFuture;
    if (existing != null) {
      return existing;
    }

    final future = _prepareLocalModelInternal(triggerSource: triggerSource);
    _prepareFuture = future;
    return future.whenComplete(() {
      if (identical(_prepareFuture, future)) {
        _prepareFuture = null;
      }
    });
  }

  Future<bool> _prepareLocalModelInternal({
    required String triggerSource,
  }) async {
    final hasInternet = await _hasLikelyInternetConnection();
    if (!hasInternet) {
      return false;
    }

    try {
      final downloadStartTime = DateTime.now();
      var lastLoggedPercent = 0;
      final model = await _modelRepository.ensureModelAvailable(
        onProgress: ({required int receivedBytes, required int totalBytes}) {
          if (!kDebugMode) return;
          final receivedMB = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
          final totalMB = totalBytes > 0
              ? (totalBytes / 1024 / 1024).toStringAsFixed(1)
              : "unknown";
          if (totalBytes > 0) {
            final percent = (receivedBytes * 100 ~/ totalBytes);
            if (percent >= lastLoggedPercent + 10) {
              debugPrint(
                "Model download progress: $percent% ($receivedMB MB / $totalMB MB)",
              );
              lastLoggedPercent = percent;
            }
          }
        },
      );
      if (model == null) {
        return false;
      }
      if (kDebugMode && lastLoggedPercent > 0) {
        final elapsedSec = DateTime.now()
            .difference(downloadStartTime)
            .inSeconds;
        debugPrint("Model download complete (elapsedSec=$elapsedSec).");
      }

      await _localLlm.init();
      _isLocalReady = true;
      if (kDebugMode) {
        debugPrint("Local TinyLlama model ready (trigger=$triggerSource).");
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint("Local model setup failed: $error");
      }
      _isLocalReady = false;
      return false;
    }
  }

  List<ChatMessage> _historyForLlm(List<ChatMessage> history) {
    return history
        .where((message) {
          if (message.role != MsgRole.assistant) {
            return true;
          }
          return message.assistantOrigin != AssistantOrigin.safeMode;
        })
        .toList(growable: false);
  }

  Future<bool> _hasLikelyInternetConnection() async {
    try {
      final results = await _connectivityCheck();
      return results.any((value) => value != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> _refreshLocalReadyFromService() async {
    try {
      _isLocalReady = await _localLlm.isReady();
    } catch (_) {
      _isLocalReady = false;
    }
  }

  Future<void> _cleanupLegacyQueueFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final legacyQueueFile = File("${appDir.path}/pending_queue.json");
      if (await legacyQueueFile.exists()) {
        await legacyQueueFile.delete();
      }
    } catch (_) {
      // Ignore cleanup failures for legacy queue file.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _started = false;
    await _localLlm.dispose();
    await _safeModeLlm.dispose();
  }
}
