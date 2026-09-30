// The real-pointer check of the native plugin. OPT-IN ONLY: it captures the
// pointer of whoever sits at the machine, so it is skipped unless
// LUMINA_MOUSE_CAPTURE_REAL_TEST=1 and is never run by CI or an agent.
//
// Run it yourself, at the machine, from this example directory (Windows,
// PowerShell):
//
//   $env:LUMINA_MOUSE_CAPTURE_REAL_TEST = '1'
//   Remove-Item Env:LUMINA_MOUSE_CAPTURE -ErrorAction SilentlyContinue
//   flutter test integration_test/real_pointer_capture_test.dart -d windows `
//     --dart-define=LUMINA_MOUSE_CAPTURE_REAL_TEST=1
//
// Then follow the printed steps. Every capture gives the pointer back within
// 15 seconds, and Alt+Tab or closing the test window frees it at any time.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumina_mouse_capture/lumina_mouse_capture.dart';

const String _flag = 'LUMINA_MOUSE_CAPTURE_REAL_TEST';
const bool _definedOn = bool.fromEnvironment(_flag);

bool get _enabled => _definedOn || Platform.environment[_flag] == '1';

void _say(String message) => debugPrint('\n[$_flag] $message');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the real plugin captures, reports raw motion, releases and reports a focus loss',
    (tester) async {
      // Not LuminaMouseCapture.backend: under a test binding that is always the
      // recording backend. This test is the one place that asks for the real one.
      final backend = MethodChannelMouseCaptureBackend();
      final events = <MouseCaptureEvent>[];
      final sub = backend.events.listen(events.add);
      var capturing = false;
      addTearDown(() async {
        if (capturing) await backend.release();
        await sub.cancel();
      });

      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFF101418),
          child: Center(
            child: Text(
              'lumina_mouse_capture real-pointer test: follow the console',
              style: TextStyle(color: Color(0xFFE6EDF3), fontSize: 20),
            ),
          ),
        ),
      ));

      final support = await backend.support();
      _say('support: $support');
      expect(support.kind, isNot(MouseCaptureBackendKind.disabled),
          reason: 'LUMINA_MOUSE_CAPTURE is off in this environment; unset it for this test');
      expect(support.pointerLock, isTrue, reason: '$support');
      expect(support.relativeMotion, isTrue, reason: '$support');

      Future<void> waitReal(Duration d) => tester.runAsync(() => Future<void>.delayed(d));

      Future<bool> captureWhenForeground() async {
        _say('Click once inside the test window so it is in the foreground (waiting up to 20 s).');
        final until = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(until)) {
          final centre = tester.view.physicalSize / tester.view.devicePixelRatio;
          if (await backend.capture(centre: Offset(centre.width / 2, centre.height / 2))) return true;
          await waitReal(const Duration(milliseconds: 250));
        }
        return false;
      }

      // 1. Capture and raw motion.
      capturing = await captureWhenForeground();
      expect(capturing, isTrue, reason: 'the window never came to the foreground');
      _say('CAPTURED. The cursor is hidden and held at the window centre.\n'
          'Move the mouse in wide circles, past the screen edges, for the next 6 seconds.');
      await waitReal(const Duration(seconds: 6));
      await backend.release();
      capturing = false;
      await tester.pump();
      _say('RELEASED. The cursor should be visible again, where it was before the capture.');

      expect(events.whereType<MouseCaptureLocked>(), isNotEmpty);
      final motion = events.whereType<MouseCaptureMotion>().toList();
      final travelled = motion.fold<double>(0, (sum, m) => sum + m.dx.abs() + m.dy.abs());
      _say('${motion.length} motion events, ${travelled.toStringAsFixed(0)} logical px travelled.');
      expect(travelled, greaterThan(200), reason: 'move the mouse while captured');

      // 2. No motion after release.
      final before = events.length;
      _say('Move the mouse for 2 seconds: nothing should be reported now.');
      await waitReal(const Duration(seconds: 2));
      expect(events.skip(before).whereType<MouseCaptureMotion>(), isEmpty);

      // 3. A focus loss gives the pointer back and says why.
      capturing = await captureWhenForeground();
      expect(capturing, isTrue);
      _say('CAPTURED again. Press Alt+Tab to switch to another window (within 15 seconds).');
      final lostAt = events.length;
      final until = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(until) && events.skip(lostAt).whereType<MouseCaptureLost>().isEmpty) {
        await waitReal(const Duration(milliseconds: 100));
      }
      final lost = events.skip(lostAt).whereType<MouseCaptureLost>().toList();
      if (lost.isEmpty) {
        await backend.release();
        capturing = false;
        fail('no loss reported within 15 s (the capture was released)');
      }
      capturing = false;
      _say('LOST: $lost. The cursor should be free and visible.');
      if (Platform.isWindows) expect(lost.first.reason, 'focus');
      _say('Done: all checks passed.');
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
