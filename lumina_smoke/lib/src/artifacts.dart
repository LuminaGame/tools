import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'png.dart';
import 'tools.dart';
import 'video.dart';
import 'video_recorder.dart';
import 'webm.dart';

/// Publishes smoke-test evidence: PNG screenshots and VP8 / WebM videos, each
/// with a sidecar JSON (`<sanitized name>.json`) that records the **declared
/// test name** the report matches it to (never file times), the files, the
/// video's measurements, the real 3D assets the scenario loaded
/// (`usedAssets`) and optional `metrics`.
///
/// Artifacts go to [dir]: `build/smoke_artifacts/` of the package under test,
/// or `LUMINA_SMOKE_OUT` (the report runner sets it). Every video is checked
/// against the smoke-video rules before anything is written: at least
/// [minimumVideoSeconds] long, [minimumVideoWidth] × [minimumVideoHeight],
/// [minimumVideoFps] fps, no frame held longer than [maximumFrameHoldSeconds].
abstract final class SmokeArtifacts {
  // ---------------------------------------------------------------------------
  // Directories
  // ---------------------------------------------------------------------------

  /// An in-process artifact directory for tests of the harness itself; wins
  /// over the environment. [clear] only works while it is set.
  static String? outputDirOverride;

  /// An in-process test-assets directory; wins over `LUMINA_TEST_ASSETS`.
  static String? testAssetsDirOverride;

  /// Sets (or, with null, clears) [outputDirOverride].
  static void overrideDirForTesting(Directory? d) => outputDirOverride = d?.path;

