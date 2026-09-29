import '../video.dart';
import 'ansi.dart';
import 'config.dart';
import 'model.dart';
import 'paths.dart';

/// The report's HTML: an index page and one page per category, every PNG and
/// video linked relative to the page it is on, never embedded.
class SmokeReportHtml {
  SmokeReportHtml(this.config);

  final SmokeReportConfig config;

  /// File name (under the report's folder) of a category's page.
  static String categorySlug(String category) {
    final slug = category
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? 'other' : slug;
  }

  /// Anchor of a test's card on its category page.
  static String testAnchor(TestResultItem test) {
    final file = test.suite.replaceAll(r'\', '/').split('/').last;
    return 'test-${categorySlug([file, test.name, ?test.backend].where((s) => s.isNotEmpty).join('-'))}';
  }

  /// Anchor of an unmatched artifact's card on its category page.
  static String orphanAnchor(OrphanedArtifact orphan) =>
      'orphan-${categorySlug([orphan.testName, ?orphan.backend].join('-'))}';

  /// The index plus one page per category, keyed by path relative to
  /// [reportDir].
  Map<String, String> renderPages(SmokeReportModel model, {String reportDir = 'build'}) {
    final pages = <String, String>{'smoke_report.html': renderIndex(model)};
    for (final c in model.categories) {
      pages['smoke_report/${categorySlug(c)}.html'] = renderCategory(model, c, reportDir: reportDir);
    }
    return pages;
  }

  String get _title => config.title;

  int _failuresIn(SmokeReportModel model, String category) =>
      model.tests.where((t) => t.category == category && t.isFailure).length +
      model.orphanedArtifacts.where((o) => o.category == category && o.badVideos.isNotEmpty).length;

  // ---------------------------------------------------------------------------
  // Index
  // ---------------------------------------------------------------------------

  /// The index page: overall totals, the failing tests (each linking to its
  /// card) and one row per category linking to `smoke_report/<slug>.html`.
  String renderIndex(SmokeReportModel model) {
    final sb = StringBuffer();
    _writeHead(sb, _title);
    sb.writeln('<div class="header">');
    sb.writeln('<div class="header-title-group">');
    sb.writeln('<h1>${_titleText(_title)}${_tagHtml()}</h1>');
    sb.writeln('</div>');
    _writeHeaderMeta(sb, model);
    sb.writeln('</div>');

    final smokeCount = model.tests.where((t) => t.isSmoke).length;
    final minimum = SmokeVideo.minimumSeconds.toStringAsFixed(0);
    const minimumSize = '${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}';
    final pngs = model.tests.fold(0, (n, t) => n + t.screenshots.length) +
        model.orphanedArtifacts.fold(0, (n, o) => n + o.screenshots.length);
    final videos = model.tests.fold(0, (n, t) => n + t.videos.length) +
        model.orphanedArtifacts.fold(0, (n, o) => n + o.videos.length);

    sb.writeln('<div class="section-title">Summary</div>');
    sb.writeln('<div class="summary-bar">');
    _summaryCard(sb, 'total', model.totalCount, '${model.totalCount} tests');
    _summaryCard(sb, 'smoke', smokeCount, '$smokeCount smoke');
    _summaryCard(sb, 'passed', model.passedCount, '${model.passedCount} passed');
    _summaryCard(sb, 'failed', model.failedCount, '${model.failedCount} failed');
    _summaryCard(sb, 'skipped', model.skippedCount, '${model.skippedCount} skipped');
    _summaryCard(sb, 'media', model.artifactCount, '${model.artifactCount} artifacts ($pngs PNG / $videos video)');
    _summaryCard(sb, model.shortVideoCount > 0 ? 'failed' : 'passed', model.shortVideoCount,
        '${model.shortVideoCount} videos &lt; $minimum s');
    _summaryCard(sb, model.smallVideoCount > 0 ? 'failed' : 'passed', model.smallVideoCount,
        '${model.smallVideoCount} videos &lt; $minimumSize');
    _summaryCard(sb, model.slowVideoCount > 0 ? 'failed' : 'passed', model.slowVideoCount,
        '${model.slowVideoCount} videos &lt; ${SmokeVideo.minimumFps} fps');
    sb.writeln('</div>');

    final failing = model.tests.where((t) => t.isFailure).toList();
    final failingOrphans = model.orphanedArtifacts.where((o) => o.badVideos.isNotEmpty).toList();
    if (failing.isNotEmpty || failingOrphans.isNotEmpty) {
      sb.writeln('<div class="section-title">Failing tests (${failing.length + failingOrphans.length})</div>');
      sb.writeln('<ul class="failing-list" id="failing-tests">');
      for (final t in failing) {
        sb.writeln('<li><span class="badge fail">FAIL</span> '
            '<a href="smoke_report/${categorySlug(t.category)}.html#${testAnchor(t)}">${escapeHtml(t.name)}</a>'
            '${_backendTag(t.backend)}'
            '<span class="test-suite">${escapeHtml(t.category)}${t.suite.isNotEmpty ? ' · ${escapeHtml(t.suite)}' : ''}</span></li>');
      }
      for (final o in failingOrphans) {
        sb.writeln('<li><span class="badge fail">VIDEO</span> '
            '<a href="smoke_report/${categorySlug(o.category)}.html#${orphanAnchor(o)}">${escapeHtml(o.testName)}</a>'
            '${_backendTag(o.backend)}'
            '<span class="test-suite">${escapeHtml(o.category)} · unmatched artifact</span></li>');
      }
      sb.writeln('</ul>');
    }

    sb.writeln('<div class="section-title">Categories</div>');
    sb.writeln('<div class="section-note">${escapeHtml(config.categoryNote)}</div>');
    sb.writeln('<table class="category-table" id="category-table">');
    sb.writeln('<thead><tr><th>Category</th><th>Tests</th><th>Passed</th><th>Failed</th><th>Skipped</th>'
        '<th>PNGs</th><th>Videos</th><th></th></tr></thead>');
    sb.writeln('<tbody>');
    for (final c in model.categories) {
      final tests = model.tests.where((t) => t.category == c).toList();
      final orphans = model.orphanedArtifacts.where((o) => o.category == c).toList();
      final passed = tests.where((t) => t.isPassed).length;
      final failed = _failuresIn(model, c);
      final skipped = tests.where((t) => t.isSkipped).length;
      final pngCount =
          tests.fold(0, (n, t) => n + t.screenshots.length) + orphans.fold(0, (n, o) => n + o.screenshots.length);
      final videoCount = tests.fold(0, (n, t) => n + t.videos.length) + orphans.fold(0, (n, o) => n + o.videos.length);
      final href = 'smoke_report/${categorySlug(c)}.html';
      sb.writeln('<tr data-category="${escapeHtml(c)}">'
          '<td><a href="$href">${escapeHtml(c)}</a></td>'
          '<td class="num">${tests.length}</td>'
          '<td class="num pass">$passed</td>'
          '<td class="num${failed > 0 ? ' fail' : ''}">$failed</td>'
          '<td class="num skip">$skipped</td>'
          '<td class="num">$pngCount</td>'
          '<td class="num">$videoCount</td>'
          '<td><a href="$href">open →</a></td></tr>');
    }
    sb.writeln('</tbody></table>');
    sb.writeln('</div>'); // container
    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  void _summaryCard(StringBuffer sb, String kind, int number, String label) =>
      sb.writeln('<div class="summary-card $kind"><div class="number">$number</div><div class="label">$label</div></div>');

  // ---------------------------------------------------------------------------
  // Category pages
  // ---------------------------------------------------------------------------

  /// One category's page: its tests' cards (media, coloured console output,
  /// badges, zoom modal), the unmatched artifacts of that category, a link
  /// back to the index and a navigation bar to the sibling categories.
  String renderCategory(SmokeReportModel model, String category, {String reportDir = 'build'}) {
    final pageDir = '${slashPath(reportDir).replaceAll(RegExp(r'/+$'), '')}/smoke_report';
    final tests = model.tests.where((t) => t.category == category).toList();
    final orphans = model.orphanedArtifacts.where((o) => o.category == category).toList();
    final sb = StringBuffer();
    _writeHead(sb, '$category · $_title');

    final smokeCount = tests.where((t) => t.isSmoke).length;
    final mediaCount = tests.where((t) => t.media.isNotEmpty || t.usedAssets.isNotEmpty).length;
    final passed = tests.where((t) => t.isPassed).length;
    final failed = tests.where((t) => t.isFailure).length;
    final skipped = tests.where((t) => t.isSkipped).length;
    final badOrphans = orphans.where((o) => o.badVideos.isNotEmpty).length;

    sb.writeln('<div class="header">');
    sb.writeln('<div class="header-title-group">');
    sb.writeln('<h1>${escapeHtml(category)}${_tagHtml()}</h1>');
    sb.writeln('<a class="back-link" href="../smoke_report.html">← ${_titleText(_title)} index</a>');
    sb.writeln('</div>');
    _writeHeaderMeta(sb, model);
    sb.writeln('</div>');

    sb.writeln('<div class="category-bar" id="category-nav">');
    for (final c in model.categories) {
      final failedHere = _failuresIn(model, c);
      final classes = ['category-chip', if (c == category) 'active', if (failedHere > 0) 'has-failures'];
      sb.writeln('<a class="${classes.join(' ')}" href="${categorySlug(c)}.html" data-category="${escapeHtml(c)}">'
          '${escapeHtml(c)}${failedHere > 0 ? ' <span class="count fail">$failedHere failed</span>' : ''}</a>');
    }
    sb.writeln('</div>');

    sb.writeln('<div class="summary-bar">');
    _summaryCard(sb, 'total', tests.length, '${tests.length} tests');
    _summaryCard(sb, 'smoke', smokeCount, '$smokeCount smoke');
    _summaryCard(sb, 'passed', passed, '$passed passed');
    _summaryCard(sb, 'failed', failed + badOrphans, '${failed + badOrphans} failed');
    _summaryCard(sb, 'skipped', skipped, '$skipped skipped');
    sb.writeln('</div>');

    sb.writeln('<div class="controls-bar">');
    sb.writeln('<div class="filter-tabs">');
    sb.writeln('<button class="filter-btn active" onclick="filterTests(\'all\', this)">All (${tests.length + orphans.length})</button>');
    sb.writeln('<button class="filter-btn" onclick="filterTests(\'smoke\', this)">⚡ Smoke Tests ($smokeCount)</button>');
    sb.writeln('<button class="filter-btn" onclick="filterTests(\'media\', this)">🎨 With Media ($mediaCount)</button>');
    sb.writeln('<button class="filter-btn" onclick="filterTests(\'passed\', this)">✅ Passed ($passed)</button>');
    if (failed + badOrphans > 0) {
      sb.writeln('<button class="filter-btn" onclick="filterTests(\'failed\', this)">❌ Failed (${failed + badOrphans})</button>');
    }
    if (skipped > 0) {
      sb.writeln('<button class="filter-btn" onclick="filterTests(\'skipped\', this)">⏭ Skipped ($skipped)</button>');
    }
    if (orphans.isNotEmpty) {
      sb.writeln('<button class="filter-btn" onclick="filterTests(\'orphan\', this)">📎 Orphans (${orphans.length})</button>');
    }
    sb.writeln('</div>');
    sb.writeln('<div class="action-tools">');
    sb.writeln('<input type="text" id="search-input" class="search-box" placeholder="Search tests..." onkeyup="searchTests(this.value)" />');
    sb.writeln('<button class="toggle-all-btn" onclick="toggleAllCards()">Expand / Collapse All</button>');
    sb.writeln('</div>');
    sb.writeln('</div>');

    sb.writeln('<div class="test-list" id="test-container">');
    if (tests.isNotEmpty) {
      sb.writeln('<div class="category-header" data-category="${escapeHtml(category)}">${escapeHtml(category)}'
          '<span class="category-meta">${tests.length} tests · $passed passed'
          '${failed > 0 ? ' · <span class="fail">$failed failed</span>' : ''}</span></div>');
    }
    for (final test in tests) {
      _writeTestCard(sb, test, category, pageDir);
    }
    sb.writeln('</div>'); // test-list

    if (orphans.isNotEmpty) {
      sb.writeln('<div class="section-title">Orphaned Artifacts (${orphans.length})</div>');
      sb.writeln('<div class="section-note">Screenshots and videos in the artifact directory that match no test of this '
          'report (a test that did not run here, a renamed test, or a file saved without a sidecar). Every one is '
          'shown.</div>');
      sb.writeln('<div class="test-list" id="orphan-container">');
      for (final orphan in orphans) {
        final bad = orphan.badVideos.isNotEmpty;
        sb.writeln('<div id="${orphanAnchor(orphan)}" class="test-card ${bad ? 'failed' : 'skipped'} open" '
            'data-status="${bad ? 'failed' : 'orphan'}" data-orphan="true" data-media="true" '
            'data-category="${escapeHtml(category)}">');
        sb.writeln('<div class="test-header" onclick="this.parentElement.classList.toggle(\'open\')">');
        sb.writeln('<div class="test-title-group">');
        sb.writeln('<span class="badge ${bad ? 'fail' : 'skip'}">ORPHAN</span>');
        _writeMediaBadges(sb, orphan);
        sb.writeln('<span class="test-name">${escapeHtml(orphan.testName)}</span>');
        sb.write(_backendTag(orphan.backend));
        sb.writeln('<span class="test-suite">${escapeHtml(orphan.fileName)}</span>');
        sb.writeln('</div>');
        sb.writeln('</div>');
        sb.writeln('<div class="test-body">');
        if (bad) sb.writeln('<div class="logs error">${escapeHtml(_rulesText)}</div>');
        _writeGallery(sb, orphan, orphan.testName, pageDir);
        _writeAssets(sb, orphan);
        sb.writeln('</div>');
        sb.writeln('</div>');
      }
      sb.writeln('</div>');
    }

    sb.writeln('</div>'); // container
    sb.writeln('<div id="modal" class="modal" onclick="closeModal()"><img id="modal-img" src="" alt="Zoom" /></div>');
    sb.writeln('<script>');
    sb.writeln(_script);
    sb.writeln('</script>');
    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  static final String _rulesText = 'Smoke videos must run at least ${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s '
      'of frames captured while the scenario runs, at ${SmokeVideo.minimumFps} fps or more, and be at least '
      '${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}.';

  void _writeTestCard(StringBuffer sb, TestResultItem test, String category, String pageDir) {
    final chipClass = test.isFailure ? 'failed' : (test.isSkipped ? 'skipped' : 'passed');
    final chipText = test.isFailure ? 'FAIL' : (test.isSkipped ? 'SKIP' : 'PASS');
    final isSmoke = test.isSmoke;
    final hasMedia = test.media.isNotEmpty || test.usedAssets.isNotEmpty;
    final classes = [
      'test-card',
      chipClass,
      if (isSmoke) 'is-smoke',
      if (hasMedia) 'has-media',
      if (test.isFailure || (isSmoke && hasMedia)) 'open',
    ];
    sb.writeln('<div id="${testAnchor(test)}" class="${classes.join(' ')}" data-status="$chipClass" '
        'data-smoke="$isSmoke" data-media="$hasMedia" data-category="${escapeHtml(category)}"'
        '${test.backend == null ? '' : ' data-backend="${escapeHtml(test.backend!)}"'}>');
    sb.writeln('<div class="test-header" onclick="this.parentElement.classList.toggle(\'open\')">');
    sb.writeln('<div class="test-title-group">');
    sb.writeln('<span class="badge ${test.isFailure ? 'fail' : (test.isSkipped ? 'skip' : 'pass')}">$chipText</span>');
    if (isSmoke) sb.writeln('<span class="badge smoke">⚡ SMOKE</span>');
    _writeMediaBadges(sb, test);
    sb.writeln('<span class="test-name">${escapeHtml(test.name)}</span>');
    sb.write(_backendTag(test.backend));
    if (test.suite.isNotEmpty) sb.writeln('<span class="test-suite">${escapeHtml(test.suite)}</span>');
    sb.writeln('</div>');
    sb.writeln('<div class="test-duration">${test.durationMs}ms</div>');
    sb.writeln('</div>'); // test-header

    sb.writeln('<div class="test-body">');
    if (test.error != null) {
      sb.write('<div class="logs error">${ansiToHtml(test.error!)}');
      if (test.stackTrace != null) sb.write('\n${ansiToHtml(test.stackTrace!)}');
      sb.writeln('</div>');
    }
    if (test.badVideos.isNotEmpty) sb.writeln('<div class="logs error">${escapeHtml(_rulesText)}</div>');
    if (test.prints.isNotEmpty) sb.writeln('<div class="logs">${ansiToHtml(test.prints.join('\n'))}</div>');
    if (test.media.isNotEmpty) {
      _writeGallery(sb, test, test.name, pageDir);
    } else if (isSmoke && test.isPassed) {
      sb.writeln('<div class="media-note muted">No visual artifact generated.</div>');
    }
    _writeAssets(sb, test);
    sb.writeln('</div>'); // test-body
    sb.writeln('</div>'); // test-card
  }

  String _backendTag(String? backend) => backend == null
      ? ''
      : '<span class="backend-tag ${escapeHtml(categorySlug(backend))}">${escapeHtml(backend)}</span>';

  void _writeMediaBadges(StringBuffer sb, MediaHolder holder) {
    final pngs = holder.screenshots.length;
    final videos = holder.videos;
    if (pngs > 0) sb.writeln('<span class="badge png">🖼️ ${pngs > 1 ? '$pngs ' : ''}PNG</span>');
    if (videos.isNotEmpty) sb.writeln('<span class="badge video">🎬 ${videos.length > 1 ? '${videos.length} ' : ''}VIDEO</span>');
    if (holder.shortVideos.isNotEmpty) {
      sb.writeln('<span class="badge short-video">VIDEO &lt; ${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s</span>');
    }
    if (holder.smallVideos.isNotEmpty) {
      sb.writeln('<span class="badge short-video">VIDEO &lt; ${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}</span>');
    }
    if (holder.slowVideos.isNotEmpty) {
      sb.writeln('<span class="badge short-video">VIDEO &lt; ${SmokeVideo.minimumFps} fps</span>');
    }
    final measured = videos.where((m) => !m.missing).map((m) => m.video).toList();
    if (measured.any((v) => v?.seconds == null)) sb.writeln('<span class="badge unknown">VIDEO LENGTH ?</span>');
    if (measured.any((v) => v?.width == null || v?.height == null)) sb.writeln('<span class="badge unknown">VIDEO SIZE ?</span>');
    if (measured.any((v) => v?.fps == null)) sb.writeln('<span class="badge unknown">VIDEO FPS ?</span>');
    if (holder.media.any((m) => m.missing)) sb.writeln('<span class="badge unknown">MISSING FILE</span>');
    if (holder.media.length > 1) sb.writeln('<span class="badge gallery">${holder.media.length} ARTIFACTS</span>');
    if (holder.usedAssets.isNotEmpty) sb.writeln('<span class="badge assets">📦 ${holder.usedAssets.length} ASSETS</span>');
  }

  /// Every PNG and video of [holder], videos first (they show the scenario
  /// running), each captioned with the name it was saved under, its file and,
  /// for a video, what was measured; linked relative to [pageDir].
  void _writeGallery(StringBuffer sb, MediaHolder holder, String alt, String pageDir) {
    if (holder.media.isEmpty) return;
    sb.writeln('<div class="media-grid">');
    for (final m in [...holder.videos, ...holder.screenshots]) {
      final file = escapeHtml(m.fileName);
      final src = escapeHtml(artifactHref(m.path, pageDir));
      final label = m.label != null && m.label != alt ? ' · ${escapeHtml(m.label!)}' : '';
      sb.writeln('<div class="media-box${m.breaksVideoRule ? ' short' : ''}" data-file="$file">');
      if (m.isVideo) {
        final encoder = m.video?.encoder;
        final measured = escapeHtml('${m.video?.describe ?? 'unmeasured'}${encoder == null ? '' : ' · encoded by $encoder'}');
        sb.writeln('<div class="media-header vid-title">🎬 Smoke Video$label · $measured');
        if (m.isShortVideo) {
          sb.writeln('<span class="badge short-video">VIDEO &lt; ${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s</span>');
        }
        if (m.isSmallVideo) {
          sb.writeln('<span class="badge short-video">VIDEO &lt; ${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}</span>');
        }
        if (m.isSlowVideo) sb.writeln('<span class="badge short-video">VIDEO &lt; ${SmokeVideo.minimumFps} fps</span>');
        sb.writeln('<span class="media-file">${escapeHtml(m.relativePath)}</span></div>');
        if (m.missing) {
          sb.writeln('<div class="media-note">Missing file: ${escapeHtml(m.path)}</div>');
        } else {
          sb.writeln('<video class="screenshot-video" controls autoplay loop muted playsinline preload="metadata" src="$src"></video>');
        }
      } else {
        sb.writeln('<div class="media-header png-title">🖼️ Smoke Screenshot$label <span class="media-file">${escapeHtml(m.relativePath)}</span></div>');
        if (m.missing) {
          sb.writeln('<div class="media-note">Missing file: ${escapeHtml(m.path)}</div>');
        } else {
          sb.writeln('<img class="screenshot-img" src="$src" onclick="openModal(this.src)" alt="${escapeHtml(alt)}" />');
        }
      }
      sb.writeln('</div>');
    }
    sb.writeln('</div>');
  }

  void _writeAssets(StringBuffer sb, MediaHolder holder) {
    if (holder.usedAssets.isEmpty) return;
    sb.writeln('<div class="used-assets-container">');
    sb.writeln('<span class="assets-label">📦 Real 3D Test Assets:</span>');
    for (final asset in holder.usedAssets) {
      sb.writeln('<span class="asset-chip" title="${escapeHtml(asset)}">${escapeHtml(_assetLabel(asset))}</span>');
    }
    sb.writeln('</div>');
  }

  /// An asset path from `test-assets/` on (or the whole path when it is not
  /// under one).
  static String _assetLabel(String asset) {
    final p = asset.replaceAll(r'\', '/');
    final i = p.lastIndexOf('/test-assets/');
    return i < 0 ? p : p.substring(i + '/test-assets/'.length);
  }

  // ---------------------------------------------------------------------------
  // Shared page parts
  // ---------------------------------------------------------------------------

  /// A title as HTML text: escaped, except an `&` before a space, which
  /// HTML reads as a plain `&` (so `Smoke & Test Report` reads the same in
  /// the page source).
  static String _titleText(String title) => escapeHtml(title).replaceAll('&amp; ', '& ');

  String _tagHtml() => config.tag == null ? '' : ' <span class="engine-tag">${escapeHtml(config.tag!)}</span>';

  void _writeHeaderMeta(StringBuffer sb, SmokeReportModel model) {
    final backends = {for (final t in model.tests) ?t.backend}.toList()..sort();
    sb.writeln('<div class="header-meta">');
    sb.writeln('<div>Generated: <strong>${model.timestamp.toIso8601String()}</strong></div>');
    sb.writeln('<div>Run time: <strong>${(model.wallDurationMs / 1000).toStringAsFixed(1)} s</strong></div>');
    sb.writeln('<div>Dart Version: <strong>${escapeHtml(model.dartVersion)}</strong></div>');
    sb.writeln('<div>Target GPU: <strong>${escapeHtml(config.gpuLabel)}</strong></div>');
    if (backends.isNotEmpty) sb.writeln('<div>Backends: <strong>${escapeHtml(backends.join(', '))}</strong></div>');
    sb.writeln('</div>');
  }

  static void _writeHead(StringBuffer sb, String title) {
    sb.writeln('<!DOCTYPE html>');
    sb.writeln('<html lang="en">');
    sb.writeln('<head>');
    sb.writeln('<meta charset="UTF-8">');
    sb.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    sb.writeln('<title>${_titleText(title)}</title>');
    sb.writeln('<style>');
    sb.writeln(_css);
    sb.writeln('</style>');
    sb.writeln('</head>');
    sb.writeln('<body>');
    sb.writeln('<div class="container">');
  }

  static const String _script = '''
      function openModal(src) {
        document.getElementById('modal-img').src = src;
        document.getElementById('modal').classList.add('active');
      }
      function closeModal() {
        document.getElementById('modal').classList.remove('active');
      }
      let activeStatus = 'all';
      function statusMatches(card) {
        switch (activeStatus) {
          case 'smoke': return card.getAttribute('data-smoke') === 'true';
          case 'media': return card.getAttribute('data-media') === 'true';
          case 'passed': return card.getAttribute('data-status') === 'passed';
          case 'failed': return card.getAttribute('data-status') === 'failed';
          case 'skipped': return card.getAttribute('data-status') === 'skipped';
          case 'orphan': return card.getAttribute('data-orphan') === 'true';
          default: return true;
        }
      }
      function applyFilters() {
        document.querySelectorAll('.test-list').forEach(list => {
          let visible = false;
          list.querySelectorAll('.test-card').forEach(card => {
            const show = statusMatches(card);
            card.style.display = show ? '' : 'none';
            if (show) visible = true;
          });
          list.querySelectorAll('.category-header').forEach(h => {
            h.style.display = visible ? '' : 'none';
          });
        });
      }
      function filterTests(type, btn) {
        document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeStatus = type;
        applyFilters();
      }
      function searchTests(query) {
        const q = query.toLowerCase();
        document.querySelectorAll('#test-container .test-card, #orphan-container .test-card').forEach(card => {
          const text = card.textContent.toLowerCase();
          card.style.display = text.includes(q) && statusMatches(card) ? '' : 'none';
        });
      }
      let allExpanded = false;
      function toggleAllCards() {
        allExpanded = !allExpanded;
        document.querySelectorAll('#test-container .test-card, #orphan-container .test-card').forEach(card => {
          if (allExpanded) card.classList.add('open');
          else card.classList.remove('open');
        });
      }
''';

  static const String _css = '''
      :root {
        --bg-main: #0b0f17;
        --bg-card: #151a24;
        --bg-card-hover: #1c2331;
        --bg-elevated: #222b3d;
        --border: #283347;
        --border-subtle: #1e2638;
        --text-main: #f0f6fc;
        --text-muted: #8b9bb4;
        --pass: #10b981;
        --pass-bg: rgba(16, 185, 129, 0.15);
        --fail: #f43f5e;
        --fail-bg: rgba(244, 63, 94, 0.18);
        --skip: #f59e0b;
        --skip-bg: rgba(245, 158, 11, 0.15);
        --smoke: #f59e0b;
        --smoke-bg: rgba(245, 158, 11, 0.18);
        --media-png: #06b6d4;
        --media-png-bg: rgba(6, 182, 212, 0.15);
        --media-vid: #a855f7;
        --media-vid-bg: rgba(168, 85, 247, 0.18);
        --media-asset: #3b82f6;
        --media-asset-bg: rgba(59, 130, 246, 0.15);
        --accent: #38bdf8;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
      body { background-color: var(--bg-main); color: var(--text-main); padding: 24px; line-height: 1.5; }
      a { color: var(--accent); }
      .container { max-width: 1300px; margin: 0 auto; }

      .header { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; border-bottom: 1px solid var(--border); padding-bottom: 20px; margin-bottom: 24px; }
      .header-title-group h1 { font-size: 26px; font-weight: 700; letter-spacing: -0.5px; display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
      .header-title-group .engine-tag { font-size: 11px; font-weight: 700; padding: 3px 8px; border-radius: 6px; background: rgba(56, 189, 248, 0.2); color: var(--accent); border: 1px solid rgba(56, 189, 248, 0.4); text-transform: uppercase; }
      .header-title-group .back-link { font-size: 13px; color: var(--text-muted); display: block; margin-top: 4px; }
      .header-meta { font-size: 13px; color: var(--text-muted); text-align: right; line-height: 1.6; }
      .header-meta strong { color: var(--text-main); }

      .summary-bar { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 28px; }
      .summary-card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 12px; padding: 18px 20px; text-align: left; box-shadow: 0 4px 12px rgba(0,0,0,0.25); transition: transform 0.2s, border-color 0.2s; }
      .summary-card:hover { transform: translateY(-2px); border-color: var(--accent); }
      .summary-card .number { font-size: 32px; font-weight: 800; margin-bottom: 2px; line-height: 1; }
      .summary-card .label { font-size: 12px; text-transform: uppercase; color: var(--text-muted); font-weight: 700; letter-spacing: 0.6px; }
      .summary-card.passed .number { color: var(--pass); }
      .summary-card.failed .number { color: var(--fail); }
      .summary-card.skipped .number { color: var(--skip); }
      .summary-card.total .number { color: var(--accent); }
      .summary-card.smoke .number { color: var(--smoke); }
      .summary-card.media .number { color: var(--media-png); }

      .controls-bar { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 20px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 10px; padding: 12px 16px; }
      .filter-tabs { display: flex; flex-wrap: wrap; gap: 8px; }
      .filter-btn { background: var(--bg-elevated); border: 1px solid var(--border); color: var(--text-muted); font-size: 13px; font-weight: 600; padding: 6px 14px; border-radius: 8px; cursor: pointer; transition: all 0.15s; }
      .filter-btn:hover { background: var(--bg-card-hover); color: var(--text-main); border-color: var(--accent); }
      .filter-btn.active { background: rgba(56, 189, 248, 0.2); color: var(--accent); border-color: var(--accent); }

      .action-tools { display: flex; align-items: center; gap: 10px; }
      .search-box { background: var(--bg-main); border: 1px solid var(--border); border-radius: 8px; padding: 6px 12px; color: var(--text-main); font-size: 13px; width: 220px; outline: none; transition: border-color 0.2s; }
      .search-box:focus { border-color: var(--accent); }
      .toggle-all-btn { background: var(--bg-elevated); border: 1px solid var(--border); color: var(--text-main); font-size: 12px; font-weight: 600; padding: 6px 12px; border-radius: 8px; cursor: pointer; }
      .toggle-all-btn:hover { border-color: var(--accent); }

      .test-list { display: flex; flex-direction: column; gap: 14px; }

      .test-card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; box-shadow: 0 4px 16px rgba(0,0,0,0.2); transition: border-color 0.2s, box-shadow 0.2s; }
      .test-card:hover { border-color: rgba(56, 189, 248, 0.4); }
      .test-card:target { border-color: var(--accent); box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.4); }
      .test-card.is-smoke { border-left: 4px solid var(--smoke); }
      .test-card.failed { border-left: 4px solid var(--fail); }
      .test-card.passed:not(.is-smoke) { border-left: 4px solid var(--pass); }
      .test-card.skipped { border-left: 4px solid var(--skip); }

      .test-header { display: flex; align-items: center; justify-content: space-between; padding: 14px 18px; cursor: pointer; user-select: none; background: var(--bg-card); transition: background 0.15s; }
      .test-header:hover { background: var(--bg-card-hover); }
      .test-title-group { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; flex: 1; min-width: 0; }

      .badge { font-size: 11px; font-weight: 700; padding: 3px 9px; border-radius: 6px; text-transform: uppercase; letter-spacing: 0.5px; display: inline-flex; align-items: center; gap: 4px; white-space: nowrap; }
      .badge.pass { background: var(--pass-bg); color: var(--pass); border: 1px solid rgba(16, 185, 129, 0.4); }
      .badge.fail { background: var(--fail-bg); color: var(--fail); border: 1px solid rgba(244, 63, 94, 0.4); }
      .badge.skip { background: var(--skip-bg); color: var(--skip); border: 1px solid rgba(245, 158, 11, 0.4); }
      .badge.smoke { background: var(--smoke-bg); color: var(--smoke); border: 1px solid rgba(245, 158, 11, 0.5); font-weight: 800; }
      .badge.png { background: var(--media-png-bg); color: var(--media-png); border: 1px solid rgba(6, 182, 212, 0.4); }
      .badge.video { background: var(--media-vid-bg); color: var(--media-vid); border: 1px solid rgba(168, 85, 247, 0.4); }
      .badge.assets { background: var(--media-asset-bg); color: var(--media-asset); border: 1px solid rgba(59, 130, 246, 0.4); }
      .badge.gallery { background: rgba(56, 189, 248, 0.15); color: var(--accent); border: 1px solid rgba(56, 189, 248, 0.4); }
      .badge.unknown { background: var(--skip-bg); color: var(--skip); border: 1px solid rgba(245, 158, 11, 0.4); }
      .badge.short-video { background: var(--fail); color: #fff; border: 1px solid var(--fail); font-weight: 800; }

      .backend-tag { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 11px; padding: 3px 6px; border-radius: 4px; background: var(--bg-elevated); border: 1px solid var(--border); color: var(--text-muted); }
      .backend-tag.vulkan { color: #d2a8ff; border-color: rgba(210, 168, 255, 0.3); }
      .backend-tag.opengl { color: #79c0ff; border-color: rgba(121, 192, 255, 0.3); }

      .test-name { font-size: 14px; font-weight: 700; color: var(--text-main); word-break: break-word; }
      .test-suite { font-size: 12px; color: var(--text-muted); font-family: ui-monospace, SFMono-Regular, monospace; overflow-wrap: anywhere; }
      .test-duration { font-size: 12px; color: var(--text-muted); font-variant-numeric: tabular-nums; font-weight: 600; white-space: nowrap; margin-left: 12px; }

      .test-body { padding: 18px; border-top: 1px solid var(--border); background: var(--bg-main); display: none; }
      .test-card.open .test-body, .test-card:target .test-body { display: block; }

      .media-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 20px; margin-top: 14px; margin-bottom: 14px; }
      .media-box { background: var(--bg-card); border: 1px solid var(--border); border-radius: 10px; padding: 14px; min-width: 0; }
      .media-box.short { border-color: var(--fail); }
      .media-header { font-size: 13px; font-weight: 700; margin-bottom: 10px; display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
      .media-header.png-title { color: var(--media-png); }
      .media-header.vid-title { color: var(--media-vid); }
      .media-file { font-size: 11px; font-weight: 500; color: var(--text-muted); font-family: ui-monospace, SFMono-Regular, monospace; word-break: break-all; }
      .media-note { color: var(--skip); font-size: 12px; overflow-wrap: anywhere; }
      .media-note.muted { color: var(--text-muted); font-style: italic; }

      .screenshot-img { width: 100%; max-height: 280px; object-fit: contain; background: #000; border-radius: 8px; border: 1px solid var(--border); cursor: pointer; transition: transform 0.2s; display: block; }
      .screenshot-img:hover { transform: scale(1.01); }
      .screenshot-video { width: 100%; max-height: 280px; background: #000; border-radius: 8px; border: 1px solid var(--border); display: block; }

      .logs { background: #000; padding: 14px; border-radius: 8px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 12px; line-height: 1.5; color: #adbac7; overflow-x: auto; white-space: pre-wrap; margin-bottom: 12px; border: 1px solid var(--border); }
      .logs.error { border-left: 4px solid var(--fail); color: #f85149; }
      .logs .ansi-b { font-weight: 700; } .logs .ansi-d { opacity: 0.65; } .logs .ansi-i { font-style: italic; } .logs .ansi-u { text-decoration: underline; }
      .logs .ansi-30 { color: #545d68; } .logs .ansi-31 { color: #f47067; } .logs .ansi-32 { color: #57ab5a; } .logs .ansi-33 { color: #c69026; }
      .logs .ansi-34 { color: #539bf5; } .logs .ansi-35 { color: #b083f0; } .logs .ansi-36 { color: #39c5cf; } .logs .ansi-37 { color: #adbac7; }
      .logs .ansi-90 { color: #768390; } .logs .ansi-91 { color: #ff938a; } .logs .ansi-92 { color: #6bc46d; } .logs .ansi-93 { color: #daaa3f; }
      .logs .ansi-94 { color: #6cb6ff; } .logs .ansi-95 { color: #dcbdfb; } .logs .ansi-96 { color: #56d4dd; } .logs .ansi-97 { color: #cdd9e5; }
      .logs .ansi-bg-40 { background: #545d68; } .logs .ansi-bg-41 { background: #922323; } .logs .ansi-bg-42 { background: #1b4721; } .logs .ansi-bg-43 { background: #6c4b00; }
      .logs .ansi-bg-44 { background: #143d79; } .logs .ansi-bg-45 { background: #472c82; } .logs .ansi-bg-46 { background: #0d4a52; } .logs .ansi-bg-47 { background: #adbac7; color: #22272e; }

      .used-assets-container { margin-top: 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; padding: 10px 14px; }
      .assets-label { font-size: 12px; color: var(--text-muted); font-weight: 700; display: flex; align-items: center; gap: 4px; }
      .asset-chip { font-size: 11px; padding: 3px 8px; border-radius: 6px; background: rgba(59, 130, 246, 0.15); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.3); font-family: ui-monospace, SFMono-Regular, monospace; }

      .category-bar { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 20px; }
      .category-chip { background: var(--bg-elevated); color: var(--text-muted); border: 1px solid var(--border); border-radius: 999px; padding: 6px 12px; font-size: 12px; font-weight: 600; cursor: pointer; text-decoration: none; }
      .category-chip:hover { color: var(--text-main); border-color: var(--accent); }
      .category-chip.active { border-color: var(--accent); color: var(--accent); background: rgba(56, 189, 248, 0.2); }
      .category-chip.has-failures { border-color: rgba(244, 63, 94, 0.6); }
      .category-chip .count { color: var(--text-muted); margin-left: 4px; font-variant-numeric: tabular-nums; }
      .category-chip .count.fail, .category-meta .fail, .category-table .fail { color: var(--fail); }
      .category-header { display: flex; align-items: baseline; gap: 12px; margin: 18px 0 2px; font-size: 16px; font-weight: 700; color: var(--text-main); border-bottom: 1px solid var(--border); padding-bottom: 6px; }
      .category-meta { font-size: 12px; font-weight: 500; color: var(--text-muted); }
      .section-title { margin-top: 32px; margin-bottom: 6px; font-size: 18px; font-weight: 700; }
      .section-note { margin-bottom: 14px; font-size: 13px; color: var(--text-muted); }

      .category-table { width: 100%; border-collapse: collapse; background: var(--bg-card); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; font-size: 13px; }
      .category-table th, .category-table td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border-subtle); font-variant-numeric: tabular-nums; }
      .category-table th { font-size: 11px; text-transform: uppercase; letter-spacing: 0.6px; color: var(--text-muted); background: var(--bg-elevated); }
      .category-table tr:hover td { background: var(--bg-card-hover); }
      .category-table td.num { text-align: right; }
      .category-table .pass { color: var(--pass); } .category-table .skip { color: var(--skip); }
      .failing-list { list-style: none; display: flex; flex-direction: column; gap: 6px; margin-bottom: 8px; }
      .failing-list li { background: var(--fail-bg); border: 1px solid rgba(244, 63, 94, 0.4); border-radius: 8px; padding: 8px 12px; font-size: 13px; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }

      .modal { display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.85); justify-content: center; align-items: center; }
      .modal.active { display: flex; }
      .modal img { max-width: 90%; max-height: 90%; border-radius: 8px; box-shadow: 0 0 24px rgba(0,0,0,0.8); }
      @media (max-width: 600px) {
        body { padding: 16px; }
        .header { flex-direction: column; }
        .header-meta { text-align: left; }
      }
''';
}
