import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/src/flutter/capture.dart';
import 'package:lumina_smoke/src/flutter/recorder.dart';

/// A smoke MCP tool's answer: MCP content items (text, PNG images) and
/// whether it failed.
class SmokeMcpResult {
  SmokeMcpResult(this.content, {this.isError = false});

  SmokeMcpResult.text(String text, {bool isError = false})
    : this([
        {'type': 'text', 'text': text},
      ], isError: isError);

  final List<Map<String, Object?>> content;
  final bool isError;

  Map<String, Object?> toJson() => {'content': content, if (isError) 'isError': true};
}

/// The smoke MCP's tools on a running app, through [tester]: every input is
/// synthesized inside Flutter (the real mouse and keyboard are never used).
/// Coordinates are logical pixels from the view's top left. A widget is
/// named by `text` (`exact: false` for a part of it), `key` (a string
/// `ValueKey`), `tooltip` or `semantics_label`, and `index` among several.
class SmokeMcpCommands {
  SmokeMcpCommands(this.tester, {Directory? screenshotDir})
    : screenshotDir = screenshotDir ?? Directory.systemTemp.createTempSync('lumina_smoke_mcp_shots_');

  final WidgetTester tester;

  /// Where screenshots are written (their paths are in the answers).
  final Directory screenshotDir;

  SmokeRecorder? _recorder;
  var _shots = 0;

  /// The tool names [run] answers.
  static const tools = [
    'info',
    'screenshot',
    'widgets',
    'tap',
    'tap_at',
    'drag',
    'drag_from',
    'scroll',
    'scroll_until_visible',
    'enter_text',
    'press_key',
    'wait',
    'wait_for',
    'record_start',
    'record_stop',
  ];

  /// Runs [tool] with [args]; a failure is an error result, never a throw.
  Future<SmokeMcpResult> run(String tool, Map<String, Object?> args) async {
    try {
      final result = switch (tool) {
        'info' => _info(),
        'screenshot' => _screenshot(args),
        'widgets' => _widgets(args),
        'tap' => _act(() => tester.tap(_target(args), warnIfMissed: false), 'tapped ${_describe(args)}'),
        'tap_at' => _act(() => tester.tapAt(_point(args)), 'tapped at ${_point(args)}'),
        'drag' => _act(
          () => _drag(tester.getCenter(_target(args)), args),
          'dragged ${_describe(args)} by ${_delta(args)}',
        ),
        'drag_from' => _act(() => _drag(_point(args), args), 'dragged from ${_point(args)} by ${_delta(args)}'),
        'scroll' => _act(() => _scroll(_point(args), _delta(args, dyDefault: 120)), 'scrolled at ${_point(args)}'),
        'scroll_until_visible' => _scrollUntilVisible(args),
        'enter_text' => _act(
          () => tester.enterText(_target(args), args['value'] as String? ?? ''),
          'entered text into ${_describe(args)}',
        ),
        'press_key' => _act(() => tester.sendKeyEvent(_key(args['key'])), 'pressed ${args['key']}'),
        'wait' => _wait(args),
        'wait_for' => _waitFor(args),
        'record_start' => _recordStart(args),
        'record_stop' => _recordStop(args),
        _ => Future.value(SmokeMcpResult.text('Unknown tool "$tool"', isError: true)),
      };
      return await result;
    } catch (e) {
      return SmokeMcpResult.text('$tool failed: $e', isError: true);
    }
  }

  Size get _viewSize => tester.view.physicalSize / tester.view.devicePixelRatio;

  Future<SmokeMcpResult> _info() async => SmokeMcpResult.text(
    jsonEncode({
      'view': {'width': _viewSize.width, 'height': _viewSize.height, 'devicePixelRatio': tester.view.devicePixelRatio},
      'recording': _recorder != null,
      'screenshots': screenshotDir.path,
    }),
  );

