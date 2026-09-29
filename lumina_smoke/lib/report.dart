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

export 'src/report/ansi.dart';
export 'src/report/categories.dart';
export 'src/report/config.dart';
export 'src/report/dashboard_server.dart';
export 'src/report/generator.dart';
export 'src/report/html.dart';
export 'src/report/model.dart';
export 'src/report/paths.dart';
export 'src/report/process_groups.dart';
export 'src/report/run_mode.dart';
export 'src/report/runner.dart';
export 'src/video.dart';
