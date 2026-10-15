import 'dart:typed_data';

import 'package:record/record.dart';

/// Microphone access. Capture starts only after the user taps the mic and
/// streams PCM16 mono 24 kHz in memory; nothing is written to storage.
abstract interface class VoiceCapture {
  /// Asks for microphone permission when needed. False when refused.
  Future<bool> ensurePermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordVoiceCapture implements VoiceCapture {
  final _recorder = AudioRecorder();

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 24000,
      numChannels: 1,
      noiseSuppress: true,
      echoCancel: true,
    ),
  );

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
