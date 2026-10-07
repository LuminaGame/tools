import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lumina_smoke/src/artifacts.dart';
import 'package:lumina_smoke/src/video.dart';
import 'package:lumina_smoke/src/report/config.dart';
import 'package:lumina_smoke/src/report/dashboard_server.dart';
import 'package:lumina_smoke/src/report/generator.dart';
import 'package:lumina_smoke/src/report/paths.dart';
import 'package:lumina_smoke/src/report/process_groups.dart';
import 'package:lumina_smoke/src/report/run_mode.dart';

/// Where a report run reads and writes, from the environment:
/// `LUMINA_SMOKE_OUT` (artifacts), `LUMINA_SMOKE_REPORT_OUT` (the index
/// page), `LUMINA_SMOKE_EVENTS_OUT` (the events file), each also accepted
/// under its older `FILAMENT_SMOKE_*` / `LUMINA_UI_SMOKE_*` name, defaulting
/// to `build/smoke_artifacts`, `build/smoke_report.html` and
/// `build/smoke_report.events.jsonl` of the working directory.
class SmokeReportPaths {
  SmokeReportPaths({required this.artifactsDir, required this.reportFile, required this.eventsFile});

  factory SmokeReportPaths.fromEnvironment({String? eventsFile, Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    String? pick(List<String> names) {
      for (final n in names) {
        final v = env[n];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final cwd = Directory.current.path;
    final sep = Platform.pathSeparator;
    return SmokeReportPaths(
      artifactsDir: Directory(
        pick(const ['LUMINA_SMOKE_OUT', 'LUMINA_UI_SMOKE_OUT', 'FILAMENT_SMOKE_OUT']) ?? '$cwd${sep}build${sep}smoke_artifacts',
      ).absolute,
      reportFile: File(
        pick(const ['LUMINA_SMOKE_REPORT_OUT', 'LUMINA_UI_SMOKE_REPORT_OUT', 'FILAMENT_SMOKE_REPORT_OUT']) ??
            '$cwd${sep}build${sep}smoke_report.html',
      ).absolute,
      eventsFile: File(
        eventsFile ??
            pick(const ['LUMINA_SMOKE_EVENTS_OUT', 'LUMINA_UI_SMOKE_EVENTS_OUT', 'FILAMENT_SMOKE_EVENTS_OUT']) ??
            '$cwd${sep}build${sep}smoke_report.events.jsonl',
      ).absolute,
    );
  }

  final Directory artifactsDir;
  final File reportFile;
  final File eventsFile;

  /// The folder of the category pages next to [reportFile].
  Directory get pagesDir => Directory(reportFile.path.replaceAll(RegExp(r'\.html?$'), ''));
}

/// `dart run tool/smoke_report.dart [targets…] [flags…]` for a package
/// configured by [config]: runs the tests with `flutter test --machine`, on
/// the configured GPU, and writes the report. Returns the exit code (0 when
/// every counted test passed and every counted video meets the rules). See
/// [SmokeRunMode] for the flags. [paths] replaces the ones from the
/// environment; [packageDir] is the package whose tests run (the working
/// directory by default).
Future<int> runSmokeReport(
  List<String> args,
  SmokeReportConfig config, {
  SmokeReportPaths? paths,
  String? packageDir,
}) async {
  final mode = SmokeRunMode.parse(args);
  SmokeProcessGroups.killChildrenOnSignals();
  paths ??= SmokeReportPaths.fromEnvironment(eventsFile: mode.eventsFile);
  final generator = SmokeReportGenerator(config);

  if (mode.wipe) {
    for (final entity in <FileSystemEntity>[paths.artifactsDir, paths.pagesDir, paths.reportFile, paths.eventsFile]) {
      try {
        if (entity.existsSync()) entity.deleteSync(recursive: true);
      } catch (_) {}
    }
    stdout.writeln('Cleaned the previous smoke artifacts, report pages and events.');
  }
  paths.artifactsDir.createSync(recursive: true);

  SmokeDashboardServer? dashboard;
  if (!mode.reportOnly && !mode.noDashboard) {
    dashboard = SmokeDashboardServer(artifactsDir: paths.artifactsDir, title: config.dashboardTitle ?? config.title);
    await dashboard.start();
  }

  var events = <Map<String, dynamic>>[];
  Set<int>? countedRuns;
  if (mode.reportOnly) {
    if (!paths.eventsFile.existsSync()) {
      stderr.writeln('Error: ${paths.eventsFile.path} does not exist for --report-only');
      return 1;
    }
    events = readSmokeEvents(paths.eventsFile);
  } else {
    var nextRun = 0;
    final kept = <Map<String, dynamic>>[];
    if (mode.merge && paths.eventsFile.existsSync()) {
      final previous = readSmokeEvents(paths.eventsFile);
      final latestRun = <String, int>{};
      for (final e in previous) {
        final run = runOf(e);
        if (run >= nextRun) nextRun = run + 1;
        final key = smokeRunKey(e);
        if (key != null && run > (latestRun[key] ?? -1)) latestRun[key] = run;
      }
      kept.addAll(smokeEventsKeptOnMerge(previous,
          rerun: mode.targets.toSet(), filter: mode.filter, latestRun: latestRun));
    }
    events.addAll(kept);
    paths.eventsFile.parent.createSync(recursive: true);
    final sink = paths.eventsFile.openWrite();
    for (final e in kept) {
      sink.writeln(jsonEncode(e));
    }

    final configDir =
        config.configDirVariable == null ? null : Directory.systemTemp.createTempSync('lumina_smoke_config_');
    final fresh = <int>{};
    try {
      for (final phase in planSmokeRuns(mode, config, packageDir: packageDir)) {
        final run = nextRun++;
        fresh.add(run);
        final outDir = phase.backend == null
            ? paths.artifactsDir.path
            : '${paths.artifactsDir.path}${Platform.pathSeparator}${phase.backend!.name}';
        Directory(outDir).createSync(recursive: true);
        final env = smokeRunEnvironment(config, backend: phase.backend, artifactsDir: outDir, configDir: configDir?.path);
        final tags = <String, dynamic>{
          'run': run,
          'target': phase.targets.join(' '),
          'targets': phase.targets,
          'filter': ?mode.filter,
          'backend': ?phase.backend?.name,
        };
        void emit(Map<String, dynamic> e) {
          e.addAll(tags);
          events.add(e);
          sink.writeln(jsonEncode(e));
          dashboard?.handleMachineEvent(e);
        }

        try {
          await runFlutterMachine(phase.flutterArgs(mode.filters), env,
              onEvent: emit, dashboard: dashboard, workingDirectory: packageDir);
        } on ProcessException catch (e) {
          // The run never started: a failed pseudo-test says so.
          final now = DateTime.now().millisecondsSinceEpoch;
          const id = 999999;
          emit({'type': 'testStart', 'test': {'id': id, 'name': 'flutter test ${phase.targets.join(' ')} launch', 'suiteID': 0}, 'time': now});
          emit({'type': 'error', 'testID': id, 'error': 'Failed to launch flutter test: $e', 'stackTrace': '', 'time': now});
          emit({'type': 'testDone', 'testID': id, 'result': 'failure', 'hidden': false, 'time': now});
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
      try {
        configDir?.deleteSync(recursive: true);
      } on FileSystemException catch (_) {}
    }
    if (mode.merge) countedRuns = fresh;
  }

  final model = generator.processEvents(events, artifactsDir: paths.artifactsDir, countedRuns: countedRuns);
  final index = generator.writeReport(model, paths.reportFile);
  stdout.writeln('Smoke report generated at ${index.path} (one page per category under ${paths.pagesDir.path})'
      '${mode.merge ? ', merged' : ''}.');
  stdout.writeln('Summary: ${model.totalCount} tests, ${model.passedCount} passed, ${model.failedCount} failed, '
      '${model.skippedCount} skipped; ${model.artifactCount} artifacts, ${model.shortVideoCount} videos under '
      '${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s, ${model.smallVideoCount} under '
      '${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}, ${model.slowVideoCount} under ${SmokeVideo.minimumFps} fps.');
  for (final m in model.badVideos) {
    stderr.writeln('VIDEO ${m.violations.join(', ')}: ${m.relativePath} (${m.video?.describe ?? 'unmeasured'})');
  }

  if (dashboard != null) {
    dashboard.onSuiteDone(exitCode: model.exitCode);
    if (!mode.noWait) {
      await dashboard.waitIfInteractive();
    } else {
      await dashboard.stop();
    }
  }
  return model.exitCode;
}

/// [runSmokeReport], then exit with its code, killing any child process
/// left behind: the whole body of a package's `tool/smoke_report.dart`.
Future<Never> smokeReportMain(List<String> args, SmokeReportConfig config) async {
  final code = await runSmokeReport(args, config);
  SmokeProcessGroups.exitKillingChildren(code);
}

/// The environment of a run: the GPU it is pinned to (by name, and on Linux
/// the PRIME offload variables), the artifact directory, the test assets,
/// the backend and a throwaway configuration directory, plus the package's
/// own [SmokeReportConfig.environment].
Map<String, String> smokeRunEnvironment(
  SmokeReportConfig config, {
  SmokeBackend? backend,
  required String artifactsDir,
  String? configDir,
}) {
  final assets = SmokeArtifacts.testAssetsDir;
  return {
    'LUMINA_SMOKE_OUT': artifactsDir,
    'CUDA_VISIBLE_DEVICES': config.cudaDevice,
    // By name: under PRIME offload the Vulkan device order changes, so an
    // index would pick another card.
    'FILAMENT_GPU': config.gpuName,
    if (Platform.isLinux) ...{
      '__NV_PRIME_RENDER_OFFLOAD': '1',
      '__VK_LAYER_NV_optimus': 'NVIDIA_only',
      'DRI_PRIME': '1',
    },
    if (assets.existsSync()) 'LUMINA_TEST_ASSETS': assets.absolute.path,
    if (config.configDirVariable != null && configDir != null) config.configDirVariable!: configDir,
    ...config.environment,
    if (backend != null) ...{'LUMINA_SMOKE_BACKEND': backend.name, ...backend.environment},
  };
}

/// Runs `flutter` with [args] and [environment], passing every
/// `flutter test --machine` event to [onEvent] and every other line to the
/// console (and [dashboard]). Both output streams are drained before it
/// returns: a fast run's whole JSON output can arrive after the process
/// exits. A run that exits non-zero without a `done` event gets one with
/// `success: false`, so a crash is never mistaken for a pass.
Future<int> runFlutterMachine(
  List<String> args,
  Map<String, String> environment, {
  required void Function(Map<String, dynamic> event) onEvent,
  SmokeDashboardServer? dashboard,
  String executable = 'flutter',
  String? workingDirectory,
}) async {
  final process =
      await SmokeProcessGroups.start(executable, args, environment: environment, workingDirectory: workingDirectory);
  unawaited(process.stdin.close());
  var sawDone = false;
  void event(Map<String, dynamic> e) {
    if (e['type'] == 'done') sawDone = true;
    onEvent(e);
  }

  final out = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (line.startsWith('[{') || line.startsWith('{')) {
      try {
        final decoded = jsonDecode(line);
        for (final d in decoded is List ? decoded : [decoded]) {
          if (d is Map<String, dynamic>) event(d);
        }
        return;
      } catch (_) {
        // Not an event after all: print it.
      }
    }
    stdout.writeln(line);
    dashboard?.handleRawLog(line);
  }).asFuture<void>();
  final err = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    stderr.writeln(line);
    dashboard?.handleRawLog(line);
  }).asFuture<void>();
  final code = await process.exitCode;
  await Future.wait([out, err]);
  if (code != 0 && !sawDone) {
    event({'type': 'done', 'success': false, 'time': DateTime.now().millisecondsSinceEpoch});
  }
  return code;
}

/// The events of an events file (one JSON object per line; bad lines are
/// skipped).
List<Map<String, dynamic>> readSmokeEvents(File file) {
  final events = <Map<String, dynamic>>[];
  if (!file.existsSync()) return events;
  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) events.add(decoded);
    } catch (_) {}
  }
  return events;
}

/// Whether [target] (a path relative to the package) is one of the smoke
/// folders of [config] or inside one.
bool isSmokeTarget(String target, SmokeReportConfig config) =>
    config.smokeDirs.any((d) => isSmokePathWithin(target, d)) ||
    config.extraSmokeTargets.any((d) => isSmokePathWithin(target, d));
