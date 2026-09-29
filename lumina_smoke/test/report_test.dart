import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/lumina_smoke.dart';
import 'package:lumina_smoke/report.dart';

import 'support/videos.dart';

/// Word-start, longest-keyword categories with folder rules, as an engine
/// package configures them.
const _modules = TestCategories(
  [
    ('World', ['world', 'declarative']),
    ('Level', ['level', 'level_streaming']),
    ('Pawn & Player', ['pawn', 'player']),
    ('Input', ['input']),
    ('Game Framework', ['game_framework']),
    ('Test Harness', ['smoke_report', 'test_report']),
  ],
  longestMatch: true,
  folders: {'testing': 'Test Harness'},
  fallbackFolders: {'world': 'World'},
);

final _generator = SmokeReportGenerator(const SmokeReportConfig(title: 'Engine Smoke & Test Report', tag: 'Core', categories: _modules));

/// Backends, first-match categories and failing categories first, as a
/// renderer package configures them.
final _gpu = SmokeReportGenerator(const SmokeReportConfig(
  title: 'Renderer Test Report',
  categories: TestCategories([
    ('engine', ['engine']),
    ('gltfio', ['gltf']),
    ('camera', ['camera']),
    ('light_manager', ['light']),
  ]),
  failingCategoriesFirst: true,
  backends: [SmokeBackend('opengl'), SmokeBackend('vulkan')],
));

String _allPages(SmokeReportGenerator g, SmokeReportModel model, {String reportDir = 'build'}) =>
    g.renderPages(model, reportDir: reportDir).values.join('\n');

String _page(SmokeReportGenerator g, SmokeReportModel model, String category, {String reportDir = 'build'}) =>
    g.renderPages(model, reportDir: reportDir)['smoke_report/${SmokeReportGenerator.categorySlug(category)}.html']!;

