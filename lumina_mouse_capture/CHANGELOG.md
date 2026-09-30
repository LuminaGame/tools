## Unreleased

* Windows: raw mouse input (`WM_INPUT`) with the cursor hidden and clipped to
  the capture centre; `MouseCaptureBackendKind.windows`; `MouseCaptureLost.reason`
  (`focus`, `minimized`, `window`). The default backend is the platform channel
  on Windows too.

## 0.0.1

* Wayland pointer lock + relative motion, X11 grab + warp, recording backend
  for tests.
