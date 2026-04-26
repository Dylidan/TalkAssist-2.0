import "dart:async";
import "dart:typed_data";

import "package:flutter/foundation.dart";
import "package:record/record.dart";
import "package:sherpa_onnx/sherpa_onnx.dart" as sherpa_onnx;

import "wake_word_config.dart";
import "wake_word_model_repository.dart";

class WakeWordService {
  static const int _sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  final WakeWordModelRepository _modelRepository = WakeWordModelRepository();
  final StreamController<String> _detectionsController =
      StreamController<String>.broadcast();

  WakeWordModelRecord? _modelRecord;
  sherpa_onnx.KeywordSpotter? _spotter;
  sherpa_onnx.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _initialized = false;
  bool _listening = false;
  bool _handlingDetection = false;

  Stream<String> get detections => _detectionsController.stream;
  bool get isListening => _listening;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception("Microphone permission denied");
    }

    _modelRecord = await _modelRepository.ensureModelAvailable();
    _initialized = true;
  }

  Future<void> startListening() async {
    if (_listening) {
      return;
    }

    if (!_initialized) {
      await initialize();
    }

    final record = _modelRecord;
    if (record == null) {
      throw StateError("Wake word model was not initialized");
    }

    _spotter = sherpa_onnx.KeywordSpotter(
      sherpa_onnx.KeywordSpotterConfig(
        model: sherpa_onnx.OnlineModelConfig(
          transducer: sherpa_onnx.OnlineTransducerModelConfig(
            encoder: record.encoderPath,
            decoder: record.decoderPath,
            joiner: record.joinerPath,
          ),
          tokens: record.tokensPath,
          numThreads: 1,
          provider: "cpu",
          debug: true,
        ),
        keywordsFile: record.keywordsPath,
        keywordsThreshold: 0.2,
        numTrailingBlanks: 1,
      ),
    );
    _stream = _spotter!.createStream();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: true,
        noiseSuppress: true,
        streamBufferSize: 4096,
      ),
    );

    _listening = true;
    debugPrint("WAKE WORD: listening for ${WakeWordConfig.wakePhrase}");

    _audioSubscription = stream.listen(
      _processAudioChunk,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint("WAKE WORD: audio stream error: $error");
      },
      cancelOnError: false,
    );
  }

  void _processAudioChunk(Uint8List chunk) {
    final spotter = _spotter;
    final stream = _stream;
    if (!_listening || _handlingDetection || spotter == null || stream == null) {
      return;
    }

    final samples = _convertPcm16ChunkToFloat32(chunk);
    if (samples.isEmpty) {
      return;
    }

    stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);

    while (spotter.isReady(stream)) {
      spotter.decode(stream);
      final result = spotter.getResult(stream);
      if (result.keyword.isEmpty) {
        continue;
      }

      debugPrint("WAKE WORD: detected ${result.keyword}");
      _handlingDetection = true;
      unawaited(_emitDetection(result.keyword));
      return;
    }
  }

  Future<void> _emitDetection(String keyword) async {
    await stopListening();
    if (!_detectionsController.isClosed) {
      _detectionsController.add(keyword);
    }
    _handlingDetection = false;
  }

  Float32List _convertPcm16ChunkToFloat32(Uint8List chunk) {
    final pcmSamples = _recorder.convertBytesToInt16(chunk);
    final samples = Float32List(pcmSamples.length);
    for (var i = 0; i < pcmSamples.length; i++) {
      samples[i] = pcmSamples[i] / 32768.0;
    }
    return samples;
  }

  Future<void> stopListening() async {
    if (!_listening) {
      return;
    }

    _listening = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    _stream?.free();
    _stream = null;
    _spotter?.free();
    _spotter = null;
  }

  Future<void> dispose() async {
    await stopListening();
    await _detectionsController.close();
    await _recorder.dispose();
  }
}
