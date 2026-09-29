import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riglogic_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Provide asset loader for sample.dna
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.contains('sample.dna')) {
        final bytes = File('assets/sample.dna').readAsBytesSync();
        return ByteData.sublistView(bytes);
      }
      return null;
    });
  });

  testWidgets('Renders RigLogic Example App and loads DNA', (WidgetTester tester) async {
    await tester.pumpWidget(const RigLogicExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Lumina RigLogic — Realtime MetaHuman Evaluator'), findsOneWidget);
    expect(find.text('DNA METADATA'), findsOneWidget);
    expect(find.text('INPUT CONTROLS'), findsOneWidget);
    expect(find.text('CALCULATED BLEND SHAPES (MORPH TARGETS)'), findsOneWidget);
  });
}
