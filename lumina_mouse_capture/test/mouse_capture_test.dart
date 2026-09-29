import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_mouse_capture/lumina_mouse_capture.dart';

/// The Dart half of the mouse-capture plugin. The
/// native half is exercised for real by the nested-compositor smoke
/// (`lumina/test/smoke/input_smoke_test.dart`); here the seam that keeps every
/// test away from the user's pointer, and the wire format both halves share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('default backend', () {
    test('a test binding always gets the recording backend', () {
      final choice = LuminaMouseCapture.chooseDefault(environment: const {});
      expect(choice.reason, 'test binding');
      expect(choice.createBackend(), isA<RecordingMouseCaptureBackend>());
      expect(LuminaMouseCapture.backend, isA<RecordingMouseCaptureBackend>(),
          reason: 'flutter test must never reach the platform backend');
    });

    test('LUMINA_MOUSE_CAPTURE=off or record forces the recording backend, even outside a test binding', () {
      for (final value in ['off', 'record']) {
        final choice = LuminaMouseCapture.chooseDefault(
          environment: {'LUMINA_MOUSE_CAPTURE': value},
          isTestBinding: false,
          platform: TargetPlatform.linux,
          isWeb: false,
        );
        expect(choice.reason, 'LUMINA_MOUSE_CAPTURE=$value');
        expect(choice.createBackend(), isA<RecordingMouseCaptureBackend>());
      }
    });

    test('the web and other platforms get the recording backend; Linux gets the platform channel', () {
      expect(
        LuminaMouseCapture.chooseDefault(environment: const {}, isTestBinding: false, isWeb: true).reason,
        'web',
      );
      expect(
        LuminaMouseCapture.chooseDefault(
          environment: const {},
          isTestBinding: false,
          platform: TargetPlatform.windows,
          isWeb: false,
        ).reason,
        'not Linux',
      );
      final linux = LuminaMouseCapture.chooseDefault(
        environment: const {},
        isTestBinding: false,
        platform: TargetPlatform.linux,
        isWeb: false,
      );
      expect(linux.reason, 'platform channel');
      expect(linux.createBackend(), isA<MethodChannelMouseCaptureBackend>());
    });
  });

  group('RecordingMouseCaptureBackend', () {
    test('records capture and release without calling the platform', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelMouseCaptureBackend.channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelMouseCaptureBackend.channel, null));

      final backend = RecordingMouseCaptureBackend();
      expect(await backend.capture(centre: const Offset(640, 360)), isTrue);
      await backend.release();
      expect(backend.requests, ['capture(640.0,360.0)', 'release']);
      expect(backend.isCaptured, isFalse);
      expect(calls, isEmpty, reason: 'the recording backend must never reach the native side');
    });

    test('support reports the simulated lock', () async {
      final soft = await RecordingMouseCaptureBackend().support();
      expect(soft.kind, MouseCaptureBackendKind.recording);
      expect(soft.pointerLock, isFalse);
      expect(soft.relativeMotion, isFalse);

      final locked = await RecordingMouseCaptureBackend(simulateLock: true).support();
      expect(locked.pointerLock, isTrue);
      expect(locked.relativeMotion, isTrue);
    });

    test('emitted motion and loss arrive on events, and a simulated lock confirms itself', () async {
      final backend = RecordingMouseCaptureBackend(simulateLock: true);
      final events = <MouseCaptureEvent>[];
      final sub = backend.events.listen(events.add);
      addTearDown(sub.cancel);

      await backend.capture();
      backend.emitMotion(3, -2);
      backend.emitLost();
      await pumpEventQueue();

      expect(events, [
        const MouseCaptureLocked(),
        const MouseCaptureMotion(3, -2),
        const MouseCaptureLost(),
      ]);
      expect(backend.isCaptured, isFalse, reason: 'a loss ends the capture');
    });
  });

  group('MethodChannelMouseCaptureBackend', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelMouseCaptureBackend.channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'support':
            return {'kind': 'wayland', 'pointerLock': true, 'relativeMotion': true, 'detail': 'zwp_pointer_constraints_v1'};
          case 'capture':
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelMouseCaptureBackend.channel, null);
    });

    test('support, capture and release speak the channel format', () async {
      final backend = MethodChannelMouseCaptureBackend();
      final support = await backend.support();
      expect(support.kind, MouseCaptureBackendKind.wayland);
      expect(support.pointerLock, isTrue);
      expect(support.relativeMotion, isTrue);
      expect(support.detail, 'zwp_pointer_constraints_v1');

      expect(await backend.capture(centre: const Offset(640, 360)), isTrue);
      await backend.release();
      expect(calls.map((c) => c.method), ['support', 'capture', 'release']);
      expect(calls[1].arguments, {'x': 640.0, 'y': 360.0});
    });

    test('a missing plugin is reported as unsupported, never thrown', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelMouseCaptureBackend.channel, null);
      final backend = MethodChannelMouseCaptureBackend();
      final support = await backend.support();
      expect(support.kind, MouseCaptureBackendKind.unsupported);
      expect(await backend.capture(), isFalse);
      await backend.release();
    });

    test('event-channel messages decode into capture events', () async {
      final backend = MethodChannelMouseCaptureBackend();
      final events = <MouseCaptureEvent>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        MethodChannelMouseCaptureBackend.eventChannel,
        MockStreamHandler.inline(onListen: (args, sink) {
          sink.success({'type': 'locked'});
          sink.success({'type': 'motion', 'dx': 1.5, 'dy': -2});
          sink.success({'type': 'lost'});
          sink.success({'type': 'unknown-from-a-newer-plugin'});
        }),
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(MethodChannelMouseCaptureBackend.eventChannel, null));

      final sub = backend.events.listen(events.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(events, [
        const MouseCaptureLocked(),
        const MouseCaptureMotion(1.5, -2),
        const MouseCaptureLost(),
      ]);
    });
  });

  test('capture events compare by value and describe themselves', () {
    expect(const MouseCaptureMotion(1, 2), const MouseCaptureMotion(1, 2));
    expect(const MouseCaptureMotion(1, 2), isNot(const MouseCaptureMotion(2, 1)));
    expect(const MouseCaptureMotion(1, 2).toString(), 'MouseCaptureMotion(1.0, 2.0)');
    expect(MouseCaptureBackendKind.x11.name, 'x11');
  });

  test('the process-wide backend can be replaced and restored', () {
    final previous = LuminaMouseCapture.backend;
    final mine = RecordingMouseCaptureBackend(simulateLock: true);
    LuminaMouseCapture.backend = mine;
    expect(LuminaMouseCapture.backend, same(mine));
    LuminaMouseCapture.backend = previous;
    expect(LuminaMouseCapture.backend, same(previous));
  });
}
