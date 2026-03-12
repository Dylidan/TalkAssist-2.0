/// Central configuration for the TinyLlama on-device LLM.
/// All tunable parameters live here so changes are isolated to one file.
/// This is the single source of truth for model identity, file conventions, context/generation settings, and system prompts.
class ModelConfig {
  const ModelConfig._();

  // Human-readable model name for UI display.
  static const String modelDisplayName = "TinyLlama";
  static const String officialRepoId = "TinyLlama/TinyLlama-1.1B-Chat-v1.0";
  static const String officialModelApiUrl =
      "https://huggingface.co/api/models/TinyLlama/TinyLlama-1.1B-Chat-v1.0";
  static const String fallbackGgufUrl =
      "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf";

  static const String preferredQuantizationHint = "q4_k_m";
  static const String modelExtension = "gguf";
  static const String preferredModelFileName =
      "tinyllama-1.1b-chat-v1.0-q4_k_m.gguf";
  static const String modelDirectoryName = "models";

  // Minimum valid GGUF file size (64 MB) to prevent partial downloads.
  static const int minimumModelSizeBytes = 64 * 1024 * 1024;

  // Estimated time to show in UI for first-time model download.
  static const Duration firstSetupEstimate = Duration(minutes: 5);

  // Primary configuration (tuned for emulator constraints: 4 cores, 4GB RAM)
  /// Context window size in tokens is 256. Yes this is tight but necessary on slow
  /// emulators to keep decode batches small and responsive.
  static const int contextWindowTokens = 256;

  /// Batch size for prompt processing. Does NOT affect token generation speed.
  /// Larger batches can improve throughput but increase latency and memory usage.
  /// Kept small for emulator performance.
  /// It can also be 16 for slightly better context understanding at the cost of higher latency.
  static const int batchSizeTokens = 32;

  /// Maximum prior messages to include in the LLM prompt.
  /// Keeps prompts short for the small context window.
  static const int maxHistoryMessages = 2;

  /// Maximum new tokens to generate per completion.
  static const int maxPredictTokens = 16;

  // Sampling parameters for conservative, helpful replies
  // https://discuss.ai.google.dev/t/about-topk-topp-and-temprature/33094
  // It is like a dies roll.
  static const double temperature =
      0.30; // favoring focused and coherent replies
  static const int topK = 20; // for less random responses, avg = 40
  static const double topP = 0.8; // less random responses, avg = 0.9

  /// Number of CPU threads for inference.
  static const int inferenceThreads =
      4; // Set to match emulator configuration (4 cores).

  /// Timeout for the very first successful generation.
  /// Includes model load time plus inference.
  /// This is set due to the fact that in some runs with 1 CPU and 2 GB RAM,
  /// it can haev performance of 8 seconds per token. (Upper bound?)
  static const Duration coldStartInferenceTimeout = Duration(seconds: 160);

  /// Timeout for subsequent generations after the model is warm.
  /// Same value as cold-start because emulator performance is uniformly slow.
  static const Duration steadyStateInferenceTimeout = Duration(seconds: 160);

  /// Fallback reply when the local model isn't ready yet.
  static const String safeModeStatusMessage =
      "I am still setting up your local assistant on this device. "
      "The first setup can take up to 5 minutes.";

  /// Reply shown when the conversation exceeds the context window.
  static const String contextWindowLimitReachedMessage =
      "Chat limit reached. Please say 'Start new chat' to continue.";

  /// Thresholds for context window usage warnings (tokens remaining).
  static const int contextWindowNearFullThresholdTokens = 96;
  static const int contextWindowFullThresholdTokens = 24;

  // ── OpenRouter (online) settings ──────────────────────────────────────────

  /// Max tokens for OpenRouter API responses.
  static const int openRouterMaxTokens = 512;

  /// Sampling temperature for OpenRouter. Slightly higher than local for richer replies.
  static const double openRouterTemperature = 0.7;

  // ──────────────────────────────────────────────────────────────────────────

  /// Persona instructions for TinyLlama.
  /// Targets visually impaired users with simple, practical replies.
  /// Note: For some reason TinyLlama seems to like to continue the conversation even with instructions to not do so.
  static const String systemPrompt =
      "You are TalkAssist, a friendly assistant for a visually impaired user. "
      "Use simple words, short sentences, and direct practical help. "
      "Avoid technical jargon. "
      "Give only your reply. Do not continue the conversation.";
}
