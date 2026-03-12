import "dart:async";
import "dart:io";

import "package:fllama/fllama.dart";
import "package:flutter/foundation.dart";
import "package:talk_assist/llm/llm_service.dart";
import "package:talk_assist/llm/model_config.dart";
import "package:talk_assist/llm/model_repository.dart";
import "package:talk_assist/message.dart";

/// On-device LLM service using the fllama plugin (llama.cpp).
/// Wraps the native TinyLlama inference engine. Manages context lifecycle,
/// prompt formatting, completion serialization, timeout handling, and
/// context window guards. Falls back to progressively larger nCtx/nBatch
/// candidates if initialization fails.
class FllamaLlmService implements LlmService {
  FllamaLlmService({
    required ModelRepository modelRepository,
    Fllama? fllama,
    FllamaClient? fllamaClient,
  }) : _modelRepository = modelRepository,
       _fllamaClient =
           fllamaClient ??
           _PluginFllamaClient(
             fllama ?? (Fllama.instance() ?? (throw StateError("No fllama"))),
           );

  /// Stop tokens that end generation.
  /// [</s>] and [<|eot_id|>] are model-native end-of-text tokens.
  /// [\n] mechanically prevents the model from self-answering with
  /// multi-turn text (TinyLlama would generate "User:" then answer itself).
  static const List<String> _stopTokens = <String>["</s>", "<|eot_id|>", "\n"];

  final ModelRepository _modelRepository;
  final FllamaClient _fllamaClient;

  double? _contextId;
  Future<void>? _initFuture;
  Future<void> _completionLane = Future<void>.value();
  StreamSubscription<Map<Object?, dynamic>>? _eventSubscription;

  bool _hasSuccessfulGeneration = false;
  int? _lastLoggedLoadProgressBucket;
  int? _activeContextWindowTokens;

  /// Lazy, idempotent initialization.
  /// Tries progressively larger nCtx/nBatch candidates until one succeeds.
  /// Safe to call multiple times; subsequent calls are no-ops if already ready.
  @override
  Future<void> init() {
    if (_contextId != null) {
      return Future<void>.value();
    }
    return _initFuture ??= _initInternal();
  }

