import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_smoke/src/flutter/recorder.dart';

/// What a tutorial recording draws over the app: the current step's caption
/// (with its number and a bar that fills while the step is held) and a
/// virtual cursor with a click ripple and a highlight around the control
/// being used. Driven by [SmokeTutor]; drawn by [SmokeTutorialOverlay].
class SmokeTutorialController extends ChangeNotifier {
  String? _caption;
  int _step = 0;
  int total = 0;
  double _progress = 0;
  Offset? _cursor;
  Offset? _rippleAt;
  double _ripple = -1;
  Rect? _highlight;
  int _tick = 0;

  String? get caption => _caption;

  /// Frames drawn so far: the caption's live dot pulses with it, so a held
  /// step still changes on screen.
  int get tick => _tick;

  void advance() {
    _tick++;
    notifyListeners();
  }
  int get step => _step;

  /// How far the current step's hold has run (0–1).
  double get progress => _progress;

  /// The virtual cursor's position (global, logical pixels), null hidden.
  Offset? get cursor => _cursor;
  Offset? get rippleAt => _rippleAt;

  /// The click ripple's phase (0–1), or below 0 when none runs.
  double get ripple => _ripple;
  Rect? get highlight => _highlight;

  void setCaption(String text, {int? step}) {
    _caption = text;
    _step = step ?? _step + 1;
    _progress = 0;
    notifyListeners();
  }

  void setProgress(double value) {
    _progress = value.clamp(0, 1);
    notifyListeners();
  }

  void setCursor(Offset? position) {
    _cursor = position;
    notifyListeners();
  }

  void setRipple(Offset? at, double phase) {
    _rippleAt = at;
    _ripple = phase;
    notifyListeners();
  }

  void setHighlight(Rect? rect) {
    _highlight = rect;
    notifyListeners();
  }
}

/// Wraps the app (inside the recorded `RepaintBoundary`) and draws
/// [controller]'s caption, cursor, ripple and highlight over it. Ignores
/// pointers: input reaches the app as usual.
class SmokeTutorialOverlay extends StatelessWidget {
  const SmokeTutorialOverlay({super.key, required this.controller, required this.child});

  final SmokeTutorialController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            IgnorePointer(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => CustomPaint(painter: _TutorialPainter(controller)),
              ),
            ),
          ],
        ),
      );
}

class _TutorialPainter extends CustomPainter {
  _TutorialPainter(this.c) : super(repaint: c);

  final SmokeTutorialController c;

  static const _accent = Color(0xFFF97316);

  @override
  void paint(Canvas canvas, Size size) {
    final highlight = c.highlight;
    if (highlight != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(highlight.inflate(4), const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _accent,
      );
    }
    final at = c.rippleAt;
    if (at != null && c.ripple >= 0) {
      final t = c.ripple;
      canvas.drawCircle(at, 8 + 34 * t, Paint()..color = _accent.withValues(alpha: 0.45 * (1 - t)));
      canvas.drawCircle(
        at,
        8 + 34 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _accent.withValues(alpha: 1 - t),
      );
    }
    final caption = c.caption;
    if (caption != null) _paintCaption(canvas, size, caption);
    final cursor = c.cursor;
    if (cursor != null) _paintCursor(canvas, cursor);
  }

  void _paintCaption(Canvas canvas, Size size, String caption) {
    final label = c.total > 0 ? '${c.step}/${c.total}' : '${c.step}';
    final number = TextPainter(
      text: TextSpan(text: label, style: const TextStyle(color: Color(0xFF1C1917), fontSize: 22, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final maxText = math.min(size.width * 0.8, 1100.0);
    final text = TextPainter(
      text: TextSpan(
        text: caption,
        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 26, fontWeight: FontWeight.w700, height: 1.25),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: maxText);
    const pad = 16.0;
    final badge = Size(number.width + 20, number.height + 8);
    final w = badge.width + 14 + text.width + pad * 2;
    final h = math.max(badge.height, text.height) + pad * 2 + 6;
    final left = (size.width - w) / 2;
    const top = 18.0;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(12));
    canvas.drawRRect(box.shift(const Offset(0, 3)), Paint()..color = const Color(0x66000000));
    canvas.drawRRect(box, Paint()..color = const Color(0xE6111827));
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + pad, top + (h - 6 - badge.height) / 2, badge.width, badge.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(badgeRect, Paint()..color = _accent);
    number.paint(canvas, badgeRect.outerRect.topLeft + Offset(10, 4));
    text.paint(canvas, Offset(left + pad + badge.width + 14, top + (h - 6 - text.height) / 2));
    // A live dot pulsing every frame.
    final pulse = 0.5 + 0.5 * math.sin(c.tick * 0.35);
    canvas.drawCircle(Offset(left + w - 12, top + 12), 4, Paint()..color = _accent.withValues(alpha: 0.35 + 0.65 * pulse));
    // The step's hold, filling.
    final bar = Rect.fromLTWH(left + 12, top + h - 8, (w - 24) * c.progress, 3);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = _accent);
  }

  void _paintCursor(Canvas canvas, Offset p) {
    final path = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(p.dx, p.dy + 26)
      ..lineTo(p.dx + 7, p.dy + 20)
      ..lineTo(p.dx + 12, p.dy + 31)
      ..lineTo(p.dx + 17, p.dy + 29)
      ..lineTo(p.dx + 12, p.dy + 18)
      ..lineTo(p.dx + 21, p.dy + 18)
      ..close();
    canvas.drawPath(path.shift(const Offset(2, 2)), Paint()..color = const Color(0x55000000));
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF111111),
    );
  }

  @override
  bool shouldRepaint(_TutorialPainter old) => true;
}

