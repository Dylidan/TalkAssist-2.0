import "dart:async";
import "dart:io";
import "dart:math" as math;
import "dart:typed_data";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";

enum StatusSound { thinking, ready }

/// Plays short non-speech cues for voice-mode handoffs.
class StatusSoundService {
  StatusSoundService({AudioPlayer? audioPlayer})
    : _audioPlayer = audioPlayer ?? AudioPlayer() {
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  static const int _sampleRate = 44100;
  static const double _volume = 0.26;

  final AudioPlayer _audioPlayer;
  final Map<StatusSound, String> _cachedPaths = <StatusSound, String>{};

  bool _disposed = false;

  Future<void> playThinkingCue() {
    return _play(StatusSound.thinking, awaitCompletion: false);
  }

  Future<void> playReadyCue() {
    return _play(StatusSound.ready, awaitCompletion: true);
  }

  Future<void> _play(StatusSound sound, {required bool awaitCompletion}) async {
    if (_disposed) {
      return;
    }

    try {
      final path = await _ensureSoundFile(sound);
      await _audioPlayer.stop();

      final completion = Completer<void>();
      late final StreamSubscription<void> completeSubscription;
      late final StreamSubscription<PlayerState> stateSubscription;

      completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        if (!completion.isCompleted) {
          completion.complete();
        }
      });
      stateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
        if ((state == PlayerState.stopped || state == PlayerState.completed) &&
            !completion.isCompleted) {
          completion.complete();
        }
      });

      try {
        await _audioPlayer.play(DeviceFileSource(path), volume: 1.0);
        if (awaitCompletion) {
          await completion.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        }
      } finally {
        await completeSubscription.cancel();
        await stateSubscription.cancel();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("STATUS SOUND: skipped $sound cue: $e");
      }
    }
  }

  Future<String> _ensureSoundFile(StatusSound sound) async {
    final cachedPath = _cachedPaths[sound];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }

    final tempDir = await getTemporaryDirectory();
    final path = "${tempDir.path}/talk_assist_${sound.name}_cue.wav";
    final file = File(path);
    await file.writeAsBytes(_wavBytesFor(sound), flush: true);
    _cachedPaths[sound] = path;
    return path;
  }

  Uint8List _wavBytesFor(StatusSound sound) {
    switch (sound) {
      case StatusSound.thinking:
        return _buildToneSequence(const <_Tone>[
          _Tone(frequency: 620, durationMs: 65, pauseAfterMs: 35),
          _Tone(frequency: 840, durationMs: 85, pauseAfterMs: 35),
        ]);
      case StatusSound.ready:
        return _buildToneSequence(const <_Tone>[
          _Tone(frequency: 920, durationMs: 70, pauseAfterMs: 35),
          _Tone(frequency: 700, durationMs: 95, pauseAfterMs: 35),
        ]);
    }
  }

  Uint8List _buildToneSequence(List<_Tone> tones) {
    const int bytesPerSample = 2;
    final samples = <int>[];

    for (final tone in tones) {
      final sampleCount = (_sampleRate * tone.durationMs / 1000).round();
      final fadeSamples = math.min((_sampleRate * 0.012).round(), sampleCount);

      for (var index = 0; index < sampleCount; index += 1) {
        final time = index / _sampleRate;
        final fadeIn = fadeSamples == 0 ? 1.0 : index / fadeSamples;
        final fadeOut = fadeSamples == 0
            ? 1.0
            : (sampleCount - index) / fadeSamples;
        final envelope = math.min(1.0, math.min(fadeIn, fadeOut));
        final wave = math.sin(2 * math.pi * tone.frequency * time);
        samples.add((wave * envelope * _volume * 32767).round());
      }

      final pauseSamples = (_sampleRate * tone.pauseAfterMs / 1000).round();
      samples.addAll(List<int>.filled(pauseSamples, 0));
    }

    final dataLength = samples.length * bytesPerSample;
    final bytes = BytesBuilder();
    bytes.add(_ascii("RIFF"));
    bytes.add(_uint32(36 + dataLength));
    bytes.add(_ascii("WAVE"));
    bytes.add(_ascii("fmt "));
    bytes.add(_uint32(16));
    bytes.add(_uint16(1));
    bytes.add(_uint16(1));
    bytes.add(_uint32(_sampleRate));
    bytes.add(_uint32(_sampleRate * bytesPerSample));
    bytes.add(_uint16(bytesPerSample));
    bytes.add(_uint16(16));
    bytes.add(_ascii("data"));
    bytes.add(_uint32(dataLength));

    final pcm = ByteData(dataLength);
    for (var index = 0; index < samples.length; index += 1) {
      pcm.setInt16(index * bytesPerSample, samples[index], Endian.little);
    }
    bytes.add(pcm.buffer.asUint8List());
    return bytes.toBytes();
  }

  Uint8List _ascii(String value) {
    return Uint8List.fromList(value.codeUnits);
  }

  Uint8List _uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _audioPlayer.dispose();
  }
}

class _Tone {
  const _Tone({
    required this.frequency,
    required this.durationMs,
    required this.pauseAfterMs,
  });

  final double frequency;
  final int durationMs;
  final int pauseAfterMs;
}
