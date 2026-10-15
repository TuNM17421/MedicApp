import 'dart:math' as math;
import 'dart:typed_data';

/// Client-side end-of-turn detection on PCM16 mono audio.
///
/// `gpt-live-transcribe` has no server VAD, so the app commits a turn after
/// [silence] of quiet that follows at least [minSpeech] of speech. The
/// threshold adapts to background noise. Starting values follow PRD §5.4
/// (1.5–2 s) and still need tuning with slow speakers on the OPPO device.
class SilenceDetector {
  SilenceDetector({
    this.sampleRate = 24000,
    this.silence = const Duration(milliseconds: 1700),
    this.minSpeech = const Duration(milliseconds: 250),
    this.minLevel = 450,
  });
  final int sampleRate;
  final Duration silence, minSpeech;
  final double minLevel;

  double _noise = 300;
  int _speechMs = 0;
  int _quietMs = 0;

  bool get hasSpeech => _speechMs >= minSpeech.inMilliseconds;

  /// Root-mean-square level of little-endian PCM16 samples.
  static double level(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final s = data.getInt16(i * 2, Endian.little).toDouble();
      sum += s * s;
    }
    return math.sqrt(sum / samples);
  }

  /// Feeds one chunk; returns true when the current turn just ended.
  bool add(Uint8List pcm) {
    final ms = (pcm.lengthInBytes ~/ 2) * 1000 ~/ sampleRate;
    if (ms == 0) return false;
    final rms = level(pcm);
    final threshold = math.max(minLevel, _noise * 2.5);
    if (rms >= threshold) {
      _speechMs += ms;
      _quietMs = 0;
      return false;
    }
    // Track the noise floor only while quiet, slowly.
    _noise = _noise * 0.95 + rms * 0.05;
    if (!hasSpeech) {
      _speechMs = 0;
      return false;
    }
    _quietMs += ms;
    if (_quietMs >= silence.inMilliseconds) {
      reset();
      return true;
    }
    return false;
  }

  void reset() {
    _speechMs = 0;
    _quietMs = 0;
  }
}
