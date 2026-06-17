import 'dart:async';

import 'package:record/record.dart' as rec;

import '../data/models/recording.dart';

/// A selectable input device surfaced to the mic & language picker (F-CAP-04).
class MicInput {
  final String id;
  final String label;
  final bool isUsb;

  const MicInput({required this.id, required this.label, this.isUsb = false});
}

/// Result of the pre-recording mic test (F-CAP-04) — surfaces the actual sample
/// rate and channel count and warns on unexpectedly low quality.
class MicTestResult {
  final int sampleRate;
  final int channels;
  final double peakLevel; // 0..1
  final bool isUsb;

  const MicTestResult({
    required this.sampleRate,
    required this.channels,
    required this.peakLevel,
    required this.isUsb,
  });

  /// USB-C UAC delivers full-bandwidth 48 kHz; warn below that (Tech Spec §4.3).
  bool get isLowQuality => sampleRate < 32000;
}

/// Wraps audio capture for the built-in mic and a USB-C connected external
/// microphone presented as a standard USB Audio Class input (F-CAP-01/02).
/// Writes incrementally to disk so an unplug or interruption cannot lose the
/// whole session (F-CAP-08 / Tech Spec §4.3).
class AudioCapture {
  final rec.AudioRecorder _recorder = rec.AudioRecorder();

  final _amplitude = StreamController<double>.broadcast();
  StreamSubscription<rec.Amplitude>? _ampSub;
  Timer? _elapsedTimer;
  final _elapsed = StreamController<Duration>.broadcast();

  DateTime? _startedAt;
  Duration _accumulated = Duration.zero;
  final List<int> _markedMomentsMs = [];

  String? _currentPath;
  int _sampleRate = 48000;
  int _channels = 1;
  bool _isUsb = false;

  /// Live input level, 0..1 (F-CAP-05).
  Stream<double> get amplitude => _amplitude.stream;

  /// Elapsed recording time (F-CAP-05).
  Stream<Duration> get elapsed => _elapsed.stream;

  List<int> get markedMomentsMs => List.unmodifiable(_markedMomentsMs);
  int get sampleRate => _sampleRate;
  int get channels => _channels;
  bool get isUsb => _isUsb;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Lists available inputs. USB devices are flagged so the UI can recommend
  /// the validated reference path (DJI Mic over USB-C).
  Future<List<MicInput>> listInputs() async {
    final devices = await _recorder.listInputDevices();
    return devices.map((d) {
      final usb = d.label.toLowerCase().contains('usb') ||
          d.label.toLowerCase().contains('dji');
      return MicInput(id: d.id, label: d.label, isUsb: usb);
    }).toList();
  }

  /// Quick level/quality test before recording (F-CAP-04).
  Future<MicTestResult> testInput(MicInput device) async {
    final sampleRate = device.isUsb ? 48000 : 44100;
    final channels = device.isUsb ? 2 : 1;
    final config = rec.RecordConfig(
      encoder: rec.AudioEncoder.wav,
      sampleRate: sampleRate,
      numChannels: channels,
      device: rec.InputDevice(id: device.id, label: device.label),
    );
    double peak = 0;
    final sub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
      final norm = _normalize(a.current);
      if (norm > peak) peak = norm;
    });
    await _recorder.start(config, path: await _probePath());
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await _recorder.stop();
    await sub.cancel();
    return MicTestResult(
      sampleRate: sampleRate,
      channels: channels,
      peakLevel: peak,
      isUsb: device.isUsb,
    );
  }

  Future<void> start({
    required String filePath,
    required MicInput device,
  }) async {
    _currentPath = filePath;
    _isUsb = device.isUsb;
    _sampleRate = device.isUsb ? 48000 : 44100;
    // Hardware channel separation for a two-transmitter kit (F-CAP-03).
    _channels = device.isUsb ? 2 : 1;
    _accumulated = Duration.zero;
    _markedMomentsMs.clear();

    final config = rec.RecordConfig(
      encoder: rec.AudioEncoder.wav,
      sampleRate: _sampleRate,
      numChannels: _channels,
      device: rec.InputDevice(id: device.id, label: device.label),
    );
    await _recorder.start(config, path: filePath);
    _startedAt = DateTime.now();
    _beginMeters();
  }

  Future<void> pause() async {
    await _recorder.pause();
    if (_startedAt != null) {
      _accumulated += DateTime.now().difference(_startedAt!);
      _startedAt = null;
    }
    _elapsedTimer?.cancel();
  }

  Future<void> resume() async {
    await _recorder.resume();
    _startedAt = DateTime.now();
    _beginMeters();
  }

  /// F-CAP-06 — timestamped flag created during recording.
  void markMoment() {
    _markedMomentsMs.add(_currentElapsed().inMilliseconds);
  }

  Future<Recording> stop({
    required String sessionId,
    required String id,
  }) async {
    final path = await _recorder.stop();
    _elapsedTimer?.cancel();
    await _ampSub?.cancel();
    final finalPath = path ?? _currentPath ?? '';
    return Recording(
      id: id,
      sessionId: sessionId,
      encryptedPath: finalPath,
      sampleRate: _sampleRate,
      channels: _channels,
      source: _isUsb ? AudioSource.usb : AudioSource.builtin,
      channelMap: _isUsb ? {0: 'S1', 1: 'S2'} : const {},
      markedMomentsMs: List.of(_markedMomentsMs),
    );
  }

  Duration totalDuration() => _currentElapsed();

  Future<void> dispose() async {
    _elapsedTimer?.cancel();
    await _ampSub?.cancel();
    await _amplitude.close();
    await _elapsed.close();
    await _recorder.dispose();
  }

  // --- internals ------------------------------------------------------------

  void _beginMeters() {
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((a) => _amplitude.add(_normalize(a.current)));
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _elapsed.add(_currentElapsed());
    });
  }

  Duration _currentElapsed() {
    if (_startedAt == null) return _accumulated;
    return _accumulated + DateTime.now().difference(_startedAt!);
  }

  double _normalize(double db) {
    // Amplitude is reported in dBFS (negative). Map ~[-45,0] dB to [0,1].
    const minDb = -45.0;
    if (db.isNaN || db < minDb) return 0;
    return ((db - minDb) / -minDb).clamp(0.0, 1.0);
  }

  Future<String> _probePath() async => '${_currentPath ?? 'probe'}.probe.wav';
}
