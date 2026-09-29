import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../artifacts.dart';
import '../temp_dirs.dart';
import '../video.dart';
import '../video_recorder.dart';

/// Records a smoke scenario as it runs: real frames of the app captured at a
/// fixed rate while the test drives it. Every smoke video is at least 10 s of
/// the scenario happening, 1024×768 or larger, at 30 fps.
///
/// Frames go straight to a temporary raw file (a 1600×1000 frame is 6 MB),
/// at full resolution and 30 fps, and are encoded to high-quality WebM on
/// [save].
///
/// ```dart
/// final rec = SmokeRecorder(tester, boundary: find.byKey(boundaryKey));
/// await rec.hold(const Duration(seconds: 2));   // the opening state
/// await tester.tap(...);                        // a step
/// await rec.hold(const Duration(milliseconds: 1500));
/// rec.save(name);                               // throws under 10 s
/// ```
class SmokeRecorder {
  final WidgetTester tester;
  final Finder boundary;

  /// Time between captured frames, and so each frame's length in the video.
  final Duration frameInterval;

  /// Capture scale relative to the window's logical size: at least 1.0, and
  /// raised so a frame is never smaller than [SmokeArtifacts.minimumVideoWidth]
  /// × [SmokeArtifacts.minimumVideoHeight] (the UI is re-rasterised, so text
  /// stays sharp).
  final double pixelRatio;

  SmokeRecorder(
    this.tester, {
    required this.boundary,
    this.frameInterval = const Duration(microseconds: 33333), // 30 fps
    this.pixelRatio = 1.0,
  }) {
    SmokeTempDirs.purgeStale('smoke_');
    _dir = Directory.systemTemp.createTempSync(tempPrefix);
    // The raw frames run to gigabytes (a 1920×1080 frame is 8 MB) and the
    // temp directory may be RAM: a test that fails before [save] must not
    // leave them behind.
    addTearDown(_discard);
  }

  /// The prefix of every recorder's temporary directory.
  static const String tempPrefix = 'smoke_recorder_';

  late final Directory _dir;
  late final RandomAccessFile _raw = File('${_dir.path}/frames.rgba').openSync(mode: FileMode.write);
  bool _closed = false;
  int _frames = 0;

  void _close() {
    if (_closed) return;
    _closed = true;
    _raw.closeSync();
  }

  void _discard() {
    _close();
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }

  int? _width;
  int? _height;
  Uint8List? _lastFrame;
  int _stillRun = 0;
  int _longestStillRun = 0;

  /// The longest stretch of byte-identical frames recorded so far: how long
  /// the video shows one unchanging picture (never more than
  /// [SmokeVideo.maximumFrameHoldSeconds]).
  Duration get longestStill => frameInterval * _longestStillRun;

  int get frameCount => _frames;

  /// Length of the video recorded so far.
  Duration get recorded => frameInterval * _frames;

  /// Captures the current frame of the app.
  Future<void> capture() async {
    await _capture();
  }

