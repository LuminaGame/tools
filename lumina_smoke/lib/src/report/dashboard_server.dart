import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lumina_smoke/src/video.dart';

part 'dashboard_server/dashboard_body.dart';
part 'dashboard_server/dashboard_component_styles.dart';
part 'dashboard_server/dashboard_head_styles.dart';

/// Live interactive dashboard HTTP server for smoke test execution.
///
/// Serves:
/// - GET / : Single Page Application with live metrics, test list, log streaming,
///   interactive video player, and screenshot lightbox.
/// - GET /api/stream : Server-Sent Events (SSE) broadcasting test events in real time.
/// - GET /api/state : JSON snapshot of current run state.
/// - GET /artifacts/* : Serves images, videos (with HTTP Range support), and sidecars.
/// - POST /api/stop : Gracefully stops the server.
class SmokeDashboardServer {
  final int requestedPort;
  final Directory artifactsDir;
  final String title;

  HttpServer? _server;
  int? actualPort;
  bool isRunning = true;
  final int startTimeMs = DateTime.now().millisecondsSinceEpoch;
  int? endTimeMs;
  int? exitCode;

  final List<HttpResponse> _sseClients = [];
  Timer? _heartbeatTimer;

  // Active state
  Map<String, dynamic>? activeTest;
  final List<String> activeTestLogs = [];
  final Map<dynamic, Map<String, dynamic>> tests = {};
  final List<dynamic> testOrder = [];
  final Map<String, String> _suitePaths = {};

  SmokeDashboardServer({
    this.requestedPort = 8088,
    required this.artifactsDir,
    this.title = 'Lumina Smoke Test Studio',
  });

  String get url => 'http://localhost:$actualPort';

