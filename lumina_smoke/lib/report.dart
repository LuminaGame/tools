/// The smoke report: runs `flutter test --machine` on the configured GPU
/// ([runSmokeReport] / [smokeReportMain]), matches every artifact to its
/// test through its sidecar, and writes an index page plus one page per
/// category, linking (never embedding) the PNGs and videos.
///
/// A package's `tool/smoke_report.dart` is only its [SmokeReportConfig]:
///
/// ```dart
/// import 'package:lumina_smoke/report.dart';
///
/// Future<void> main(List<String> args) => smokeReportMain(args, const SmokeReportConfig(title: 'My Smoke Report'));
/// ```
///
/// Plain Dart: it runs under `dart run`.
library;

export 'package:lumina_smoke/src/report/ansi.dart';
export 'package:lumina_smoke/src/report/categories.dart';
export 'package:lumina_smoke/src/report/config.dart';
export 'package:lumina_smoke/src/report/dashboard_server.dart';
export 'package:lumina_smoke/src/report/generator.dart';
export 'package:lumina_smoke/src/report/html.dart';
export 'package:lumina_smoke/src/report/model.dart';
export 'package:lumina_smoke/src/report/paths.dart';
export 'package:lumina_smoke/src/report/process_groups.dart';
export 'package:lumina_smoke/src/report/run_mode.dart';
export 'package:lumina_smoke/src/report/runner.dart';
export 'package:lumina_smoke/src/video.dart';
