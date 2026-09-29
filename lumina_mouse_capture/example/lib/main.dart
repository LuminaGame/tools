import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lumina_mouse_capture/lumina_mouse_capture.dart';

/// The app lumina's input smoke runs inside a nested, headless GNOME Shell:
/// it captures the pointer through the real plugin
/// and prints every capture event as a JSON line on stdout.
///
/// C captures at the window centre, F4 releases, a click while released
/// captures again. A captured mouse turns the "view" (yaw/pitch) on screen,
/// however far it moves.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A second, plain window that takes the focus away (the smoke's "lost").
  if (Platform.environment['LMC_DECOY'] == '1') {
    runApp(WidgetsApp(color: const Color(0xFF30363D), builder: _decoy));
    return;
  }
  runApp(const CaptureDemoApp());
}

Widget _decoy(BuildContext context, Widget? child) => const ColoredBox(
      color: Color(0xFF30363D),
      child: Center(
        child: Text('another window has the focus', style: TextStyle(color: Color(0xFFE6EDF3), fontSize: 22)),
      ),
    );

void emit(Map<String, Object?> event) {
  stdout.writeln(jsonEncode(event));
}

class CaptureDemoApp extends StatelessWidget {
  const CaptureDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF101418),
      debugShowCheckedModeBanner: false,
      builder: (context, _) => const DefaultTextStyle(
        style: TextStyle(color: Color(0xFFE6EDF3), fontSize: 16, fontFamily: 'monospace'),
        child: CaptureDemo(),
      ),
    );
  }
}

class CaptureDemo extends StatefulWidget {
  const CaptureDemo({super.key});

  @override
  State<CaptureDemo> createState() => _CaptureDemoState();
}

class _CaptureDemoState extends State<CaptureDemo> {
  final MouseCaptureBackend backend = LuminaMouseCapture.backend;
  final FocusNode focus = FocusNode();
  final GlobalKey viewKey = GlobalKey();
  StreamSubscription<MouseCaptureEvent>? events;
  MouseCaptureSupport support = MouseCaptureSupport.none;
  bool captured = false;
  bool locked = false;
  double yaw = 0;
  double pitch = 0;
  double sumDx = 0;
  double sumDy = 0;
  int pointerEvents = 0;
  Offset? pointer;

  @override
  void initState() {
    super.initState();
    events = backend.events.listen(onEvent);
    unawaited(backend.support().then((value) {
      emit({
        'ev': 'support',
        'kind': value.kind.name,
        'lock': value.pointerLock,
        'relative': value.relativeMotion,
        'reason': LuminaMouseCapture.defaultBackendReason,
      });
      if (mounted) setState(() => support = value);
    }));
  }

  @override
  void dispose() {
    unawaited(events?.cancel());
    focus.dispose();
    super.dispose();
  }

  void onEvent(MouseCaptureEvent event) {
    switch (event) {
      case MouseCaptureMotion(:final dx, :final dy):
        sumDx += dx;
        sumDy += dy;
        yaw = (yaw + dx * 0.15) % 360;
        pitch = (pitch - dy * 0.15).clamp(-89.0, 89.0);
        emit({'ev': 'motion', 'dx': dx, 'dy': dy, 'sum_dx': sumDx, 'sum_dy': sumDy});
      case MouseCaptureLocked():
        locked = true;
        emit({'ev': 'locked'});
      case MouseCaptureLost():
        captured = false;
        locked = false;
        emit({'ev': 'lost'});
    }
    if (mounted) setState(() {});
  }

