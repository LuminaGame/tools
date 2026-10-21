import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The stdio bridge as an MCP client starts it: `dart bin/smoke_mcp_bridge.dart`.
void main() {
  test('Answers the handshake and lists the tools; without a launched app the app tools say so', () async {
    final dart = Platform.resolvedExecutable.contains('flutter_tester') ? 'dart' : Platform.resolvedExecutable;
    final process = await Process.start(dart, ['bin/smoke_mcp_bridge.dart'], runInShell: Platform.isWindows);
    final replies = StreamController<Map<String, Object?>>.broadcast();
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      replies.add(Map<String, Object?>.from(jsonDecode(l) as Map));
    });
    final next = StreamIterator(replies.stream);
    Future<Map<String, Object?>> ask(int id, String method, [Map<String, Object?> params = const {}]) async {
      process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
      await process.stdin.flush();
      expect(await next.moveNext().timeout(const Duration(seconds: 60)), isTrue);
      return next.current;
    }

    final init = await ask(1, 'initialize', {'protocolVersion': '2025-06-18'});
    expect(((init['result']! as Map)['serverInfo'] as Map)['name'], 'lumina-smoke');
    process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
    final list = await ask(2, 'tools/list');
    final names = [for (final t in (list['result']! as Map)['tools'] as List) (t as Map)['name']];
    expect(
      names,
      containsAll(['smoke_launch', 'smoke_stop', 'screenshot', 'widgets', 'tap', 'drag_from', 'record_stop']),
    );
    final tap = await ask(3, 'tools/call', {
      'name': 'tap',
      'arguments': {'text': 'x'},
    });
    final result = tap['result']! as Map;
    expect(result['isError'], isTrue);
    expect(((result['content'] as List).first as Map)['text'], contains('call smoke_launch first'));
    expect((await ask(4, 'tools/call', {'name': 'fly'}))['error'], isNotNull);
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 30)), 0);
  });
}
