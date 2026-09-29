import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/report.dart';

void main() {
  late Directory tempDir;
  late SmokeDashboardServer server;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('dashboard_test_');
    server = SmokeDashboardServer(
      requestedPort: 0, // ephemeral port
      artifactsDir: tempDir,
      title: 'Test Dashboard',
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('serves dashboard HTML with Recent 10 active by default and All inactive', () async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://localhost:${server.actualPort}/'));
    final response = await request.close();
    expect(response.statusCode, equals(HttpStatus.ok));

    final html = await response.transform(utf8.decoder).join();
    client.close();

    // Verify "Recent" is active by default
    expect(html, contains('data-filter="recent"'));
    expect(html, contains('class="pill-btn active" data-filter="recent"'));

    // Verify "All" is not active by default
    expect(html, contains('<button class="pill-btn" data-filter="all">All'));
    expect(html.contains('class="pill-btn active" data-filter="all"'), isFalse);
    expect(html, contains("let activeFilter = 'recent';"));
  });

  test('scopes test IDs by run number so multiple runs do not overwrite tests', () async {
    // Run 0, test 0
    server.handleMachineEvent({
      'type': 'testStart',
      'run': 0,
      'test': {'id': 0, 'name': 'First Run Test', 'suiteID': 0},
      'time': 100,
    });
    server.handleMachineEvent({
      'type': 'testDone',
      'run': 0,
      'testID': 0,
      'result': 'success',
      'time': 150,
    });

    // Run 1, test 0 (same raw ID 0 from a second process!)
    server.handleMachineEvent({
      'type': 'testStart',
      'run': 1,
      'test': {'id': 0, 'name': 'Second Run Test', 'suiteID': 0},
      'time': 100,
    });
    server.handleMachineEvent({
      'type': 'testDone',
      'run': 1,
      'testID': 0,
      'result': 'failure',
      'time': 200,
    });

    final snapshot = server.getSnapshot();
    final tests = snapshot['tests'] as List;

    // Both tests must exist without collision
    expect(tests.length, equals(2));
    expect(tests[0]['name'], equals('First Run Test'));
    expect(tests[0]['status'], equals('passed'));
    expect(tests[1]['name'], equals('Second Run Test'));
    expect(tests[1]['status'], equals('failed'));

    final stats = snapshot['stats'] as Map<String, dynamic>;
    expect(stats['total'], equals(2));
    expect(stats['passed'], equals(1));
    expect(stats['failed'], equals(1));
  });

  test('does not count synthetic loading events in total tests', () async {
    server.handleMachineEvent({
      'type': 'testStart',
      'run': 0,
      'test': {'id': 0, 'name': 'loading /path/to/suite_test.dart', 'suiteID': 0},
      'time': 100,
    });

    // Active test in spotlight should reflect loading
    expect(server.activeTest?['name'], equals('loading /path/to/suite_test.dart'));

    // But snapshot tests and total should not count it
    final snapshot = server.getSnapshot();
    final tests = snapshot['tests'] as List;
    expect(tests.isEmpty, isTrue);
    expect(snapshot['stats']['total'], equals(0));
  });

  test('attaches the media of a sidecar by its declared test name, from backend folders too, and serves it', () async {
    final vulkan = Directory('${tempDir.path}/vulkan')..createSync();
    File('${vulkan.path}/shot.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    File('${vulkan.path}/walk.webm').writeAsBytesSync([1, 2, 3]);
    File('${vulkan.path}/walk.json').writeAsStringSync(jsonEncode({
      'test': 'Attached Test',
      'file': 'shot.png',
      'video': 'walk.webm',
      'durationSeconds': 4.0,
      'fps': 30.0,
      'width': 1024,
      'height': 768,
    }));
    server.handleMachineEvent({'type': 'testStart', 'run': 0, 'test': {'id': 1, 'name': 'Attached Test', 'suiteID': 0}, 'time': 1});
    server.handleMachineEvent({'type': 'testDone', 'run': 0, 'testID': 1, 'result': 'success', 'time': 2});

    final media = (server.getSnapshot()['tests'] as List).single['media'] as List;
    expect(media.map((m) => m['path']), ['/artifacts/vulkan/shot.png', '/artifacts/vulkan/walk.webm']);
    expect(media.last['violations'], ['4.0s < 10s']);

    final client = HttpClient();
    addTearDown(client.close);
    final ok = await (await client.getUrl(Uri.parse('http://localhost:${server.actualPort}/artifacts/vulkan/shot.png'))).close();
    expect(ok.statusCode, HttpStatus.ok);
    await ok.drain<void>();
    final outside = await (await client.getUrl(Uri.parse('http://localhost:${server.actualPort}/artifacts/..%2F..%2Fsecret.txt'))).close();
    expect(outside.statusCode, HttpStatus.notFound, reason: 'only files under the artifact directory are served');
    await outside.drain<void>();
  });
}
