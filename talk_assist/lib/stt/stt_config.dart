class SttConfig {
  const SttConfig._();

  static const String modelFamily = 'whisper_tiny';
  static const String modelDirName = 'stt_models';
  static const String modelSubDirName = 'whisper_tiny';

  static const String encoderFileName = 'tiny-encoder.int8.onnx';
  static const String decoderFileName = 'tiny-decoder.int8.onnx';
  static const String tokensFileName = 'tiny-tokens.txt';
  static const String vadFileName = 'silero_vad.onnx';

  static const String prefsModelDirKey = 'stt_model_dir';
  static const String prefsModelReadyKey = 'stt_model_ready';

  static const int minimumEncoderSizeBytes = 1024 * 1024;
  static const int minimumDecoderSizeBytes = 100 * 1024;
  static const int minimumVadSizeBytes = 100 * 1024;

  static const String encoderUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx';
  static const String decoderUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx';
  static const String tokensUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt';
  static const String vadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';
}