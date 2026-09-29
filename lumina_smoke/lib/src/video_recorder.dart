import 'dart:io';
import 'dart:typed_data';

import 'temp_dirs.dart';
import 'video.dart';
import 'webm.dart';

/// Records a smoke video frame by frame while the scenario runs, then encodes
/// it with [SmokeWebm.vp8QualitySettings] at the frames' own resolution.
///
/// Frames stream to a temporary file instead of piling up in memory, so a
/// long recording costs one frame of heap. The smoke-video rules are enforced
/// with a [StateError] naming [testName]: the constructor refuses a size under
/// [SmokeVideo.minimumWidth] × [SmokeVideo.minimumHeight] or a rate under
/// [SmokeVideo.minimumFps], and [finish] a video under
/// [SmokeVideo.minimumSeconds] or one holding a frame longer than
/// [SmokeVideo.maximumFrameHoldSeconds].
class SmokeVideoRecorder {
  /// A recorder for [width] × [height] frames played at [fps] frames per
  /// second or, when [frameDurationMs] is given, each shown that many
  /// milliseconds (1000 / [frameDurationMs] fps).
  SmokeVideoRecorder({
    required this.width,
    required this.height,
    int fps = SmokeVideo.minimumFps,
    int? frameDurationMs,
    this.testName,
  })  : _rateNumerator = frameDurationMs == null ? fps : 1000,
        _rateDenominator = frameDurationMs ?? 1 {
    if (SmokeVideo.isTooSmall(width, height)) {
      throw StateError(
        '$_label is $width×$height; smoke videos must be at least '
        '${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}: render the scene at that size or larger.',
      );
    }
    if (_rateNumerator <= 0 || _rateDenominator <= 0) {
      throw StateError('$_label: the frame rate must be positive (fps $fps, frameDurationMs $frameDurationMs).');
    }
    if (SmokeVideo.isTooSlow(framesPerSecond)) {
      throw StateError(
        '$_label plays at ${framesPerSecond.toStringAsFixed(2)} fps; smoke videos must play at least '
        '${SmokeVideo.minimumFps} real frames per second: capture the scene that often while it runs.',
      );
    }
    purgeStaleSmokeTempDirs();
    _dir = Directory.systemTemp.createTempSync('smoke_video_');
    _raw = File('${_dir.path}/frames.rgba').openSync(mode: FileMode.write);
  }

  /// Deletes `smoke_*` temp directories in which nothing was written for
  /// [olderThan], once per process (see [SmokeTempDirs.purgeStale]).
  static void purgeStaleSmokeTempDirs({Duration olderThan = const Duration(minutes: 30)}) =>
      SmokeTempDirs.purgeStale('smoke_', olderThan: olderThan);

  final int width;
  final int height;
  final String? testName;

  // The frame rate as a fraction, so a video runs exactly frames / rate.
  final int _rateNumerator;
  final int _rateDenominator;

  /// Frames per second the video plays at.
  double get framesPerSecond => _rateNumerator / _rateDenominator;

  late final Directory _dir;
  late final RandomAccessFile _raw;
  bool _closed = false;
  int _frames = 0;
  Uint8List? _previous;
  int _run = 0;
  int _longestRun = 0;

  String get _label => testName == null ? 'Smoke video' : 'Smoke video "$testName"';

  /// Frames recorded so far.
  int get frameCount => _frames;

  /// The length of the video so far, in seconds.
  double get seconds => _frames * _rateDenominator / _rateNumerator;

  /// The longest stretch one unchanged frame stays on screen so far, in
  /// seconds.
  double get longestStillSeconds => _longestRun * _rateDenominator / _rateNumerator;

  /// Appends one RGBA8 frame of [width] × [height]. [rgba] is copied, so a
  /// reused read-back buffer is fine.
  void addFrame(Uint8List rgba) {
    if (_closed) throw StateError('$_label: already finished.');
    final expected = width * height * 4;
    if (rgba.length != expected) {
      throw StateError('$_label: a frame has ${rgba.length} bytes, expected $expected for ${width}x$height RGBA.');
    }
    _raw.writeFromSync(rgba);
    final previous = _previous;
    _run = previous != null && sameBytes(previous, rgba) ? _run + 1 : 1;
    if (_run > _longestRun) _longestRun = _run;
    if (previous != null && previous.length == rgba.length) {
      previous.setAll(0, rgba);
    } else {
      _previous = Uint8List.fromList(rgba);
    }
    _frames++;
  }

  /// Checks the smoke-video rules and encodes the recording to WebM bytes.
  Uint8List finish() {
    if (_closed) throw StateError('$_label: already finished.');
    _closed = true;
    _raw.closeSync();
    try {
      if (SmokeVideo.isTooShort(seconds)) {
        throw StateError(
          '$_label is ${seconds.toStringAsFixed(2)} s ($_frames frames at ${framesPerSecond.toStringAsFixed(2)} fps); '
          'smoke videos must run at least ${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s of frames captured '
          'while the scenario runs.',
        );
      }
      final held = longestStillSeconds;
      if (held > SmokeVideo.maximumFrameHoldSeconds) {
        throw StateError(
          '$_label holds one frame for ${held.toStringAsFixed(2)} s; no frame may stay on screen longer than '
          '${SmokeVideo.maximumFrameHoldSeconds.toStringAsFixed(0)} s: capture the scene while it runs.',
        );
      }
      final out = File('${_dir.path}/out.webm');
      final ProcessResult result;
      try {
        result = SmokeWebm.encodeRawRgba(
          rawFrames: '${_dir.path}/frames.rgba',
          out: out.path,
          width: width,
          height: height,
          rateNumerator: _rateNumerator,
          rateDenominator: _rateDenominator,
        );
      } on ProcessException catch (e) {
        throw StateError('$_label: GStreamer (with vp8enc / webmmux) or ffmpeg (libvpx) is needed to encode it: $e');
      }
      if (result.exitCode != 0 || !out.existsSync() || out.lengthSync() == 0) {
        throw StateError('$_label: WebM encoding failed (exit ${result.exitCode}): ${result.stderr}');
      }
      return out.readAsBytesSync();
    } finally {
      discard();
    }
  }

  /// Deletes the temporary recording; safe to call more than once.
  void discard() {
    if (!_closed) {
      _closed = true;
      try {
        _raw.closeSync();
      } catch (_) {}
    }
    _previous = null;
    try {
      if (_dir.existsSync()) _dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Whether [a] and [b] hold the same bytes (compared eight at a time when
  /// both are 8-byte aligned).
  static bool sameBytes(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    if (a.offsetInBytes % 8 == 0 && b.offsetInBytes % 8 == 0) {
      final words = a.length ~/ 8;
      final wa = a.buffer.asUint64List(a.offsetInBytes, words);
      final wb = b.buffer.asUint64List(b.offsetInBytes, words);
      for (var i = 0; i < words; i++) {
        if (wa[i] != wb[i]) return false;
      }
      for (var i = words * 8; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