  /// Starts the HTTP server on [requestedPort] (or next available port).
  Future<int> start() async {
    int port = requestedPort;
    while (_server == null && port < requestedPort + 50) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        actualPort = _server!.port;
      } catch (_) {
        port++;
      }
    }

    if (_server == null) {
      // Fallback to ephemeral port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      actualPort = _server!.port;
    }

    _server!.listen(_handleRequest);

    // Heartbeat every 15s to keep SSE connections alive
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _broadcastSse('ping', {'time': DateTime.now().millisecondsSinceEpoch});
    });

    _printBanner();
    return actualPort!;
  }

  void _printBanner() {
    stdout.writeln('');
    stdout.writeln('╔═══════════════════════════════════════════════════════════════════════════╗');
    stdout.writeln('║  🚀 LIVE SMOKE TEST DASHBOARD ACTIVE                                      ║');
    stdout.writeln('║     👉 URL: http://localhost:$actualPort                                       ║');
    stdout.writeln('║     Open in your browser to view running tests, logs, videos & shots live ║');
    stdout.writeln('╚═══════════════════════════════════════════════════════════════════════════╝');
    stdout.writeln('');
  }

  /// Handles incoming HTTP requests.
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // CORS headers
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Range');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (path == '/' || path == '/index.html') {
      await _serveDashboardHtml(request);
    } else if (path == '/api/stream') {
      await _handleSseStream(request);
    } else if (path == '/api/state') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(getSnapshot()));
      await request.response.close();
    } else if (path.startsWith('/artifacts/')) {
      await _serveArtifact(request);
    } else if (path == '/api/stop' && request.method == 'POST') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
      unawaited(stop());
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
      await request.response.close();
    }
  }

  /// Serves media and sidecar artifacts from [artifactsDir] with HTTP Range support.
  Future<void> _serveArtifact(HttpRequest request) async {
    final subPath = Uri.decodeComponent(request.uri.path.substring('/artifacts/'.length));
    final file = File('${artifactsDir.path}/$subPath');
    // Only files under the artifact directory are served.
    final inside = file.absolute.uri.normalizePath().path.startsWith(artifactsDir.absolute.uri.normalizePath().path);

    if (!inside || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Artifact not found: $subPath');
      await request.response.close();
      return;
    }

    final totalBytes = file.lengthSync();
    final ext = file.path.toLowerCase().split('.').last;
    ContentType contentType;
    if (ext == 'png') {
      contentType = ContentType('image', 'png');
    } else if (ext == 'webm') {
      contentType = ContentType('video', 'webm');
    } else if (ext == 'mp4') {
      contentType = ContentType('video', 'mp4');
    } else if (ext == 'json') {
      contentType = ContentType.json;
    } else {
      contentType = ContentType.binary;
    }

    request.response.headers.contentType = contentType;
    request.response.headers.set('Accept-Ranges', 'bytes');

    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? (totalBytes - 1)
          : totalBytes - 1;

      if (start >= totalBytes || end >= totalBytes || start > end) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set('Content-Range', 'bytes */$totalBytes');
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set('Content-Range', 'bytes $start-$end/$totalBytes');
      request.response.headers.contentLength = (end - start) + 1;

      await file.openRead(start, end + 1).pipe(request.response);
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentLength = totalBytes;
      await file.openRead().pipe(request.response);
    }
  }

  /// SSE endpoint connection.
  Future<void> _handleSseStream(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set('Cache-Control', 'no-cache');
    response.headers.set('Connection', 'keep-alive');
    response.headers.set('X-Accel-Buffering', 'no');

    _sseClients.add(response);

    // Initial state packet
    response.write('event: init\ndata: ${jsonEncode(getSnapshot())}\n\n');
    await response.flush();

    request.response.done.then((_) {
      _sseClients.remove(response);
    }).catchError((_) {
      _sseClients.remove(response);
    });
  }

  void _broadcastSse(String event, dynamic data) {
    final message = 'event: $event\ndata: ${jsonEncode(data)}\n\n';
    final dead = <HttpResponse>[];
    for (final client in _sseClients) {
      try {
        client.write(message);
        client.flush().catchError((_) {
          dead.add(client);
        });
      } catch (_) {
        dead.add(client);
      }
    }
    for (final d in dead) {
      _sseClients.remove(d);
    }
  }

  /// Ingests a raw event from `flutter test --machine`.
  void handleMachineEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final run = (event['run'] as num?)?.toInt() ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (type == 'suite') {
      final suite = event['suite'] as Map<String, dynamic>?;
      if (suite != null) {
        final id = suite['id'];
        final path = suite['path'] as String?;
        if (id != null && path != null) {
          _suitePaths['$run:$id'] = path;
        }
      }
    } else if (type == 'testStart') {
      final test = event['test'] as Map<String, dynamic>?;
      if (test != null) {
        final rawId = test['id'];
        final id = '$run:$rawId';
        final name = test['name'] as String? ?? 'Unnamed Test';
        final suiteId = '$run:${test['suiteID']}';
        final suitePath = _suitePaths[suiteId] ?? (event['target'] as String? ?? '');

        // Handle synthetic loading events
        if (name.startsWith('loading ')) {
          activeTest = {
            'id': id,
            'name': name,
            'suite': suitePath,
            'startTimeMs': nowMs,
            'status': 'running',
          };
          _broadcastSse('test_start', activeTest);
          return;
        }

        final testObj = <String, dynamic>{
          'id': id,
          'name': name,
          'suite': suitePath,
          'startTimeMs': nowMs,
          'durationMs': 0,
          'status': 'running',
          'error': null,
          'stackTrace': null,
          'prints': <String>[],
          'media': <Map<String, dynamic>>[],
          'usedAssets': <String>[],
        };

        tests[id] = testObj;
        if (!testOrder.contains(id)) {
          testOrder.add(id);
        }

        activeTest = testObj;
        activeTestLogs.clear();

        _broadcastSse('test_start', {
          'id': id,
          'name': name,
          'suite': suitePath,
          'startTimeMs': nowMs,
        });
      }
    } else if (type == 'print') {
      final rawTestId = event['testID'];
      final testId = '$run:$rawTestId';
      final message = event['message'] as String? ?? '';
      if (tests.containsKey(testId)) {
        (tests[testId]!['prints'] as List<String>).add(message);
      }
      activeTestLogs.add(message);
      _broadcastSse('test_log', {'testID': testId, 'line': message});
    } else if (type == 'error') {
      final rawTestId = event['testID'];
      final testId = '$run:$rawTestId';
      final error = event['error'] as String? ?? '';
      final stack = event['stackTrace'] as String? ?? '';
      if (tests.containsKey(testId)) {
        tests[testId]!['error'] = error;
        tests[testId]!['stackTrace'] = stack;
      }
      _broadcastSse('test_error', {'testID': testId, 'error': error, 'stackTrace': stack});
    } else if (type == 'testDone') {
      final rawTestId = event['testID'];
      final testId = '$run:$rawTestId';
      final result = event['result'] as String? ?? 'unknown';
      final hidden = event['hidden'] == true;

      if (tests.containsKey(testId)) {
        final t = tests[testId]!;
        final start = (t['startTimeMs'] as num).toInt();
        t['endTimeMs'] = nowMs;
        t['durationMs'] = nowMs - start;
        t['status'] = result == 'success'
            ? 'passed'
            : (result == 'failure' || result == 'error' ? 'failed' : 'skipped');

        // Match media from artifacts directory
        _attachArtifactsToTest(t);

        if (activeTest?['id'] == testId) {
          activeTest = null;
        }

        if (!hidden) {
          _broadcastSse('test_done', t);
        }
      } else if (activeTest?['id'] == testId) {
        activeTest = null;
      }
    }
  }

  /// Appends raw output lines (e.g. build logs).
  void handleRawLog(String line) {
    if (line.trim().isEmpty) return;
    activeTestLogs.add(line);
    _broadcastSse('raw_log', {'line': line});
  }

  /// Attaches the media of every sidecar under [artifactsDir] (recursively:
  /// backends write into their own folders) whose declared test name matches
  /// [testObj]'s.
  void _attachArtifactsToTest(Map<String, dynamic> testObj) {
    if (!artifactsDir.existsSync()) return;

    final testName = testObj['name'] as String;
    final mediaList = <Map<String, dynamic>>[];
    final assetsList = <String>[];
    final base = artifactsDir.absolute.path.replaceAll(r'\', '/');

    String servedPath(File sidecar, String declared) {
      final name = declared.replaceAll(r'\', '/').split('/').last;
      final dir = sidecar.parent.absolute.path.replaceAll(r'\', '/');
      final rel = dir.length > base.length ? '${dir.substring(base.length + 1)}/' : '';
      return '/artifacts/${Uri(path: '$rel$name').path}';
    }

    try {
      final files = artifactsDir.listSync(recursive: true).whereType<File>().toList();
      for (final f in files) {
        if (!f.path.endsWith('.json')) continue;
        try {
          final content = f.readAsStringSync();
          final meta = jsonDecode(content) as Map<String, dynamic>;
          final sidecarTestName = (meta['test'] ?? meta['testName']) as String?;

          if (sidecarTestName != null && _isMatch(testName, sidecarTestName)) {
            final mediaFile = (meta['file'] ?? meta['screenshot']) as String?;
            final videoFile = meta['video'] as String?;
            final used = (meta['usedAssets'] as List?)?.map((e) => '$e') ?? const <String>[];
            for (final u in used) {
              if (!assetsList.contains(u)) assetsList.add(u);
            }

            if (mediaFile != null) {
              mediaList.add({
                'label': sidecarTestName,
                'fileName': mediaFile.replaceAll(r'\', '/').split('/').last,
                'isVideo': false,
                'path': servedPath(f, mediaFile),
              });
            }

            if (videoFile != null) {
              final seconds = ((meta['durationSeconds'] ?? meta['videoSeconds'] ?? meta['seconds']) as num?)?.toDouble();
              final fps = ((meta['fps'] ?? meta['videoFps']) as num?)?.toDouble();
              final width = ((meta['width'] ?? meta['videoWidth']) as num?)?.toInt();
              final height = ((meta['height'] ?? meta['videoHeight']) as num?)?.toInt();

              final violations = <String>[];
              if (seconds != null && SmokeVideo.isTooShort(seconds)) {
                violations.add('${seconds.toStringAsFixed(1)}s < ${SmokeVideo.minimumSeconds.toStringAsFixed(0)}s');
              }
              if (fps != null && SmokeVideo.isTooSlow(fps)) {
                violations.add('${fps.toStringAsFixed(0)} fps < ${SmokeVideo.minimumFps} fps');
              }
              if (width != null && height != null && SmokeVideo.isTooSmall(width, height)) {
                violations.add('${width}x$height < ${SmokeVideo.minimumWidth}x${SmokeVideo.minimumHeight}');
              }

              mediaList.add({
                'label': sidecarTestName,
                'fileName': videoFile.replaceAll(r'\', '/').split('/').last,
                'isVideo': true,
                'path': servedPath(f, videoFile),
                'seconds': seconds,
                'fps': fps,
                'width': width,
                'height': height,
                'violations': violations,
              });
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    testObj['media'] = mediaList;
    testObj['usedAssets'] = assetsList;
  }

  bool _isMatch(String a, String b) {
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return norm(a) == norm(b) || norm(a).contains(norm(b)) || norm(b).contains(norm(a));
  }

  /// Marks entire run as completed.
  void onSuiteDone({required int exitCode}) {
    isRunning = false;
    endTimeMs = DateTime.now().millisecondsSinceEpoch;
    this.exitCode = exitCode;
    activeTest = null;

    // Final scan for all tests
    for (final t in tests.values) {
      if ((t['media'] as List).isEmpty) {
        _attachArtifactsToTest(t);
      }
    }

    _broadcastSse('suite_done', getSnapshot());
  }

  /// Snapshot representing all current tests and statistics.
  Map<String, dynamic> getSnapshot() {
    final list = testOrder.map((id) => tests[id]!).where((t) {
      final name = t['name'] as String;
      return !name.startsWith('loading ');
    }).toList();

    int passed = 0;
    int failed = 0;
    int skipped = 0;
    int running = 0;
    int videoCount = 0;
    int screenshotCount = 0;
    double totalVideoSeconds = 0;

    for (final t in list) {
      final st = t['status'];
      if (st == 'passed') {
        passed++;
      } else if (st == 'failed') {
        failed++;
      } else if (st == 'skipped') {
        skipped++;
      } else {
        running++;
      }

      final media = t['media'] as List? ?? [];
      for (final m in media) {
        if (m['isVideo'] == true) {
          videoCount++;
          final s = m['seconds'] as num?;
          if (s != null) totalVideoSeconds += s.toDouble();
        } else {
          screenshotCount++;
        }
      }
    }

    return {
      'title': title,
      'isRunning': isRunning,
      'startTimeMs': startTimeMs,
      'endTimeMs': endTimeMs,
      'exitCode': exitCode,
      'activeTest': activeTest,
      'activeTestLogs': activeTestLogs.take(200).toList(),
      'stats': {
        'total': list.length,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'running': running,
        'videoCount': videoCount,
        'screenshotCount': screenshotCount,
        'totalVideoSeconds': totalVideoSeconds,
      },
      'tests': list,
    };
  }

  /// If interactive, keeps server running so user can inspect results.
  Future<void> waitIfInteractive() async {
    if (!stdin.hasTerminal) return;

    stdout.writeln('');
    stdout.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    stdout.writeln('  📊 Live Dashboard remains open at: http://localhost:$actualPort');
    stdout.writeln('  Press [Enter] or Ctrl+C to close the dashboard server.');
    stdout.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final completer = Completer<void>();
    StreamSubscription? stdinSub;
    StreamSubscription? sigintSub;

    try {
      stdinSub = stdin.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
    } catch (_) {}

    if (!Platform.isWindows) {
      try {
        sigintSub = ProcessSignal.sigint.watch().listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
      } catch (_) {}
    }

    await completer.future;
    try {
      await stdinSub?.cancel();
    } catch (_) {}
    try {
      await sigintSub?.cancel();
    } catch (_) {}
    await stop();
  }

  /// Gracefully closes server.
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    for (final client in _sseClients) {
      try {
        await client.close();
      } catch (_) {}
    }
    _sseClients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  /// Serves the single-page web application.
  Future<void> _serveDashboardHtml(HttpRequest request) async {
    request.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    request.response.write(_dashboardHtml);
    await request.response.close();
  }

  static const String _dashboardHtml =
      _dashboardHeadStyles + _dashboardComponentStyles + _dashboardBody;
}