/// Records a tutorial: captions, a virtual cursor that glides to each
/// control, click ripples, all drawn by [SmokeTutorialOverlay] inside the
/// recorded app and recorded frame by frame by [recorder]. Clicks, drags and
/// typing are virtual input through [tester] (never the real mouse). Every
/// wait keeps rendering (the caption's bar fills), so no frame is held.
class SmokeTutor {
  SmokeTutor(this.tester, this.recorder, this.controller, {int total = 0}) {
    controller.total = total;
  }

  final WidgetTester tester;
  final SmokeRecorder recorder;
  final SmokeTutorialController controller;

  /// How long a caption stays before the step's actions start.
  Duration readTime = const Duration(milliseconds: 2600);

  /// Where the virtual cursor rests.
  Offset _at = const Offset(800, 500);

  Future<void> _frame() {
    controller.advance();
    return recorder.hold(recorder.frameInterval);
  }

  /// Keeps the app running for [duration], recording every frame; the
  /// caption's bar fills meanwhile.
  Future<void> hold(Duration duration) async {
    final n = math.max(1, (duration.inMicroseconds / recorder.frameInterval.inMicroseconds).ceil());
    final from = controller.progress;
    for (var i = 1; i <= n; i++) {
      controller.setProgress(from + (1 - from) * i / n);
      await _frame();
    }
  }

  /// Shows [text] as the next step and holds it for [readTime] (or [read]).
  Future<void> step(String text, {Duration? read}) async {
    controller.setCaption(text);
    await hold(read ?? readTime);
  }

  /// Glides the cursor to [to] (global position) in [duration], eased.
  Future<void> moveTo(Offset to, {Duration duration = const Duration(milliseconds: 750)}) async {
    final from = controller.cursor ?? _at;
    final n = math.max(2, (duration.inMicroseconds / recorder.frameInterval.inMicroseconds).ceil());
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      final e = t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
      controller.setCursor(Offset.lerp(from, to, e.toDouble()));
      await _frame();
    }
    _at = to;
  }

  /// Scrolls [finder] into view, glides to its centre and outlines it.
  Future<Offset> point(Finder finder) async {
    // Scrolled into view first (a long list, a dialog).
    await tester.ensureVisible(finder.first);
    await tester.pump();
    final rect = tester.getRect(finder.first);
    controller.setHighlight(rect);
    await moveTo(rect.center);
    return rect.center;
  }

  Future<void> _ripple(Offset at) async {
    for (var i = 0; i <= 12; i++) {
      controller.setRipple(at, i / 12);
      await _frame();
    }
    controller.setRipple(null, -1);
  }

  /// Glides to [finder], clicks it (virtual tap) with a ripple, then holds
  /// [after] to show the result.
  Future<void> click(Finder finder, {Duration after = const Duration(milliseconds: 900), bool doubleClick = false}) async {
    final at = await point(finder);
    await tester.tap(finder.first, kind: PointerDeviceKind.mouse);
    if (doubleClick) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(finder.first, kind: PointerDeviceKind.mouse);
    }
    await _ripple(at);
    controller.setHighlight(null);
    await hold(after);
  }

  /// Glides to [at] (global) and clicks there (virtual tap).
  Future<void> clickAt(Offset at, {Duration after = const Duration(milliseconds: 900)}) async {
    await moveTo(at);
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await _ripple(at);
    await hold(after);
  }

  /// Presses at [from] and drags to [to] in [steps] moves with [buttons]
  /// held (a gizmo handle, an orbit), the cursor following.
  Future<void> drag(Offset from, Offset to, {int steps = 40, int buttons = kPrimaryButton}) async {
    await moveTo(from);
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse, buttons: buttons);
    await _frame();
    for (var i = 1; i <= steps; i++) {
      final p = Offset.lerp(from, to, i / steps)!;
      await gesture.moveTo(p);
      controller.setCursor(p);
      await _frame();
    }
    await gesture.up();
    _at = to;
    await hold(const Duration(milliseconds: 500));
  }

  /// Clicks [field] and types [text] into it, a character at a time.
  Future<void> type(Finder field, String text) async {
    await click(field, after: const Duration(milliseconds: 200));
    controller.setHighlight(tester.getRect(field.first));
    await recorder.typeText(field, text, perCharacter: const Duration(milliseconds: 140));
    controller.setHighlight(null);
  }

  /// Hides the cursor and the caption (the end).
  void finish() {
    controller
      ..setCursor(null)
      ..setHighlight(null);
  }
}
