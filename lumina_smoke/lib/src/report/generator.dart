import 'dart:convert';
import 'dart:io';

import 'package:lumina_smoke/src/video.dart';
import 'package:lumina_smoke/src/report/config.dart';
import 'package:lumina_smoke/src/report/html.dart';
import 'package:lumina_smoke/src/report/model.dart';
import 'package:lumina_smoke/src/report/paths.dart';

/// Turns `flutter test --machine` events and the artifact directory into a
/// [SmokeReportModel], and the model into HTML pages.
///
/// Events may carry the runner's tags: `run` (the `flutter test` process,
/// whose test ids start from 0 again), `target` / `targets` (what it ran),
/// `filter` (its scenario filter, e.g. `--plain-name x`) and `backend`.
/// Untagged events (a canned stream) are one run.
class SmokeReportGenerator {
  SmokeReportGenerator(this.config) : html = SmokeReportHtml(config);

  final SmokeReportConfig config;
  final SmokeReportHtml html;

  /// Builds the report of [events], matching every PNG and video under
  /// [artifactsDir] (recursively) to a test through its sidecar's declared
  /// name.
  ///
  /// The exit code counts every visible test, crash and rule-breaking video;
  /// with [countedRuns] (a merged report) only those of the given runs.
  SmokeReportModel processEvents(
    List<Map<String, dynamic>> events, {
    Directory? artifactsDir,
    DateTime? timestamp,
    Set<int>? countedRuns,
  }) {
    // A target run more than once (merged runs) counts once: its latest run.
    final latestRun = <String, int>{};
    final filteredRuns = <int>{};
    for (final e in events) {
      final key = smokeRunKey(e);
      final run = runOf(e);
      if (key != null && run > (latestRun[key] ?? -1)) latestRun[key] = run;
      if (e['filter'] is String) filteredRuns.add(run);
    }
    events = [
      for (final e in events)
        if (smokeRunKey(e) == null || runOf(e) == latestRun[smokeRunKey(e)]) e,
    ];

    final testsById = <String, TestResultItem>{};
    final suitesById = <String, String>{};
    final groupsById = <String, String>{};
    final hidden = <String>{};
    final failedRuns = <int>{};
    var firstTime = -1;
    var lastTime = -1;

    for (final event in events) {
      final type = event['type'] as String?;
      final time = (event['time'] as num?)?.toInt() ?? 0;
      if (firstTime == -1 || time < firstTime) firstTime = time;
      if (time > lastTime) lastTime = time;
      final run = runOf(event);
      final backend = backendOf(event);
      String key(Object? id) => '$run:${backend ?? ''}:$id';

      switch (type) {
        case 'suite':
          final suite = event['suite'];
          if (suite is Map) suitesById[key(suite['id'])] = '${suite['path'] ?? ''}';
        case 'group':
          final group = event['group'];
          if (group is Map) groupsById[key(group['id'])] = '${group['name'] ?? ''}';
        case 'testStart':
          final test = event['test'];
          if (test is! Map) continue;
          final name = '${test['name'] ?? 'Unnamed Test'}';
          final suite = test['suiteID'] == null ? '' : (suitesById[key(test['suiteID'])] ?? '');
          final groupIds = test['groupIDs'] is List ? test['groupIDs'] as List : const [];
          String? leaf;
          if (groupIds.isNotEmpty) {
            final groupName = groupsById[key(groupIds.last)] ?? '';
            if (groupName.isNotEmpty && name.startsWith('$groupName ')) leaf = name.substring(groupName.length + 1);
          }
          final id = key(test['id']);
          testsById[id] = TestResultItem(
            id: id,
            name: name,
            leafName: leaf,
            suite: suite,
            startTimeMs: time,
            backend: backend,
            run: run,
            category: config.categoryOf(suite, name),
          );
        case 'print':
          testsById[key(event['testID'])]?.prints.add('${event['message'] ?? ''}');
        case 'error':
          final t = testsById[key(event['testID'])];
          if (t != null) {
            final message = '${event['error'] ?? ''}';
            t.error = t.error == null ? message : '${t.error}\n\n$message';
            final stack = '${event['stackTrace'] ?? ''}';
            if (stack.isNotEmpty) t.stackTrace = t.stackTrace == null ? stack : '${t.stackTrace}\n\n$stack';
            t.status = 'failed';
          }
        case 'testDone':
          final id = key(event['testID']);
          final t = testsById[id];
          if (t == null) continue;
          if (event['hidden'] == true) hidden.add(id);
          t.durationMs = time - t.startTimeMs;
          final result = '${event['result'] ?? 'success'}';
          if (result == 'skipped' || (event['skipped'] == true && result == 'success' && t.error == null)) {
            t.status = 'skipped';
          } else if (result == 'failure' || result == 'error' || t.error != null) {
            t.status = 'failed';
            if (event['error'] != null) t.error ??= '${event['error']}';
            if (event['stackTrace'] != null) t.stackTrace ??= '${event['stackTrace']}';
          } else {
            t.status = 'passed';
          }
        case 'done':
          if (event['success'] == false) failedRuns.add(run);
      }
    }

    // setUpAll / tearDownAll and the loading pseudo-tests are shown only
    // when they fail.
    for (final t in testsById.values) {
      // Started but never done: its run ended (or was killed) first.
      if (t.status != 'running') continue;
      t.status = 'failed';
      t.error = [?t.error, 'The test did not finish: its run ended, or was stopped, before the test was done.'].join('\n');
    }
    bool isPlumbing(TestResultItem t) =>
        !t.isFailure && (t.name.contains('(setUpAll)') || t.name.contains('(tearDownAll)') || t.name.startsWith('loading '));

    // The same test (backend + file + name) run again in a later run counts
    // once: its latest result. A file's latest whole-file run replaces all of
    // its older results, including tests that no longer exist under the same
    // name; a filtered run replaces only the tests it ran.
    final latestRunOfSuite = <String, int>{};
    for (final t in testsById.values) {
      if (filteredRuns.contains(t.run) || t.suite.isEmpty) continue;
      final k = '${t.backend}\u0000${t.suite}';
      if (t.run > (latestRunOfSuite[k] ?? -1)) latestRunOfSuite[k] = t.run;
    }
    final latestByTest = <String, TestResultItem>{};
    for (final t in testsById.values) {
      if (hidden.contains(t.id) || isPlumbing(t)) continue;
      if (t.suite.isNotEmpty && t.run < (latestRunOfSuite['${t.backend}\u0000${t.suite}'] ?? -1)) continue;
      final k = '${t.backend}\u0000${t.suite}\u0000${t.name}';
      final kept = latestByTest[k];
      if (kept == null || t.run >= kept.run) latestByTest[k] = t;
    }
    final tests = latestByTest.values.toList();

    // Every artifact lands on a card: matched to a test through its sidecar,
    // or on its own card.
    final orphansByKey = <String, OrphanedArtifact>{};
    if (artifactsDir != null && artifactsDir.existsSync()) {
      for (final found in scanArtifacts(artifactsDir)) {
        final match = found.testName == null ? null : bestTestFor(found.testName!, found.backend, tests);
        final MediaHolder holder = match ??
            orphansByKey.putIfAbsent('${found.backend}\u0000${found.title}', () {
              return OrphanedArtifact(
                testName: found.title,
                backend: found.backend,
                category: config.orphanCategory ??
                    config.categoryOf(found.media.isEmpty ? '' : found.media.first.relativePath, found.title),
              );
            });
        found.media.forEach(holder.addMedia);
        holder.addAssets(found.usedAssets);
      }
    }
    final orphans = orphansByKey.values.toList()
      ..sort((a, b) {
        final byName = a.testName.compareTo(b.testName);
        return byName != 0 ? byName : '${a.backend}'.compareTo('${b.backend}');
      });

    // A video under the minimum length, size or rate fails its test.
    var shortVideos = 0, smallVideos = 0, slowVideos = 0, artifacts = 0;
    for (final t in tests) {
      artifacts += t.media.length;
      shortVideos += t.shortVideos.length;
      smallVideos += t.smallVideos.length;
      slowVideos += t.slowVideos.length;
      final bad = t.badVideos;
      if (bad.isEmpty) continue;
      final why = 'Smoke video under ${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s, '
          '${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight} or ${SmokeVideo.minimumFps} fps: '
          '${bad.map((m) => '${m.relativePath} (${m.violations.join(', ')}; ${m.video?.describe ?? 'unmeasured'})').join('; ')}';
      t.status = 'failed';
      t.error = t.error == null ? why : '${t.error}\n$why';
    }
    var badOrphans = 0;
    for (final o in orphans) {
      artifacts += o.media.length;
      shortVideos += o.shortVideos.length;
      smallVideos += o.smallVideos.length;
      slowVideos += o.slowVideos.length;
      if (o.badVideos.isNotEmpty) badOrphans++;
    }

    tests.sort((a, b) {
      int score(TestResultItem t) => t.isFailure ? 0 : (t.isPassed ? 1 : 2);
      final byStatus = score(a).compareTo(score(b));
      if (byStatus != 0) return byStatus;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : '${a.backend}'.compareTo('${b.backend}');
    });

    // A run that failed without leaving any test result (a crash, a load
    // error) fails the report; superseded failures do not.
    final runsWithResults = {for (final t in testsById.values) t.run};
    final crashed = failedRuns.where((r) => !runsWithResults.contains(r)).toSet();
    bool counted(int run) => countedRuns == null || countedRuns.contains(run);
    final failing = tests.any((t) => t.isFailure && counted(t.run)) ||
        crashed.any(counted) ||
        (countedRuns == null && badOrphans > 0);

    final categories = <String>{for (final t in tests) t.category, for (final o in orphans) o.category}.toList();
    int failuresIn(String c) =>
        tests.where((t) => t.category == c && t.isFailure).length +
        orphans.where((o) => o.category == c && o.badVideos.isNotEmpty).length;
    categories.sort((a, b) {
      if (config.failingCategoriesFirst) {
        final fa = failuresIn(a) > 0, fb = failuresIn(b) > 0;
        if (fa != fb) return fa ? -1 : 1;
      }
      final byOrder = config.categoryOrder(a).compareTo(config.categoryOrder(b));
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });

    return SmokeReportModel(
      tests: tests,
      orphanedArtifacts: orphans,
      categories: categories,
      totalCount: tests.length,
      passedCount: tests.where((t) => t.isPassed).length,
      failedCount: tests.where((t) => t.isFailure).length + badOrphans,
      skippedCount: tests.where((t) => t.isSkipped).length,
      shortVideoCount: shortVideos,
      smallVideoCount: smallVideos,
      slowVideoCount: slowVideos,
      artifactCount: artifacts,
      wallDurationMs: lastTime >= firstTime && firstTime >= 0 ? lastTime - firstTime : 0,
      timestamp: timestamp ?? DateTime.now(),
      exitCode: failing ? 1 : 0,
      dartVersion: Platform.version.split(' ').first,
    );
  }

