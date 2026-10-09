part of '../dashboard_server.dart';

/// Dashboard page: body markup and the client script (SSE, rendering, filters).
const String _dashboardBody = r'''</head>
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
