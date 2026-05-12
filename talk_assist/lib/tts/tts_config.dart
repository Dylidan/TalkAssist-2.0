class TtsVoiceConfig {
  const TtsVoiceConfig({
    required this.displayName,
    required this.modelName,
    required this.locale,
    required this.downloadUrl,
    required this.onnxModelFileName,
    required this.minimumModelSizeBytes,
  });

  final String displayName;
  final String modelName;
  final String locale;
  final String downloadUrl;
  final String onnxModelFileName;
  final int minimumModelSizeBytes;
}

/// Central configuration for the Piper TTS voice model.
/// All tunable parameters live here so changes are isolated to one file.
/// This is the single source of truth for voice identity, model URLs, and synthesis settings.


// static const String voiceModelName = "vits-piper-en_US-amy-low";
// static const String modelDownloadUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-low.tar.bz2";
// static const String onnxModelFileName = "en_US-amy-low.onnx";
// static const int minimumModelSizeBytes = 61 * 1024 * 1024;
// static const String tokensFileName = "tokens.txt";
// static const String espeakDataDirName = "espeak-ng-data";
// static const String ttsModelDirectoryName = "tts_models";
// English only version

class TtsConfig {
  const TtsConfig._();

  static const String defaultLanguageCode = "en";

  // Can add more language later (I believe these are enough,no one really use our app anyway :P)
  static const Map<String, TtsVoiceConfig> voices = {
    "en": TtsVoiceConfig(
      displayName: "Amy",
      modelName: "en_US-amy-medium",
      locale: "en_US",
      downloadUrl:
          "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-medium.tar.bz2",
      onnxModelFileName: "en_US-amy-medium.onnx",
      minimumModelSizeBytes: 61 * 1024 * 1024,
    ),

    "zh": TtsVoiceConfig(
      displayName: "Chaowen",
      modelName: "zh_CN-chaowen-medium",
      locale: "zh_CN",
      downloadUrl:
          "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-chaowen-medium.tar.bz2",
      onnxModelFileName: "zh_CN-chaowen-medium.onnx",
      minimumModelSizeBytes: 20 * 1024 * 1024,
    ),

    "es": TtsVoiceConfig(
      displayName: "DaveFX",
      modelName: "es_ES-davefx-medium",
      locale: "es_ES",
      downloadUrl:
          "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-davefx-medium.tar.bz2",
      onnxModelFileName: "es_ES-davefx-medium.onnx",
      minimumModelSizeBytes: 20 * 1024 * 1024,
    ),

    "fr": TtsVoiceConfig(
      displayName: "Tom",
      modelName: "fr_FR-tom-medium",
      locale: "fr_FR",
      downloadUrl:
          "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-tom-medium.tar.bz2",
      onnxModelFileName: "fr_FR-tom-medium.onnx",
      minimumModelSizeBytes: 20 * 1024 * 1024,
    ),
  };

  static TtsVoiceConfig get defaultVoice => voices[defaultLanguageCode]!;

  static TtsVoiceConfig voiceForLanguageCode(String languageCode) {
    return voices[languageCode] ?? defaultVoice;
  }

  static String detectLanguageCode(String text) {
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return "zh";
    if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) return "ja";
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return "ko";
    return defaultLanguageCode;
  }

  static TtsVoiceConfig voiceForText(String text) {
    final languageCode = detectLanguageCode(text);
    return voiceForLanguageCode(languageCode);
  }

  // Human-readable voice name for UI display.
  static String get voiceDisplayName => defaultVoice.displayName;

  // Piper voice model identity.
  static String get voiceModelName => defaultVoice.modelName;
  static String get voiceLocale => defaultVoice.locale;

  // Model download URL from sherpa-onnx releases.
  // Format: https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-{modelName}.tar.bz2
  static String get modelDownloadUrl => defaultVoice.downloadUrl;

  // File names after extraction.
  static String get onnxModelFileName => defaultVoice.onnxModelFileName;
  static const String tokensFileName = "tokens.txt";
  static const String espeakDataDirName = "espeak-ng-data";

  // Directory names.
  static const String ttsModelDirectoryName = "tts_models";

  // Minimum expected total size for the extracted model (~61MB).
  static int get minimumModelSizeBytes => defaultVoice.minimumModelSizeBytes;

  // Estimated time to show in UI for first-time model download.
  static const Duration firstSetupEstimate = Duration(minutes: 1);

  /// TTS synthesis settings.
  /// Number of CPU threads for synthesis.
  static const int synthesisThreads = 2;

  // Speech speed multiplier (1.0 = normal, 0.5 = half speed, 2.0 = double speed).
  static const double speechSpeed = 1.0;

  // Speaker ID (0 for single-speaker models).
  static const int speakerId = 0;

  // Provider configuration.
  static const String onnxProvider = "cpu";
  static const bool debugMode = false;

  // Max sentences per generation call.
  static const int maxNumSentences = 1;
}