  /// Every sidecar under [base] (recursively) with its PNG and video, plus
  /// one group per file base name for the media no sidecar names. A folder
  /// named like a configured backend tags its artifacts with that backend;
  /// otherwise a sidecar's own `backend` does.
  List<ArtifactGroup> scanArtifacts(Directory base) {
    final result = <ArtifactGroup>[];
    if (!base.existsSync()) return result;
    final backendNames = {for (final b in config.backends) b.name};
    final baseAbs = slashPath(base.absolute.path).replaceAll(RegExp(r'/+$'), '');
    String rel(String path) {
      final abs = slashPath(File(path).absolute.path);
      final prefix = '$baseAbs/';
      final inside = Platform.isWindows ? abs.toLowerCase().startsWith(prefix.toLowerCase()) : abs.startsWith(prefix);
      return inside ? abs.substring(prefix.length) : abs;
    }

    final dirs = <Directory>[base, ...base.listSync(recursive: true, followLinks: false).whereType<Directory>()]
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final dir in dirs) {
      final dirName = dir.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      final folderBackend = dir.path != base.path && backendNames.contains(dirName) ? dirName : null;
      final files = dir.listSync(followLinks: false).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
      final claimed = <String>{};

      File resolve(String declared) {
        final asDeclared = File(declared);
        if (asDeclared.isAbsolute && asDeclared.existsSync()) return asDeclared;
        final local = File('${dir.path}${Platform.pathSeparator}$declared');
        if (!asDeclared.isAbsolute) return local;
        final byName = File('${dir.path}${Platform.pathSeparator}${declared.split(RegExp(r'[/\\]')).last}');
        return byName.existsSync() ? byName : asDeclared;
      }

      for (final jsonFile in files.where((f) => f.path.toLowerCase().endsWith('.json'))) {
        Map<String, dynamic> meta;
        try {
          final decoded = jsonDecode(jsonFile.readAsStringSync());
          if (decoded is! Map<String, dynamic>) continue;
          meta = decoded;
        } catch (_) {
          continue;
        }
        final testName = (meta['test'] ?? meta['testName']) as String?;
        if (testName == null) continue;
        final savedAt = (meta['savedAt'] as num?)?.toInt() ?? 0;
        final group = ArtifactGroup(
          title: testName,
          testName: testName,
          backend: folderBackend ?? meta['backend'] as String?,
        );
        final declared = <String>{
          for (final k in const ['file', 'screenshot', 'video'])
            if (meta[k] is String && (meta[k] as String).isNotEmpty) meta[k] as String,
        };
        final seenPaths = <String>{};
        for (final d in declared) {
          final f = resolve(d);
          final norm = normalizeSmokePath(f.path);
          if (!seenPaths.add(norm)) continue;
          claimed.add(norm);
          final item = ReportMedia.load(
            f,
            relativePath: rel(f.path),
            label: testName,
            declared: _declaredVideo(meta),
            savedAt: savedAt,
          );
          if (item != null) group.media.add(item);
        }
        group.usedAssets.addAll(((meta['usedAssets'] as List?) ?? const []).map((e) => '$e'));
        if (group.media.isNotEmpty) result.add(group);
      }

      // Media no sidecar claims still belongs in the report.
      final loose = <String, ArtifactGroup>{};
      for (final f in files) {
        if (claimed.contains(normalizeSmokePath(f.path))) continue;
        final name = f.uri.pathSegments.last;
        if (ReportMedia.mimeFor(name) == null) continue;
        final baseName = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
        final item = ReportMedia.load(f, relativePath: rel(f.path));
        if (item == null) continue;
        loose.putIfAbsent(baseName, () {
          final g = ArtifactGroup(title: baseName, testName: null, backend: folderBackend);
          result.add(g);
          return g;
        }).media.add(item);
      }
    }
    return result;
  }

  static SmokeVideoInfo _declaredVideo(Map<String, dynamic> meta) {
    double? d(String k) => (meta[k] as num?)?.toDouble();
    int? i(String k) => (meta[k] as num?)?.toInt();
    final fps = d('fps') ?? d('videoFps');
    final frames = i('frameCount');
    return SmokeVideoInfo(
      seconds: d('durationSeconds') ?? d('videoSeconds') ?? (frames != null && fps != null && fps > 0 ? frames / fps : null),
      width: i('width') ?? i('videoWidth'),
      height: i('height') ?? i('videoHeight'),
      fps: fps,
      encoder: meta['encoder'] as String?,
    );
  }

  /// The test an artifact saved as [artifactName] (on [backend]) belongs to,
  /// or null: an exact full or leaf name first, then the same name ignoring
  /// case and punctuation, then the longest test name the artifact name
  /// extends (`<test name> (<detail>)`, `<test name>: <step>`), then one name
  /// containing the other, then the same `Scenario NN` of the same module,
  /// and last a test of the file the artifact is named after
  /// (`<file>_smoke_test: <step>`).
  TestResultItem? bestTestFor(String artifactName, String? backend, List<TestResultItem> tests) {
    TestResultItem? best;
    var bestScore = 0;
    for (final t in tests) {
      if (backend != null && t.backend != null && t.backend != backend) continue;
      final score = matchScore(t, artifactName);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best ?? _matchBySuiteFile(artifactName, backend, tests);
  }

  /// How well the artifact name [artifactName] matches [test] (0: not at
  /// all).
  int matchScore(TestResultItem test, String artifactName) {
    final title = test.name;
    final leaf = test.leafName;
    if (title == artifactName) return 1 << 24;
    if (leaf != null && leaf == artifactName) return (1 << 24) - 1;
    final normTitle = _norm(title);
    final normArtifact = _norm(artifactName);
    if (normTitle.isEmpty || normArtifact.isEmpty) return 0;
    if (normTitle == normArtifact) return 1 << 23;
    if (_extends(artifactName, title)) return (1 << 22) + title.length * 2;
    if (leaf != null && _extends(artifactName, leaf)) return (1 << 22) + leaf.length * 2 - 1;
    if (normTitle.contains(normArtifact) || normArtifact.contains(normTitle)) return (1 << 21) + normTitle.length;
    final scenario = RegExp(r'scenario\s*([0-9]+)', caseSensitive: false);
    final m1 = scenario.firstMatch(title);
    final m2 = scenario.firstMatch(artifactName);
    if (m1 == null || m2 == null || int.parse(m1.group(1)!) != int.parse(m2.group(1)!)) return 0;
    final suiteFile = _norm(test.suite.replaceAll(r'\', '/').split('/').last.replaceAll(RegExp(r'\.dart$'), ''));
    if (config.scenarioKeywords.isNotEmpty) {
      var hits = 0;
      for (final k in config.scenarioKeywords) {
        final kn = _norm(k);
        if (kn.isNotEmpty && normArtifact.contains(kn) && (normTitle.contains(kn) || suiteFile.contains(kn))) hits++;
      }
      return hits == 0 ? 0 : 1000 + 300 * hits;
    }
    final shared = _words(artifactName).intersection({..._words(title), ..._words(test.suite.split(RegExp(r'[/\\]')).last)});
    return shared.isEmpty ? 0 : 1000 + shared.length;
  }

  /// Fallback for artifacts named after their test file
  /// (`game_framework_smoke_test: PIE control 01 playing`): the test in that
  /// file whose name shares the most words with the rest of the artifact name.
  TestResultItem? _matchBySuiteFile(String artifactName, String? backend, List<TestResultItem> tests) {
    final artifact = _sanitize(artifactName);
    final candidates = <TestResultItem>[];
    var prefixLength = 0;
    for (final t in tests) {
      if (t.suite.isEmpty) continue;
      if (backend != null && t.backend != null && t.backend != backend) continue;
      final file = t.suite.replaceAll(r'\', '/').split('/').last;
      final base = _sanitize(file.endsWith('.dart') ? file.substring(0, file.length - 5) : file);
      if (base.isEmpty || !(artifact == base || artifact.startsWith('${base}_'))) continue;
      candidates.add(t);
      prefixLength = base.length;
    }
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single;
    final words = _words(artifact.substring(prefixLength));
    TestResultItem? best;
    var bestOverlap = 0;
    for (final t in candidates) {
      final overlap = _words(t.name).intersection(words).length;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = t;
      }
    }
    return best;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _sanitize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  static const _stopWords = {'the', 'and', 'with', 'test', 'tests', 'smoke', 'scenario', 'real', 'dart'};

  static Set<String> _words(String text) =>
      _sanitize(text).split('_').where((w) => w.length >= 3 && !_stopWords.contains(w)).toSet();

  /// Whether [artifactName] is [testName] followed by a detail that starts
  /// with something other than a letter or digit.
  static bool _extends(String artifactName, String testName) {
    if (testName.isEmpty || artifactName.length <= testName.length || !artifactName.startsWith(testName)) return false;
    return !RegExp(r'[A-Za-z0-9]').hasMatch(artifactName[testName.length]);
  }

  // ---------------------------------------------------------------------------
  // Pages
  // ---------------------------------------------------------------------------

  /// The report as pages keyed by their path relative to [reportDir]: the
  /// index `smoke_report.html` and `smoke_report/<slug>.html` per category.
  /// Every PNG and video is linked relative to its page (never embedded).
  Map<String, String> renderPages(SmokeReportModel model, {String reportDir = 'build'}) => html.renderPages(model, reportDir: reportDir);

  /// The index page.
  String renderHtml(SmokeReportModel model) => html.renderIndex(model);

  /// One category's page.
  String renderCategoryHtml(SmokeReportModel model, String category, {String reportDir = 'build'}) =>
      html.renderCategory(model, category, reportDir: reportDir);

  /// Writes [renderPages] under [reportFile] (the index) and its sibling
  /// `<name without .html>/` folder, removing pages of categories that no
  /// longer exist. Returns the index.
  File writeReport(SmokeReportModel model, File reportFile) {
    final index = reportFile.absolute;
    final pagesDir = Directory(index.path.replaceAll(RegExp(r'\.html?$'), ''));
    final pages = renderPages(model, reportDir: index.parent.path);
    index.parent.createSync(recursive: true);
    pagesDir.createSync(recursive: true);
    final wanted = {
      for (final k in pages.keys)
        if (k != 'smoke_report.html') k.substring('smoke_report/'.length),
    };
    for (final f in pagesDir.listSync().whereType<File>()) {
      if (f.path.endsWith('.html') && !wanted.contains(f.uri.pathSegments.last)) f.deleteSync();
    }
    for (final entry in pages.entries) {
      final target = entry.key == 'smoke_report.html'
          ? index
          : File('${pagesDir.path}${Platform.pathSeparator}${entry.key.substring('smoke_report/'.length)}');
      target.writeAsStringSync(entry.value);
    }
    return index;
  }

  /// File name (under the report's folder) of a category's page.
  static String categorySlug(String category) => SmokeReportHtml.categorySlug(category);

  /// Anchor of a test's card on its category page.
  static String testAnchor(TestResultItem test) => SmokeReportHtml.testAnchor(test);

  /// Anchor of an unmatched artifact's card on its category page.
  static String orphanAnchor(OrphanedArtifact orphan) => SmokeReportHtml.orphanAnchor(orphan);
}

/// A sidecar (or a set of files no sidecar names) found under the artifact
/// directory.
class ArtifactGroup {
  ArtifactGroup({required this.title, required this.testName, required this.backend});

  final String title;

  /// The declared test name from the sidecar; null for media without one.
  final String? testName;

  /// From the folder, else the sidecar; null when unknown.
  final String? backend;
  final List<ReportMedia> media = [];
  final List<String> usedAssets = [];
}

/// The run an event belongs to (0 when untagged).
int runOf(Map<String, dynamic> e) => (e['run'] as num?)?.toInt() ?? 0;

/// The backend an event ran on (`backend`, or the older `__backend`).
String? backendOf(Map<String, dynamic> e) => (e['backend'] ?? e['__backend']) as String?;

/// What an event's run ran, for merging: its target, backend and scenario
/// filter. Null for untagged events.
String? smokeRunKey(Map<String, dynamic> e) {
  final target = e['target'];
  if (target is! String) return null;
  final filter = e['filter'];
  final backend = backendOf(e);
  return [target, backend ?? '', if (filter is String) filter].join('\u0000');
}

/// The targets a run's events name (`targets`, else `target`).
List<String> targetsOf(Map<String, dynamic> e) {
  final list = e['targets'];
  if (list is List) return [for (final t in list) '$t'];
  final target = e['target'];
  return target is String ? [target] : const [];
}

/// The earlier events a merging run keeps: targets being re-run are replaced
/// (a filtered re-run replaces only the same filter's earlier run), older
/// runs of any target are replaced, and a run none of whose targets exists
/// any more (a deleted or renamed smoke file, or a mistyped target such as a
/// `--plain-name` value taken for a file) is dropped, so its result cannot
/// sit in the merged report forever.
List<Map<String, dynamic>> smokeEventsKeptOnMerge(
  List<Map<String, dynamic>> previous, {
  required Set<String> rerun,
  String? filter,
  required Map<String, int> latestRun,
  bool Function(String target)? targetExists,
}) {
  final exists = targetExists ?? (t) => FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound;
  final existing = <String, bool>{};
  final rerunNorm = {for (final r in rerun) normalizeSmokePath(r)};
  bool isRerun(String target) {
    final t = normalizeSmokePath(target);
    return rerunNorm.any((r) => t == r || t.startsWith('$r/'));
  }

  final kept = <Map<String, dynamic>>[];
  for (final e in previous) {
    final targets = targetsOf(e);
    if (targets.isNotEmpty) {
      if (targets.every(isRerun) && (filter == null || e['filter'] == filter)) continue;
      if (runOf(e) != latestRun[smokeRunKey(e)]) continue;
      if (!targets.any((t) => existing.putIfAbsent(t, () => exists(t)))) continue;
    }
    kept.add(e);
  }
  return kept;
}