  Future<bool> _capture({bool skipIfUnchanged = false}) async {
    final element = boundary.evaluate().firstOrNull;
    if (element == null) return false;
    final render = element.renderObject;
    if (render is! RenderRepaintBoundary || render.debugNeedsPaint) return false;
    final size = render.size;
    final ratio = [
      pixelRatio,
      SmokeArtifacts.minimumVideoWidth / size.width,
      SmokeArtifacts.minimumVideoHeight / size.height,
    ].reduce((a, b) => a > b ? a : b);
    final frame = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final size = (image.width, image.height);
      image.dispose();
      return data == null ? null : (size, data.buffer.asUint8List());
    });
    if (frame == null) return false;
    final ((w, h), bytes) = frame;
    _width ??= w;
    _height ??= h;
    // A resized window cannot join the same stream.
    if (w != _width || h != _height || _closed) return false;
    final last = _lastFrame;
    final same = last != null && SmokeVideoRecorder.sameBytes(last, bytes);
    if (skipIfUnchanged && same) return false;
    _raw.writeFromSync(bytes);
    _lastFrame = bytes;
    _frames++;
    _stillRun = same ? _stillRun + 1 : 1;
    if (_stillRun > _longestStillRun) _longestStillRun = _stillRun;
    return true;
  }

  /// Captures the current frame only if it differs from the last one
  /// captured. For long waits recorded as a time-lapse: a still screen adds
  /// nothing, so it is never padded out with copies of the same frame.
  /// Returns whether a frame was added.
  Future<bool> captureIfChanged() => _capture(skipIfUnchanged: true);

  /// Keeps the app running for [duration] in real time, capturing a frame
  /// every [frameInterval]: the scenario's time on screen.
  Future<void> hold(Duration duration) async {
    final count = (duration.inMicroseconds / frameInterval.inMicroseconds).ceil();
    for (var i = 0; i < count; i++) {
      await tester.pump(frameInterval);
      await tester.runAsync(() => Future<void>.delayed(frameInterval));
      await capture();
    }
  }

  /// Types [text] into [field] the way a user does, one character at a time,
  /// with the field updating on video as it goes. Each prefix goes through
  /// [WidgetTester.enterText], so the field's `onChanged` fires per keystroke.
  Future<void> typeText(Finder field, String text, {Duration perCharacter = const Duration(milliseconds: 100)}) async {
    // Pinned to the element found now: a finder that matches on the field's
    // text or placeholder stops matching after the first keystroke. (.first:
    // some text fields nest a second one under the same text.)
    final element = field.evaluate().first;
    final pinned = find.byElementPredicate((e) => identical(e, element));
    for (var i = 1; i <= text.length; i++) {
      await tester.enterText(pinned, text.substring(0, i));
      await hold(perCharacter);
    }
  }

  /// Drags a pointer from [from] to [to] in [steps] moves, recording every
  /// step: the drag plays out on video at the pace a hand would move.
  Future<void> drag(
    Offset from,
    Offset to, {
    int steps = 30,
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int buttons = kPrimaryButton,
  }) async {
    final gesture = await tester.startGesture(from, kind: kind, buttons: buttons);
    await hold(frameInterval * 2);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
      await hold(frameInterval);
    }
    await gesture.up();
    await hold(frameInterval * 2);
  }

  /// Encodes the recording and saves it as [testName]'s video. Throws when it
  /// is shorter than [SmokeArtifacts.minimumVideoSeconds] or smaller than
  /// [SmokeArtifacts.minimumVideoWidth] × [SmokeArtifacts.minimumVideoHeight].
  File save(String testName, {List<String>? usedAssets}) {
    _close();
    final seconds = recorded.inMicroseconds / 1e6;
    try {
      if (_frames > 0 && SmokeVideo.isTooSmall(_width!, _height!)) {
        throw StateError('Smoke video "$testName" is $_width×$_height; smoke videos must be at least '
            '${SmokeArtifacts.minimumVideoWidth}×${SmokeArtifacts.minimumVideoHeight}.');
      }
      if (SmokeVideo.isTooShort(seconds)) {
        throw StateError(
          'Smoke video "$testName" is ${seconds.toStringAsFixed(2)} s; smoke videos must be at least '
          '${SmokeArtifacts.minimumVideoSeconds.toStringAsFixed(0)} s of the scenario running. Extend the scenario '
          "with more real steps; hold() only to show a step's result.",
        );
      }
      final bytes = SmokeArtifacts.encodeWebmFromRawFile(
        File('${_dir.path}/frames.rgba'),
        width: _width!,
        height: _height!,
        frameDurationMs: frameInterval.inMilliseconds,
        framesPerSecond: (1e6 / frameInterval.inMicroseconds).round(),
      );
      final video = SmokeArtifacts.saveVideoToDir(testName, bytes, SmokeArtifacts.dir, usedAssets: usedAssets);
      // Next to the length in the sidecar, so a still stretch is visible
      // without decoding the video.
      SmokeArtifacts.annotate(testName, {'longestStillSeconds': longestStill.inMicroseconds / 1e6},
          targetDir: video.parent);
      // ignore: avoid_print
      print('[SmokeRecorder] "$testName": ${seconds.toStringAsFixed(2)} s, longest still '
          '${(longestStill.inMicroseconds / 1e6).toStringAsFixed(2)} s');
      return video;
    } finally {
      _discard();
    }
  }
}
