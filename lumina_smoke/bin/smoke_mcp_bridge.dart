// The smoke MCP's stdio server: an MCP client (Claude Code) launches an app's
// smoke MCP integration test with `smoke_launch`, then drives the app with
// the app tools, which this bridge forwards to the test's own server
// (`serveSmokeMcp` in package:lumina_smoke/smoke_mcp.dart) over HTTP on
// 127.0.0.1 with its bearer token. All input is synthesized inside Flutter:
// the user's mouse and keyboard are never touched, and the app runs in its
// own window beside whatever the user is doing.
//
// Register it with `claude mcp add lumina-smoke -- dart <this file>`; it
// imports nothing but `dart:` libraries, so `dart` runs it from anywhere.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _version = '2025-06-18';
const int _unavailable = -32000;

final _client = HttpClient();
Process? _app;
File? _connection;
File? _log;
String? _launched;

void main() async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException catch (e) {
      _emit({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error: ${e.message}'},
      });
      continue;
    }
    if (message is! Map) continue;
    final id = message['id'];
    final method = message['method'];
    final params = message['params'] is Map ? Map<String, Object?>.from(message['params'] as Map) : <String, Object?>{};
    if (id == null) continue; // notifications
    try {
      final result = switch (method) {
        'initialize' => {
          'protocolVersion': _version,
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': 'lumina-smoke', 'version': '0.1.0'},
          'instructions':
              'Launch an app\'s smoke MCP integration test with smoke_launch, then drive it with the app tools '
              '(coordinates in logical pixels; widgets named by text, key, tooltip or semantics_label). '
              'smoke_stop ends the run.',
        },
        'ping' => <String, Object?>{},
        'tools/list' => {'tools': _tools},
        'tools/call' => await _call(params['name'] as String? ?? '', _map(params['arguments'])),
        _ => throw _RpcError(-32601, 'Method not found: $method'),
      };
      _emit({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on _RpcError catch (e) {
      _emit({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': e.code, 'message': e.message},
      });
    }
  }
  await _stop();
  _client.close(force: true);
}

void _emit(Object message) => stdout.writeln(jsonEncode(message));

Map<String, Object?> _map(Object? o) => o is Map ? Map<String, Object?>.from(o) : {};

class _RpcError {
  _RpcError(this.code, this.message);
  final int code;
  final String message;
}

Map<String, Object?> _text(String text, {bool error = false}) => {
  'content': [
    {'type': 'text', 'text': text},
  ],
  if (error) 'isError': true,
};

Future<Map<String, Object?>> _call(String name, Map<String, Object?> args) async {
  switch (name) {
    case 'smoke_launch':
      return _launch(args);
    case 'smoke_status':
      return _text(await _status());
    case 'smoke_stop':
      return _text(await _stop());
  }
  if (!_appTools.any((t) => t['name'] == name)) throw _RpcError(-32602, 'Unknown tool: $name');
  return _forward(name, args);
}

/// [name] with [args] to the served app.
Future<Map<String, Object?>> _forward(String name, Map<String, Object?> args) async {
  final connection = _readConnection();
  if (connection == null) {
    return _text('No app is being served: call smoke_launch first. ${await _status()}', error: true);
  }
  try {
    final request = await _client.postUrl(Uri.parse(connection['url'] as String));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${connection['token']}');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'tool': name, 'arguments': args}));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      return _text('The app answered HTTP ${response.statusCode}: $body', error: true);
    }
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } on SocketException catch (e) {
    throw _RpcError(_unavailable, 'The app is not reachable (${e.message}). ${await _status()}');
  }
}

Map<String, Object?>? _readConnection() {
  final file = _connection;
  if (file == null || !file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map && decoded['url'] is String && decoded['token'] is String) {
      return Map<String, Object?>.from(decoded);
    }
  } catch (_) {}
  return null;
}

