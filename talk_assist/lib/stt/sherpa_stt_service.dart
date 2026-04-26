// This service wraps recording and offline transcription using Sherpa ONNX.
// It now uses streamed PCM audio plus Sherpa VAD to detect end-of-turn more
// reliably than amplitude-only silence detection.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'stt_model_repository.dart';
import 'stt_service.dart';

class SherpaSttService implements SttService {
  static const int _sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  final SttModelRepository _modelRepository = SttModelRepository();

  String? _modelDirPath;
  bool _initialized = false;

  Completer<String?>? _activeRecordingCompleter;
  StreamSubscription<Uint8List>? _activeAudioStreamSubscription;
  Timer? _activeMaxTimer;
  sherpa_onnx.VoiceActivityDetector? _activeVad;
  bool _isFinishingActiveRecording = false;

  @override
  Future<String?> recordUntilSilenceAndTranscribe({
    Duration maxDuration = const Duration(seconds: 20),
    Duration silenceDuration = const Duration(milliseconds: 700),
    Duration leadingSilenceGrace = const Duration(milliseconds: 800),
    double silenceThresholdDb = -20.0,
  }) async {
    if (_activeRecordingCompleter != null &&
        !_activeRecordingCompleter!.isCompleted) {
      print('STT start: reusing active VAD recording session');
      return _activeRecordingCompleter!.future;
    }

    await initialize();

    final completer = Completer<String?>();
    _activeRecordingCompleter = completer;

    print(
      'STT start: maxDuration=$maxDuration, silenceDuration=$silenceDuration, leadingSilenceGrace=$leadingSilenceGrace, mode=vad',
    );
    if (silenceThresholdDb != -20.0) {
      print(
        'STT start: ignoring silenceThresholdDb=$silenceThresholdDb because VAD does not use dB thresholds',
      );
    }

    try {
      await _startVadRecordingSession(
        maxDuration: maxDuration,
        silenceDuration: silenceDuration,
      );
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      if (identical(_activeRecordingCompleter, completer)) {
        _activeRecordingCompleter = null;
      }
    }

    return completer.future;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    await _modelRepository.ensureModelAvailable();

    final modelDir = await _modelRepository.getWhisperTinyEnDirectory();
    _modelDirPath = modelDir.path;

    final ready = await _modelRepository.isModelReady();
    print('STT model ready: $ready');
    final summary = await _modelRepository.getModelStatusSummary();
    print('STT model status: $summary');

    _initialized = true;
  }

  @override
  Future<void> startRecording() async {
    print('STT startRecording: initialized=$_initialized');
    if (!_initialized) {
      await initialize();
    }

    if (_activeRecordingCompleter != null &&
        !_activeRecordingCompleter!.isCompleted) {
      print('STT startRecording: active VAD session already running');
      return;
    }

    _activeRecordingCompleter = Completer<String?>();
    await _startVadRecordingSession(
      maxDuration: const Duration(minutes: 5),
      silenceDuration: const Duration(milliseconds: 700),
    );
  }

  @override
  Future<String?> stopRecordingAndTranscribe() async {
    if (_activeRecordingCompleter != null &&
        !_activeRecordingCompleter!.isCompleted) {
      final completer = _activeRecordingCompleter!;
      print('STT stop: manual stop requested');
      unawaited(
        _finishActiveRecording(
          reason: 'manual-stop',
          flushVad: true,
        ),
      );
      return completer.future;
    }

    return null;
  }

  Future<void> _startVadRecordingSession({
    required Duration maxDuration,
    required Duration silenceDuration,
  }) async {
    final expected = await _modelRepository.getExpectedFilePaths();
    final vadPath = expected['vad'];
    if (vadPath == null || vadPath.isEmpty) {
      throw Exception('STT VAD model path is missing');
    }

    final vadConfig = sherpa_onnx.VadModelConfig(
      sileroVad: sherpa_onnx.SileroVadModelConfig(
        model: vadPath,
        threshold: 0.5,
        minSilenceDuration: silenceDuration.inMilliseconds / 1000.0,
        minSpeechDuration: 0.2,
        maxSpeechDuration: maxDuration.inMilliseconds / 1000.0,
      ),
      sampleRate: _sampleRate,
      numThreads: 1,
      provider: 'cpu',
      debug: true,
    );

    final bufferSizeInSeconds = maxDuration.inMilliseconds / 1000.0 + 1.0;
    _activeVad = sherpa_onnx.VoiceActivityDetector(
      config: vadConfig,
      bufferSizeInSeconds: bufferSizeInSeconds,
    );

    print('STT startRecording: starting PCM stream for VAD');
    final audioStream = await _recorder.startStream(
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
    print('STT startRecording: recorder.startStream() completed');

    _activeMaxTimer?.cancel();
    _activeMaxTimer = Timer(maxDuration, () {
      print('STT stop: max duration reached');
      unawaited(
        _finishActiveRecording(
          reason: 'max-duration',
          flushVad: true,
        ),
      );
    });

    _activeAudioStreamSubscription = audioStream.listen(
      _handleAudioChunk,
      onError: (Object error, StackTrace stackTrace) {
        print('STT stream error: $error');
        unawaited(_failActiveRecording(error, stackTrace));
      },
      onDone: () {
        print('STT stream: audio stream closed');
      },
      cancelOnError: false,
    );
  }

  void _handleAudioChunk(Uint8List chunk) {
    final vad = _activeVad;
    if (vad == null || chunk.isEmpty) {
      return;
    }

    final samples = _convertPcm16ChunkToFloat32(chunk);
    if (samples.isEmpty) {
      return;
    }

    vad.acceptWaveform(samples);

    if (vad.isDetected()) {
      print('STT vad: speech endpoint detected');
    }

    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();

      if (segment.samples.isEmpty) {
        continue;
      }

      print(
        'STT vad: segment ready start=${segment.start} samples=${segment.samples.length}',
      );
      unawaited(
        _finishActiveRecording(
          reason: 'vad-endpoint',
          detectedSamples: segment.samples,
        ),
      );
      return;
    }
  }

