import 'dart:io';

import 'config.dart';
import 'paths.dart';

/// How a report run treats the report already in `build/`, and what it runs.
///
/// - Named test files or folders run alone and **merge**: every other
///   file's artifacts and results stay, the re-run files' results are
///   replaced.
/// - A whole-suite run (no targets: the smoke folders; `--all` adds `test/`
///   and the integration tests, `--unit-only` runs `test/`,
///   `--integration-only` the integration smoke folders) **wipes**
///   `build/smoke_artifacts/`, the report pages and the events file first.
/// - `--fresh` / `--clean` wipe on purpose, even for named files.
/// - `--merge` merges a whole-suite run; `--no-clean` / `--keep-old` keep the
///   old files without merging their results; `--report-only` re-renders the
///   report from the events file and touches nothing else.
/// - `flutter test`'s scenario filters (`--plain-name`, `--name` / `-n`,
///   `--tags` / `-t`, `--exclude-tags` / `-x`, with their value) are forwarded
///   to every run as [filters], never taken for a target; a filtered run
///   replaces only the scenarios it ran.
/// - `--no-dashboard` starts no live dashboard; `--no-wait` does not keep it
///   open at the end; `--events-file=<path>` names the events file.
class SmokeRunMode {
  const SmokeRunMode({
    required this.wipe,
    required this.merge,
    required this.targets,
    required this.filters,
    this.reportOnly = false,
    this.smokeOnly = true,
    this.all = false,
    this.unitOnly = false,
    this.integrationOnly = false,
    this.noDashboard = false,
    this.noWait = false,
    this.eventsFile,
  });

  final bool wipe;
  final bool merge;

  /// The test files and folders named on the command line.
  final List<String> targets;

  /// The scenario filters, forwarded to `flutter test`.
  final List<String> filters;
  final bool reportOnly;

  /// No targets and neither `--all` nor `--unit-only`: the smoke folders.
  final bool smokeOnly;
  final bool all;
  final bool unitOnly;
  final bool integrationOnly;
  final bool noDashboard;
  final bool noWait;
  final String? eventsFile;

  /// The filters as one string, telling a filtered run apart from a
  /// whole-file run of the same target; null without filters.
  String? get filter => filters.isEmpty ? null : filters.join(' ');

  static const Set<String> _valued = {'--plain-name', '--name', '-n', '--tags', '-t', '--exclude-tags', '-x'};

  /// Parses the runner's command line.
  factory SmokeRunMode.parse(List<String> args) {
    final targets = <String>[];
    final filters = <String>[];
    String? eventsFile;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (_valued.contains(a)) {
        filters.add(a);
        if (i + 1 < args.length) filters.add(args[++i]);
      } else if (_valued.any((f) => f.startsWith('--') && a.startsWith('$f='))) {
        filters.add(a);
      } else if (a.startsWith('--events-file=')) {
        eventsFile = a.substring('--events-file='.length);
      } else if (!a.startsWith('-')) {
        targets.add(a);
      }
    }
    final all = args.contains('--all');
    final unitOnly = args.contains('--unit-only');
    final integrationOnly = args.contains('--integration-only');
    final smokeOnly = args.contains('--smoke-only') || (!all && !unitOnly && targets.isEmpty);
    final reportOnly = args.contains('--report-only');
    final fresh = args.contains('--fresh') || args.contains('--clean');
    final merge = !reportOnly && !fresh && (args.contains('--merge') || targets.isNotEmpty);
    final keep = args.contains('--no-clean') || args.contains('--keep-old');
    return SmokeRunMode(
      wipe: !reportOnly && (fresh || (!merge && !keep)),
      merge: merge,
      targets: targets,
      filters: filters,
      reportOnly: reportOnly,
      smokeOnly: smokeOnly,
      all: all,
      unitOnly: unitOnly,
      integrationOnly: integrationOnly,
      noDashboard: args.contains('--no-dashboard'),
      noWait: args.contains('--no-wait'),
      eventsFile: eventsFile,
    );
  }
}

/// [SmokeRunMode.parse].
SmokeRunMode smokeRunMode(List<String> args) => SmokeRunMode.parse(args);

/// What one `flutter test` process runs.
enum SmokePhaseKind {
  /// Unit tests, with `flutter test`'s default concurrency.
  unit,

  /// Smoke tests, one file at a time (`--concurrency=1`): the GPU and the
  /// machine are shared.
  smoke,

  /// One integration-test file on the host's desktop device.
  integration,
}

/// One `flutter test` process of a run.
class SmokeRunPhase {
  const SmokeRunPhase(this.kind, this.targets, {this.backend});

