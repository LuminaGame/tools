import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/smoke_mcp.dart';

/// A small app: a counter button, a long list, a horizontal drag area and
/// a key listener.
class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  var taps = 0;
  var dragged = 0.0;
  var keys = 0;
  final focus = FocusNode();

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF000000),
    builder: (context, _) => Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        setState(() => keys++);
        return KeyEventResult.handled;
      },
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => taps++),
            child: SizedBox(height: 40, child: Text('Tapped $taps', key: const ValueKey('counter'))),
          ),
          GestureDetector(
            onHorizontalDragUpdate: (d) => setState(() => dragged += d.delta.dx),
            child: SizedBox(height: 40, width: 400, child: Text('Dragged ${dragged.round()}')),
          ),
          Text('Keys $keys'),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < 100; i++) SizedBox(height: 30, child: Text('Item $i')),
                // A boundary larger than the window, mostly off it.
                const RepaintBoundary(child: SizedBox(height: 3000, child: Text('Long'))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _text(SmokeMcpResult r) => r.content.first['text']! as String;

void main() {
  testWidgets('The tools list, tap, drag, scroll, press keys and capture the running app', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _App());
    final c = SmokeMcpCommands(tester);

    final listed = _text(await c.run('widgets', {'contains': 'item'}));
    expect(listed, contains('text "Item 0" at (0, 94, 800×30)'));
    expect(listed, isNot(contains('Item 99')));
    expect(_text(await c.run('widgets', {'contains': 'counter'})), contains('key "counter" (Text)'));

    expect((await c.run('tap', {'key': 'counter'})).isError, isFalse);
    await c.run('tap', {'text': 'Tapped', 'exact': false});
    expect(find.text('Tapped 2'), findsOneWidget);

    await c.run('drag_from', {'x': 300, 'y': 60, 'dx': 150, 'dy': 0});
    // The drag recognizer keeps the slop before it accepts.
    final dragged = tester.widget<Text>(find.textContaining('Dragged ')).data!;
    expect(int.parse(dragged.split(' ').last), inInclusiveRange(100, 150));

    final scrolled = await c.run('scroll_until_visible', {'text': 'Item 80', 'x': 200, 'y': 400});
    expect(scrolled.isError, isFalse, reason: _text(scrolled));
    expect(tester.getRect(find.text('Item 80')).bottom, lessThanOrEqualTo(600));

    await c.run('press_key', {'key': 'pageDown'});
    await c.run('press_key', {'key': 'a'});
    expect(find.text('Keys 4'), findsOneWidget); // down and up each

    final shot = await c.run('screenshot', {});
    expect(shot.isError, isFalse, reason: _text(shot));
    expect(SmokeMcpCommands.decodeImage(shot).sublist(1, 4), 'PNG'.codeUnits);
    // What the window shows (here the list, no boundary covers the whole
    // window), not the long boundary scrolled into view and mostly off it.
    await c.run('scroll_until_visible', {'text': 'Long', 'x': 200, 'y': 400});
    final size = RegExp(r'\((\d+)×(\d+)\)').firstMatch(_text(await c.run('screenshot', {'save_only': true})))!;
    expect(int.parse(size.group(2)!), lessThanOrEqualTo(600));

    final missing = await c.run('tap', {'text': 'Nowhere'});
    expect(missing.isError, isTrue);
    expect(_text(missing), contains('no widget matches text "Nowhere"'));
    expect((await c.run('fly', {})).isError, isTrue);
    expect((await c.run('wait_for', {'text': 'Tapped 2', 'timeout_ms': 500})).isError, isFalse);
  });
}