  /// After an action: a frame, and while recording the next 0.4 s on video.
  Future<SmokeMcpResult> _act(Future<void> Function() action, String done) async {
    await action();
    await tester.pump();
    final recorder = _recorder;
    if (recorder != null) {
      await recorder.hold(const Duration(milliseconds: 400));
    } else {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    return SmokeMcpResult.text(done);
  }

  Finder _finder(Map<String, Object?> a) {
    final exact = a['exact'] != false;
    if (a['text'] case final String text) return exact ? find.text(text) : find.textContaining(text);
    if (a['key'] case final String key) return find.byKey(ValueKey<String>(key));
    if (a['tooltip'] case final String tooltip) return find.byTooltip(tooltip);
    if (a['semantics_label'] case final String label) return find.bySemanticsLabel(label);
    throw ArgumentError('name the widget by text, key, tooltip or semantics_label');
  }

  Finder _target(Map<String, Object?> a) {
    final f = _finder(a);
    final count = f.evaluate().length;
    final index = (a['index'] as num?)?.toInt() ?? 0;
    if (count == 0) throw StateError('no widget matches ${_describe(a)}');
    if (index >= count) throw StateError('${_describe(a)} matches $count widgets; index $index is past them');
    return f.at(index);
  }

  String _describe(Map<String, Object?> a) {
    for (final k in const ['text', 'key', 'tooltip', 'semantics_label']) {
      if (a[k] is String) return '$k "${a[k]}"${a['index'] == null ? '' : ' #${a['index']}'}';
    }
    return 'nothing';
  }

  Offset _point(Map<String, Object?> a) {
    final x = a['x'], y = a['y'];
    if (x is! num || y is! num) throw ArgumentError('x and y (logical pixels) are required');
    return Offset(x.toDouble(), y.toDouble());
  }

  Offset _delta(Map<String, Object?> a, {double dyDefault = 0}) =>
      Offset((a['dx'] as num?)?.toDouble() ?? 0, (a['dy'] as num?)?.toDouble() ?? dyDefault);

  Duration _duration(Map<String, Object?> a) => Duration(milliseconds: (a['duration_ms'] as num?)?.toInt() ?? 300);

  /// A drag over its duration; while recording, every step on video.
  Future<void> _drag(Offset from, Map<String, Object?> args) async {
    final recorder = _recorder;
    final delta = _delta(args), duration = _duration(args);
    if (recorder == null) return tester.timedDragFrom(from, delta, duration);
    final steps = math.max(2, duration.inMicroseconds ~/ recorder.frameInterval.inMicroseconds);
    await recorder.drag(from, from + delta, steps: steps);
  }

  Future<void> _scroll(Offset at, Offset delta) async {
    // Through the tester: a live binding drops events it takes for the
    // device's while a test runs.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(delta));
    await tester.pump();
  }

  Future<SmokeMcpResult> _scrollUntilVisible(Map<String, Object?> a) async {
    final f = _finder(a);
    final at = _point(a);
    final step = _delta(a, dyDefault: 200);
    final most = (a['max_scrolls'] as num?)?.toInt() ?? 60;
    for (var i = 0; i <= most; i++) {
      if (f.evaluate().isNotEmpty) {
        await tester.ensureVisible(f.first);
        await tester.pump();
        final r = tester.getRect(f.first);
        return _act(() async {}, 'visible after $i scrolls: ${_describe(a)} at ${_rect(r)}');
      }
      await _scroll(at, step);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    return SmokeMcpResult.text('${_describe(a)} not found after $most scrolls', isError: true);
  }

  LogicalKeyboardKey _key(Object? name) {
    if (name is! String || name.isEmpty) throw ArgumentError('key is required (for example "pageDown", "tab", "a")');
    final wanted = name.toLowerCase().replaceAll(' ', '');
    for (final k in LogicalKeyboardKey.knownLogicalKeys) {
      final label = (k.debugName ?? '').toLowerCase().replaceAll(' ', '');
      if (label == wanted || k.keyLabel.toLowerCase() == wanted) return k;
    }
    throw ArgumentError('unknown key "$name"');
  }

  Future<SmokeMcpResult> _wait(Map<String, Object?> a) async {
    final d = Duration(milliseconds: (a['ms'] as num?)?.toInt() ?? 500);
    final recorder = _recorder;
    if (recorder != null) {
      await recorder.hold(d);
    } else {
      await tester.runAsync(() => Future<void>.delayed(d));
      await tester.pump();
    }
    return SmokeMcpResult.text('waited ${d.inMilliseconds} ms');
  }

  Future<SmokeMcpResult> _waitFor(Map<String, Object?> a) async {
    final f = _finder(a);
    final timeout = Duration(milliseconds: (a['timeout_ms'] as num?)?.toInt() ?? 10000);
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      if (f.evaluate().isNotEmpty) return SmokeMcpResult.text('${_describe(a)} after ${watch.elapsedMilliseconds} ms');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    return SmokeMcpResult.text('${_describe(a)} did not appear in ${timeout.inMilliseconds} ms', isError: true);
  }

  /// The whole view's boundary: the [RepaintBoundary] showing the most of the
  /// screen (its area inside the view: a long scrolled list's boundary is
  /// larger than the window but mostly off it).
  Finder _screen() {
    final view = tester.view;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    Element? best;
    var area = -1.0;
    for (final e in find.byType(RepaintBoundary).evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final shown = (box.localToGlobal(Offset.zero) & box.size).intersect(screen);
      if (shown.width <= 0 || shown.height <= 0) continue;
      final a = shown.width * shown.height;
      if (a > area) {
        area = a;
        best = e;
      }
    }
    if (best == null) throw StateError('nothing painted yet');
    return find.byElementPredicate((e) => identical(e, best));
  }

  Future<SmokeMcpResult> _screenshot(Map<String, Object?> a) async {
    final boundary = a['key'] is String ? find.byKey(ValueKey<String>(a['key'] as String)) : _screen();
    final scale = (a['scale'] as num?)?.toDouble() ?? 1.0;
    await tester.pump();
    final png = await SmokeCapture.captureWidgetPng(tester, boundary, pixelRatio: scale);
    final file = File('${screenshotDir.path}/shot_${(_shots++).toString().padLeft(4, '0')}.png')..writeAsBytesSync(png);
    final size = tester.getSize(boundary);
    return SmokeMcpResult([
      {'type': 'text', 'text': '${file.path} (${(size.width * scale).round()}×${(size.height * scale).round()})'},
      if (a['save_only'] != true) {'type': 'image', 'data': base64Encode(png), 'mimeType': 'image/png'},
    ]);
  }

  String _rect(Rect r) => '(${r.left.round()}, ${r.top.round()}, ${r.width.round()}×${r.height.round()})';

  /// Text, text fields and string keys on screen with their rectangles, top
  /// to bottom.
  Future<SmokeMcpResult> _widgets(Map<String, Object?> a) async {
    final contains = (a['contains'] as String?)?.toLowerCase();
    final limit = (a['limit'] as num?)?.toInt() ?? 200;
    final view = Offset.zero & _viewSize;
    final rows = <(Rect, String)>[];
    void add(Element e, String what) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (!r.overlaps(view)) return;
      if (contains != null && !what.toLowerCase().contains(contains)) return;
      rows.add((r, what));
    }

    for (final e in find.byType(Text).evaluate()) {
      final t = (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText();
      if (t != null && t.trim().isNotEmpty) add(e, 'text "${t.trim()}"');
    }
    for (final e in find.byType(EditableText).evaluate()) {
      add(e, 'field "${(e.widget as EditableText).controller.text}"');
    }
    for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate()) {
      add(e, 'key "${(e.widget.key! as ValueKey<String>).value}" (${e.widget.runtimeType})');
    }
    rows.sort((p, q) => p.$1.top != q.$1.top ? p.$1.top.compareTo(q.$1.top) : p.$1.left.compareTo(q.$1.left));
    final shown = rows.take(limit).map((r) => '${r.$2} at ${_rect(r.$1)}').join('\n');
    final more = rows.length > limit ? '\n… ${rows.length - limit} more (narrow with contains)' : '';
    return SmokeMcpResult.text(rows.isEmpty ? 'nothing matches' : '$shown$more');
  }

  Future<SmokeMcpResult> _recordStart(Map<String, Object?> a) async {
    if (_recorder != null) return SmokeMcpResult.text('already recording', isError: true);
    final boundary = a['key'] is String ? find.byKey(ValueKey<String>(a['key'] as String)) : _screen();
    final size = tester.getSize(boundary);
    // At least the smallest smoke video, the UI re-rasterised.
    final ratio = math.max(1.0, math.max(1024 / size.width, 768 / size.height));
    _recorder = SmokeRecorder(tester, boundary: boundary, pixelRatio: ratio);
    await _recorder!.capture();
    return SmokeMcpResult.text(
      'recording ${size.width.round()}×${size.height.round()} at ×${ratio.toStringAsFixed(2)}',
    );
  }

  Future<SmokeMcpResult> _recordStop(Map<String, Object?> a) async {
    final recorder = _recorder;
    if (recorder == null) return SmokeMcpResult.text('not recording', isError: true);
    final name = a['name'];
    if (name is! String || name.isEmpty) {
      return SmokeMcpResult.text('name (the smoke test name) is required', isError: true);
    }
    _recorder = null;
    // Encoded off the UI isolate: the app's window keeps answering.
    final file = (await tester.runAsync(() => recorder.saveInBackground(name)))!;
    return SmokeMcpResult.text('saved ${file.path} (${recorder.recorded.inMilliseconds / 1000} s)');
  }

  /// [png] bytes for tests.
  @visibleForTesting
  static List<int> decodeImage(SmokeMcpResult r) =>
      base64Decode(r.content.firstWhere((c) => c['type'] == 'image')['data']! as String);
}