  Future<String?> _finishActiveRecording({
    required String reason,
    bool flushVad = false,
    Float32List? detectedSamples,
  }) async {
    if (_isFinishingActiveRecording) {
      final completer = _activeRecordingCompleter;
      return completer == null ? null : completer.future;
    }

    _isFinishingActiveRecording = true;
    final completer = _activeRecordingCompleter;
    final vad = _activeVad;

    _activeMaxTimer?.cancel();
    _activeMaxTimer = null;

    try {
      Float32List? finalSamples = detectedSamples;

      if (finalSamples == null && flushVad && vad != null) {
        print('STT stop: flushing VAD for reason=$reason');
        vad.flush();
        while (!vad.isEmpty()) {
          final segment = vad.front();
          vad.pop();
          if (segment.samples.isNotEmpty) {
            finalSamples = segment.samples;
            break;
          }
        }
      }

      await _activeAudioStreamSubscription?.cancel();
      _activeAudioStreamSubscription = null;

      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }

      String? text;
      if (finalSamples == null || finalSamples.isEmpty) {
        print('STT stop: no speech segment available for reason=$reason');
        text = null;
      } else {
        text = await _transcribeSamples(finalSamples, _sampleRate);
      }

      if (completer != null && !completer.isCompleted) {
        completer.complete(text);
      }
      return text;
    } catch (error, stackTrace) {
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      rethrow;
    } finally {
      _freeActiveVad();
      if (identical(_activeRecordingCompleter, completer)) {
        _activeRecordingCompleter = null;
      }
      _isFinishingActiveRecording = false;
    }
  }

  Float32List _convertPcm16ChunkToFloat32(Uint8List chunk) {
    final pcmSamples = _recorder.convertBytesToInt16(chunk);
    final samples = Float32List(pcmSamples.length);
    for (var i = 0; i < pcmSamples.length; i++) {
      samples[i] = pcmSamples[i] / 32768.0;
    }
    return samples;
  }

  Future<String?> _transcribeSamples(Float32List samples, int sampleRate) async {
    if (_modelDirPath == null) {
      throw Exception('STT model directory is not initialized');
    }

    final expected = await _modelRepository.getExpectedFilePaths();
    final encoder = expected['encoder']!;
    final decoder = expected['decoder']!;
    final tokens = expected['tokens']!;

    print(
      'STT transcribe: samples=${samples.length}, sampleRate=$sampleRate, mode=vad',
    );
    print('STT transcribe: encoder=$encoder');
    print('STT transcribe: decoder=$decoder');
    print('STT transcribe: tokens=$tokens');

    if (sampleRate <= 0 || samples.isEmpty) {
      print('STT transcribe: no samples available from detected speech segment');
      return null;
    }

    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        whisper: sherpa_onnx.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          language: 'en',
          task: 'transcribe',
        ),
        tokens: tokens,
        debug: true,
        modelType: 'whisper',
        numThreads: 2,
      ),
    );

    final recognizer = sherpa_onnx.OfflineRecognizer(config);
    final stream = recognizer.createStream();

    stream.acceptWaveform(
      samples: samples,
      sampleRate: sampleRate,
    );
    recognizer.decode(stream);

    final result = recognizer.getResult(stream);
    final text = result.text.trim();

    stream.free();
    recognizer.free();

    print('STT transcribe result: $text');
    return text.isEmpty ? null : text;
  }

  void _freeActiveVad() {
    final vad = _activeVad;
    _activeVad = null;
    vad?.free();
  }

  Future<void> _failActiveRecording(
    Object error,
    StackTrace stackTrace,
  ) async {
    final completer = _activeRecordingCompleter;
    _activeRecordingCompleter = null;

    _activeMaxTimer?.cancel();
    _activeMaxTimer = null;

    await _activeAudioStreamSubscription?.cancel();
    _activeAudioStreamSubscription = null;

    _freeActiveVad();

    if (await _recorder.isRecording()) {
      await _recorder.cancel();
    }

    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> cancel() async {
    print('STT cancel: cancelling active recording');
    final completer = _activeRecordingCompleter;
    _activeRecordingCompleter = null;

    _activeMaxTimer?.cancel();
    _activeMaxTimer = null;

    await _activeAudioStreamSubscription?.cancel();
    _activeAudioStreamSubscription = null;

    _freeActiveVad();

    if (await _recorder.isRecording()) {
      await _recorder.cancel();
    }

    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