  Offset? viewCentre() {
    final box = viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> capture() async {
    final centre = viewCentre();
    final ok = await backend.capture(centre: centre);
    captured = ok;
    emit({'ev': 'capture', 'ok': ok, 'cx': centre?.dx, 'cy': centre?.dy});
    if (mounted) setState(() {});
  }

  Future<void> release() async {
    await backend.release();
    captured = false;
    locked = false;
    emit({'ev': 'release'});
    if (mounted) setState(() {});
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    emit({'ev': 'key', 'key': event.logicalKey.keyLabel});
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(capture());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f4) {
      unawaited(release());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void onPointer(PointerEvent event) {
    pointerEvents++;
    pointer = event.position;
    emit({'ev': 'pointer', 'x': event.position.dx, 'y': event.position.dy});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = captured ? (locked ? 'CAPTURED · LOCKED' : 'CAPTURED · waiting for the lock') : 'RELEASED';
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: onKey,
      child: MouseRegion(
        cursor: captured ? SystemMouseCursors.none : SystemMouseCursors.basic,
        onHover: onPointer,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove: onPointer,
          onPointerDown: (event) {
            emit({'ev': 'button'});
            if (!captured) unawaited(capture());
          },
          child: Container(
            key: viewKey,
            color: const Color(0xFF101418),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _ViewPainter(yaw: yaw, pitch: pitch, pointer: pointer))),
                Positioned(
                  left: 24,
                  top: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: captured ? const Color(0xFF3FB950) : const Color(0xFFF0883E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('backend: ${support.kind.name}  lock: ${support.pointerLock}  relative: ${support.relativeMotion}'),
                      Text('relative motion  Σdx ${sumDx.toStringAsFixed(0)}  Σdy ${sumDy.toStringAsFixed(0)}'),
                      Text('view  yaw ${yaw.toStringAsFixed(1)}°  pitch ${pitch.toStringAsFixed(1)}°'),
                      Text('pointer events $pointerEvents  at ${pointer == null ? '-' : '${pointer!.dx.toStringAsFixed(0)},${pointer!.dy.toStringAsFixed(0)}'}'),
                      const SizedBox(height: 8),
                      const Text('C capture · F4 release · click recaptures', style: TextStyle(color: Color(0xFF8B949E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizon that turns with yaw and tilts with pitch, and the last pointer
/// position Flutter saw (it stays put while the pointer is locked).
class _ViewPainter extends CustomPainter {
  _ViewPainter({required this.yaw, required this.pitch, required this.pointer});

  final double yaw;
  final double pitch;
  final Offset? pointer;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final horizonY = centre.dy + pitch * 4;
    canvas.drawRect(Offset.zero & Size(size.width, horizonY.clamp(0, size.height)), Paint()..color = const Color(0xFF16324F));
    canvas.drawRect(
      Rect.fromLTRB(0, horizonY.clamp(0, size.height), size.width, size.height),
      Paint()..color = const Color(0xFF223322),
    );
    // Posts every 30° of yaw scroll past as the view turns.
    final post = Paint()..color = const Color(0xFFE3B341);
    for (var a = 0; a < 360; a += 30) {
      final rel = (a - yaw + 540) % 360 - 180;
      if (rel.abs() > 60) continue;
      final x = centre.dx + rel / 60 * size.width / 2;
      canvas.drawRect(Rect.fromCenter(center: Offset(x, horizonY - 40), width: 10, height: 80), post);
    }
    final ring = Paint()
      ..color = const Color(0xFFE6EDF3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(centre, 18, ring);
    canvas.drawLine(centre + const Offset(-30, 0), centre + const Offset(30, 0), ring);
    canvas.drawLine(centre + const Offset(0, -30), centre + const Offset(0, 30), ring);
    final needle = Paint()
      ..color = const Color(0xFFFF7B72)
      ..strokeWidth = 4;
    final r = yaw * math.pi / 180;
    canvas.drawLine(centre, centre + Offset(math.sin(r), -math.cos(r)) * 60, needle);
    if (pointer != null) {
      canvas.drawCircle(pointer!, 6, Paint()..color = const Color(0xFFBC8CFF));
    }
  }

  @override
  bool shouldRepaint(_ViewPainter old) => old.yaw != yaw || old.pitch != pitch || old.pointer != pointer;
}
