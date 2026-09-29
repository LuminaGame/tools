import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/lumina_smoke.dart';
import 'package:lumina_smoke/report.dart';

const _fixture = 'test/fixtures/report_fixture.dart';

/// The fixture folder counts as a smoke folder, run on two backends.
const _config = SmokeReportConfig(
  title: 'Runner Test Report',
  smokeDirs: ['test/fixtures'],
  backends: [SmokeBackend('first'), SmokeBackend('second')],
);

void main() {
  late Directory tempDir;
  late SmokeReportPaths paths;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('smoke_runner_test_');
    paths = SmokeReportPaths(
      artifactsDir: Directory('${tempDir.path}/smoke_artifacts'),
      reportFile: File('${tempDir.path}/smoke_report.html'),
      eventsFile: File('${tempDir.path}/events.jsonl'),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('--report-only renders the report from the events file and fails on a failure in it', () async {
    paths.eventsFile.writeAsStringSync([
      {'test': {'id': 1, 'name': 'test1'}, 'type': 'testStart', 'time': 0},
      {'testID': 1, 'message': 'hello from 1', 'type': 'print', 'time': 1},
      {'test': {'id': 2, 'name': 'test2'}, 'type': 'testStart', 'time': 0},
      {'testID': 1, 'result': 'success', 'type': 'testDone', 'time': 3},
      {'testID': 2, 'result': 'failure', 'error': 'failed!', 'stackTrace': 'stack', 'type': 'testDone', 'time': 4},
    ].map(jsonEncode).join('\n'));
    final code = await runSmokeReport(['--report-only'], _config, paths: paths);
    expect(code, 1);
    final index = paths.reportFile.readAsStringSync();
    expect(index, contains('Runner Test Report'));
    final page = File('${tempDir.path}/smoke_report/other.html').readAsStringSync();
    expect(page, contains('hello from 1'));
    expect(page, contains('failed!'));
    expect(page.indexOf('test2'), lessThan(page.indexOf('test1')));
    expect(await runSmokeReport(['--report-only'], _config, paths: SmokeReportPaths(
      artifactsDir: paths.artifactsDir,
      reportFile: paths.reportFile,
      eventsFile: File('${tempDir.path}/missing.jsonl'),
    )), 1, reason: 'no events file to render');
  });

  test('a targeted run on two backends merges into the report, then a --plain-name run replaces only its scenario',
      () async {
    // Evidence and results of an earlier run of another file: kept.
    final keepDir = Directory('${paths.artifactsDir.path}/first')..createSync(recursive: true);
    final kept = SmokeArtifacts.saveScreenshotToDir('old unit test', SmokeArtifacts.encodePng(2, 2, Uint8List(16)), keepDir);
    final previous = [
      {'suite': {'id': 0, 'path': '${Directory.current.path}/test/old_test.dart'}, 'type': 'suite', 'time': 0},
      {'test': {'id': 1, 'name': 'old unit test', 'suiteID': 0}, 'type': 'testStart', 'time': 0},
      {'testID': 1, 'result': 'success', 'type': 'testDone', 'time': 1},
    ].map((e) => {...e, 'run': 0, 'target': 'pubspec.yaml', 'backend': 'first'});
    // An earlier run of the fixture that failed: replaced.
    final stale = [
      {'suite': {'id': 0, 'path': '${Directory.current.path}/$_fixture'}, 'type': 'suite', 'time': 0},
      {'test': {'id': 1, 'name': 'stale fixture test', 'suiteID': 0}, 'type': 'testStart', 'time': 0},
      {'testID': 1, 'result': 'failure', 'type': 'testDone', 'time': 1},
    ].map((e) => {...e, 'run': 1, 'target': _fixture, 'backend': 'first'});
    paths.eventsFile
      ..createSync(recursive: true)
      ..writeAsStringSync([...previous, ...stale].map(jsonEncode).join('\n'));

    final code = await runSmokeReport([_fixture, '--no-dashboard'], _config, paths: paths);
    expect(code, 0, reason: 'the fixture passes; the stale failure was replaced');
    expect(kept.existsSync(), isTrue, reason: 'a targeted run keeps the artifact directory');
    final model = SmokeReportGenerator(_config).processEvents(readSmokeEvents(paths.eventsFile), artifactsDir: paths.artifactsDir);
    expect(model.tests.map((t) => '${t.name} @${t.backend}').toSet(), {
      'old unit test @first',
      'fixture: saves a screenshot @first',
      'fixture: saves a screenshot @second',
      'fixture: second scenario @first',
      'fixture: second scenario @second',
    });
    for (final backend in ['first', 'second']) {
      final shot = model.tests.firstWhere((t) => t.name == 'fixture: saves a screenshot' && t.backend == backend);
      expect(shot.screenshots.single.relativePath, '$backend/fixture_saves_a_screenshot.png');
    }
    final page = File('${tempDir.path}/smoke_report/other.html').readAsStringSync();
    expect(page, contains('src="../smoke_artifacts/second/fixture_saves_a_screenshot.png"'));
    expect(page, contains('src="../smoke_artifacts/first/old_unit_test.png"'));
    expect(page, isNot(contains('stale fixture test')));

    // Only one scenario again: the other keeps its result.
    final runsBefore = readSmokeEvents(paths.eventsFile).map(runOf).toSet();
    final filtered = await runSmokeReport([_fixture, '--plain-name', 'fixture: second scenario', '--no-dashboard'], _config, paths: paths);
    expect(filtered, 0);
    final events = readSmokeEvents(paths.eventsFile);
    final newRuns = events.map(runOf).toSet().difference(runsBefore);
    expect(newRuns, hasLength(2), reason: 'one run per backend');
    expect(events.where((e) => newRuns.contains(runOf(e)) && e['type'] == 'testStart').map((e) => '${(e['test'] as Map)['name']}').where((n) => !n.startsWith('loading ')).toSet(),
        {'fixture: second scenario'}, reason: '--plain-name is a filter, never a target');
    final after = SmokeReportGenerator(_config).processEvents(events, artifactsDir: paths.artifactsDir);
    expect(after.tests, hasLength(5));
    expect(after.tests.every((t) => t.isPassed), isTrue);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
