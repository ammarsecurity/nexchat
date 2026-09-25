import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

enum RingKind {
  /// Incoming alert — bright C5/E5 chirps (existing feel).
  incoming,

  /// Outgoing dial while waiting for answer — warmer, spaced dual-tone.
  outgoing,

  /// Peer busy — short classic busy beeps (plays once, no loop).
  busy,
}

/// Procedural call tones (incoming / outgoing / busy).
class RingSound {
  RingSound._();

  static AudioPlayer? _player;
  static final Map<RingKind, Uint8List> _wav = {};
  static int _generation = 0;
  static RingKind? _playing;

  static Uint8List _buildIncoming() {
    const rate = 22050;
    const total = 2.2;
    final samples = Float64List((rate * total).round());
    void tone(double freq, double start, double duration) {
      final s0 = (start * rate).round();
      final n = (duration * rate).round();
      for (var i = 0; i < n && s0 + i < samples.length; i++) {
        final t = i / rate;
        final gain = 0.22 * math.pow(0.02 / 0.22, t / duration);
        samples[s0 + i] += gain * math.sin(2 * math.pi * freq * t);
      }
    }

    tone(523.25, 0, 0.2);
    tone(659.25, 0.25, 0.2);
    tone(523.25, 0.55, 0.2);
    tone(659.25, 0.8, 0.25);
    return _toWav(samples, rate);
  }

  /// Soft dual-tone ring (≈440+480) with gentle fade — WhatsApp-like outgoing.
  static Uint8List _buildOutgoing() {
    const rate = 22050;
    const total = 4.0;
    final samples = Float64List((rate * total).round());

    void dual(double start, double duration) {
      final s0 = (start * rate).round();
      final n = (duration * rate).round();
      for (var i = 0; i < n && s0 + i < samples.length; i++) {
        final t = i / rate;
        final attack = (t / 0.04).clamp(0.0, 1.0);
        final release = ((duration - t) / 0.08).clamp(0.0, 1.0);
        final env = attack * release;
        final a = math.sin(2 * math.pi * 440 * t);
        final b = math.sin(2 * math.pi * 480 * t);
        samples[s0 + i] += 0.18 * env * (0.55 * a + 0.45 * b);
      }
    }

    // Ring · pause · ring · longer pause (loop feels natural).
    dual(0.15, 1.05);
    dual(1.45, 1.05);
    return _toWav(samples, rate);
  }

  /// Classic busy: 0.4s on / 0.4s off × 3.
  static Uint8List _buildBusy() {
    const rate = 22050;
    const total = 2.6;
    final samples = Float64List((rate * total).round());
    for (var beat = 0; beat < 3; beat++) {
      final start = beat * 0.8;
      final s0 = (start * rate).round();
      final n = (0.4 * rate).round();
      for (var i = 0; i < n && s0 + i < samples.length; i++) {
        final t = i / rate;
        final env = (t < 0.02 ? t / 0.02 : ((0.4 - t) < 0.03 ? (0.4 - t) / 0.03 : 1.0)).clamp(0.0, 1.0);
        samples[s0 + i] += 0.2 * env * math.sin(2 * math.pi * 480 * t);
      }
    }
    return _toWav(samples, rate);
  }

  static Uint8List _wavFor(RingKind kind) => _wav.putIfAbsent(kind, () {
        switch (kind) {
          case RingKind.incoming:
            return _buildIncoming();
          case RingKind.outgoing:
            return _buildOutgoing();
          case RingKind.busy:
            return _buildBusy();
        }
      });

  static Uint8List _toWav(Float64List samples, int rate) {
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

  static Future<void> start([RingKind kind = RingKind.incoming]) async {
    if (kind == RingKind.busy) {
      await playBusy();
      return;
    }
    if (_playing == kind && _player != null) return;
    final gen = ++_generation;
    await _release();
    if (gen != _generation) return;
    final p = AudioPlayer();
    _player = p;
    _playing = kind;
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      if (gen != _generation) return;
      await p.play(BytesSource(_wavFor(kind), mimeType: 'audio/wav'));
    } catch (_) {}
    if (gen != _generation) await _dispose(p);
  }

  /// One-shot busy signal (stops looping tones first).
  static Future<void> playBusy() async {
    final gen = ++_generation;
    await _release();
    if (gen != _generation) return;
    final p = AudioPlayer();
    _player = p;
    _playing = RingKind.busy;
    try {
      await p.setReleaseMode(ReleaseMode.release);
      if (gen != _generation) return;
      await p.play(BytesSource(_wavFor(RingKind.busy), mimeType: 'audio/wav'));
      await Future.any([
        p.onPlayerComplete.first,
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);
    } catch (_) {}
    if (gen == _generation) await _release();
  }

  static Future<void> stop() async {
    _generation++;
    _playing = null;
    await _release();
  }

  static Future<void> _release() async {
    final p = _player;
    _player = null;
    _playing = null;
    if (p != null) await _dispose(p);
  }

  static Future<void> _dispose(AudioPlayer p) async {
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}