  /// The package under test: the nearest directory holding a `pubspec.yaml`,
  /// walking up from the working directory.
  static Directory get packageRoot {
    var dir = Directory.current.absolute;
    while (true) {
      if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) return dir;
      if (dir.parent.path == dir.path) return Directory.current.absolute;
      dir = dir.parent;
    }
  }

  /// The artifact directory, created on first use: [outputDirOverride], else
  /// `LUMINA_SMOKE_OUT` (or the older `LUMINA_UI_SMOKE_OUT` /
  /// `FILAMENT_SMOKE_OUT`), else `<package>/build/smoke_artifacts`.
  static Directory get dir {
    final env = Platform.environment;
    final path = outputDirOverride ??
        env['LUMINA_SMOKE_OUT'] ??
        env['LUMINA_UI_SMOKE_OUT'] ??
        env['FILAMENT_SMOKE_OUT'] ??
        '${packageRoot.path}${Platform.pathSeparator}build${Platform.pathSeparator}smoke_artifacts';
    final d = Directory(path);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// The shared real 3D test assets (`test-assets/`): [testAssetsDirOverride],
  /// else `LUMINA_TEST_ASSETS`, else the first `test-assets` directory found
  /// walking up from the package under test.
  static Directory get testAssetsDir {
    final configured = testAssetsDirOverride ?? Platform.environment['LUMINA_TEST_ASSETS'];
    if (configured != null && configured.isNotEmpty) return Directory(configured);
    for (final start in [packageRoot, Directory.current.absolute]) {
      var dir = start;
      while (true) {
        final candidate = Directory('${dir.path}${Platform.pathSeparator}test-assets');
        if (candidate.existsSync()) return candidate;
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    }
    return Directory('../test-assets');
  }

  /// A test name as a file name: lower case, every run of other characters
  /// than `a-z0-9` one `_`, no leading or trailing `_`.
  static String sanitizeTestName(String testName) => testName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  // ---------------------------------------------------------------------------
  // Assets the scenario loaded
  // ---------------------------------------------------------------------------

  static final Set<String> _recordedAssets = <String>{};

  /// Records a real 3D asset the running scenario loaded; every later save
  /// adds the recorded set to its sidecar's `usedAssets`.
  static void recordAsset(String path) => _recordedAssets.add(path);

  /// The assets recorded so far with [recordAsset], in insertion order.
  static List<String> get recordedAssets => List.unmodifiable(_recordedAssets);

  /// Forgets the recorded assets (call between independent scenarios).
  static void resetRecordedAssets() => _recordedAssets.clear();

  // ---------------------------------------------------------------------------
  // The smoke-video rules
  // ---------------------------------------------------------------------------

  /// Every smoke video runs at least this long.
  static const double minimumVideoSeconds = SmokeVideo.minimumSeconds;

  /// Longest time one frame may stay on screen, in seconds: a video must show
  /// the scenario happening, never one frame stretched.
  static const double maximumFrameHoldSeconds = SmokeVideo.maximumFrameHoldSeconds;

  /// Every smoke video plays at least this many real frames per second: a
  /// 10 s video is at least 300 rendered frames.
  static const double minimumVideoFps = 30.0;

  /// Every smoke video is at least [minimumVideoWidth] × [minimumVideoHeight].
  static const int minimumVideoWidth = SmokeVideo.minimumWidth;

  /// See [minimumVideoWidth].
  static const int minimumVideoHeight = SmokeVideo.minimumHeight;

  /// Playback length of [frameCount] frames at [fps].
  static double framesDurationSeconds(int frameCount, double fps) => frameCount / fps;

  /// Frames needed at [fps] for a video of at least [seconds].
  static int framesForSeconds(double fps, {double seconds = minimumVideoSeconds}) => (seconds * fps - 1e-9).ceil();

  /// Throws a [StateError] naming [testName] when [frameCount] frames at [fps]
  /// run shorter than [minimumVideoSeconds], hold each frame longer than
  /// [maximumFrameHoldSeconds] or play slower than [minimumVideoFps].
  static void checkVideoDuration(String testName, int frameCount, double fps) {
    final seconds = framesDurationSeconds(frameCount, fps);
    if (seconds + 1e-9 < minimumVideoSeconds) {
      throw StateError(
        'Smoke video "$testName" is ${seconds.toStringAsFixed(2)} s ($frameCount frames at ${_fmt(fps)} fps); every '
        'smoke video must run at least ${_fmt(minimumVideoSeconds)} s of frames captured while the scenario runs. '
        'Record at least ${framesForSeconds(fps)} frames.',
      );
    }
    final hold = 1 / fps;
    if (hold > maximumFrameHoldSeconds + 1e-9) {
      throw StateError(
        'Smoke video "$testName" holds each frame ${hold.toStringAsFixed(2)} s (${_fmt(fps)} fps); no frame may stay '
        'on screen longer than ${_fmt(maximumFrameHoldSeconds)} s. Capture more frames instead of stretching them.',
      );
    }
    checkVideoFps(testName, fps);
  }

  /// Throws a [StateError] naming [testName] when [fps] is under
  /// [minimumVideoFps] (allowing [SmokeVideo.fpsTolerance]).
  static void checkVideoFps(String testName, double fps) {
    if (SmokeVideo.isTooSlow(fps)) {
      throw StateError(
        'Smoke video "$testName" plays at ${fps.toStringAsFixed(2)} fps; smoke videos need at least '
        '${_fmt(minimumVideoFps)} real frames per second while the scene animates.',
      );
    }
  }

  /// Throws a [StateError] naming [testName] when a [width] × [height] video is
  /// smaller than [minimumVideoWidth] × [minimumVideoHeight].
  static void checkVideoSize(String testName, int width, int height) {
    if (SmokeVideo.isTooSmall(width, height)) {
      throw StateError(
        'Smoke video "$testName" is $width×$height; every smoke video must be at least '
        '$minimumVideoWidth×$minimumVideoHeight (render the scene at that size, do not upscale).',
      );
    }
  }

  /// Throws a [StateError] when a run of byte-identical consecutive frames in
  /// [pngFrames] stays on screen longer than [maximumFrameHoldSeconds] at
  /// [fps] (a frozen scenario padded out to the minimum length).
  static void checkFramesMove(String testName, List<Uint8List> pngFrames, double fps) {
    final maxRun = (maximumFrameHoldSeconds * fps + 1e-9).floor();
    var run = 1;
    for (var i = 1; i < pngFrames.length; i++) {
      run = SmokeVideoRecorder.sameBytes(pngFrames[i - 1], pngFrames[i]) ? run + 1 : 1;
      if (run > maxRun) {
        throw StateError(
          'Smoke video for "$testName" repeats one frame $run times from frame ${i - run + 1} '
          '(${(run / fps).toStringAsFixed(2)} s at ${_fmt(fps)} fps); no frame may stay on screen longer than '
          '${_fmt(maximumFrameHoldSeconds)} s. Capture frames while the scenario runs.',
        );
      }
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ---------------------------------------------------------------------------
  // PNG
  // ---------------------------------------------------------------------------

  /// Encodes [w] × [h] RGBA8 (or, with [bgra], BGRA8) pixels as a PNG;
  /// [flipY] flips GL-style bottom-up rows.
  static Uint8List encodePng(int w, int h, Uint8List rgba, {bool flipY = false, bool bgra = false}) =>
      SmokePng.encode(w, h, rgba, flipY: flipY, bgra: bgra);

  /// [encodePng] with the pixels first.
  static Uint8List encodeRgbaToPng(Uint8List rawPixels, int width, int height, {bool flipY = false, bool bgra = false}) =>
      SmokePng.encode(width, height, rawPixels, flipY: flipY, bgra: bgra);

  /// Width and height from a PNG's IHDR chunk; null when [png] is not a PNG.
  static (int, int)? pngSize(Uint8List png) => SmokePng.size(png);

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  /// See [SmokeWebm.vp8QualitySettings].
  static const List<String> vp8QualitySettings = SmokeWebm.vp8QualitySettings;

  /// See [SmokeWebm.ffmpegVp8QualitySettings].
  static const List<String> ffmpegVp8QualitySettings = SmokeWebm.ffmpegVp8QualitySettings;

  /// Whether a video encoder is available: GStreamer or ffmpeg.
  static bool get videoEncoderAvailable => SmokeWebm.available;

  /// Whether GStreamer encodes RGBA frames in-process here.
  static bool get gstreamerEncoderAvailable => SmokeWebm.gstreamerEncodesRgba;

  /// See [SmokeWebm.encodePngFrames].
  static Uint8List encodeWebmFromPngFrames(List<Uint8List> pngFrames, {double fps = minimumVideoFps}) =>
      SmokeWebm.encodePngFrames(pngFrames, fps: fps);

  /// See [SmokeWebm.encodeRawRgba].
  static ProcessResult encodeRawRgbaToWebm({
    required String rawFrames,
    required String out,
    required int width,
    required int height,
    required int rateNumerator,
    required int rateDenominator,
  }) =>
      SmokeWebm.encodeRawRgba(
        rawFrames: rawFrames,
        out: out,
        width: width,
        height: height,
        rateNumerator: rateNumerator,
        rateDenominator: rateDenominator,
      );

  /// See [SmokeWebm.encodeRawFile].
  static Uint8List encodeWebmFromRawFile(
    File rawFrames, {
    required int width,
    required int height,
    required int frameDurationMs,
    int? framesPerSecond,
  }) =>
      SmokeWebm.encodeRawFile(rawFrames,
          width: width, height: height, frameDurationMs: frameDurationMs, framesPerSecond: framesPerSecond);

  /// Encodes RGBA frames, played at [fps] (or each shown [frameDurationMs]),
  /// into a WebM at their own resolution through a [SmokeVideoRecorder], so
  /// the smoke-video rules apply and a breach throws a [StateError] naming
  /// [testName]. For long or large recordings, use a [SmokeVideoRecorder]
  /// directly: it streams the frames instead of holding them all.
  static Uint8List encodeWebmFromRgbaFrames({
    required int width,
    required int height,
    required List<Uint8List> frames,
    int fps = SmokeVideo.minimumFps,
    int? frameDurationMs,
    String? testName,
  }) {
    final recorder = SmokeVideoRecorder(
      width: width,
      height: height,
      fps: fps,
      frameDurationMs: frameDurationMs,
      testName: testName,
    );
    try {
      frames.forEach(recorder.addFrame);
      return recorder.finish();
    } finally {
      recorder.discard();
    }
  }

  // ---------------------------------------------------------------------------
  // Probing
  // ---------------------------------------------------------------------------

  /// Playback length, frame size and average frame rate of the video at
  /// [path] (see [SmokeVideo.probe]); null when nothing could be read.
  static ({double? seconds, int? width, int? height, double? fps})? probeVideo(String path) {
    final info = SmokeVideo.probe(File(path));
    if (info.isEmpty) return null;
    return (seconds: info.seconds, width: info.width, height: info.height, fps: info.fps);
  }

  /// Playback length of the video at [path] in seconds, or null.
  static double? probeVideoSeconds(String path) => SmokeVideo.probe(File(path)).seconds;

  /// A video's length in seconds, or null when it cannot be read.
  static double? videoDurationSeconds(File video) => SmokeVideo.probe(video).seconds;

  /// A video's frame rate, or null when it cannot be read.
  static double? videoFramesPerSecond(File video) => SmokeVideo.probe(video).fps;

  /// A video's frame size, or null when it cannot be read.
  static (int, int)? videoFrameSize(File video) {
    final info = SmokeVideo.probe(video);
    return info.width == null || info.height == null ? null : (info.width!, info.height!);
  }

  // ---------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------

  /// Writes a PNG as `<sanitized name>.png` in [dir] and merges its sidecar.
  static File saveScreenshot(
    String testName,
    Uint8List pngBytes, {
    List<String>? usedAssets,
    Map<String, Object?>? metrics,
  }) =>
      saveScreenshotToDir(testName, pngBytes, dir, usedAssets: usedAssets, metrics: metrics);

  /// [saveScreenshot] into [targetDir].
  static File saveScreenshotToDir(
    String testName,
    Uint8List pngBytes,
    Directory targetDir, {
    List<String>? usedAssets,
    Map<String, Object?>? metrics,
  }) {
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
    final name = sanitizeTestName(testName);
    final pngFile = File('${targetDir.path}${Platform.pathSeparator}$name.png')..writeAsBytesSync(pngBytes, flush: true);
    _mergeSidecar(targetDir, name, testName, {
      'file': '$name.png',
      'screenshot': '$name.png',
      'metrics': ?metrics,
    }, usedAssets);
    return pngFile;
  }

  /// Encodes PNG frames into a WebM and saves it like [saveVideo], recording
  /// `frameCount` and `fps`.
  ///
  /// Throws a [StateError] naming the test before anything is encoded when
  /// the video would run shorter than [minimumVideoSeconds], play slower than
  /// [minimumVideoFps], hold or repeat a frame longer than
  /// [maximumFrameHoldSeconds], or be smaller than [minimumVideoWidth] ×
  /// [minimumVideoHeight].
  static File saveVideoFromPngFrames(
    String testName,
    List<Uint8List> pngFrames, {
    double fps = minimumVideoFps,
    List<String>? usedAssets,
  }) {
    if (pngFrames.isEmpty) {
      throw ArgumentError.value(pngFrames, 'pngFrames', 'must contain at least one frame');
    }
    if (fps <= 0) throw ArgumentError.value(fps, 'fps', 'must be > 0');
    checkVideoDuration(testName, pngFrames.length, fps);
    final size = pngSize(pngFrames.first);
    if (size == null) throw ArgumentError.value(pngFrames, 'pngFrames', 'frame 0 is not a PNG');
    final (width, height) = size;
    for (var i = 1; i < pngFrames.length; i++) {
      if (pngSize(pngFrames[i]) != size) {
        throw ArgumentError.value(pngFrames, 'pngFrames', 'frame $i is not a ${width}x$height PNG like frame 0');
      }
    }
    checkVideoSize(testName, width, height);
    checkFramesMove(testName, pngFrames, fps);
    final bytes = encodeWebmFromPngFrames(pngFrames, fps: fps);
    final padded = !SmokeWebm.gstreamerEncodesPng; // ffmpeg pads odd sizes by one pixel
    return saveVideo(
      testName,
      bytes,
      usedAssets: usedAssets,
      frameCount: pngFrames.length,
      fps: fps,
      width: padded ? width + (width & 1) : width,
      height: padded ? height + (height & 1) : height,
    );
  }

  /// Writes an encoded video (WebM by default, MP4 with [extension]) as
  /// `<sanitized name>.<extension>` in [dir] and merges its sidecar.
  ///
  /// The length comes from [durationSeconds], else [frameCount] / [fps], else
  /// the file; the rate from [fps], else the file; the size from [width] /
  /// [height], else the file (see [SmokeVideo.probe]). A video under
  /// [minimumVideoSeconds], [minimumVideoFps] or [minimumVideoWidth] ×
  /// [minimumVideoHeight], or one whose length, rate or size cannot be
  /// determined, throws a [StateError] naming the test, and nothing is written.
  static File saveVideo(
    String testName,
    Uint8List videoBytes, {
    String extension = 'webm',
    List<String>? usedAssets,
    int? frameCount,
    double? fps,
    double? durationSeconds,
    int? width,
    int? height,
  }) =>
      saveVideoToDir(testName, videoBytes, dir,
          extension: extension,
          usedAssets: usedAssets,
          frameCount: frameCount,
          fps: fps,
          durationSeconds: durationSeconds,
          width: width,
          height: height);

  /// [saveVideo] under its older name.
  static File saveEncodedVideo(
    String testName,
    Uint8List videoBytes, {
    String extension = 'webm',
    List<String>? usedAssets,
    int? frameCount,
    double? fps,
    double? durationSeconds,
    int? width,
    int? height,
  }) =>
      saveVideoToDir(testName, videoBytes, dir,
          extension: extension,
          usedAssets: usedAssets,
          frameCount: frameCount,
          fps: fps,
          durationSeconds: durationSeconds,
          width: width,
          height: height);

  /// [saveVideo] into [targetDir].
  static File saveVideoToDir(
    String testName,
    Uint8List videoBytes,
    Directory targetDir, {
    String extension = 'webm',
    List<String>? usedAssets,
    int? frameCount,
    double? fps,
    double? durationSeconds,
    int? width,
    int? height,
  }) {
    double? seconds = durationSeconds;
    if (seconds == null && frameCount != null && fps != null) {
      checkVideoDuration(testName, frameCount, fps);
      seconds = framesDurationSeconds(frameCount, fps);
    }
    var info = SmokeVideoInfo(seconds: seconds, width: width, height: height, fps: fps);
    if (!info.isComplete) info = info.orElse(SmokeVideo.probeBytes(videoBytes, extension: extension));
    final measured = '.$extension, ${videoBytes.length} bytes, ${info.describe}';
    if (info.seconds == null) {
      throw StateError(
        'Cannot tell how long the smoke video "$testName" is ($measured): pass frameCount and fps (or '
        'durationSeconds), or install GStreamer or ffprobe. Every smoke video must run at least '
        '${_fmt(minimumVideoSeconds)} s.',
      );
    }
    if (SmokeVideo.isTooShort(info.seconds!)) {
      throw StateError(
        'Smoke video "$testName" is ${info.seconds!.toStringAsFixed(2)} s; every smoke video must run at least '
        '${_fmt(minimumVideoSeconds)} s of frames captured while the scenario runs.',
      );
    }
    if (info.fps == null) {
      throw StateError(
        'Cannot tell the frame rate of the smoke video "$testName" ($measured): pass fps, or install GStreamer or '
        'ffprobe. Every smoke video must play at ${_fmt(minimumVideoFps)} fps or more.',
      );
    }
    checkVideoFps(testName, info.fps!);
    if (info.width == null || info.height == null) {
      throw StateError(
        'Cannot tell the frame size of the smoke video "$testName" ($measured): pass width and height, or install '
        'GStreamer or ffprobe. Every smoke video must be at least $minimumVideoWidth×$minimumVideoHeight.',
      );
    }
    checkVideoSize(testName, info.width!, info.height!);
    // What encoded it (GStreamer or the ffmpeg fallback), from the muxer the
    // WebM header names.
    final encoder = info.encoder ??
        (extension == 'webm'
            ? SmokeVideo.webmInfo(videoBytes.length > 65536 ? Uint8List.sublistView(videoBytes, 0, 65536) : videoBytes).encoder
            : null);

    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
    final name = sanitizeTestName(testName);
    final videoFile = File('${targetDir.path}${Platform.pathSeparator}$name.$extension')
      ..writeAsBytesSync(videoBytes, flush: true);
    _mergeSidecar(targetDir, name, testName, {
      'video': '$name.$extension',
      'videoType': extension == 'webm' ? 'video/webm' : 'video/$extension',
      'frameCount': ?frameCount,
      'fps': info.fps,
      'durationSeconds': info.seconds,
      'width': info.width,
      'height': info.height,
      'encoder': ?encoder,
    }, usedAssets);
    return videoFile;
  }

  /// Adds [fields] to the sidecar of [testName] in [targetDir] (default
  /// [dir]), e.g. how long a recording stayed still.
  static void annotate(String testName, Map<String, Object?> fields, {Directory? targetDir}) =>
      _mergeSidecar(targetDir ?? dir, sanitizeTestName(testName), testName, fields, null);

  static void _mergeSidecar(
    Directory d,
    String name,
    String testName,
    Map<String, Object?> fields,
    List<String>? usedAssets,
  ) {
    final jsonFile = File('${d.path}${Platform.pathSeparator}$name.json');
    var meta = <String, dynamic>{};
    if (jsonFile.existsSync()) {
      try {
        final decoded = jsonDecode(jsonFile.readAsStringSync());
        // Two test names can share a file name: never merge into another's.
        if (decoded is Map<String, dynamic> && decoded['test'] == testName) meta = decoded;
      } catch (_) {}
    }
    meta['test'] = testName;
    meta.addAll(fields);
    // Which GPU backend the run used, when the runner says (a direct
    // `flutter test` run writes into the root of the artifact directory).
    final backend = Platform.environment['LUMINA_SMOKE_BACKEND'] ?? Platform.environment['FILAMENT_SMOKE_BACKEND'];
    if (backend != null && backend.isNotEmpty) meta['backend'] = backend;
    meta['savedAt'] = DateTime.now().millisecondsSinceEpoch;
    final assets = <String>{
      ...((meta['usedAssets'] as List?)?.map((e) => '$e') ?? const <String>[]),
      ..._recordedAssets,
      ...?usedAssets,
    };
    if (assets.isNotEmpty) meta['usedAssets'] = assets.toList();
    jsonFile.writeAsStringSync(jsonEncode(meta), flush: true);
  }

  // ---------------------------------------------------------------------------
  // Clearing
  // ---------------------------------------------------------------------------

  /// Wipes every file from the artifact directory, only while
  /// [outputDirOverride] is set.
  ///
  /// The default directory is shared by every smoke test of the package and
  /// is where their evidence is published: one test clearing it deletes what
  /// another run wrote seconds earlier, silently, because the publishing test
  /// has already passed. Artifacts are matched to tests by declared name
  /// through their sidecar JSON, so nothing needs the directory emptied first.
  static void clear() {
    if (outputDirOverride == null) {
      throw StateError(
        'SmokeArtifacts.clear() refuses to wipe the shared artifact directory (${dir.path}). Other smoke runs '
        'publish their evidence there. Set outputDirOverride (overrideDirForTesting) to a directory this test '
        'owns, or use clearDir().',
      );
    }
    clearDir(dir);
  }

  /// Deletes everything inside [targetDir].
  static void clearDir(Directory targetDir) {
    if (!targetDir.existsSync()) return;
    for (final entity in targetDir.listSync()) {
      try {
        entity.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// The ffmpeg / ffprobe the smoke system falls back to (see [SmokeTools]).
  static String? get ffmpegPath => SmokeTools.ffmpeg;
  static String? get ffprobePath => SmokeTools.ffprobe;
}
