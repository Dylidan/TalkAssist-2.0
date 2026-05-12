class SttConfig {
  const SttConfig._();

  static const String modelFamily = 'whisper_small';
  static const String modelDirName = 'stt_models';
  static const String modelSubDirName = 'whisper_small';

  static const String encoderFileName = 'small-encoder.int8.onnx';
  static const String decoderFileName = 'small-decoder.int8.onnx';
  static const String tokensFileName = 'small-tokens.txt';
  static const String vadFileName = 'silero_vad.onnx';

  static const String prefsModelDirKey = 'stt_model_dir';
  static const String prefsModelReadyKey = 'stt_model_ready';

  // Whisper Small int8: encoder ~112MB, decoder ~262MB
  static const int minimumEncoderSizeBytes = 100 * 1024 * 1024;
  static const int minimumDecoderSizeBytes = 200 * 1024 * 1024;
  static const int minimumVadSizeBytes = 100 * 1024;

  static const String encoderUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main/small-encoder.int8.onnx';
  static const String decoderUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main/small-decoder.int8.onnx';
  static const String tokensUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main/small-tokens.txt';
  static const String vadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';
}