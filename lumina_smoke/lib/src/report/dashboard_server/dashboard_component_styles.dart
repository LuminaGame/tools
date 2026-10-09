part of '../dashboard_server.dart';

/// Dashboard page: the rest of the stylesheet (filters, cards, terminal, lightbox).
const String _dashboardComponentStyles = r'''    .filter-pills {
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
''';
