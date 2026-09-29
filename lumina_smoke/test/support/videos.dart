import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gstreamer/flutter_gstreamer.dart' show GstPipeline;
import 'package:lumina_smoke/lumina_smoke.dart';

/// Why a real video cannot be encoded here, or null when it can.
String? get noEncoderReason => SmokeArtifacts.videoEncoderAvailable
    ? null
    : 'neither GStreamer (vp8enc, webmmux) nor ffmpeg is installed (put ffmpeg on the PATH or set LUMINA_SMOKE_FFMPEG)';

const fw = SmokeVideo.minimumWidth;
const fh = SmokeVideo.minimumHeight;

/// [count] RGBA frames of the minimum smoke size, each a different colour: a
/// scene that keeps changing.
List<Uint8List> movingFrames(int count) => [for (var i = 0; i < count; i++) frame(i)];

Uint8List frame(int i) =>
    (Uint32List(fw * fh)..fillRange(0, fw * fh, 0xFF000000 | (i * 0x2F1B07 & 0xFFFFFF))).buffer.asUint8List();

/// Records [count] frames at 30 fps through [SmokeVideoRecorder], one frame
/// in memory at a time; frames where [frozen] holds repeat the last one.
Uint8List record(int count, {String? testName, bool Function(int frame)? frozen}) {
  final recorder = SmokeVideoRecorder(width: fw, height: fh, testName: testName);
  try {
    var shown = 0;
    for (var i = 0; i < count; i++) {
      if (frozen == null || !frozen(i)) shown = i;
      recorder.addFrame(frame(shown));
    }
    return recorder.finish();
  } finally {
    recorder.discard();
  }
}

/// One real 10 s, 30 fps, 1024×768 smoke video, encoded once per test file.
Uint8List realVideo() => _cachedVideo ??= record(300);
Uint8List? _cachedVideo;

/// A real WebM that breaks the rules (a video saved before they existed):
/// [seconds] long, [width] × [height] at 10 fps, encoded straight through
/// GStreamer or, without it, ffmpeg. Null when neither is installed.
Uint8List? legacyWebm({required int seconds, int width = 64, int height = 36}) {
  final dir = Directory.systemTemp.createTempSync('legacy_webm_');
  try {
    final out = '${dir.path}/legacy.webm';
    if (SmokeVideo.gstreamerAvailable && SmokeWebm.gstreamerEncodesRgba) {
      final pipeline = GstPipeline.parse(
        'videotestsrc pattern=ball num-buffers=${seconds * 10} ! '
        'video/x-raw,width=$width,height=$height,framerate=10/1 ! videoconvert ! vp8enc ! '
        'webmmux ! filesink name=out',
      );
      try {
        pipeline.element('out')!.set('location', out);
        pipeline.play();
        pipeline.waitForEos();
      } finally {
        pipeline.dispose();
      }
    } else {
      final ffmpeg = SmokeTools.ffmpeg;
      if (ffmpeg == null) return null;
      final r = Process.runSync(ffmpeg, [
        '-y', '-hide_banner', '-loglevel', 'error', //
        '-f', 'lavfi', '-i', 'testsrc=size=${width}x$height:rate=10',
        '-t', '$seconds',
        '-c:v', 'libvpx', '-pix_fmt', 'yuv420p', '-f', 'webm', out,
      ]);
      if (r.exitCode != 0) throw StateError('ffmpeg failed: ${r.stderr}');
    }
    return File(out).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