List<Map<String, dynamic>> _passing(List<String> names, {String suite = '', Map<String, dynamic> tags = const {}}) => [
      {'type': 'suite', 'suite': {'id': 0, 'path': suite}, 'time': 0, ...tags},
      for (final (i, n) in names.indexed) ...[
        {'type': 'testStart', 'test': {'id': i + 1, 'name': n, 'suiteID': 0}, 'time': 0, ...tags},
        {'type': 'testDone', 'testID': i + 1, 'result': 'success', 'hidden': false, 'time': 10, ...tags},
      ],
      {'type': 'done', 'success': true, 'time': 20, ...tags},
    ];

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('smoke_report_test_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('events', () {
    test('a canned stream: failures first, errors, stack traces and interleaved prints', () {
      final events = [
        {'type': 'suite', 'suite': {'id': 0, 'path': 'test/unit/sample_test.dart'}, 'time': 100},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'test passing', 'suiteID': 0}, 'time': 105},
        {'type': 'testStart', 'test': {'id': 2, 'name': 'test failing', 'suiteID': 0}, 'time': 110},
        {'type': 'testStart', 'test': {'id': 3, 'name': 'test skipped', 'suiteID': 0}, 'time': 115},
        {'type': 'testStart', 'test': {'id': 4, 'name': 'loading test/unit/sample_test.dart', 'suiteID': 0}, 'time': 90},
        {'type': 'testDone', 'testID': 4, 'result': 'success', 'hidden': true, 'time': 95},
        {'type': 'print', 'testID': 1, 'message': 'Passing print line 1', 'time': 120},
        {'type': 'print', 'testID': 2, 'message': 'Failing print line 1', 'time': 125},
        {'type': 'print', 'testID': 1, 'message': 'Passing print line 2', 'time': 130},
        {'type': 'error', 'testID': 2, 'error': 'Expected true but got false', 'stackTrace': 'package:foo/bar.dart 12:34', 'time': 135},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'time': 140},
        {'type': 'testDone', 'testID': 2, 'result': 'failure', 'time': 145},
        {'type': 'testDone', 'testID': 3, 'result': 'success', 'skipped': true, 'time': 150},
        {'type': 'done', 'success': false, 'time': 155},
      ];
      final model = _generator.processEvents(events);
      expect(model.totalCount, 3, reason: 'the hidden loading test is left out');
      expect((model.passedCount, model.failedCount, model.skippedCount), (1, 1, 1));
      expect(model.exitCode, 1);
      expect(model.tests.first.name, 'test failing');
      expect(model.tests.first.error, 'Expected true but got false');
      expect(model.tests.first.prints, ['Failing print line 1']);
      final passing = model.tests.firstWhere((t) => t.name == 'test passing');
      expect(passing.prints, ['Passing print line 1', 'Passing print line 2']);
      expect(passing.durationMs, 35);

      final html = _page(_generator, model, 'Other');
      expect(html.indexOf('test failing'), lessThan(html.indexOf('test passing')));
      expect(html, contains('package:foo/bar.dart 12:34'));
      expect(html, contains('Passing print line 2'));
    });

    test('an error carried by testDone alone, and a skipped result', () {
      final model = _generator.processEvents([
        {'test': {'id': 1, 'name': 'test1'}, 'type': 'testStart', 'time': 0},
        {'test': {'id': 2, 'name': 'test2'}, 'type': 'testStart', 'time': 0},
        {'test': {'id': 3, 'name': 'test3'}, 'type': 'testStart', 'time': 0},
        {'testID': 1, 'result': 'success', 'type': 'testDone', 'time': 3},
        {'testID': 2, 'result': 'failure', 'error': 'failed!', 'stackTrace': 'stack', 'type': 'testDone', 'time': 4},
        {'testID': 3, 'result': 'skipped', 'type': 'testDone', 'time': 5},
      ]);
      expect({for (final t in model.tests) t.name: t.status}, {'test1': 'passed', 'test2': 'failed', 'test3': 'skipped'});
      expect(model.tests.first.error, 'failed!');
      expect(model.tests.first.stackTrace, 'stack');
      expect(model.exitCode, 1);
    });

    test('the exit code mirrors the results; a crash without results fails too', () {
      expect(_generator.processEvents(_passing(['test 1'])).exitCode, 0);
      expect(
        _generator.processEvents([
          {'type': 'testStart', 'test': {'id': 1, 'name': 'test 1', 'suiteID': 0}, 'time': 0},
          {'type': 'testDone', 'testID': 1, 'result': 'failure', 'hidden': false, 'time': 10},
          {'type': 'done', 'success': false, 'time': 20},
        ]).exitCode,
        1,
      );
      expect(_generator.processEvents([{'type': 'done', 'success': false, 'time': 1, 'run': 3}]).exitCode, 1,
          reason: 'a run that failed without leaving a test result crashed');
    });

    test('tests of different runs with the same process-local id are all kept', () {
      final model = _generator.processEvents([
        {'type': 'suite', 'suite': {'id': 0, 'path': 'a_test.dart'}, 'run': 0, 'time': 1},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'first file test', 'suiteID': 0}, 'run': 0, 'time': 2},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'run': 0, 'time': 3},
        {'type': 'suite', 'suite': {'id': 0, 'path': 'b_test.dart'}, 'run': 1, 'time': 4},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'second file test', 'suiteID': 0}, 'run': 1, 'time': 5},
        {'type': 'testDone', 'testID': 1, 'result': 'failure', 'run': 1, 'time': 6},
      ]);
      expect(model.tests.map((t) => t.name).toSet(), {'first file test', 'second file test'});
      expect(model.tests.firstWhere((t) => t.name == 'second file test').suite, 'b_test.dart');
    });

    test('a test re-run in a later run counts once, with its latest result', () {
      Map<String, dynamic> e(Map<String, dynamic> m, int run, String target) => {...m, 'run': run, 'target': target};
      final model = _generator.processEvents([
        e({'type': 'suite', 'suite': {'id': 0, 'path': 'test/ui/pie_test.dart'}, 'time': 0}, 0, 'test/ui test/data'),
        e({'type': 'testStart', 'test': {'id': 1, 'name': 'restores on stop', 'suiteID': 0}, 'time': 1}, 0, 'test/ui test/data'),
        e({'type': 'error', 'testID': 1, 'error': 'Expected -35', 'stackTrace': '', 'time': 2}, 0, 'test/ui test/data'),
        e({'type': 'testDone', 'testID': 1, 'result': 'failure', 'time': 3}, 0, 'test/ui test/data'),
        e({'type': 'done', 'success': false, 'time': 4}, 0, 'test/ui test/data'),
        e({'type': 'suite', 'suite': {'id': 0, 'path': 'test/ui/pie_test.dart'}, 'time': 10}, 1, 'test/ui/pie_test.dart'),
        e({'type': 'testStart', 'test': {'id': 1, 'name': 'restores on stop', 'suiteID': 0}, 'time': 11}, 1, 'test/ui/pie_test.dart'),
        e({'type': 'testDone', 'testID': 1, 'result': 'success', 'time': 12}, 1, 'test/ui/pie_test.dart'),
        e({'type': 'done', 'success': true, 'time': 13}, 1, 'test/ui/pie_test.dart'),
      ]);
      expect((model.totalCount, model.failedCount, model.exitCode), (1, 0, 0));
    });

    test("a test file's latest run replaces its older results, even for renamed tests", () {
      final model = _generator.processEvents([
        {'type': 'suite', 'suite': {'id': 0, 'path': 'test/ui/pie_test.dart'}, 'run': 0, 'target': 'test/ui', 'time': 0},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'old name', 'suiteID': 0}, 'run': 0, 'target': 'test/ui', 'time': 1},
        {'type': 'testDone', 'testID': 1, 'result': 'failure', 'run': 0, 'target': 'test/ui', 'time': 2},
        {'type': 'suite', 'suite': {'id': 0, 'path': 'test/ui/pie_test.dart'}, 'run': 1, 'target': 'test/ui/pie_test.dart', 'time': 10},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'group new name', 'suiteID': 0}, 'run': 1, 'target': 'test/ui/pie_test.dart', 'time': 11},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'run': 1, 'target': 'test/ui/pie_test.dart', 'time': 12},
      ]);
      expect(model.tests.map((t) => t.name), ['group new name']);
      expect(model.failedCount, 0);
    });

    test('a filtered re-run replaces only the scenarios it ran', () {
      const file = 'integration_test/smoke/door_smoke_test.dart';
      Map<String, dynamic> e(Map<String, dynamic> m, int run, [String? filter]) =>
          {...m, 'run': run, 'target': file, 'filter': ?filter};
      final model = _generator.processEvents([
        e({'type': 'suite', 'suite': {'id': 0, 'path': file}, 'time': 0}, 0),
        e({'type': 'testStart', 'test': {'id': 1, 'name': 'opens', 'suiteID': 0}, 'time': 1}, 0),
        e({'type': 'testDone', 'testID': 1, 'result': 'failure', 'time': 2}, 0),
        e({'type': 'testStart', 'test': {'id': 2, 'name': 'closes', 'suiteID': 0}, 'time': 3}, 0),
        e({'type': 'testDone', 'testID': 2, 'result': 'success', 'time': 4}, 0),
        e({'type': 'suite', 'suite': {'id': 0, 'path': file}, 'time': 10}, 1, '--plain-name opens'),
        e({'type': 'testStart', 'test': {'id': 1, 'name': 'opens', 'suiteID': 0}, 'time': 11}, 1, '--plain-name opens'),
        e({'type': 'testDone', 'testID': 1, 'result': 'success', 'time': 12}, 1, '--plain-name opens'),
        e({'type': 'done', 'success': true, 'time': 13}, 1, '--plain-name opens'),
      ]);
      expect({for (final t in model.tests) t.name: t.status}, {'opens': 'passed', 'closes': 'passed'});
      expect(model.exitCode, 0);
    });

    test('results of the same file on two backends are both kept; counted runs decide the exit code', () {
      final gl = _passing(['renders'], suite: '/r/test/smoke/engine_smoke_test.dart', tags: {'run': 0, 'target': 't', 'backend': 'opengl'});
      final vk = [
        {'type': 'suite', 'suite': {'id': 0, 'path': '/r/test/smoke/engine_smoke_test.dart'}, 'run': 1, 'target': 't', 'backend': 'vulkan', 'time': 0},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'renders', 'suiteID': 0}, 'run': 1, 'target': 't', 'backend': 'vulkan', 'time': 0},
        {'type': 'testDone', 'testID': 1, 'result': 'failure', 'run': 1, 'target': 't', 'backend': 'vulkan', 'time': 1},
      ];
      final model = _gpu.processEvents([...gl, ...vk]);
      expect(model.tests.map((t) => '${t.name} ${t.backend} ${t.status}').toSet(),
          {'renders opengl passed', 'renders vulkan failed'});
      expect(model.exitCode, 1);
      expect(_gpu.processEvents([...gl, ...vk], countedRuns: {0}).exitCode, 0,
          reason: 'a merged report fails only on the runs of this invocation');
    });

    test('a test that started but never finished (its run was killed) is a failure', () {
      final model = _generator.processEvents([
        {'type': 'testStart', 'test': {'id': 1, 'name': 'opens a door', 'suiteID': 0}, 'time': 0},
      ]);
      expect(model.tests.single.isFailure, isTrue);
      expect(model.tests.single.error, contains('did not finish'));
      expect(model.exitCode, 1);
    });

    test('setUpAll and tearDownAll are shown only when they fail', () {
      final model = _generator.processEvents([
        {'type': 'testStart', 'test': {'id': 1, 'name': '(setUpAll)', 'suiteID': 0}, 'time': 0},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'time': 1},
        {'type': 'testStart', 'test': {'id': 2, 'name': '(tearDownAll)', 'suiteID': 0}, 'time': 0},
        {'type': 'error', 'testID': 2, 'error': 'leak', 'stackTrace': '', 'time': 1},
        {'type': 'testDone', 'testID': 2, 'result': 'error', 'time': 1},
      ]);
      expect(model.tests.map((t) => t.name), ['(tearDownAll)']);
    });

    test('--report-only renders byte-identical pages from persisted events', () {
      final events = [
        {'type': 'testStart', 'test': {'id': 1, 'name': 'repro test', 'suiteID': 0}, 'time': 0},
        {'type': 'print', 'testID': 1, 'message': 'repro message', 'time': 10},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'hidden': false, 'time': 20},
        {'type': 'done', 'success': true, 'time': 30},
      ];
      final at = DateTime.utc(2026, 8, 21, 12);
      final html1 = _allPages(_generator, _generator.processEvents(events, artifactsDir: dir, timestamp: at));
      final file = File('${dir.path}/events.jsonl')..writeAsStringSync(events.map((e) => '${jsonEncode(e)}\n').join());
      final html2 = _allPages(_generator, _generator.processEvents(readSmokeEvents(file), artifactsDir: dir, timestamp: at));
      expect(html2, html1);
    });
  });

  group('artifacts', () {
    File png(String testName, {Directory? into, List<String>? usedAssets}) => SmokeArtifacts.saveScreenshotToDir(
        testName, SmokeArtifacts.encodePng(2, 2, Uint8List(16)), into ?? dir,
        usedAssets: usedAssets);

    test('every PNG and video matched to a test is shown in save order, videos first', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      png('gallery walk 01 start');
      sleep(const Duration(milliseconds: 5)); // a later save
      png('gallery walk');
      SmokeArtifacts.saveVideoToDir('gallery walk', realVideo(), dir);
      final model = _generator.processEvents(_passing(['gallery walk']), artifactsDir: dir);
      final t = model.tests.single;
      expect(t.screenshots.map((m) => m.fileName), ['gallery_walk_01_start.png', 'gallery_walk.png']);
      expect(t.videos.single.fileName, 'gallery_walk.webm');
      expect(t.isPassed, isTrue);
      expect(model.orphanedArtifacts, isEmpty);
      expect(model.artifactCount, 3);
      final html = _page(_generator, model, 'Other');
      expect(html.indexOf('data-file="gallery_walk.webm"'), lessThan(html.indexOf('data-file="gallery_walk_01_start.png"')));
      expect(html, contains('src="${artifactHref('${dir.path}/gallery_walk_01_start.png', 'build/smoke_report')}"'));
      expect(html, contains(' · gallery walk 01 start'), reason: 'a file saved under another name is captioned with it');
      expect(html, contains('2 PNG'));
      expect(html, contains('3 ARTIFACTS'));
      expect(html, isNot(contains(';base64,')));
      expect(html, isNot(contains('VIDEO &lt; 10 s</span>')));
      expect(t.videos.single.video?.encoder, SmokeWebm.gstreamerEncodesRgba ? 'GStreamer' : 'ffmpeg');
      expect(html, contains('encoded by ${t.videos.single.video?.encoder}'), reason: 'the report says which encoder wrote it');
    });

    test('PNGs and videos are linked relative to the page, never embedded', () {
      final build = Directory('${dir.path}/build');
      final artifacts = Directory('${build.path}/smoke_artifacts')..createSync(recursive: true);
      File('${artifacts.path}/walk.json').writeAsStringSync(jsonEncode({
        'test': 'gallery walk',
        'file': 'walk shot.png',
        'video': 'walk.webm',
        'durationSeconds': 12.0,
        'fps': 30.0,
        'width': 1280,
        'height': 800,
      }));
      File('${artifacts.path}/walk shot.png').writeAsBytesSync(Uint8List(1 << 20)); // 1 MiB
      File('${artifacts.path}/walk.webm').writeAsBytesSync(Uint8List(4096));
      final model = _generator.processEvents(_passing(['gallery walk']), artifactsDir: artifacts);
      expect(model.tests.single.isPassed, isTrue, reason: 'the declared measurements stand in for an unreadable file');
      final pages = _generator.renderPages(model, reportDir: build.path);
      final all = pages.values.join('\n');
      expect(all, isNot(contains(';base64,')));
      final page = pages['smoke_report/other.html']!;
      expect(page, contains('<img class="screenshot-img" src="../smoke_artifacts/walk%20shot.png" onclick="openModal(this.src)"'));
      expect(page, contains('src="../smoke_artifacts/walk.webm"></video>'));
      expect(all.length, lessThan(96 * 1024), reason: 'the report grows with the artifacts it embeds');
      final nested = _generator.renderCategoryHtml(model, 'Other', reportDir: '${build.path}/reports');
      expect(nested, contains('src="../../smoke_artifacts/walk%20shot.png"'));
    });

    test('sidecars with absolute paths and artifacts in backend folders are matched per backend', () {
      final vk = Directory('${dir.path}/vulkan')..createSync();
      final gl = Directory('${dir.path}/opengl')..createSync();
      final shot = png('camera: dolly in', into: vk);
      // An older sidecar naming its file by absolute path.
      File('${gl.path}/camera_dolly_in.png').writeAsBytesSync(shot.readAsBytesSync());
      File('${gl.path}/camera_dolly_in.json')
          .writeAsStringSync(jsonEncode({'test': 'camera: dolly in', 'file': File('${gl.path}/camera_dolly_in.png').absolute.path}));
      final events = [
        ..._passing(['camera: dolly in'], suite: '/r/test/smoke/camera_smoke_test.dart', tags: {'run': 0, 'target': 'x', 'backend': 'opengl'}),
        ..._passing(['camera: dolly in'], suite: '/r/test/smoke/camera_smoke_test.dart', tags: {'run': 1, 'target': 'x', 'backend': 'vulkan'}),
      ];
      final model = _gpu.processEvents(events, artifactsDir: dir);
      for (final t in model.tests) {
        expect(t.screenshots.single.relativePath, '${t.backend}/camera_dolly_in.png');
      }
      final page = _page(_gpu, model, 'camera');
      expect(page, contains('src="${artifactHref('${dir.path}/vulkan/camera_dolly_in.png', 'build/smoke_report')}"'));
      expect(page, contains('<span class="backend-tag vulkan">vulkan</span>'));
      expect(page, contains('data-backend="opengl"'));
    });

    test('an artifact extending its test name, or its leaf name inside a group, is matched to it', () {
      png('engine: renders on the chosen GPU (GPU A)');
      png('engine: renders on the chosen GPU (GPU B)');
      png('renamed smoke: spinning barrel');
      final model = _gpu.processEvents([
        {'group': {'id': 10, 'suiteID': 0, 'parentID': null, 'name': ''}, 'type': 'group', 'time': 0},
        {'group': {'id': 11, 'suiteID': 0, 'parentID': 10, 'name': 'Engine Smoke Tests'}, 'type': 'group', 'time': 0},
        {'test': {'id': 1, 'name': 'Engine Smoke Tests engine: renders on the chosen GPU', 'suiteID': 0, 'groupIDs': [10, 11]}, 'type': 'testStart', 'time': 0},
        {'testID': 1, 'result': 'success', 'type': 'testDone', 'time': 1},
      ], artifactsDir: dir);
      expect(model.tests.single.leafName, 'engine: renders on the chosen GPU');
      expect(model.tests.single.screenshots, hasLength(2));
      expect(model.orphanedArtifacts.single.testName, 'renamed smoke: spinning barrel');
    });

    test('an artifact named after its test file matches a test of that file', () {
      png('game_framework_smoke_test: PIE control 02 paused after step');
      final model = _generator.processEvents(
        _passing(['PIE control Smoke Test: play, pause, step, restart', 'GameInstance Smoke Test: Rendering Lifecycle'],
            suite: '/home/x/engine/test/smoke/game_framework_smoke_test.dart'),
        artifactsDir: dir,
      );
      expect(model.orphanedArtifacts, isEmpty);
      final pie = model.tests.firstWhere((t) => t.name.startsWith('PIE control'));
      expect(pie.screenshots.single.fileName, 'game_framework_smoke_test_pie_control_02_paused_after_step.png');
    });

    test('a Scenario NN artifact goes to the Scenario NN test of its own module', () {
      png('static mesh scenario 01: barrel lit');
      png('camera scenario 01: orbit');
      final model = _generator.processEvents([
        {'type': 'suite', 'suite': {'id': 0, 'path': '/p/test/smoke/static_mesh_smoke_test.dart'}, 'time': 0},
        {'type': 'suite', 'suite': {'id': 1, 'path': '/p/test/smoke/camera_smoke_test.dart'}, 'time': 0},
        {'type': 'testStart', 'test': {'id': 1, 'name': 'Scenario 01: loads a mesh', 'suiteID': 0}, 'time': 0},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'time': 1},
        {'type': 'testStart', 'test': {'id': 2, 'name': 'Scenario 01: follows the pawn', 'suiteID': 1}, 'time': 0},
        {'type': 'testDone', 'testID': 2, 'result': 'success', 'time': 1},
      ], artifactsDir: dir);
      expect(model.orphanedArtifacts, isEmpty);
      String shotOf(String suite) => model.tests.firstWhere((t) => t.suite.contains(suite)).screenshots.single.fileName;
      expect(shotOf('static_mesh'), 'static_mesh_scenario_01_barrel_lit.png');
      expect(shotOf('camera'), 'camera_scenario_01_orbit.png');
    });

    test('artifacts that match no test get their own card, videos and loose files included', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      png('nobody runs this');
      SmokeArtifacts.saveVideoToDir('nobody runs this', realVideo(), dir);
      File('${dir.path}/loose_capture.png').writeAsBytesSync(SmokeArtifacts.encodePng(2, 2, Uint8List(16)));
      File('${dir.path}/loose_capture.webm').writeAsBytesSync(realVideo());
      final model = _generator.processEvents(_passing(['something else']), artifactsDir: dir);
      expect(model.orphanedArtifacts.map((o) => o.testName), ['loose_capture', 'nobody runs this']);
      expect(model.orphanedArtifacts.first.media, hasLength(2), reason: 'files sharing a base name share a card');
      final orphan = model.orphanedArtifacts.last;
      expect(orphan.videos.single.fileName, 'nobody_runs_this.webm');
      final html = _page(_generator, model, 'Other');
      final section = html.substring(html.indexOf('Orphaned Artifacts'));
      expect(section, contains('data-file="nobody_runs_this.webm"'));
      expect(section, contains('<video class="screenshot-video"'));
      expect(section, contains('data-file="loose_capture.png"'));
    });

    test('an orphan lands on its module page, or on one page when the package says so', () {
      png('pawn possessed: loose shot');
      final model = _generator.processEvents(_passing(['input works'], suite: '/p/test/smoke/input_smoke_test.dart'), artifactsDir: dir);
      expect(model.orphanedArtifacts.single.category, 'Pawn & Player');
      final single = SmokeReportGenerator(const SmokeReportConfig(title: 't', orphanCategory: 'Artifacts without a matching test'))
          .processEvents(_passing(['input works']), artifactsDir: dir);
      expect(single.orphanedArtifacts.single.category, 'Artifacts without a matching test');
      expect(single.categories, contains('Artifacts without a matching test'));
    });

    test('a sidecar naming a file that is gone shows a note instead of a broken link', () {
      File('${dir.path}/gone.json').writeAsStringSync(jsonEncode({'test': 'gone test', 'file': 'gone.png'}));
      final model = _generator.processEvents(_passing(['gone test']), artifactsDir: dir);
      final html = _page(_generator, model, 'Other');
      expect(model.tests.single.screenshots.single.missing, isTrue);
      expect(html, contains('Missing file:'));
      expect(html, contains('MISSING FILE'));
    });

    test('a video under 10 s, 1024×768 or 30 fps gets red badges and fails its test and the report', () {
      final short = legacyWebm(seconds: 3);
      if (short == null) return markTestSkipped(noEncoderReason ?? 'no encoder');
      File('${dir.path}/pie_control.webm').writeAsBytesSync(short);
      File('${dir.path}/pie_control.json').writeAsStringSync(jsonEncode({'test': 'pie control', 'video': 'pie_control.webm'}));
      File('${dir.path}/stray.webm').writeAsBytesSync(short);
      // Declared measurements of an unreadable file count as well.
      File('${dir.path}/declared.webm').writeAsBytesSync(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 1]));
      File('${dir.path}/declared.json').writeAsStringSync(
          jsonEncode({'test': 'declared', 'video': 'declared.webm', 'frameCount': 24, 'fps': 12, 'width': 1024, 'height': 768}));

      final model = _generator.processEvents(_passing(['pie control', 'declared']), artifactsDir: dir);
      final t = model.tests.firstWhere((t) => t.name == 'pie control');
      expect(t.isFailure, isTrue);
      expect(t.error, allOf(contains('pie_control.webm'), contains('3.0 s < 10 s')));
      expect(model.tests.firstWhere((t) => t.name == 'declared').error, allOf(contains('2.0 s < 10 s'), contains('12.0 fps < 30 fps')));
      expect(model.shortVideoCount, 3);
      expect(model.smallVideoCount, 2, reason: '64×36, under 1024×768 too');
      expect(model.slowVideoCount, 3);
      expect(model.failedCount, 3, reason: 'both tests and the unmatched short video');
      expect(model.exitCode, 1);
      expect(model.badVideos, hasLength(3));

      final html = _allPages(_generator, model);
      expect(html, contains('<span class="badge short-video">VIDEO &lt; 10 s</span>'));
      expect(html, contains('3 videos &lt; 10 s'));
      expect(html, contains('<span class="badge short-video">VIDEO &lt; 1024×768</span>'));
      expect(html, contains('<span class="badge short-video">VIDEO &lt; 30 fps</span>'));
    });

    test('a video nothing can measure fails as unknown, flagged as such', () {
      File('${dir.path}/blob.webm').writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      File('${dir.path}/blob.json').writeAsStringSync(jsonEncode({'test': 'blob', 'video': 'blob.webm'}));
      final model = _generator.processEvents(_passing(['blob']), artifactsDir: dir);
      expect(model.tests.single.isFailure, isTrue);
      final html = _page(_generator, model, 'Other');
      expect(html, contains('VIDEO LENGTH ?'));
      expect(html, contains('length unknown'));
    });

    test('asset badges and chips come from the sidecars', () {
      png('uses assets', usedAssets: ['/w/test-assets/Props/Barrels/fuel_barrel_black.glb', 'Props/AC_units/ac.glb']);
      final model = _generator.processEvents(_passing(['uses assets']), artifactsDir: dir);
      expect(model.tests.single.usedAssets, hasLength(2));
      final html = _page(_generator, model, 'Other');
      expect(html, contains('📦 2 ASSETS'));
      expect(html, contains('>Props/Barrels/fuel_barrel_black.glb</span>'));
      expect(html, contains('>Props/AC_units/ac.glb</span>'));
    });
  });

  group('pages', () {
    List<Map<String, dynamic>> inputAndWorld() => [
          {'type': 'suite', 'suite': {'id': 0, 'path': '/p/test/smoke/input_smoke_test.dart'}, 'time': 0},
          {'type': 'suite', 'suite': {'id': 1, 'path': '/p/test/smoke/world_smoke_test.dart'}, 'time': 0},
          {'type': 'testStart', 'test': {'id': 1, 'name': 'input works', 'suiteID': 0}, 'time': 0},
          {'type': 'testDone', 'testID': 1, 'result': 'success', 'hidden': false, 'time': 5},
          {'type': 'testStart', 'test': {'id': 2, 'name': 'input breaks', 'suiteID': 0}, 'time': 0},
          {'type': 'error', 'testID': 2, 'error': 'boom', 'stackTrace': '', 'time': 5},
          {'type': 'testDone', 'testID': 2, 'result': 'failure', 'hidden': false, 'time': 6},
          {'type': 'testStart', 'test': {'id': 3, 'name': 'input skipped', 'suiteID': 0}, 'time': 0},
          {'type': 'testDone', 'testID': 3, 'result': 'success', 'skipped': true, 'hidden': false, 'time': 6},
          {'type': 'testStart', 'test': {'id': 4, 'name': 'world ticks', 'suiteID': 1}, 'time': 0},
          {'type': 'testDone', 'testID': 4, 'result': 'success', 'hidden': false, 'time': 7},
          {'type': 'done', 'success': false, 'time': 8},
        ];

    test('the index lists every category with its counts and links the failing tests to their cards', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      final build = Directory('${dir.path}/build')..createSync();
      final artifacts = Directory('${build.path}/smoke_artifacts')..createSync();
      SmokeArtifacts.saveScreenshotToDir('input works', SmokeArtifacts.encodePng(2, 2, Uint8List(16)), artifacts);
      SmokeArtifacts.saveVideoToDir('input works', realVideo(), artifacts);
      final model = _generator.processEvents(inputAndWorld(), artifactsDir: artifacts);
      expect(model.categories, ['World', 'Input'], reason: 'the configured order');
      final pages = _generator.renderPages(model, reportDir: build.path);
      expect(pages.keys, ['smoke_report.html', 'smoke_report/world.html', 'smoke_report/input.html']);

      final index = pages['smoke_report.html']!;
      for (final s in ['4 tests', '2 passed', '1 failed', '1 skipped', 'Summary', '<h1>Engine Smoke & Test Report', 'Core']) {
        expect(index, contains(s));
      }
      final table = index.substring(index.indexOf('<table class="category-table"'), index.indexOf('</table>'));
      expect(table.indexOf('data-category="World"'), lessThan(table.indexOf('data-category="Input"')));
      expect(table, contains('<td><a href="smoke_report/input.html">Input</a></td>'
          '<td class="num">3</td><td class="num pass">1</td><td class="num fail">1</td><td class="num skip">1</td>'
          '<td class="num">1</td><td class="num">1</td>'));
      expect(table, contains('<td><a href="smoke_report/world.html">World</a></td>'
          '<td class="num">1</td><td class="num pass">1</td><td class="num">0</td><td class="num skip">0</td>'
          '<td class="num">0</td><td class="num">0</td>'));
      final failing = index.substring(index.indexOf('<ul class="failing-list"'), index.indexOf('</ul>'));
      final anchor = SmokeReportGenerator.testAnchor(model.tests.firstWhere((t) => t.name == 'input breaks'));
      expect(failing, contains('<a href="smoke_report/input.html#$anchor">input breaks</a>'));
      expect(failing, isNot(contains('input works')));
      expect(index, isNot(contains('class="test-card')), reason: 'the index holds no cards');

      final input = pages['smoke_report/input.html']!;
      expect(input, contains('id="$anchor"'));
      expect(input, isNot(contains('world ticks')));
      expect(input, contains('<a class="back-link" href="../smoke_report.html">'));
      expect(input, contains('href="world.html" data-category="World"'));
      expect(input, contains('class="category-chip active has-failures" href="input.html"'));
      expect(input, contains('src="../smoke_artifacts/input_works.webm"'));
      final header = input.indexOf('<div class="category-header" data-category="Input">');
      expect(header, isNonNegative);
      expect(input.indexOf('input breaks'), greaterThan(header));
      expect(input, contains("onclick=\"filterTests('failed', this)\">❌ Failed (1)</button>"));
      expect(input, contains('function applyFilters('));
      final nav = input.substring(input.indexOf('<div class="category-bar" id="category-nav">'), input.indexOf('<div class="summary-bar">'));
      expect(nav.indexOf('href="world.html"'), lessThan(nav.indexOf('href="input.html"')));
      expect(nav, contains('href="input.html" data-category="Input">Input <span class="count fail">1 failed</span></a>'));
      expect(pages['smoke_report/world.html'], isNot(contains('input works')));
    });

    test('failing categories first, when the package asks for it', () {
      final model = _gpu.processEvents([
        {'suite': {'id': 0, 'path': '/r/test/smoke/camera_smoke_test.dart'}, 'type': 'suite', 'time': 0},
        {'suite': {'id': 1, 'path': '/r/test/src/gltf_loader_test.dart'}, 'type': 'suite', 'time': 0},
        {'test': {'id': 10, 'name': 'dolly-in', 'suiteID': 0}, 'type': 'testStart', 'time': 0},
        {'testID': 10, 'result': 'success', 'type': 'testDone', 'time': 1},
        {'test': {'id': 11, 'name': 'breaks on purpose', 'suiteID': 1}, 'type': 'testStart', 'time': 0},
        {'testID': 11, 'result': 'failure', 'type': 'testDone', 'time': 1},
      ]);
      expect(model.categories, ['gltfio', 'camera']);
    });

    test('writeReport writes the index and the pages and removes stale pages; every link resolves', () {
      final build = Directory('${dir.path}/build')..createSync();
      final artifacts = Directory('${build.path}/smoke_artifacts')..createSync();
      final stale = File('${build.path}/smoke_report/gone_module.html')..createSync(recursive: true);
      SmokeArtifacts.saveScreenshotToDir('input works', SmokeArtifacts.encodePng(2, 2, Uint8List(16)), artifacts);
      SmokeArtifacts.saveScreenshotToDir('pawn possessed: loose shot', SmokeArtifacts.encodePng(2, 2, Uint8List(16)), artifacts);
      final model = _generator.processEvents(inputAndWorld(), artifactsDir: artifacts);
      final index = _generator.writeReport(model, File('${build.path}/smoke_report.html'));
      expect(index.existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
      final pages = [index, ...Directory('${build.path}/smoke_report').listSync().whereType<File>()];
      expect(pages.map((f) => f.uri.pathSegments.last).toSet(),
          {'smoke_report.html', 'world.html', 'input.html', 'pawn_player.html'});
      var links = 0;
      for (final page in pages) {
        for (final m in RegExp(r'(?:href|src)="([^"]+)"').allMatches(page.readAsStringSync())) {
          final link = m.group(1)!;
          expect(link, isNot(startsWith('data:')));
          final path = link.split('#').first;
          if (path.isEmpty) continue;
          final target = page.parent.uri.resolveUri(Uri.parse(path)).toFilePath();
          expect(File(target).existsSync(), isTrue, reason: '$link in ${page.path} -> $target');
          links++;
        }
      }
      expect(links, greaterThan(6));
      expect(File('${build.path}/smoke_report/pawn_player.html').readAsStringSync(),
          contains('src="../smoke_artifacts/pawn_possessed_loose_shot.png"'));
    });

    test('no page references anything on the network', () {
      final model = _generator.processEvents(inputAndWorld());
      expect(RegExp(r'https?://', caseSensitive: false).hasMatch(_allPages(_generator, model)), isFalse);
    });
  });

  group('artifactHref', () {
    test('relative within one root, percent-encoded', () {
      expect(artifactHref('/home/u/build/smoke_artifacts/a b.png', '/home/u/build'), 'smoke_artifacts/a%20b.png');
      expect(artifactHref('/home/u/build/smoke_artifacts/x/c#1.webm', '/home/u/out/'), '../build/smoke_artifacts/x/c%231.webm');
      expect(artifactHref(r'C:\w\build\smoke_artifacts\opengl\a b.png', r'C:\w\build\smoke_report'),
          '../smoke_artifacts/opengl/a%20b.png');
      expect(artifactHref('C:/w/Build/smoke_artifacts/a.png', r'c:\w\build\smoke_report'), '../smoke_artifacts/a.png',
          reason: 'Windows paths compare case-insensitively');
    });

    test('an artifact outside the report\'s tree is linked by an absolute file:// URI', () {
      expect(artifactHref('/home/u/build/smoke_artifacts/a b.png', '/tmp/report'), 'file:///home/u/build/smoke_artifacts/a%20b.png');
      expect(artifactHref('C:/home/u/build/smoke_artifacts/a b.png', 'D:/tmp/report'), 'file:///C:/home/u/build/smoke_artifacts/a%20b.png');
      expect(artifactHref(r'\\server\share\a.png', 'C:/report'), 'file://server/share/a.png');
    });
  });

  group('smokeEventsKeptOnMerge', () {
    Map<String, dynamic> ev(String target, int run, {String? filter}) =>
        {'type': 'testDone', 'target': target, 'run': run, 'filter': ?filter};
    Map<String, int> latest(List<Map<String, dynamic>> events) {
      final m = <String, int>{};
      for (final e in events) {
        final k = smokeRunKey(e)!;
        final r = e['run'] as int;
        if (r > (m[k] ?? -1)) m[k] = r;
      }
      return m;
    }

    test('a target that no longer exists is dropped; existing ones stay', () {
      final previous = [ev('level blueprint', 7), ev('integration_test/smoke/a_test.dart', 8)];
      final kept = smokeEventsKeptOnMerge(previous,
          rerun: {'integration_test/smoke/b_test.dart'}, latestRun: latest(previous), targetExists: (t) => t != 'level blueprint');
      expect(kept.map((e) => e['target']), ['integration_test/smoke/a_test.dart']);
    });

    test('re-run targets and older runs are replaced; a filtered re-run replaces only its filter', () {
      final previous = [
        ev('integration_test/smoke/a_test.dart', 1),
        ev('integration_test/smoke/a_test.dart', 2),
        ev('integration_test/smoke/b_test.dart', 3, filter: '--plain-name x'),
        ev('integration_test/smoke/b_test.dart', 4, filter: '--plain-name y'),
      ];
      final kept = smokeEventsKeptOnMerge(previous,
          rerun: {'integration_test/smoke/b_test.dart'}, filter: '--plain-name x', latestRun: latest(previous), targetExists: (_) => true);
      expect(kept.map((e) => e['run']), [2, 4]);
    });

    test('a run of several targets stays while one of them exists; untagged events always stay', () {
      final previous = [
        {'type': 'testDone', 'target': 'test/a test/b', 'targets': ['test/a', 'test/b'], 'run': 1},
        {'type': 'testDone'},
      ];
      final kept = smokeEventsKeptOnMerge(previous,
          rerun: const {}, latestRun: latest([previous.first]), targetExists: (t) => t == 'test/b');
      expect(kept, hasLength(2));
    });

    test('by default existence is checked on disk, relative to the package', () {
      final previous = [ev('pubspec.yaml', 1), ev('no/such/smoke_test.dart', 2)];
      final kept = smokeEventsKeptOnMerge(previous, rerun: const {}, latestRun: latest(previous));
      expect(kept.map((e) => e['target']), ['pubspec.yaml']);
    });
  });

  group('ansiToHtml', () {
    test('colours the logger output instead of printing escape codes', () {
      final html = ansiToHtml('\x1B[36m[INFO]\x1B[0m [AssetRepository] <11> assets');
      expect(html, '<span class="ansi-36">[INFO]</span> [AssetRepository] &lt;11&gt; assets');
      expect(html, isNot(contains('\x1B')));
    });

    test('bold, bright, 256-colour and true-colour codes, and resets', () {
      expect(ansiToHtml('\x1B[1;32mOK\x1B[22m done\x1B[0m'), '<span class="ansi-b ansi-32">OK</span><span class="ansi-32"> done</span>');
      expect(ansiToHtml('\x1B[91mE\x1B[39m'), '<span class="ansi-91">E</span>');
      expect(ansiToHtml('\x1B[38;5;196mred\x1B[0m'), '<span style="color:#ff0000">red</span>');
      expect(ansiToHtml('\x1B[38;2;1;2;3mrgb\x1B[m'), '<span style="color:#010203">rgb</span>');
      expect(ansiToHtml('\x1B[41mbg\x1B[49m'), '<span class="ansi-bg-41">bg</span>');
    });

    test('other escape sequences are dropped and an unclosed colour is closed', () {
      expect(ansiToHtml('a\x1B[2Kb\x1B[1Gc'), 'abc');
      expect(ansiToHtml('\x1B[33mwarn'), '<span class="ansi-33">warn</span>');
    });

    test('the report renders prints, errors and stack traces through it', () {
      final model = _generator.processEvents([
        {'test': {'id': 1, 'name': 'logs'}, 'type': 'testStart', 'time': 0},
        {'testID': 1, 'message': '\x1B[32m[SUCCESS]\x1B[0m parsed', 'type': 'print', 'time': 1},
        {'testID': 1, 'error': '\x1B[31mExpected: <1>\x1B[0m', 'stackTrace': '\x1B[90mpackage:x/y.dart 3:4\x1B[0m', 'type': 'error', 'time': 2},
        {'testID': 1, 'result': 'failure', 'type': 'testDone', 'time': 3},
      ]);
      final html = _page(_generator, model, 'Other');
      expect(html, contains('<span class="ansi-32">[SUCCESS]</span> parsed'));
      expect(html, contains('<span class="ansi-31">Expected: &lt;1&gt;</span>'));
      expect(html, contains('<span class="ansi-90">package:x/y.dart 3:4</span>'));
      expect(html, contains('.logs .ansi-36 {'), reason: 'the colour classes are styled');
      expect(html, isNot(contains('\x1B')));
    });
  });

  group('TestCategories', () {
    test('longest word-start keyword: folder first, then the file name, then the fallback folder, then the test name', () {
      String cat(String path, [String name = '']) => _modules.categoryOf('/home/x/engine/$path', name);
      expect(cat('test/smoke/world_smoke_test.dart'), 'World');
      expect(cat('test/src/world/level_streaming_test.dart'), 'Level');
      expect(cat('test/world/spawn_actor_registration_test.dart'), 'World',
          reason: 'the world folder decides when the name does not; "spawn" is not "pawn"');
      expect(cat('test/src/pawn_possession_test.dart'), 'Pawn & Player');
      expect(cat('test/src/testing/whatever_test.dart'), 'Test Harness');
      expect(cat('test/misc/odd_one_test.dart', 'totally unrelated'), 'Other');
      expect(_modules.categoryOf('', 'input modifiers: negate'), 'Input', reason: 'no file: the test name decides');
      expect(_modules.orderOf('World'), lessThan(_modules.orderOf('Input')));
      expect(_modules.orderOf('Other'), _modules.categories.length);
    });

    test('Windows paths are grouped like POSIX ones', () {
      expect(_modules.categoryOf(r'D:\w\engine\test\src\world\level_streaming_test.dart', ''), 'Level');
      expect(_modules.categoryOf(r'D:\w\engine\test\world\spawn_actor_test.dart', ''), 'World');
    });

    test('first match on the file name, path rules and name prefixes', () {
      const c = TestCategories(
        [('material_instance', ['material_instance']), ('material', ['material']), ('web', ['web_'])],
        pathRules: {'/test/math/': 'dart_math'},
        namePrefixes: {'web ': 'web'},
      );
      expect(c.categoryOf('/r/test/src/material_instance_params_test.dart', 'x'), 'material_instance');
      expect(c.categoryOf('/r/test/src/material_test.dart', 'x'), 'material');
      expect(c.categoryOf(r'C:\r\test\math\viewport_test.dart', 'x'), 'dart_math');
      expect(c.categoryOf('opengl/web_api__gltf_barrel.png', 'web api: gltf barrel'), 'web');
      expect(c.categoryOf('unknown', 'test1'), 'Other');
    });
  });
}
