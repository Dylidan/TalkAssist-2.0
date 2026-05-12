class WakeWordConfig {
  const WakeWordConfig._();

  static const String wakePhrase = 'HEY TALK ASSIST';
  static const String wakeKeywordLabel = 'HEY_TALK_ASSIST';

  static const String modelDirName = 'wake_word_models';
  static const String modelSubDirName = 'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20';

  static const String archiveFileName =
      'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2';
  static const String archiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2';

  static const String encoderFileName =
      'encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx';
  static const String decoderFileName =
      'decoder-epoch-13-avg-2-chunk-8-left-64.onnx';
  static const String joinerFileName =
      'joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx';
  static const String tokensFileName = 'tokens.txt';
  static const String englishLexiconFileName = 'en.phone';
  static const String keywordsFileName = 'wake_keywords.txt';

  static const int minimumEncoderSizeBytes = 1024 * 1024;
  static const int minimumDecoderSizeBytes = 100 * 1024;
  static const int minimumJoinerSizeBytes = 50 * 1024;
  static const int minimumTokensSizeBytes = 1024;
  static const int minimumLexiconSizeBytes = 100 * 1024;
}
