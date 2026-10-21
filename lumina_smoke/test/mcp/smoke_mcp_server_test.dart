import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/smoke_mcp.dart';

/// Live frames, real HTTP: the way an integration test serves.
void main() {
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Serves commands over HTTP with its token, in order, until stop; removes its connection file', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => Directionality(
          textDirection: TextDirection.ltr,
          child: GestureDetector(
            onTap: () => setState(() => taps++),
            child: Center(child: Text('Taps $taps')),
          ),
        ),
      ),
    );
    final dir = Directory.systemTemp.createTempSync('smoke_mcp_server_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/session.json');
    final serving = serveSmokeMcp(tester, binding: binding, connectionFile: file.path);
    // The test binding answers every HttpClient request with 400; this
    // test talks to a real server.
    HttpOverrides.global = null;
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    while (!file.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final connection = jsonDecode(file.readAsStringSync()) as Map;
    expect(connection['url'], startsWith('http://127.0.0.1:'));
    expect(connection['pid'], pid);

    Future<(int, String)> post(Object body, {String? token}) async {
      final request = await client.postUrl(Uri.parse(connection['url'] as String));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${token ?? connection['token']}');
      request.write(jsonEncode(body));
      final response = await request.close();
      return (response.statusCode, await utf8.decoder.bind(response).join());
    }

    expect((await post({'tool': 'info'}, token: 'wrong')).$1, HttpStatus.unauthorized);
    expect((await post({'arguments': {}})).$1, HttpStatus.badRequest);
    final (status, body) = await post({
      'tool': 'tap',
      'arguments': {'text': 'Taps 0'},
    });
    expect(status, HttpStatus.ok);
    expect((jsonDecode(body) as Map)['content'], [
      {'type': 'text', 'text': 'tapped text "Taps 0"'},
    ]);
    expect(taps, 1);
    final stopped = await post({'tool': 'stop'});
    expect(stopped.$2, contains('stopped'));
    await serving;
    expect(file.existsSync(), isFalse);
  });

  testWidgets('Returns at once when no connection file is named', (tester) async {
    await serveSmokeMcp(tester);
  });
}
