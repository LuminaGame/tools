part of '../dashboard_server.dart';

/// Dashboard page: document head and the first half of the stylesheet.
const String _dashboardHeadStyles = r'''<!DOCTYPE html>
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
''';
