/// Smoke-test evidence for the Lumina packages, in plain Dart (`dart:io`
/// plus flutter_gstreamer's dynamically loaded GStreamer, with an `ffmpeg`
/// fallback):
///
/// * [SmokeArtifacts]: PNG and VP8 / WebM artifacts with sidecar JSON matched
///   to tests by declared name, and the smoke-video rules they are checked
///   against.
/// * [SmokeVideo] / [SmokeVideoInfo]: the rules and the video probe.
/// * [SmokeVideoRecorder]: records RGBA frames while a scenario runs.
/// * [SmokeWebm], [SmokePng], [SmokeTools]: the encoders and the tools they
///   use.
///
/// The Flutter widget recorder and captures are in
/// `package:lumina_smoke/flutter.dart`; the report runner in
/// `package:lumina_smoke/report.dart`.
library;

export 'package:lumina_smoke/src/artifacts.dart';
export 'package:lumina_smoke/src/png.dart';
export 'package:lumina_smoke/src/temp_dirs.dart';
export 'package:lumina_smoke/src/tools.dart';
export 'package:lumina_smoke/src/video.dart';
export 'package:lumina_smoke/src/video_recorder.dart';
export 'package:lumina_smoke/src/webm.dart';
