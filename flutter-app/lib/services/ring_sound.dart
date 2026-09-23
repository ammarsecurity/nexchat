import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// utils/sounds.js — the same four-tone ring (C5/E5), repeated every 2.2s.
class RingSound {
  RingSound._();

  static AudioPlayer? _player;
  static Uint8List? _wav;
  static int _generation = 0;

  static Uint8List _build() {
    const rate = 22050;
    const total = 2.2;
    final samples = Float64List((rate * total).round());
    void tone(double freq, double start, double duration) {
      final s0 = (start * rate).round();
      final n = (duration * rate).round();
      for (var i = 0; i < n && s0 + i < samples.length; i++) {
        final t = i / rate;
        final gain = 0.25 * math.pow(0.01 / 0.25, t / duration);
        samples[s0 + i] += gain * math.sin(2 * math.pi * freq * t);
      }
    }

    tone(523.25, 0, 0.2);
    tone(659.25, 0.25, 0.2);
    tone(523.25, 0.55, 0.2);
    tone(659.25, 0.8, 0.25);

    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Future<void> start() async {
    final gen = ++_generation;
    await _release();
    if (gen != _generation) return;
    final p = AudioPlayer();
    _player = p;
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      if (gen != _generation) return;
      await p.play(BytesSource(_wav ??= _build(), mimeType: 'audio/wav'));
    } catch (_) {}
    if (gen != _generation) await _dispose(p);
  }

  static Future<void> stop() async {
    _generation++;
    await _release();
  }

  static Future<void> _release() async {
    final p = _player;
    _player = null;
    if (p != null) await _dispose(p);
  }

  static Future<void> _dispose(AudioPlayer p) async {
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}
