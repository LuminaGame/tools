import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lumina_smoke/src/video.dart';

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

  static const String _dashboardHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Lumina Smoke Test Studio</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-base: #08090d;
      --bg-surface: #10121a;
      --bg-surface-elevated: #161924;
      --bg-surface-card: rgba(22, 25, 36, 0.7);
      --border-subtle: rgba(255, 255, 255, 0.08);
      --border-active: rgba(6, 182, 212, 0.5);
      --text-main: #f1f5f9;
      --text-muted: #94a3b8;
      --text-dim: #64748b;
      --accent-cyan: #06b6d4;
      --accent-cyan-glow: rgba(6, 182, 212, 0.25);
      --accent-emerald: #10b981;
      --accent-emerald-glow: rgba(16, 185, 129, 0.25);
      --accent-rose: #f43f5e;
      --accent-rose-glow: rgba(244, 63, 94, 0.25);
      --accent-amber: #f59e0b;
      --accent-violet: #8b5cf6;
      --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      --font-mono: 'JetBrains Mono', Consolas, Monaco, monospace;
      --radius-sm: 6px;
      --radius-md: 10px;
      --radius-lg: 16px;
      --radius-full: 9999px;
      --shadow-lg: 0 10px 30px -5px rgba(0, 0, 0, 0.6);
      --shadow-glow: 0 0 25px rgba(6, 182, 212, 0.2);
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg-base);
      color: var(--text-main);
      font-family: var(--font-sans);
      min-height: 100vh;
      line-height: 1.5;
      overflow-x: hidden;
      padding-bottom: 60px;
    }

    /* Ambient background mesh */
    .ambient-bg {
      position: fixed;
      top: 0; left: 0; right: 0; height: 450px;
      background: radial-gradient(ellipse at 50% -20%, rgba(6, 182, 212, 0.15), rgba(139, 92, 246, 0.08) 50%, transparent 80%);
      pointer-events: none;
      z-index: 0;
    }

    .container {
      max-width: 1360px;
      margin: 0 auto;
      padding: 0 24px;
      position: relative;
      z-index: 1;
    }

    /* Header */
    header {
      padding: 24px 0 20px;
      border-bottom: 1px solid var(--border-subtle);
      margin-bottom: 24px;
    }
    .header-inner {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
    }
    .brand-group {
      display: flex;
      align-items: center;
      gap: 14px;
    }
    .brand-icon {
      width: 44px;
      height: 44px;
      background: linear-gradient(135deg, var(--accent-cyan), var(--accent-violet));
      border-radius: var(--radius-md);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 20px rgba(6, 182, 212, 0.4);
    }
    .brand-icon svg { width: 26px; height: 26px; fill: white; }
    .brand-titles h1 {
      font-size: 22px;
      font-weight: 800;
      letter-spacing: -0.02em;
      background: linear-gradient(to right, #fff, #94a3b8);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .brand-titles p {
      font-size: 13px;
      color: var(--text-muted);
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: var(--radius-full);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
    }
    .status-badge.running {
      background: rgba(6, 182, 212, 0.15);
      color: var(--accent-cyan);
      border: 1px solid rgba(6, 182, 212, 0.3);
      box-shadow: 0 0 15px var(--accent-cyan-glow);
    }
    .status-badge.passed {
      background: rgba(16, 185, 129, 0.15);
      color: var(--accent-emerald);
      border: 1px solid rgba(16, 185, 129, 0.3);
      box-shadow: 0 0 15px var(--accent-emerald-glow);
    }
    .status-badge.failed {
      background: rgba(244, 63, 94, 0.15);
      color: var(--accent-rose);
      border: 1px solid rgba(244, 63, 94, 0.3);
      box-shadow: 0 0 15px var(--accent-rose-glow);
    }
    .pulse-dot {
      width: 8px; height: 8px;
      border-radius: 50%;
      background-color: currentColor;
      animation: pulse 1.8s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.3; transform: scale(0.8); }
    }

    .header-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .timer-badge {
      background: var(--bg-surface);
      border: 1px solid var(--border-subtle);
      padding: 6px 14px;
      border-radius: var(--radius-md);
      font-family: var(--font-mono);
      font-size: 14px;
      color: var(--text-main);
      display: flex;
      align-items: center;
      gap: 6px;
    }

    /* Overall Progress Bar */
    .progress-section {
      margin-bottom: 24px;
    }
    .progress-track {
      height: 10px;
      background: var(--bg-surface-elevated);
      border-radius: var(--radius-full);
      overflow: hidden;
      border: 1px solid var(--border-subtle);
      position: relative;
    }
    .progress-fill {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, var(--accent-cyan), var(--accent-emerald));
      border-radius: var(--radius-full);
      transition: width 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      box-shadow: 0 0 12px rgba(6, 182, 212, 0.5);
    }
    .progress-fill.has-failure {
      background: linear-gradient(90deg, var(--accent-rose), var(--accent-amber));
      box-shadow: 0 0 12px rgba(244, 63, 94, 0.5);
    }
    .progress-info {
      display: flex;
      justify-content: space-between;
      margin-top: 8px;
      font-size: 13px;
      color: var(--text-muted);
    }

    /* Metrics Grid */
    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
      gap: 14px;
      margin-bottom: 28px;
    }
    .metric-card {
      background: var(--bg-surface-card);
      backdrop-filter: blur(12px);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: 16px 18px;
      transition: transform 0.2s ease, border-color 0.2s ease;
    }
    .metric-card:hover {
      transform: translateY(-2px);
      border-color: rgba(255, 255, 255, 0.15);
    }
    .metric-label {
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--text-dim);
      margin-bottom: 6px;
    }
    .metric-value {
      font-size: 28px;
      font-weight: 800;
      letter-spacing: -0.02em;
    }
    .metric-val-passed { color: var(--accent-emerald); }
    .metric-val-failed { color: var(--accent-rose); }
    .metric-val-running { color: var(--accent-cyan); }
    .metric-sub {
      font-size: 11px;
      color: var(--text-dim);
      margin-top: 4px;
    }

    /* Currently Running Spotlight */
    .spotlight-card {
      background: linear-gradient(145deg, rgba(22, 25, 36, 0.95), rgba(12, 14, 20, 0.95));
      border: 1px solid var(--accent-cyan);
      box-shadow: 0 0 30px var(--accent-cyan-glow);
      border-radius: var(--radius-lg);
      padding: 20px 24px;
      margin-bottom: 32px;
      animation: glowBorder 4s infinite alternate;
    }
    @keyframes glowBorder {
      0% { border-color: rgba(6, 182, 212, 0.4); box-shadow: 0 0 20px rgba(6, 182, 212, 0.15); }
      100% { border-color: rgba(139, 92, 246, 0.6); box-shadow: 0 0 30px rgba(139, 92, 246, 0.25); }
    }
    .spotlight-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
      flex-wrap: wrap;
      gap: 10px;
    }
    .spotlight-tag {
      font-size: 12px;
      font-weight: 700;
      color: var(--accent-cyan);
      background: rgba(6, 182, 212, 0.15);
      padding: 4px 10px;
      border-radius: var(--radius-full);
      letter-spacing: 0.05em;
      text-transform: uppercase;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .spotlight-title {
      font-size: 18px;
      font-weight: 700;
      color: white;
      margin-bottom: 4px;
    }
    .spotlight-suite {
      font-size: 13px;
      font-family: var(--font-mono);
      color: var(--text-muted);
    }
    .terminal-container {
      margin-top: 14px;
      background: #050608;
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-md);
      overflow: hidden;
    }
    .terminal-bar {
      background: #0e1017;
      padding: 8px 12px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 1px solid var(--border-subtle);
    }
    .terminal-dots {
      display: flex;
      gap: 6px;
    }
    .terminal-dot {
      width: 10px; height: 10px; border-radius: 50%;
    }
    .dot-red { background: #ef4444; }
    .dot-yellow { background: #f59e0b; }
    .dot-green { background: #10b981; }
    .terminal-title {
      font-size: 12px;
      font-family: var(--font-mono);
      color: var(--text-dim);
    }
    .terminal-body {
      padding: 12px 14px;
      font-family: var(--font-mono);
      font-size: 12px;
      color: #cbd5e1;
      height: 180px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }
    .terminal-line { margin-bottom: 3px; }
    .terminal-line.error { color: #f87171; }
    .terminal-line.info { color: #38bdf8; }

    /* Explorer Toolbar */
    .explorer-toolbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      flex-wrap: wrap;
      margin-bottom: 16px;
    }
    .search-box {
      flex: 1;
      min-width: 260px;
      position: relative;
    }
    .search-input {
      width: 100%;
      background: var(--bg-surface);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-md);
      padding: 10px 14px 10px 38px;
      font-size: 14px;
      color: var(--text-main);
      outline: none;
      transition: border-color 0.2s ease;
    }
    .search-input:focus {
      border-color: var(--accent-cyan);
    }
    .search-icon {
      position: absolute;
      left: 12px;
      top: 50%;
      transform: translateY(-50%);
      width: 16px;
      height: 16px;
      fill: var(--text-dim);
    }
    .filter-pills {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }
    .pill-btn {
      background: var(--bg-surface);
      border: 1px solid var(--border-subtle);
      color: var(--text-muted);
      padding: 8px 14px;
      border-radius: var(--radius-full);
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .pill-btn:hover {
      background: var(--bg-surface-elevated);
      color: var(--text-main);
    }
    .pill-btn.active {
      background: var(--accent-cyan);
      color: #041017;
      border-color: var(--accent-cyan);
      font-weight: 700;
    }

    /* Test Cards */
    .tests-list {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .test-card {
      background: var(--bg-surface-card);
      backdrop-filter: blur(12px);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      overflow: hidden;
      transition: border-color 0.2s ease, box-shadow 0.2s ease;
    }
    .test-card:hover {
      border-color: rgba(255, 255, 255, 0.15);
    }
    .test-card.failed {
      border-left: 4px solid var(--accent-rose);
    }
    .test-card.passed {
      border-left: 4px solid var(--accent-emerald);
    }
    .test-card.running {
      border-left: 4px solid var(--accent-cyan);
    }

    .test-header {
      padding: 16px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      cursor: pointer;
      user-select: none;
    }
    .test-left {
      display: flex;
      align-items: center;
      gap: 14px;
      flex: 1;
      min-width: 0;
    }
    .test-status-icon {
      width: 28px;
      height: 28px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    .icon-passed {
      background: rgba(16, 185, 129, 0.15);
      color: var(--accent-emerald);
    }
    .icon-failed {
      background: rgba(244, 63, 94, 0.15);
      color: var(--accent-rose);
    }
    .icon-running {
      background: rgba(6, 182, 212, 0.15);
      color: var(--accent-cyan);
    }
    .test-info {
      min-width: 0;
      flex: 1;
    }
    .test-name {
      font-size: 15px;
      font-weight: 600;
      color: var(--text-main);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .test-suite {
      font-size: 12px;
      font-family: var(--font-mono);
      color: var(--text-dim);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .test-badges {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-shrink: 0;
    }
    .badge-media {
      background: var(--bg-surface-elevated);
      border: 1px solid var(--border-subtle);
      font-size: 12px;
      font-weight: 600;
      padding: 4px 10px;
      border-radius: var(--radius-full);
      display: flex;
      align-items: center;
      gap: 5px;
      color: var(--text-muted);
    }
    .badge-video {
      background: rgba(139, 92, 246, 0.12);
      border-color: rgba(139, 92, 246, 0.3);
      color: #c4b5fd;
    }
    .badge-duration {
      font-family: var(--font-mono);
      font-size: 12px;
      color: var(--text-dim);
    }
    .chevron {
      width: 18px;
      height: 18px;
      fill: var(--text-dim);
      transition: transform 0.2s ease;
    }
    .test-card.open .chevron {
      transform: rotate(180deg);
    }

    /* Test Card Details Body */
    .test-body {
      display: none;
      padding: 0 20px 20px;
      border-top: 1px solid var(--border-subtle);
      background: rgba(10, 12, 17, 0.4);
    }
    .test-card.open .test-body {
      display: block;
      padding-top: 18px;
    }

    /* Error alert box */
    .error-alert {
      background: rgba(244, 63, 94, 0.1);
      border: 1px solid rgba(244, 63, 94, 0.3);
      border-radius: var(--radius-md);
      padding: 14px 18px;
      margin-bottom: 18px;
    }
    .error-alert h4 {
      color: #fb7185;
      font-size: 14px;
      font-weight: 700;
      margin-bottom: 6px;
    }
    .error-alert pre {
      font-family: var(--font-mono);
      font-size: 12px;
      color: #fda4af;
      white-space: pre-wrap;
      word-break: break-all;
    }

    /* Media Gallery */
    .media-section {
      margin-bottom: 18px;
    }
    .media-title {
      font-size: 13px;
      font-weight: 700;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .video-wrapper {
      background: #000;
      border-radius: var(--radius-md);
      overflow: hidden;
      border: 1px solid var(--border-subtle);
      margin-bottom: 12px;
      max-width: 800px;
    }
    .video-wrapper video {
      width: 100%;
      height: auto;
      max-height: 480px;
      display: block;
    }
    .video-meta-bar {
      padding: 8px 14px;
      background: #0d0f17;
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 8px;
      font-size: 12px;
      color: var(--text-dim);
    }
    .video-specs {
      display: flex;
      gap: 12px;
      font-family: var(--font-mono);
    }
    .rule-violation-badge {
      background: rgba(239, 68, 68, 0.2);
      color: #f87171;
      border: 1px solid rgba(239, 68, 68, 0.4);
      padding: 2px 8px;
      border-radius: var(--radius-sm);
      font-size: 11px;
      font-weight: 600;
    }

    .screenshots-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 12px;
    }
    .screenshot-item {
      background: #000;
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-md);
      overflow: hidden;
      cursor: zoom-in;
      position: relative;
      transition: transform 0.2s ease, border-color 0.2s ease;
    }
    .screenshot-item:hover {
      transform: scale(1.02);
      border-color: var(--accent-cyan);
    }
    .screenshot-item img {
      width: 100%;
      height: 140px;
      object-fit: cover;
      display: block;
    }
    .screenshot-label {
      padding: 6px 10px;
      font-size: 11px;
      color: var(--text-muted);
      background: #0d0f17;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    /* 3D Assets badges */
    .assets-list {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-bottom: 16px;
    }
    .asset-pill {
      background: rgba(6, 182, 212, 0.1);
      border: 1px solid rgba(6, 182, 212, 0.25);
      color: #67e8f9;
      font-size: 11px;
      font-family: var(--font-mono);
      padding: 4px 10px;
      border-radius: var(--radius-full);
      display: flex;
      align-items: center;
      gap: 5px;
    }

    /* Logs accordion inside test */
    .test-logs-box {
      background: #050608;
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-md);
      padding: 12px 16px;
      font-family: var(--font-mono);
      font-size: 12px;
      color: #94a3b8;
      max-height: 240px;
      overflow-y: auto;
      white-space: pre-wrap;
    }

    /* Lightbox Modal */
    .lightbox-modal {
      display: none;
      position: fixed;
      top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(0, 0, 0, 0.9);
      backdrop-filter: blur(8px);
      z-index: 1000;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .lightbox-modal.active { display: flex; }
    .lightbox-content {
      max-width: 90vw;
      max-height: 90vh;
      border-radius: var(--radius-md);
      box-shadow: 0 0 50px rgba(0,0,0,0.8);
      border: 1px solid var(--border-subtle);
      object-fit: contain;
    }
    .lightbox-close {
      position: absolute;
      top: 24px;
      right: 24px;
      background: rgba(255,255,255,0.1);
      border: none;
      color: white;
      width: 40px; height: 40px;
      border-radius: 50%;
      cursor: pointer;
      font-size: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: background 0.2s ease;
    }
    .lightbox-close:hover { background: rgba(255,255,255,0.25); }

    /* Empty state */
    .empty-state {
      text-align: center;
      padding: 48px 24px;
      color: var(--text-dim);
    }
    .empty-state svg {
      width: 48px; height: 48px; fill: currentColor; margin-bottom: 12px; opacity: 0.5;
    }
  </style>
</head>
<body>
  <div class="ambient-bg"></div>

  <div class="container">
    <header>
      <div class="header-inner">
        <div class="brand-group">
          <div class="brand-icon">
            <svg viewBox="0 0 24 24"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
          </div>
          <div class="brand-titles">
            <h1 id="uiTitle">Lumina Smoke Test Studio</h1>
            <p>
              <span>NVIDIA RTX PRO 2000 (GPU 1)</span>
              <span>•</span>
              <span id="packageTag">lumina_ui</span>
            </p>
          </div>
        </div>

        <div class="header-actions">
          <div class="status-badge running" id="statusBadge">
            <span class="pulse-dot"></span>
            <span id="statusText">TESTING IN PROGRESS</span>
          </div>
          <div class="timer-badge">
            <span>⏱</span>
            <span id="elapsedTimer">00:00</span>
          </div>
        </div>
      </div>
    </header>

    <!-- Overall Progress -->
    <div class="progress-section">
      <div class="progress-track">
        <div class="progress-fill" id="progressFill"></div>
      </div>
      <div class="progress-info">
        <span id="progressText">0 / 0 tests completed (0%)</span>
        <span id="etaText">Streaming live from runner...</span>
      </div>
    </div>

    <!-- Metrics Cards -->
    <div class="metrics-grid">
      <div class="metric-card">
        <div class="metric-label">Total Tests</div>
        <div class="metric-value" id="valTotal">0</div>
        <div class="metric-sub" id="valActiveTarget">Discovering...</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Passed</div>
        <div class="metric-value metric-val-passed" id="valPassed">0</div>
        <div class="metric-sub" id="valPassedPercent">0%</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Failed</div>
        <div class="metric-value metric-val-failed" id="valFailed">0</div>
        <div class="metric-sub" id="valFailedSub">0 errors</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">In Progress</div>
        <div class="metric-value metric-val-running" id="valRunning">0</div>
        <div class="metric-sub">concurrency: 1</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Videos Captured</div>
        <div class="metric-value" id="valVideos" style="color: #c4b5fd;">0</div>
        <div class="metric-sub" id="valVideoSecs">0s total</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Screenshots</div>
        <div class="metric-value" id="valScreenshots" style="color: #38bdf8;">0</div>
        <div class="metric-sub">PNG frames</div>
      </div>
    </div>

    <!-- Currently Running Spotlight Card -->
    <div class="spotlight-card" id="spotlightCard" style="display: none;">
      <div class="spotlight-header">
        <div>
          <div class="spotlight-tag">
            <span class="pulse-dot"></span> CURRENTLY EXECUTING
          </div>
          <div class="spotlight-title" id="spotlightName">Test Name</div>
          <div class="spotlight-suite" id="spotlightSuite">Suite path</div>
        </div>
        <div class="timer-badge" id="spotlightTimer">⏱ 00:00</div>
      </div>

      <div class="terminal-container">
        <div class="terminal-bar">
          <div class="terminal-dots">
            <div class="terminal-dot dot-red"></div>
            <div class="terminal-dot dot-yellow"></div>
            <div class="terminal-dot dot-green"></div>
          </div>
          <div class="terminal-title">LIVE CONSOLE STREAM</div>
          <div><label style="font-size: 11px; color: var(--text-dim); cursor: pointer;"><input type="checkbox" id="chkAutoScroll" checked> Auto-scroll</label></div>
        </div>
        <div class="terminal-body" id="terminalBody"></div>
      </div>
    </div>

    <!-- Test Explorer Toolbar -->
    <div class="explorer-toolbar">
      <div class="search-box">
        <svg class="search-icon" viewBox="0 0 24 24"><path d="M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>
        <input type="text" class="search-input" id="searchInput" placeholder="Search tests by name, suite, error, or asset...">
      </div>
      <div class="filter-pills">
        <button class="pill-btn active" data-filter="recent">⚡ Recent (<span id="cntRecent">0</span>/10)</button>
        <button class="pill-btn" data-filter="all">All (<span id="cntAll">0</span>)</button>
        <button class="pill-btn" data-filter="failed">❌ Failed (<span id="cntFailed">0</span>)</button>
        <button class="pill-btn" data-filter="passed">✓ Passed (<span id="cntPassed">0</span>)</button>
        <button class="pill-btn" data-filter="video">🎬 Videos (<span id="cntVideo">0</span>)</button>
        <button class="pill-btn" data-filter="screenshot">📷 Screenshots (<span id="cntShot">0</span>)</button>
      </div>
    </div>

    <!-- Completed Tests List -->
    <div class="tests-list" id="testsList">
      <div class="empty-state">
        <svg viewBox="0 0 24 24"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"/></svg>
        <p>Waiting for test events...</p>
      </div>
    </div>
  </div>

  <!-- Lightbox Modal -->
  <div class="lightbox-modal" id="lightbox">
    <button class="lightbox-close" id="lightboxClose">&times;</button>
    <img src="" class="lightbox-content" id="lightboxImg" alt="Artifact preview">
  </div>

  <script>
    // Live State
    let appState = {
      title: 'Lumina Smoke Test Studio',
      isRunning: true,
      startTimeMs: Date.now(),
      endTimeMs: null,
      exitCode: null,
      activeTest: null,
      activeTestLogs: [],
      stats: { total: 0, passed: 0, failed: 0, skipped: 0, running: 0, videoCount: 0, screenshotCount: 0, totalVideoSeconds: 0 },
      tests: []
    };

    let activeFilter = 'recent';
    let searchQuery = '';
    let spotlightStartTime = null;
    const openTestIds = new Set();

    // Timer
    setInterval(() => {
      if (appState.startTimeMs) {
        const end = appState.endTimeMs || Date.now();
        const sec = Math.max(0, Math.floor((end - appState.startTimeMs) / 1000));
        const m = String(Math.floor(sec / 60)).padStart(2, '0');
        const s = String(sec % 60).padStart(2, '0');
        document.getElementById('elapsedTimer').textContent = `${m}:${s}`;
      }
      if (spotlightStartTime && appState.activeTest && appState.isRunning) {
        const sec = Math.max(0, Math.floor((Date.now() - spotlightStartTime) / 1000));
        const m = String(Math.floor(sec / 60)).padStart(2, '0');
        const s = String(sec % 60).padStart(2, '0');
        const el = document.getElementById('spotlightTimer');
        if (el) el.textContent = `⏱ ${m}:${s}`;
      }
    }, 1000);

    // Setup SSE connection
    function connectSse() {
      const source = new EventSource('/api/stream');

      source.addEventListener('init', (e) => {
        appState = JSON.parse(e.data);
        if (appState.activeTest && appState.isRunning) {
          spotlightStartTime = appState.activeTest.startTimeMs || Date.now();
        }
        renderAll();
      });

      source.addEventListener('test_start', (e) => {
        const data = JSON.parse(e.data);
        appState.activeTest = data;
        spotlightStartTime = Date.now();

        const body = document.getElementById('terminalBody');
        if (body) {
          body.innerHTML = '';
          const line = document.createElement('div');
          line.className = 'terminal-line info';
          line.textContent = `🚀 Running: ${data.name}`;
          body.appendChild(line);
        }

        if (!data.name.startsWith('loading ')) {
          const idx = appState.tests.findIndex(x => x.id === data.id);
          const t = {
            id: data.id,
            name: data.name,
            suite: data.suite,
            startTimeMs: Date.now(),
            durationMs: 0,
            status: 'running',
            error: null,
            stackTrace: null,
            prints: [],
            media: [],
            usedAssets: []
          };
          if (idx >= 0) {
            appState.tests[idx] = t;
          } else {
            appState.tests.unshift(t);
          }
        }
        updateStats();
        renderSpotlight();
        renderAll();
      });

      source.addEventListener('test_log', (e) => {
        const data = JSON.parse(e.data);
        appendTerminalLine(data.line);
        if (data.testID) {
          const t = appState.tests.find(x => x.id === data.testID);
          if (t) {
            t.prints = t.prints || [];
            t.prints.push(data.line);
          }
        }
      });

      source.addEventListener('raw_log', (e) => {
        const data = JSON.parse(e.data);
        appendTerminalLine(data.line);
      });

      source.addEventListener('test_error', (e) => {
        const data = JSON.parse(e.data);
        const t = appState.tests.find(x => x.id === data.testID);
        if (t) {
          t.error = data.error;
          t.stackTrace = data.stackTrace;
        }
        appendTerminalLine(data.error, 'error');
      });

      source.addEventListener('test_done', (e) => {
        const data = JSON.parse(e.data);
        data.endTimeMs = data.endTimeMs || Date.now();
        const idx = appState.tests.findIndex(x => x.id === data.id);
        if (idx >= 0) {
          appState.tests[idx] = data;
        } else {
          appState.tests.unshift(data);
        }
        if (appState.activeTest && appState.activeTest.id === data.id) {
          appState.activeTest = null;
          spotlightStartTime = null;
        }
        updateStats();
        renderSpotlight();
        renderAll();
      });

      source.addEventListener('suite_done', (e) => {
        const snapshot = JSON.parse(e.data);
        appState = snapshot;
        renderAll();
      });

      source.onerror = () => {
        // Auto-reconnects
      };
    }

    function updateStats() {
      let passed = 0, failed = 0, skipped = 0, running = 0, videos = 0, shots = 0, totalSecs = 0;
      appState.tests.forEach(t => {
        if (t.status === 'passed') passed++;
        else if (t.status === 'failed') failed++;
        else if (t.status === 'skipped') skipped++;
        else running++;

        (t.media || []).forEach(m => {
          if (m.isVideo) {
            videos++;
            if (m.seconds) totalSecs += m.seconds;
          } else {
            shots++;
          }
        });
      });

      appState.stats = {
        total: appState.tests.length,
        passed, failed, skipped, running,
        videoCount: videos,
        screenshotCount: shots,
        totalVideoSeconds: totalSecs
      };

      document.getElementById('valTotal').textContent = appState.stats.total;
      document.getElementById('valPassed').textContent = passed;
      document.getElementById('valPassedPercent').textContent = appState.stats.total ? `${Math.round((passed / appState.stats.total) * 100)}%` : '0%';
      document.getElementById('valFailed').textContent = failed;
      document.getElementById('valFailedSub').textContent = failed === 1 ? '1 failure' : `${failed} failures`;
      document.getElementById('valRunning').textContent = running;
      document.getElementById('valVideos').textContent = videos;
      document.getElementById('valVideoSecs').textContent = `${totalSecs.toFixed(1)}s total`;
      document.getElementById('valScreenshots').textContent = shots;

      document.getElementById('cntAll').textContent = appState.stats.total;
      document.getElementById('cntFailed').textContent = failed;
      document.getElementById('cntPassed').textContent = passed;
      document.getElementById('cntVideo').textContent = videos;
      document.getElementById('cntShot').textContent = shots;
      const cntRecent = document.getElementById('cntRecent');
      if (cntRecent) cntRecent.textContent = Math.min(10, appState.stats.total);

      // Progress bar
      const completed = passed + failed + skipped;
      const total = appState.stats.total;
      const pct = total ? Math.round((completed / total) * 100) : 0;
      const fill = document.getElementById('progressFill');
      fill.style.width = `${pct}%`;
      if (failed > 0) fill.classList.add('has-failure');
      else fill.classList.remove('has-failure');

      document.getElementById('progressText').textContent = `${completed} / ${total} tests completed (${pct}%)`;

      // Status badge
      const badge = document.getElementById('statusBadge');
      const badgeText = document.getElementById('statusText');
      if (appState.isRunning) {
        badge.className = 'status-badge running';
        badgeText.textContent = 'TESTING IN PROGRESS';
      } else if (failed > 0) {
        badge.className = 'status-badge failed';
        badgeText.textContent = `FAILED (${failed} ERRORS)`;
      } else {
        badge.className = 'status-badge passed';
        badgeText.textContent = 'SUITE PASSED';
      }
    }

    function appendTerminalLine(text, type = 'normal') {
      const body = document.getElementById('terminalBody');
      if (!body) return;
      const line = document.createElement('div');
      line.className = `terminal-line ${type}`;
      line.textContent = text;
      body.appendChild(line);

      const chk = document.getElementById('chkAutoScroll');
      if (chk && chk.checked) {
        body.scrollTop = body.scrollHeight;
      }
    }

    function renderSpotlight() {
      const card = document.getElementById('spotlightCard');
      if (appState.activeTest && appState.isRunning) {
        card.style.display = 'block';
        document.getElementById('spotlightName').textContent = appState.activeTest.name;
        document.getElementById('spotlightSuite').textContent = appState.activeTest.suite || '';
        const body = document.getElementById('terminalBody');
        if (body && body.children.length === 0 && appState.activeTestLogs && appState.activeTestLogs.length > 0) {
          appState.activeTestLogs.forEach(l => {
            const div = document.createElement('div');
            div.className = 'terminal-line';
            div.textContent = l;
            body.appendChild(div);
          });
          body.scrollTop = body.scrollHeight;
        }
      } else {
        card.style.display = 'none';
      }
    }

    function getSortedTests() {
      return [...appState.tests].sort((a, b) => {
        if (a.status === 'running' && b.status !== 'running') return -1;
        if (b.status === 'running' && a.status !== 'running') return 1;
        const timeA = a.endTimeMs || a.startTimeMs || 0;
        const timeB = b.endTimeMs || b.startTimeMs || 0;
        return timeB - timeA;
      });
    }

    function matchesSearch(t) {
      if (!searchQuery) return true;
      const q = searchQuery.toLowerCase();
      const inName = (t.name || '').toLowerCase().includes(q);
      const inSuite = (t.suite || '').toLowerCase().includes(q);
      const inErr = (t.error || '').toLowerCase().includes(q);
      const inAsset = (t.usedAssets || []).some(a => a.toLowerCase().includes(q));
      return inName || inSuite || inErr || inAsset;
    }

    function getVisibleTests() {
      const sorted = getSortedTests();
      if (activeFilter === 'recent') {
        return sorted.filter(matchesSearch).slice(0, 10);
      }
      return sorted.filter(t => {
        if (activeFilter === 'failed' && t.status !== 'failed') return false;
        if (activeFilter === 'passed' && t.status !== 'passed') return false;
        if (activeFilter === 'video' && !(t.media && t.media.some(m => m.isVideo))) return false;
        if (activeFilter === 'screenshot' && !(t.media && t.media.some(m => !m.isVideo))) return false;
        return matchesSearch(t);
      });
    }

    function renderAll() {
      document.getElementById('uiTitle').textContent = appState.title || 'Lumina Smoke Test Studio';
      updateStats();
      renderSpotlight();

      const listContainer = document.getElementById('testsList');
      const visible = getVisibleTests();

      if (visible.length === 0) {
        listContainer.innerHTML = '<div class="empty-state"><p>No tests match the current filter.</p></div>';
        return;
      }

      listContainer.innerHTML = '';
      visible.forEach(t => {
        const card = createCardElement(t);
        if (openTestIds.has(t.id)) {
          card.classList.add('open');
        }
        listContainer.appendChild(card);
      });
    }

    function createCardElement(t) {
      const card = document.createElement('div');
      card.id = `test-${t.id}`;
      card.className = `test-card ${t.status}`;

      const iconHtml = t.status === 'passed'
        ? '<div class="test-status-icon icon-passed">✓</div>'
        : (t.status === 'failed'
          ? '<div class="test-status-icon icon-failed">✕</div>'
          : '<div class="test-status-icon icon-running"><span class="pulse-dot"></span></div>');

      const videos = (t.media || []).filter(m => m.isVideo);
      const shots = (t.media || []).filter(m => !m.isVideo);
      const dur = (t.durationMs / 1000).toFixed(1);

      card.innerHTML = `
        <div class="test-header">
          <div class="test-left">
            ${iconHtml}
            <div class="test-info">
              <div class="test-name">${escapeHtml(t.name)}</div>
              <div class="test-suite">${escapeHtml(t.suite || '')}</div>
            </div>
          </div>
          <div class="test-badges">
            ${videos.length ? `<span class="badge-media badge-video">🎬 ${videos.length} ${videos[0].seconds ? `(${videos[0].seconds.toFixed(1)}s)` : 'video'}</span>` : ''}
            ${shots.length ? `<span class="badge-media">📷 ${shots.length}</span>` : ''}
            <span class="badge-duration">${dur}s</span>
            <svg class="chevron" viewBox="0 0 24 24"><path d="M7 10l5 5 5-5z"/></svg>
          </div>
        </div>
        <div class="test-body">
          ${t.error ? `
            <div class="error-alert">
              <h4>Failure Assertion</h4>
              <pre>${escapeHtml(t.error)}</pre>
              ${t.stackTrace ? `<pre style="margin-top: 8px; color: #fca5a5; font-size: 11px;">${escapeHtml(t.stackTrace)}</pre>` : ''}
            </div>
          ` : ''}

          ${videos.length ? `
            <div class="media-section">
              <div class="media-title">🎬 Recorded Video Evidence</div>
              ${videos.map(v => `
                <div class="video-wrapper">
                  <video controls autoplay loop muted playsinline>
                    <source src="${v.path}" type="video/webm">
                    <source src="${v.path}" type="video/mp4">
                    Your browser does not support HTML5 video.
                  </video>
                  <div class="video-meta-bar">
                    <div class="video-specs">
                      ${v.seconds ? `<span>⏱ ${v.seconds.toFixed(1)}s</span>` : ''}
                      ${v.fps ? `<span>⚡ ${v.fps.toFixed(0)} fps</span>` : ''}
                      ${v.width && v.height ? `<span>📐 ${v.width}×${v.height}</span>` : ''}
                    </div>
                    ${(v.violations && v.violations.length) ? `
                      <div>
                        ${v.violations.map(vi => `<span class="rule-violation-badge">⚠️ ${vi}</span>`).join(' ')}
                      </div>
                    ` : '<span style="color: var(--accent-emerald); font-weight: 600;">✓ Meets the smoke-video rules</span>'}
                  </div>
                </div>
              `).join('')}
            </div>
          ` : ''}

          ${shots.length ? `
            <div class="media-section">
              <div class="media-title">📷 Visual Screenshots (${shots.length})</div>
              <div class="screenshots-grid">
                ${shots.map(s => `
                  <div class="screenshot-item" onclick="openLightbox('${s.path}')">
                    <img src="${s.path}" alt="${escapeHtml(s.label || 'Screenshot')}" loading="lazy">
                    <div class="screenshot-label">${escapeHtml(s.label || s.fileName)}</div>
                  </div>
                `).join('')}
              </div>
            </div>
          ` : ''}

          ${(t.usedAssets && t.usedAssets.length) ? `
            <div class="media-section">
              <div class="media-title">📦 Real 3D Assets Used (test-assets/)</div>
              <div class="assets-list">
                ${t.usedAssets.map(a => `<span class="asset-pill">🧊 ${escapeHtml(a)}</span>`).join('')}
              </div>
            </div>
          ` : ''}

          ${(t.prints && t.prints.length) ? `
            <div class="media-section">
              <div class="media-title">📜 Console Stdout Logs (${t.prints.length} lines)</div>
              <div class="test-logs-box">${escapeHtml(t.prints.join('\n'))}</div>
            </div>
          ` : ''}
        </div>
      `;

      card.querySelector('.test-header').addEventListener('click', () => {
        const isOpen = card.classList.toggle('open');
        if (isOpen) {
          openTestIds.add(t.id);
        } else {
          openTestIds.delete(t.id);
        }
      });

      return card;
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    // Lightbox handlers
    window.openLightbox = function(url) {
      const box = document.getElementById('lightbox');
      const img = document.getElementById('lightboxImg');
      img.src = url;
      box.classList.add('active');
    };
    document.getElementById('lightboxClose').addEventListener('click', () => {
      document.getElementById('lightbox').classList.remove('active');
    });
    document.getElementById('lightbox').addEventListener('click', (e) => {
      if (e.target.id === 'lightbox') {
        document.getElementById('lightbox').classList.remove('active');
      }
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        document.getElementById('lightbox').classList.remove('active');
      }
    });

    // Filters & Search
    document.querySelectorAll('.pill-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.pill-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeFilter = btn.dataset.filter;
        renderAll();
      });
    });

    document.getElementById('searchInput').addEventListener('input', (e) => {
      searchQuery = e.target.value.trim();
      renderAll();
    });

    // Start streaming on load
    window.addEventListener('DOMContentLoaded', connectSse);
  </script>
</body>
</html>
''';
}