  Future<void> _initInternal() async {
    try {
      _lastLoggedLoadProgressBucket = null;
      final model = await _modelRepository.getConfiguredModel();
      if (model == null) {
        throw const LlmUnavailableException(
          "No local TinyLlama model is configured.",
        );
      }

      final file = File(model.path);
      if (!await file.exists()) {
        throw LlmUnavailableException(
          "Configured model file does not exist: ${model.path}",
        );
      }

      if (kDebugMode) {
        final fileSize = await file.length();
        final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
        final filename = model.path.split(Platform.pathSeparator).last;
        debugPrint(
          "TinyLlama model file (name=$filename, sizeMB=$fileSizeMB, source=${model.sourceUrl ?? 'unknown'}).",
        );
      }

      _eventSubscription ??= _fllamaClient.onTokenStream?.listen(_onTokenEvent);

      final initCandidates = _initCandidates();
      Object? lastError;

      for (final candidate in initCandidates) {
        try {
          final initResult = await _fllamaClient.initContext(
            model.path,
            nCtx: candidate.nCtx,
            nBatch: candidate.nBatch,
            nThreads: ModelConfig.inferenceThreads,
            nGpuLayers: 0,
            useMlock: false,
            useMmap: true,
            emitLoadProgress: true,
          );

          final contextId = _parseContextId(initResult?["contextId"]);
          if (contextId == null || contextId <= 0) {
            throw const LlmUnavailableException(
              "Failed to initialize TinyLlama context.",
            );
          }

          _contextId = contextId;
          _activeContextWindowTokens = candidate.nCtx;
          if (kDebugMode) {
            debugPrint(
              "TinyLlama context ready (nCtx=${candidate.nCtx}, nBatch=${candidate.nBatch}).",
            );
          }

          return;
        } catch (error) {
          lastError = error;
        }
      }

      throw LlmUnavailableException("TinyLlama init failed: $lastError");
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  void _onTokenEvent(Map<Object?, dynamic> event) {
    final function = event["function"]?.toString();
    if (function != "loadProgress") {
      return;
    }

    final progressPercent = _parseProgressPercent(event["result"]);
    if (progressPercent == null) {
      return;
    }

    final bucket = progressPercent >= 100 ? 100 : (progressPercent ~/ 20) * 20;
    if (bucket < 20) {
      return;
    }

    final lastBucket = _lastLoggedLoadProgressBucket;
    if (lastBucket == bucket) {
      return;
    }
    if (lastBucket != null && bucket < lastBucket) {
      return;
    }

    _lastLoggedLoadProgressBucket = bucket;
    if (kDebugMode) {
      debugPrint("TinyLlama model load progress: $bucket");
    }
  }

  @override
  Future<bool> isReady() async {
    if (_contextId != null) {
      return true;
    }

    final model = await _modelRepository.getConfiguredModel();
    if (model == null) {
      return false;
    }

    return File(model.path).existsSync();
  }

  /// Public entry point for generating a reply.
  /// Only one completion runs at a time. Handles context window checks, prompt building,
  /// completion with timeout, and reply normalization.
  @override
  Future<String> generateReply({
    required String userInput,
    required List<ChatMessage> history,
  }) {
    return _enqueueCompletion(
      label: "generateReply",
      operation: () =>
          _generateReplyInternal(userInput: userInput, history: history),
    );
  }

  Future<String> _generateReplyInternal({
    required String userInput,
    required List<ChatMessage> history,
  }) async {
    final contextId = await _requireContextId();

    final startedAt = DateTime.now();
    String outcome = "unknown";
    int? tokensPredicted;
    int? tokensEvaluated;
    if (kDebugMode) {
      debugPrint(
        "TinyLlama generation started (history=${history.length}, inputChars=${userInput.length}).",
      );
    }

    final primaryPrompt = _buildPrompt(
      history: history,
      userInput: userInput,
      historyLimit: ModelConfig.maxHistoryMessages,
      systemPrompt: ModelConfig.systemPrompt,
    );

    final contextUsage = await _contextWindowUsage(
      contextId: contextId,
      prompt: primaryPrompt,
    );
    if (contextUsage != null) {
      if (kDebugMode) {
        debugPrint(
          "TinyLlama context window available (nCtx=${contextUsage.contextWindow}, promptTokens=${contextUsage.promptTokens}, available=${contextUsage.remainingTokens}).",
        );
      }
      if (contextUsage.isNearFull && kDebugMode) {
        debugPrint(
          "TinyLlama context window almost full (available=${contextUsage.remainingTokens}).",
        );
      }
      if (contextUsage.isFull) {
        if (kDebugMode) {
          debugPrint(
            "TinyLlama context window full (available=${contextUsage.remainingTokens}).",
          );
        }
        _logInteractionMetrics(
          outcome: "context_limit",
          totalElapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        );
        return ModelConfig.contextWindowLimitReachedMessage;
      }
    }

    if (kDebugMode) {
      final initCandidates = _initCandidates();
      final primaryNCtx = initCandidates.firstOrNull?.nCtx ?? -1;
      final primaryNBatch = initCandidates.firstOrNull?.nBatch ?? -1;
      debugPrint(
        "TinyLlama prompt prepared (chars=${primaryPrompt.length}, nCtx=$primaryNCtx, nBatch=$primaryNBatch, nPredict=${ModelConfig.maxPredictTokens}).\nPrompt:\n${primaryPrompt.substring(0, primaryPrompt.length.clamp(0, 500))}",
      );
    }

    try {
      final completion = await _runCompletion(
        contextId: contextId,
        prompt: primaryPrompt,
        timeout: _activeInferenceTimeout(),
        nThreads: ModelConfig.inferenceThreads,
        nPredict: ModelConfig.maxPredictTokens,
        temperature: ModelConfig.temperature,
        topK: ModelConfig.topK,
        topP: ModelConfig.topP,
        attempt: "primary",
      );

      tokensPredicted = _parseMetricInt(completion, "tokens_predicted");
      tokensEvaluated = _parseMetricInt(completion, "tokens_evaluated");
      final text = _normalizeReply(completion?["text"]?.toString() ?? "");
      if (text.isNotEmpty) {
        outcome = "success";
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
        _hasSuccessfulGeneration = true;
        if (kDebugMode) {
          debugPrint(
            "TinyLlama generation succeeded (attempt=primary, elapsedMs=$elapsedMs).",
          );
        }
        return text;
      }

      outcome = "empty";
      throw const LlmUnavailableException(
        "TinyLlama returned an empty completion.",
      );
    } on TimeoutException {
      outcome = "timeout";
      await _interruptCompletion(contextId, attempt: "primary");
      // Give native side time to finish in-flight decode before next attempt
      await Future<void>.delayed(const Duration(seconds: 2));

      throw const LlmUnavailableException(
        "TinyLlama response timed out on this device.",
      );
    } finally {
      _logInteractionMetrics(
        outcome: outcome,
        totalElapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        tokensPredicted: tokensPredicted,
        tokensEvaluated: tokensEvaluated,
      );
    }
  }

  Future<double> _requireContextId() async {
    if (_contextId != null) {
      return _contextId!;
    }

    await init();
    final reloaded = _contextId;
    if (reloaded == null) {
      throw const LlmUnavailableException("Local model context is not ready.");
    }
    return reloaded;
  }

  Future<Map<Object?, dynamic>?> _runCompletion({
    required double contextId,
    required String prompt,
    required Duration timeout,
    required int nThreads,
    required int nPredict,
    required double temperature,
    required int topK,
    required double topP,
    required String attempt,
  }) async {
    final startedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        "TinyLlama completion start (attempt=$attempt, promptChars=${prompt.length}, nPredict=$nPredict, timeoutMs=${timeout.inMilliseconds}).",
      );
    }

    final completion = await _fllamaClient
        .completion(
          contextId,
          prompt: prompt,
          temperature: temperature,
          nThreads: nThreads,
          nPredict: nPredict,
          topK: topK,
          topP: topP,
          stop: _stopTokens,
          emitRealtimeCompletion: false,
        )
        .timeout(timeout);

    if (kDebugMode) {
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        "TinyLlama completion end (attempt=$attempt, elapsedMs=$elapsed).",
      );
    }

