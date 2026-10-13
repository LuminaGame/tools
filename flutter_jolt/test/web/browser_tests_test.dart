@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// flutter_jolt on the web: compiles test/web/browser_main.dart with
/// dart2js, serves it beside the WebAssembly module
/// (web/flutter_jolt.{js,wasm}, tool/web/build_jolt_wasm.sh) and runs the
/// world, shape, constraint, cloth and broad phase tests in headless Chrome
/// through the same C API as the desktop library. Skips without the module
/// or Chrome.
void main() {
  test('the Jolt tests pass in Chrome against the WebAssembly module', () async {
    final chrome = _chrome();
    if (!File('web/flutter_jolt.wasm').existsSync() || chrome == null) {
      markTestSkipped('needs web/flutter_jolt.wasm (tool/web/build_jolt_wasm.sh) and Chrome');
      return;
    }
    final stage = await Directory.systemTemp.createTemp('flutter_jolt_web_');
    addTearDown(() => stage.delete(recursive: true));
    final compile = await Process.run(
      _dart(),
      ['compile', 'js', '-O2', '-o', '${stage.path}/main.dart.js', 'test/web/browser_main.dart'],
      runInShell: Platform.isWindows,
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    for (final f in ['flutter_jolt.js', 'flutter_jolt.wasm']) {
      await File('web/$f').copy('${stage.path}/$f');
    }
    await File('${stage.path}/index.html').writeAsString(
      '<!doctype html><html><head><title>flutter_jolt web tests</title></head><body><pre id="results"></pre>'
      '<script src="main.dart.js"></script></body></html>',
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final results = Completer<String>();
    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/results') {
        final body = await utf8.decoder.bind(request).join();
        if (!results.isCompleted) results.complete(body);
        await request.response.close();
        return;
      }
      final name = request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
      final file = File('${stage.path}/$name');
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = switch (name.split('.').last) {
          'wasm' => ContentType('application', 'wasm'),
          'js' => ContentType('text', 'javascript', charset: 'utf-8'),
          _ => ContentType.html,
        };
        await request.response.addStream(file.openRead());
      }
      await request.response.close();
    });

    final profile = await Directory.systemTemp.createTemp('flutter_jolt_chrome_');
    addTearDown(() => profile.delete(recursive: true).catchError((_) => profile));
    final browser = await Process.start(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--user-data-dir=${profile.path}',
      'http://${server.address.address}:${server.port}/',
    ]);
    final stderr = StringBuffer();
    browser.stderr.transform(utf8.decoder).listen(stderr.write);
    browser.stdout.drain<void>();
    final String body;
    try {
      // The page posts its report when every test ran (real time, so the
      // step timing reads a running clock).
      body = await results.future.timeout(const Duration(minutes: 5));
    } finally {
      browser.kill();
      await browser.exitCode;
    }
    final report = jsonDecode(body) as Map<String, dynamic>;
    expect(report['fatal'], isNull, reason: '${report['fatal']}');
    final tests = (report['tests'] as List).cast<Map<String, dynamic>>();
    final failed = [for (final t in tests) if (t['passed'] != true) '${t['name']}: ${t['error']}'];
    // ignore: avoid_print
    print('flutter_jolt web: Jolt ${report['version']}, module loaded in ${report['loadMs']} ms, '
        '${report['passed']} passed, ${report['failed']} failed, a 200-box step ${report['stepMicros200Boxes']} µs');
    expect(report['available'], isTrue);
    expect(tests.length, greaterThan(20));
    expect(failed, isEmpty, reason: failed.join('\n\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// The Dart SDK of the Flutter running this test (flutter_tester is its
/// executable here, not dart): `<flutter>/bin/cache/dart-sdk/bin/dart`.
String _dart() {
  final exe = Platform.resolvedExecutable.replaceAll(r'', '/');
  final cache = exe.indexOf('/bin/cache/');
  if (cache < 0) return 'dart';
  final dart = '${exe.substring(0, cache)}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
  return File(dart).existsSync() ? dart : 'dart';
}

String? _chrome() {
  final candidates = Platform.isWindows
      ? [
          r'C:\Program Files\Google\Chrome\Application\chrome.exe',
          r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
        ]
      : ['/usr/bin/google-chrome', '/usr/bin/chromium', '/snap/bin/chromium'];
  final env = Platform.environment['CHROME_EXECUTABLE'];
  return [?env, ...candidates].where((p) => File(p).existsSync()).firstOrNull;
}