Future<Map<String, Object?>> _launch(Map<String, Object?> args) async {
  final dir = args['package_dir'] as String?;
  final target = args['target'] as String?;
  if (dir == null || target == null) return _text('package_dir and target are required', error: true);
  if (_app != null) await _stop();
  final run = DateTime.now().millisecondsSinceEpoch;
  final base = Directory('${Directory.systemTemp.path}/lumina_smoke_mcp')..createSync(recursive: true);
  final connection = File('${base.path}/session_$run.json');
  final log = File('${base.path}/session_$run.log');
  final env = {for (final e in _map(args['env']).entries) e.key: '${e.value}'};
  final device =
      args['device'] as String? ??
      (Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : 'linux');
  final flutter = args['flutter'] as String? ?? 'flutter';
  final process = await Process.start(
    flutter,
    ['test', target, '-d', device, '--dart-define=LUMINA_SMOKE_MCP=${connection.path}'],
    workingDirectory: dir,
    environment: {...env, 'LUMINA_SMOKE_MCP': connection.path},
    runInShell: Platform.isWindows,
  );
  final sink = log.openWrite();
  process.stdout.listen(sink.add);
  process.stderr.listen(sink.add);
  var exited = false;
  unawaited(
    process.exitCode.then((_) {
      exited = true;
      if (identical(_app, process)) _app = null;
    }),
  );
  _app = process;
  _connection = connection;
  _log = log;
  _launched = '$target in $dir on $device';
  final timeout = Duration(seconds: (args['timeout_s'] as num?)?.toInt() ?? 900);
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (_readConnection() != null) {
      return _text('Serving $_launched after ${watch.elapsed.inSeconds} s; log: ${log.path}');
    }
    if (exited) return _text('The test ended before serving. Log tail:\n${_tail(log)}', error: true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return _text('Not serving after ${timeout.inSeconds} s. Log tail:\n${_tail(log)}', error: true);
}

String _tail(File log, {int lines = 40}) {
  if (!log.existsSync()) return '(no log)';
  final all = log.readAsLinesSync();
  return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
}

Future<String> _status() async {
  if (_launched == null) return 'Nothing launched.';
  final serving = _readConnection() != null;
  return '${_app == null
      ? 'Ended'
      : serving
      ? 'Serving'
      : 'Starting'}: $_launched; log: ${_log?.path}';
}

Future<String> _stop() async {
  final app = _app;
  if (app == null) return 'Nothing running.';
  if (_readConnection() != null) {
    try {
      await _forward('stop', const {});
    } catch (_) {}
  }
  final code = await app.exitCode.timeout(
    const Duration(seconds: 60),
    onTimeout: () async {
      await _killTree(app);
      return -1;
    },
  );
  _app = null;
  return 'Stopped $_launched (exit $code). Log tail:\n${_tail(_log!, lines: 15)}';
}

Map<String, Object?> _schema(Map<String, Object?> properties, [List<String> required = const []]) => {
  'type': 'object',
  'properties': properties,
  if (required.isNotEmpty) 'required': required,
};

const _target = {
  'text': {'type': 'string', 'description': 'A Text widget\'s text (whole, or a part with exact: false).'},
  'exact': {'type': 'boolean'},
  'key': {'type': 'string', 'description': 'A ValueKey<String>.'},
  'tooltip': {'type': 'string'},
  'semantics_label': {'type': 'string'},
  'index': {'type': 'integer', 'description': 'Which of several matches (0 first).'},
};
const _xy = {
  'x': {'type': 'number', 'description': 'Logical pixels from the view\'s left.'},
  'y': {'type': 'number', 'description': 'Logical pixels from the view\'s top.'},
};
const _d = {
  'dx': {'type': 'number'},
  'dy': {'type': 'number'},
};

final List<Map<String, Object?>> _bridgeTools = [
  {
    'name': 'smoke_launch',
    'description':
        'Runs `flutter test <target> -d <device>` in package_dir: an integration test that pumps the app and calls '
        'serveSmokeMcp. Waits until the app serves (first builds take minutes). One app at a time.',
    'inputSchema': _schema(
      {
        'package_dir': {'type': 'string'},
        'target': {'type': 'string', 'description': 'For example integration_test/smoke_mcp_test.dart.'},
        'device': {'type': 'string'},
        'env': {'type': 'object', 'description': 'Extra environment variables.'},
        'timeout_s': {'type': 'integer'},
        'flutter': {'type': 'string', 'description': 'The flutter executable (default: flutter on PATH).'},
      },
      ['package_dir', 'target'],
    ),
  },
  {'name': 'smoke_status', 'description': 'What is launched and whether it serves.', 'inputSchema': _schema({})},
  {'name': 'smoke_stop', 'description': 'Ends the served test and closes the app.', 'inputSchema': _schema({})},
];

