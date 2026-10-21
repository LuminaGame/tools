import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/src/mcp/smoke_mcp_commands.dart';

/// The connection file the smoke MCP bridge passes to the app it launches
/// (`--dart-define=LUMINA_SMOKE_MCP=<path>`, or the environment variable).
const String smokeMcpDefine = 'LUMINA_SMOKE_MCP';

/// Serves the running app to the smoke MCP bridge until it says `stop` or
/// nothing comes for [idle]: binds 127.0.0.1 on a free port with a random
/// bearer token, writes `{url, token, pid}` to the connection file, and runs
/// each command the bridge posts (`POST /command`, `{"tool", "arguments"}`)
/// in order through [SmokeMcpCommands] on [tester]. Without a connection
/// file named (no bridge launched this run) it returns at once.
///
/// Call it from an integration test that has pumped the app:
///
/// ```dart
/// final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
/// testWidgets('drive', (tester) async {
///   await tester.pumpWidget(const MyApp());
///   await serveSmokeMcp(tester, binding: binding);
/// }, timeout: Timeout.none);
/// ```
///
/// [binding] (a `LiveTestWidgetsFlutterBinding`, typed loosely as in
/// [SmokeCapture]) is switched to fully live frames, so the app animates
/// and renders between commands as it does when used.
Future<void> serveSmokeMcp(
  WidgetTester tester, {
  Object? binding,
  String? connectionFile,
  Duration idle = const Duration(minutes: 30),
}) async {
  const defined = String.fromEnvironment(smokeMcpDefine);
  final path = connectionFile ?? (defined.isNotEmpty ? defined : Platform.environment[smokeMcpDefine]);
  if (path == null || path.isEmpty) return;
  if (binding is LiveTestWidgetsFlutterBinding) {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  }
  final random = math.Random.secure();
  final token = List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final calls = StreamController<_Call>();
  final server = await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  server!.listen((request) => _answer(request, token, calls));
  final file = File(path);
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'url': 'http://127.0.0.1:${server.port}/command', 'token': token, 'pid': pid}),
      flush: true,
    );
  });
  final commands = SmokeMcpCommands(tester);
  try {
    await for (final call in calls.stream.timeout(idle, onTimeout: (sink) => sink.close())) {
      if (call.tool == 'stop') {
        call.done.complete(SmokeMcpResult.text('stopped'));
        break;
      }
      call.done.complete(await commands.run(call.tool, call.arguments));
    }
  } finally {
    await tester.runAsync(() async {
      // The last answer out before the server goes.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await server.close(force: true);
      if (await file.exists()) await file.delete();
    });
  }
}

class _Call {
  _Call(this.tool, this.arguments);

  final String tool;
  final Map<String, Object?> arguments;
  final done = Completer<SmokeMcpResult>();
}

Future<void> _answer(HttpRequest request, String token, StreamController<_Call> calls) async {
  final response = request.response;
  try {
    // The body read first, whatever the answer (an unread body breaks it).
    final text = await utf8.decoder.bind(request).join();
    if (request.method != 'POST' || request.uri.path != '/command') {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (request.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') {
      response.statusCode = HttpStatus.unauthorized;
      return;
    }
    final body = jsonDecode(text);
    if (body is! Map || body['tool'] is! String) {
      response.statusCode = HttpStatus.badRequest;
      response.write('expected {"tool": ..., "arguments": {...}}');
      return;
    }
    final args = body['arguments'];
    final call = _Call(body['tool'] as String, args is Map ? Map<String, Object?>.from(args) : {});
    if (calls.isClosed) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    calls.add(call);
    final result = await call.done.future;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(result.toJson()));
  } catch (e) {
    response.statusCode = HttpStatus.internalServerError;
    response.write('$e');
  } finally {
    await response.close();
  }
}
