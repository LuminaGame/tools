import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/flutter.dart';

void main() {
  testWidgets('a tutorial step shows its caption, glides the cursor to a control, clicks it and never holds a frame',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var clicks = 0;
    final controller = SmokeTutorialController();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: SmokeTutorialOverlay(
        controller: controller,
        child: Container(
          color: const Color(0xFF0B0F17),
          alignment: Alignment.center,
          child: GestureDetector(
            key: const ValueKey('button'),
            onTap: () => clicks++,
            child: Container(width: 160, height: 60, color: const Color(0xFF38BDF8)),
          ),
        ),
      ),
    ));
    final rec = SmokeRecorder(tester, boundary: find.byKey(boundary));
    final tutor = SmokeTutor(tester, rec, controller, total: 2)..readTime = const Duration(milliseconds: 600);

    await tutor.step('Press the button');
    expect(controller.caption, 'Press the button');
    expect(controller.step, 1);
    expect(controller.progress, 1.0, reason: 'the bar filled over the hold');
    await tutor.click(find.byKey(const ValueKey('button')));
    expect(clicks, 1, reason: 'a virtual tap reached the app');
    expect(controller.cursor, tester.getCenter(find.byKey(const ValueKey('button'))));
    await tutor.step('Done');
    expect(controller.step, 2);
    expect(rec.frameCount, greaterThan(40));
    expect(rec.longestStill, lessThan(const Duration(milliseconds: 200)), reason: 'every frame moves: no held picture');
  });
}