    return completion;
  }

  Future<void> _interruptCompletion(
    double contextId, {
    required String attempt,
  }) async {
    try {
      await _fllamaClient.stopCompletion(contextId: contextId);
      if (kDebugMode) {
        debugPrint("TinyLlama completion interrupted (attempt=$attempt).");
      }
    } catch (_) {
      // Ignore cancellation errors.
    }
  }

  /// Only one completion runs at a time.
  /// Each new operation waits for the previous to complete (or fail).
  Future<T> _enqueueCompletion<T>({
    required String label,
    required Future<T> Function() operation,
  }) {
    final completer = Completer<T>();
    final queuedAt = DateTime.now();
    final previous = _completionLane;

    _completionLane = previous
        .catchError((_) {
          // Keep the lane alive after previous failures.
        })
        .then((_) async {
          final waitedMs = DateTime.now().difference(queuedAt).inMilliseconds;
          if (kDebugMode && waitedMs > 0) {
            debugPrint(
              "TinyLlama completion lane acquired (label=$label, waitMs=$waitedMs).",
            );
          }

          try {
            completer.complete(await operation());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });

    return completer.future;
  }

  Duration _activeInferenceTimeout() {
    if (_hasSuccessfulGeneration) {
      return ModelConfig.steadyStateInferenceTimeout;
    }
    return ModelConfig.coldStartInferenceTimeout;
  }

  List<_InitCandidate> _initCandidates() {
    return const <_InitCandidate>[
      _InitCandidate(
        nCtx: ModelConfig.contextWindowTokens,
        nBatch: ModelConfig.batchSizeTokens,
      ),
    ];
  }

  /// Formats conversation history into TinyLlama's chat template.
  /// Template: `<|role|>\ncontent\n</s>\n` ... `<|assistant|>\n`
  /// Filters out safe-mode assistant replies (they're not real conversation)
  /// and deduplicates trailing user input (prevents the model from seeing
  /// the current message twice if it's already in history).
  String _buildPrompt({
    required List<ChatMessage> history,
    required String userInput,
    required int historyLimit,
    required String systemPrompt,
  }) {
    final filteredHistory = history
        .where((message) {
          if (message.role != MsgRole.assistant) {
            return true;
          }
          return message.assistantOrigin != AssistantOrigin.safeMode;
        })
        .toList(growable: false);

    final trimmedHistory = filteredHistory.length > historyLimit
        ? filteredHistory.sublist(filteredHistory.length - historyLimit)
        : filteredHistory;

    final messages = <_PromptMessage>[
      _PromptMessage(role: "system", content: systemPrompt),
    ];

    for (final message in trimmedHistory) {
      final text = message.text.trim();
      if (text.isEmpty) {
        continue;
      }
      messages.add(
        _PromptMessage(
          role: message.role == MsgRole.user ? "user" : "assistant",
          content: text,
        ),
      );
    }

    final normalizedInput = userInput.trim();
    if (normalizedInput.isNotEmpty) {
      final isDuplicateLastUser =
          messages.isNotEmpty &&
          messages.last.role == "user" &&
          messages.last.content == normalizedInput;
      if (!isDuplicateLastUser) {
        messages.add(_PromptMessage(role: "user", content: normalizedInput));
      }
    }

    final buffer = StringBuffer();
    for (final message in messages) {
      buffer.write("<|${message.role}|>\n");
      buffer.write(message.content.trim());
      buffer.write("\n</s>\n");
    }
    buffer.write("<|assistant|>\n");
    return buffer.toString();
  }

  /// Strips role-prefix tags, stop tokens, and continuation markers.
  /// The raw model output may include `<|assistant|>`, `</s>`, or fake "User:" continuations. This cleans those artifacts.
  String _normalizeReply(String value) {
    var cleaned = value.trim();

    if (cleaned.startsWith("<|assistant|>")) {
      cleaned = cleaned.substring("<|assistant|>".length).trimLeft();
    }

    if (cleaned.toLowerCase().startsWith("assistant:")) {
      cleaned = cleaned.substring("assistant:".length).trimLeft();
    }

    for (final marker in <String>[
      "\nUser:",
      "\nSystem:",
      "\nAssistant:",
      "<|user|>",
      "<|system|>",
      "<|assistant|>",
      "</s>",
      "<|eot_id|>",
    ]) {
      final index = cleaned.indexOf(marker);
      if (index != -1) {
        cleaned = cleaned.substring(0, index).trimRight();
      }
    }

    return cleaned;
  }

  double? _parseContextId(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  int? _parseProgressPercent(Object? value) {
    int? asInt;
    if (value is int) {
      asInt = value;
    } else if (value is double) {
      asInt = value.round();
    } else if (value is String) {
      asInt = double.tryParse(value)?.round();
    }

    if (asInt == null) {
      return null;
    }
    if (asInt < 0) {
      return 0;
    }
    if (asInt > 100) {
      return 100;
    }
    return asInt;
  }

  /// Checks how much of the context window the prompt consumes.
  /// Tokenizes the prompt and compares against nCtx. Returns null if
  /// tokenization fails. Used to decide when to show "almost full" warnings
  /// or refuse generation when the window is exhausted.
  Future<_ContextWindowUsage?> _contextWindowUsage({
    required double contextId,
    required String prompt,
  }) async {
    final contextWindow =
        _activeContextWindowTokens ?? _initCandidates().firstOrNull?.nCtx;
    if (contextWindow == null || contextWindow <= 0) {
      return null;
    }

    final promptTokens = await _estimateTokenCount(contextId, prompt);
    if (promptTokens == null || promptTokens <= 0) {
      return null;
    }

    final remaining = contextWindow - promptTokens;
    return _ContextWindowUsage(
      contextWindow: contextWindow,
      promptTokens: promptTokens,
      remainingTokens: remaining,
      isNearFull: remaining <= ModelConfig.contextWindowNearFullThresholdTokens,
      isFull: remaining <= ModelConfig.contextWindowFullThresholdTokens,
    );
  }

  Future<int?> _estimateTokenCount(double contextId, String text) async {
    try {
      final tokenized = await _fllamaClient.tokenize(contextId, text);
      return _parseTokenCount(tokenized);
    } catch (error) {
      if (kDebugMode) {
        debugPrint("TinyLlama token count unavailable: $error");
      }
      return null;
    }
  }

  int? _parseTokenCount(Map<Object?, dynamic>? tokenized) {
    final raw = tokenized?["tokens"];
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.round();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    if (raw is List) {
      return raw.length;
    }
    return null;
  }

  int? _parseMetricInt(Map<Object?, dynamic>? completion, String key) {
    final raw = completion?[key];
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.round();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  void _logInteractionMetrics({
    required String outcome,
    required int totalElapsedMs,
    int? tokensPredicted,
    int? tokensEvaluated,
  }) {
    if (!kDebugMode) {
      return;
    }

    final tokensPerSecond = _tokensPerSecond(
      tokensPredicted: tokensPredicted,
      elapsedMs: totalElapsedMs,
    );
    final predictedLabel = tokensPredicted?.toString() ?? "n/a";
    final evaluatedLabel = tokensEvaluated?.toString() ?? "n/a";
    final tpsLabel = tokensPerSecond?.toStringAsFixed(2) ?? "n/a";
    final msPerToken = (tokensPredicted != null && tokensPredicted > 0)
        ? totalElapsedMs ~/ tokensPredicted
        : null;
    final msPerTokenLabel = msPerToken?.toString() ?? "n/a";

    debugPrint(
      "TinyLlama interaction metrics (outcome=$outcome, totalMs=$totalElapsedMs, tokensPredicted=$predictedLabel, tokensEvaluated=$evaluatedLabel, tokensPerSecond=$tpsLabel, msPerToken=$msPerTokenLabel).",
    );
  }

  double? _tokensPerSecond({
    required int? tokensPredicted,
    required int elapsedMs,
  }) {
    if (tokensPredicted == null || tokensPredicted <= 0 || elapsedMs <= 0) {
      return null;
    }
    return tokensPredicted / (elapsedMs / 1000.0);
  }

  /// Releases the native context and cleans up resources.
  /// Safe to call multiple times. Idempotent.
  @override
  Future<void> dispose() async {
    final contextId = _contextId;
    _contextId = null;
    _initFuture = null;
    _completionLane = Future<void>.value();

    _hasSuccessfulGeneration = false;
    _lastLoggedLoadProgressBucket = null;
    _activeContextWindowTokens = null;

    if (contextId != null) {
      try {
        await _fllamaClient.releaseContext(contextId);
      } catch (_) {
        // Ignore teardown errors.
      }
    }

    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}

/// Testable abstraction over the native fllama plugin.
/// Tests inject a fake implementation; production uses [_PluginFllamaClient].
/// This interface makes the service unit-testable without real native calls.
abstract class FllamaClient {
  Stream<Map<Object?, dynamic>>? get onTokenStream;

  Future<Map<Object?, dynamic>?> initContext(
    String modelPath, {
    int nCtx = 512,
    int nBatch = 512,
    int nThreads = 4,
    int nGpuLayers = 99,
    bool useMlock = true,
    bool useMmap = true,
    bool emitLoadProgress = false,
  });

  Future<Map<Object?, dynamic>?> completion(
    double contextId, {
    required String prompt,
    int nThreads = 0,
    int nPredict = -1,
    double temperature = 0.7,
    int topK = 40,
    double topP = 0.95,
    List<String>? stop,
    bool emitRealtimeCompletion = false,
  });

  Future<void> stopCompletion({required double contextId});

  Future<void> releaseContext(double contextId);

  Future<Map<Object?, dynamic>?> tokenize(double contextId, String text);

  Future<String?> detokenize(double contextId, List<int> tokens);
}

class _PluginFllamaClient implements FllamaClient {
  const _PluginFllamaClient(this._delegate);

  final Fllama _delegate;

  @override
  Stream<Map<Object?, dynamic>>? get onTokenStream => _delegate.onTokenStream;

  @override
  Future<Map<Object?, dynamic>?> initContext(
    String modelPath, {
    int nCtx = 512,
    int nBatch = 512,
    int nThreads = 4,
    int nGpuLayers = 99,
    bool useMlock = true,
    bool useMmap = true,
    bool emitLoadProgress = false,
  }) {
    return _delegate.initContext(
      modelPath,
      nCtx: nCtx,
      nBatch: nBatch,
      nThreads: nThreads,
      nGpuLayers: nGpuLayers,
      useMlock: useMlock,
      useMmap: useMmap,
      emitLoadProgress: emitLoadProgress,
    );
  }

  @override
  Future<Map<Object?, dynamic>?> completion(
    double contextId, {
    required String prompt,
    int nThreads = 0,
    int nPredict = -1,
    double temperature = 0.7,
    int topK = 40,
    double topP = 0.95,
    List<String>? stop,
    bool emitRealtimeCompletion = false,
  }) {
    return _delegate.completion(
      contextId,
      prompt: prompt,
      nThreads: nThreads,
      nPredict: nPredict,
      temperature: temperature,
      topK: topK,
      topP: topP,
      stop: stop,
      emitRealtimeCompletion: emitRealtimeCompletion,
    );
  }

  @override
  Future<void> stopCompletion({required double contextId}) {
    return _delegate.stopCompletion(contextId: contextId);
  }

  @override
  Future<void> releaseContext(double contextId) {
    return _delegate.releaseContext(contextId);
  }

  @override
  Future<Map<Object?, dynamic>?> tokenize(double contextId, String text) {
    return _delegate.tokenize(contextId, text: text);
  }

  @override
  Future<String?> detokenize(double contextId, List<int> tokens) {
    return _delegate.detokenize(contextId, tokens: tokens);
  }
}

class _InitCandidate {
  const _InitCandidate({required this.nCtx, required this.nBatch});

  final int nCtx;
  final int nBatch;
}

class _PromptMessage {
  const _PromptMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class _ContextWindowUsage {
  const _ContextWindowUsage({
    required this.contextWindow,
    required this.promptTokens,
    required this.remainingTokens,
    required this.isNearFull,
    required this.isFull,
  });

  final int contextWindow;
  final int promptTokens;
  final int remainingTokens;
  final bool isNearFull;
  final bool isFull;
}
