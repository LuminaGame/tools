import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/flutter.dart';

Set<String> _recorderDirs() => Directory.systemTemp
    .listSync(followLinks: false)
    .whereType<Directory>()
    .map((d) => d.path)
    .where((p) => p.replaceAll(r'\', '/').split('/').last.startsWith(SmokeRecorder.tempPrefix))
    .toSet();

/// A widget that changes every frame: a block sweeping across 1024×768.
class _Sweep extends StatefulWidget {
  const _Sweep();

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _clock,
        builder: (context, _) => Container(
          color: const Color(0xFF0B0F17),
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(_clock.value * 900, 300),
            child: Container(width: 120, height: 120, color: const Color(0xFF38BDF8)),
          ),
        ),
      );
}

void main() {
  late Directory stale;
  late Directory fresh;
  late Directory artifacts;
  final left = <String>{};

  setUpAll(() {
    // A recording killed two hours ago, and one still writing.
    stale = Directory.systemTemp.createTempSync(SmokeRecorder.tempPrefix);
    File('${stale.path}/frames.rgba')
      ..writeAsBytesSync(List.filled(16, 0))
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
    fresh = Directory.systemTemp.createTempSync(SmokeRecorder.tempPrefix);
    File('${fresh.path}/frames.rgba').writeAsBytesSync(List.filled(16, 0));
    artifacts = Directory.systemTemp.createTempSync('smoke_flutter_test_artifacts_');
    SmokeArtifacts.overrideDirForTesting(artifacts);
  });

  tearDownAll(() {
    SmokeArtifacts.overrideDirForTesting(null);
    for (final d in [stale, fresh, artifacts]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  testWidgets('a new recorder purges the temp directories a killed run left behind, and only those', (tester) async {
    expect(stale.existsSync(), isTrue);
    SmokeRecorder(tester, boundary: find.byType(RepaintBoundary));
    expect(stale.existsSync(), isFalse, reason: 'nothing written for two hours');
    expect(fresh.existsSync(), isTrue, reason: 'a live recording is left alone');
  });

  testWidgets('a test that fails before save still removes its raw frames', (tester) async {
    final before = _recorderDirs();
    await tester.pumpWidget(const RepaintBoundary(
      child: Directionality(textDirection: TextDirection.ltr, child: SizedBox(width: 64, height: 64)),
    ));
    final rec = SmokeRecorder(tester, boundary: find.byType(RepaintBoundary).first);
    await rec.hold(const Duration(milliseconds: 100));
    expect(rec.frameCount, greaterThan(0));
    left.addAll(_recorderDirs().difference(before));
    expect(left, hasLength(1), reason: 'the recorder writes into its own temp directory');
    // No save(): the test ends as a failing one would, and teardown runs.
  });

  test('…and its directory is gone once that test has torn down', () {
    for (final path in left) {
      expect(Directory(path).existsSync(), isFalse, reason: path);
    }
  });

  testWidgets('captureWidgetPng captures a RepaintBoundary as PNG', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(color: Color(0xFF10B981), child: SizedBox(width: 40, height: 30)),
      ),
    ));
    final png = await SmokeCapture.captureWidgetPng(tester, find.byKey(key));
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(SmokeArtifacts.pngSize(png), isNotNull);
    final integration = await SmokeCapture.captureIntegrationPng(Object(), tester, boundary: find.byKey(key));
    expect(integration.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('a recording under 10 s is refused; a 10.5 s one at 30 fps and 1024×768 is saved with its sidecar',
      (tester) async {
    if (!SmokeArtifacts.videoEncoderAvailable) return markTestSkipped('no GStreamer or ffmpeg');
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: const _Sweep()));
    await tester.pump();

    final short = SmokeRecorder(tester, boundary: find.byKey(key));
    await short.hold(const Duration(seconds: 2));
    expect(() => short.save('recorder: too short'), throwsStateError);
    expect(File('${artifacts.path}/recorder_too_short.webm').existsSync(), isFalse);

    final rec = SmokeRecorder(tester, boundary: find.byKey(key));
    await rec.hold(const Duration(milliseconds: 10500));
    final video = rec.save('recorder: sweep', usedAssets: const ['Props/Barrels/empty_barrel.glb']);
    expect(SmokeArtifacts.videoDurationSeconds(video), greaterThanOrEqualTo(10.0));
    expect(SmokeArtifacts.videoFramesPerSecond(video), greaterThanOrEqualTo(29.9));
    expect(SmokeArtifacts.videoFrameSize(video), (1024, 768));
    final sidecar = File('${artifacts.path}/recorder_sweep.json').readAsStringSync();
    expect(sidecar, contains('"longestStillSeconds"'));
    expect(sidecar, contains('empty_barrel.glb'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