final List<Map<String, Object?>> _appTools = [
  {'name': 'info', 'description': 'The view\'s size and whether a video records.', 'inputSchema': _schema({})},
  {
    'name': 'screenshot',
    'description': 'A PNG of the whole view (or the widget with key), also written to a file.',
    'inputSchema': _schema({
      'key': {'type': 'string'},
      'scale': {'type': 'number'},
      'save_only': {'type': 'boolean', 'description': 'Only write the file.'},
    }),
  },
  {
    'name': 'widgets',
    'description': 'Texts, fields and keyed widgets on screen with their rectangles (x, y, w×h), top to bottom.',
    'inputSchema': _schema({
      'contains': {'type': 'string'},
      'limit': {'type': 'integer'},
    }),
  },
  {'name': 'tap', 'description': 'Taps a widget.', 'inputSchema': _schema(_target)},
  {
    'name': 'tap_at',
    'description': 'Taps a point.',
    'inputSchema': _schema(_xy, ['x', 'y']),
  },
  {
    'name': 'drag',
    'description': 'Drags a widget by dx, dy.',
    'inputSchema': _schema({
      ..._target,
      ..._d,
      'duration_ms': {'type': 'integer'},
    }),
  },
  {
    'name': 'drag_from',
    'description': 'Drags from a point by dx, dy (a slider\'s thumb, a viewport orbit).',
    'inputSchema': _schema(
      {
        ..._xy,
        ..._d,
        'duration_ms': {'type': 'integer'},
      },
      ['x', 'y'],
    ),
  },
  {
    'name': 'scroll',
    'description': 'A mouse-wheel scroll at a point (dy > 0 scrolls down).',
    'inputSchema': _schema({..._xy, ..._d}, ['x', 'y']),
  },
  {
    'name': 'scroll_until_visible',
    'description': 'Scrolls at x, y by dy until the widget is built, then brings it into view.',
    'inputSchema': _schema(
      {
        ..._target,
        ..._xy,
        ..._d,
        'max_scrolls': {'type': 'integer'},
      },
      ['x', 'y'],
    ),
  },
  {
    'name': 'enter_text',
    'description': 'Replaces a text field\'s text.',
    'inputSchema': _schema({
      ..._target,
      'value': {'type': 'string'},
    }),
  },
  {
    'name': 'press_key',
    'description': 'Presses and releases a key (a logical key name: "pageDown", "tab", "enter", "a").',
    'inputSchema': _schema(
      {
        'key': {'type': 'string'},
      },
      ['key'],
    ),
  },
  {
    'name': 'wait',
    'description': 'Lets the app run (recording while a video records).',
    'inputSchema': _schema({
      'ms': {'type': 'integer'},
    }),
  },
  {
    'name': 'wait_for',
    'description': 'Waits until a widget appears.',
    'inputSchema': _schema({
      ..._target,
      'timeout_ms': {'type': 'integer'},
    }),
  },
  {
    'name': 'record_start',
    'description': 'Starts a smoke video of the view (or the widget with key); actions and waits are recorded.',
    'inputSchema': _schema({
      'key': {'type': 'string'},
    }),
  },
  {
    'name': 'record_stop',
    'description': 'Saves the video as the smoke artifact of the named test (at least 10 s).',
    'inputSchema': _schema(
      {
        'name': {'type': 'string'},
      },
      ['name'],
    ),
  },
];

final List<Map<String, Object?>> _tools = [..._bridgeTools, ..._appTools];

/// [process] and everything it started (on Windows `kill` ends only the
/// shell: `flutter test` and the app it runs would stay).
Future<void> _killTree(Process process) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
  } else {
    process.kill();
  }
}
