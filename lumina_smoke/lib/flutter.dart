/// [lumina_smoke](lumina_smoke.dart) plus what needs Flutter's test
/// framework: [SmokeRecorder], which records a running app into a smoke
/// video, [SmokeCapture], which captures widget and integration-test
/// frames as PNG, and [SmokeTutor] with [SmokeTutorialOverlay], which record
/// a captioned tutorial with a virtual cursor.
library;

export 'package:lumina_smoke/lumina_smoke.dart';
export 'package:lumina_smoke/src/flutter/capture.dart';
export 'package:lumina_smoke/src/flutter/recorder.dart';
export 'package:lumina_smoke/src/flutter/tutorial.dart';
