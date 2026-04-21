abstract class SttService {
  Future<void> initialize();
  Future<void> startRecording();
  Future<String?> recordUntilSilenceAndTranscribe({
    Duration maxDuration,
    Duration silenceDuration,
    Duration leadingSilenceGrace,
    double silenceThresholdDb,
  });
  Future<String?> stopRecordingAndTranscribe();
  Future<void> cancel();
  Future<void> dispose();
}