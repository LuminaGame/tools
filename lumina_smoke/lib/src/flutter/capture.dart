import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show RepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

/// PNG captures of a running Flutter app in widget and integration tests.
abstract final class SmokeCapture {
  /// The PNG of the [RenderRepaintBoundary] [repaintBoundary] finds, at
  /// [pixelRatio].
  static Future<Uint8List> captureWidgetPng(WidgetTester tester, Finder repaintBoundary, {double pixelRatio = 1.0}) async {
    return (await tester.runAsync(() async {
      final element = repaintBoundary.evaluate().first;
      final renderObject = element.renderObject as RenderRepaintBoundary;
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) throw StateError('Failed to encode the RepaintBoundary to PNG bytes');
        return byteData.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
  }

  /// A frame of an integration test: [boundary] (or the first
  /// [RepaintBoundary]) through [captureWidgetPng], else the binding's own
  /// screenshot.
  ///
  /// [binding] is the test's `IntegrationTestWidgetsFlutterBinding`; it is
  /// typed loosely so that this package does not depend on the
  /// `integration_test` plugin, which would then be registered in every app
  /// built on a package that depends on this one.
  static Future<Uint8List> captureIntegrationPng(Object binding, WidgetTester tester, {Finder? boundary}) async {
    if (boundary != null) return captureWidgetPng(tester, boundary);
    final defaultBoundary = find.byType(RepaintBoundary);
    if (defaultBoundary.evaluate().isNotEmpty) {
      try {
        return await captureWidgetPng(tester, defaultBoundary.first);
      } catch (_) {
        // Not paintable yet: fall back to the binding's screenshot.
      }
    }
    final bytes = await (binding as dynamic).takeScreenshot('integration_snapshot') as List<int>;
    return Uint8List.fromList(bytes);
  }
}