  final SmokePhaseKind kind;
  final List<String> targets;

  /// The backend it runs on; null for a package without backends.
  final SmokeBackend? backend;

  /// `flutter` arguments for this phase with [filters].
  List<String> flutterArgs(List<String> filters) => switch (kind) {
        SmokePhaseKind.unit => ['test', '--machine', ...filters, ...targets],
        SmokePhaseKind.smoke => ['test', '--machine', '--concurrency=1', ...filters, ...targets],
        SmokePhaseKind.integration => ['test', '--machine', '-d', desktopDevice, ...filters, ...targets],
      };

  /// The host's desktop device for integration tests.
  static String get desktopDevice => Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : 'linux');

  @override
  String toString() => 'SmokeRunPhase(${kind.name}, ${backend?.name}, $targets)';
}

/// The `flutter test` processes [mode] runs for a package configured by
/// [config], in order: per backend the unit targets, then the smoke targets;
/// then every integration file on its own. Unit targets run on the first
/// backend only; smoke targets on every backend. `test` is expanded into its
/// entries so the smoke folders run apart from the unit tests. Paths are
/// relative to [packageDir] (the working directory by default).
List<SmokeRunPhase> planSmokeRuns(SmokeRunMode mode, SmokeReportConfig config, {String? packageDir}) {
  final root = packageDir ?? Directory.current.path;
  bool exists(String p) => FileSystemEntity.typeSync(_join(root, p)) != FileSystemEntityType.notFound;
  bool within(String p, String dir) => isSmokePathWithin(_join(root, p), _join(root, dir));
  bool isIntegration(String t) => config.integrationDirs.any((d) => within(t, d));

  final plain = <String>[];
  final integration = <String>[];
  if (mode.targets.isNotEmpty) {
    for (final t in mode.targets) {
      (isIntegration(t) ? integration : plain).add(t);
    }
    if (mode.unitOnly) integration.clear();
    if (mode.integrationOnly) plain.clear();
  } else if (mode.integrationOnly) {
    integration.addAll((mode.all ? config.integrationDirs : config.integrationSmokeDirs).where(exists));
  } else if (mode.unitOnly) {
    plain.add('test');
  } else if (mode.all) {
    plain.addAll(['test', ...config.extraSmokeTargets.where(exists)]);
    integration.addAll(config.integrationDirs.where(exists));
  } else {
    plain.addAll([...config.smokeDirs, ...config.extraSmokeTargets].where(exists));
    integration.addAll(config.integrationSmokeDirs.where(exists));
  }

  bool isSmoke(String t) =>
      config.smokeDirs.any((d) => within(t, d)) || config.extraSmokeTargets.any((d) => within(t, d));
  final unit = <String>[];
  final smoke = <String>[];
  for (final t in plain) {
    if (normalizeSmokePath(_join(root, t)) == normalizeSmokePath(_join(root, 'test'))) {
      final dir = Directory(_join(root, 'test'));
      if (!dir.existsSync()) continue;
      final entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
      for (final e in entries) {
        final rel = 'test/${e.uri.pathSegments.where((s) => s.isNotEmpty).last}';
        if (isSmoke(rel)) {
          smoke.add(rel);
        } else if (e is Directory || rel.endsWith('_test.dart')) {
          unit.add(rel);
        }
      }
    } else {
      (isSmoke(t) ? smoke : unit).add(t);
    }
  }

  final integrationFiles = <String>[];
  for (final t in integration) {
    final path = _join(root, t);
    if (FileSystemEntity.isDirectorySync(path)) {
      final files = Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))
          .map((f) => slashPath(f.path).substring(slashPath(root).length).replaceAll(RegExp(r'^/+'), ''))
          .toList()
        ..sort();
      integrationFiles.addAll(files);
    } else {
      integrationFiles.add(t);
    }
  }

  final phases = <SmokeRunPhase>[];
  final backends = config.backends.isEmpty ? <SmokeBackend?>[null] : config.backends;
  for (final (i, backend) in backends.indexed) {
    if (i == 0 && unit.isNotEmpty) phases.add(SmokeRunPhase(SmokePhaseKind.unit, unit, backend: backend));
    if ((i == 0 || !mode.unitOnly) && smoke.isNotEmpty) {
      phases.add(SmokeRunPhase(SmokePhaseKind.smoke, smoke, backend: backend));
    }
  }
  for (final f in integrationFiles) {
    phases.add(SmokeRunPhase(SmokePhaseKind.integration, [f], backend: backends.first));
  }
  return phases;
}

String _join(String root, String path) {
  if (File(path).isAbsolute) return path;
  return '$root${Platform.pathSeparator}$path';
}
