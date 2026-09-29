import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/report.dart';

const _plain = SmokeReportConfig(title: 't');

const _ui = SmokeReportConfig(
  title: 't',
  integrationDirs: ['integration_test'],
  integrationSmokeDirs: ['integration_test/smoke'],
);

const _gpu = SmokeReportConfig(
  title: 't',
  extraSmokeTargets: ['tool/render_smoke.dart'],
  backends: [
    SmokeBackend('opengl', environment: {'FILAMENT_SMOKE_BACKEND': 'opengl'}),
    SmokeBackend('vulkan', environment: {'FILAMENT_SMOKE_BACKEND': 'vulkan'}),
  ],
);

void main() {
  late Directory pkg;

  setUp(() {
    // A package with unit tests, smoke tests, an extra smoke driver and
    // integration tests.
    pkg = Directory.systemTemp.createTempSync('smoke_run_mode_');
    for (final f in [
      'test/a_test.dart',
      'test/src/b_test.dart',
      'test/smoke/engine_smoke_test.dart',
      'test/smoke/camera_smoke_test.dart',
      'test/helper.dart',
      'tool/render_smoke.dart',
      'integration_test/smoke/door_smoke_test.dart',
      'integration_test/flow_test.dart',
    ]) {
      File('${pkg.path}/$f').createSync(recursive: true);
    }
  });

  tearDown(() => pkg.deleteSync(recursive: true));

  List<String> plan(List<String> args, SmokeReportConfig config) => [
        for (final p in planSmokeRuns(smokeRunMode(args), config, packageDir: pkg.path))
          '${p.kind.name}${p.backend == null ? '' : '@${p.backend!.name}'}: ${p.targets.join(' ')}',
      ];

  group('smokeRunMode', () {
    test('a run of one file merges and runs only that file', () {
      final mode = smokeRunMode(['--no-dashboard', '--concurrency=1', 'test/smoke/collision_smoke_test.dart']);
      expect((mode.merge, mode.wipe), (true, false));
      expect(mode.targets, ['test/smoke/collision_smoke_test.dart']);
      expect(mode.noDashboard, isTrue);
    });

    test('a scenario filter is forwarded to flutter test, never taken for a target', () {
      final mode = smokeRunMode(['test/smoke/collision_smoke_test.dart', '--plain-name', 'shape colliders']);
      expect(mode.targets, ['test/smoke/collision_smoke_test.dart']);
      expect(mode.filters, ['--plain-name', 'shape colliders']);
      expect(mode.filter, '--plain-name shape colliders');
      expect(smokeRunMode(['--name=door', 'test/smoke/a_smoke_test.dart']).filters, ['--name=door']);
      expect(smokeRunMode(['-n', 'door', 'test/smoke/a_test.dart']).targets, ['test/smoke/a_test.dart']);
      expect(smokeRunMode(['--plain-name', 'x']).targets, isEmpty, reason: 'a filter alone names no file');
      expect(smokeRunMode(['--plain-name', 'x']).wipe, isTrue, reason: 'and so is a whole-suite run');
    });

    test('a whole-suite run starts clean', () {
      for (final args in [<String>[], ['--smoke-only', '--no-dashboard'], ['--all'], ['--unit-only']]) {
        expect(smokeRunMode(args).wipe, isTrue, reason: '$args');
        expect(smokeRunMode(args).merge, isFalse, reason: '$args');
      }
    });

    test('--fresh and --clean wipe even for named files', () {
      for (final flag in ['--fresh', '--clean']) {
        final mode = smokeRunMode([flag, 'test/smoke/collision_smoke_test.dart']);
        expect((mode.wipe, mode.merge), (true, false), reason: flag);
        expect(mode.targets, ['test/smoke/collision_smoke_test.dart'], reason: flag);
      }
    });

    test('--merge, --no-clean and --report-only never wipe', () {
      expect((smokeRunMode(['--merge']).merge, smokeRunMode(['--merge']).wipe), (true, false));
      expect(smokeRunMode(['--no-clean']).wipe, isFalse);
      expect(smokeRunMode(['--keep-old']).wipe, isFalse);
      final reportOnly = smokeRunMode(['--report-only', '--events-file=x/e.jsonl']);
      expect((reportOnly.wipe, reportOnly.merge, reportOnly.reportOnly), (false, false, true));
      expect(reportOnly.eventsFile, 'x/e.jsonl');
    });
  });

  group('planSmokeRuns', () {
    test('no targets: the smoke folders one file at a time', () {
      expect(plan([], _plain), ['smoke: test/smoke']);
      expect(plan([], _ui), ['smoke: test/smoke', 'integration: integration_test/smoke/door_smoke_test.dart']);
    });

    test('--all expands test/ into unit entries and the smoke folder; --unit-only skips integration tests', () {
      expect(plan(['--all'], _plain), ['unit: test/a_test.dart test/src', 'smoke: test/smoke']);
      expect(plan(['--all'], _ui), [
        'unit: test/a_test.dart test/src',
        'smoke: test/smoke',
        'integration: integration_test/flow_test.dart',
        'integration: integration_test/smoke/door_smoke_test.dart',
      ]);
      expect(plan(['--unit-only'], _ui), ['unit: test/a_test.dart test/src', 'smoke: test/smoke']);
      expect(plan(['--integration-only'], _ui), ['integration: integration_test/smoke/door_smoke_test.dart']);
    });

    test('named targets run alone: unit files first, then smoke files, then integration files', () {
      expect(plan(['test/smoke/engine_smoke_test.dart', 'test/a_test.dart', 'integration_test/flow_test.dart'], _ui), [
        'unit: test/a_test.dart',
        'smoke: test/smoke/engine_smoke_test.dart',
        'integration: integration_test/flow_test.dart',
      ]);
    });

    test('backends: smoke targets run on every backend, unit targets on the first, whatever the separator', () {
      for (final target in ['test/smoke/engine_smoke_test.dart', r'test\smoke\engine_smoke_test.dart']) {
        expect(plan([target, '--no-dashboard'], _gpu), ['smoke@opengl: $target', 'smoke@vulkan: $target'], reason: target);
      }
      expect(plan(['test/a_test.dart'], _gpu), ['unit@opengl: test/a_test.dart']);
      expect(plan(['tool/render_smoke.dart'], _gpu), ['smoke@opengl: tool/render_smoke.dart', 'smoke@vulkan: tool/render_smoke.dart']);
      expect(plan([], _gpu), ['smoke@opengl: test/smoke tool/render_smoke.dart', 'smoke@vulkan: test/smoke tool/render_smoke.dart']);
      expect(plan(['--all'], _gpu), [
        'unit@opengl: test/a_test.dart test/src',
        'smoke@opengl: test/smoke tool/render_smoke.dart',
        'smoke@vulkan: test/smoke tool/render_smoke.dart',
      ]);
      expect(plan(['--unit-only'], _gpu), ['unit@opengl: test/a_test.dart test/src', 'smoke@opengl: test/smoke']);
    });

    test('an extra smoke target that does not exist is left out', () {
      File('${pkg.path}/tool/render_smoke.dart').deleteSync();
      expect(plan([], _gpu), ['smoke@opengl: test/smoke', 'smoke@vulkan: test/smoke']);
    });

    test('the flutter arguments of each phase carry the filters', () {
      final phases = planSmokeRuns(smokeRunMode(['--all', '--plain-name', 'x']), _ui, packageDir: pkg.path);
      expect(phases.first.flutterArgs(['--plain-name', 'x']), ['test', '--machine', '--plain-name', 'x', 'test/a_test.dart', 'test/src']);
      expect(phases[1].flutterArgs(const []), ['test', '--machine', '--concurrency=1', 'test/smoke']);
      expect(phases.last.flutterArgs(const []),
          ['test', '--machine', '-d', SmokeRunPhase.desktopDevice, 'integration_test/smoke/door_smoke_test.dart']);
    });
  });

  group('smokeRunEnvironment', () {
    test('pins the GPU by name, points the artifacts and names the backend', () {
      final env = smokeRunEnvironment(_gpu, backend: _gpu.backends.last, artifactsDir: '/a/vulkan', configDir: '/cfg');
      expect(env['FILAMENT_GPU'], 'RTX PRO 2000');
      expect(env['CUDA_VISIBLE_DEVICES'], '1');
      expect(env.containsKey('VK_DEVICE_INDEX'), isFalse, reason: 'under PRIME offload an index picks another card');
      expect(env['LUMINA_SMOKE_OUT'], '/a/vulkan');
      expect(env['LUMINA_SMOKE_BACKEND'], 'vulkan');
      expect(env['FILAMENT_SMOKE_BACKEND'], 'vulkan');
      expect(env['LUMINA_CONFIG_DIR'], '/cfg');
      expect(env.containsKey('__NV_PRIME_RENDER_OFFLOAD'), Platform.isLinux);
    });
  });
}
