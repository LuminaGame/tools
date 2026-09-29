[Türkçe](../tr/lumina_mouse_capture.md)

# lumina_mouse_capture

`lumina_mouse_capture` is a Flutter plugin that captures the pointer for Lumina games and Play-In-Editor: while a game owns the mouse, the pointer is hidden and held in place and the mouse keeps reporting relative motion.

## Place in Lumina

`lumina` and `lumina_ui` use this plugin when a game running in Play-In-Editor, or a shipped game, takes the mouse: the pointer is hidden and held in place, and the mouse keeps reporting how far it moved. Every test, smoke test and harness run uses a recording backend instead, so no run can lock, grab or warp the pointer of the person working at the machine.

```yaml
dependencies:
  lumina_mouse_capture:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: lumina_mouse_capture
```

## Platforms

- **Wayland**: `zwp_pointer_constraints_v1.lock_pointer` (one-shot) and `zwp_relative_pointer_v1.relative_motion`, bound on GDK's own Wayland connection.
- **X11**: a seat grab on the toplevel window, a warp to the centre, and a 4 ms poll that reads the offset and warps back.
- **Other platforms and the web**: no capture; the recording backend answers instead.

The Linux implementation (`linux/`, GTK) needs GTK 3 and, for Wayland pointer lock, `wayland-client`, `wayland-scanner` and `wayland-protocols` (pointer-constraints and relative-pointer). Without them the plugin still builds and reports no Wayland support.

## Usage

Everything goes through one seam, `LuminaMouseCapture.backend`:

```dart
import 'package:lumina_mouse_capture/lumina_mouse_capture.dart';

final capture = LuminaMouseCapture.backend;

final support = await capture.support();
// support.kind: wayland, x11, unsupported, disabled or recording
// support.pointerLock / support.relativeMotion / support.detail

final sub = capture.events.listen((event) {
  switch (event) {
    case MouseCaptureMotion(:final dx, :final dy):
      // relative movement while captured
    case MouseCaptureLocked():
      // the compositor confirmed the lock
    case MouseCaptureLost():
      // focus loss or the compositor ended the capture
  }
});

await capture.capture(centre: const Offset(640, 360)); // logical view coordinates
// ...
await capture.release();
await sub.cancel();
```

When `support.relativeMotion` is false, read deltas from your own pointer events. When `support.pointerLock` is true, clicks land wherever the pointer is held, so the host should shield its UI while captured.

## API reference

File paths are relative to the `lumina_mouse_capture/` package directory.

### `lib/lumina_mouse_capture.dart`

#### `abstract final class LuminaMouseCapture`

The process-wide mouse-capture seam.

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `environmentVariable` | `static const String environmentVariable = 'LUMINA_MOUSE_CAPTURE'` | Set to `off` (or `record`) to keep every capture away from the pointer. The test harnesses export it; the native plugin checks it too. |
| `backend` | `static MouseCaptureBackend get backend` / `set backend(...)` | The backend every caller uses. The first read creates the default backend (and, for the platform backend, releases any capture a hot restart left behind); assigning one replaces it. |
| `defaultBackendReason` | `static String? get defaultBackendReason` | Why the default backend was chosen, or null when one was assigned. |
| `chooseDefault` | `static MouseCaptureBackendChoice chooseDefault({Map<String, String>? environment, bool? isTestBinding, TargetPlatform? platform, bool isWeb})` | The default rule: `LUMINA_MOUSE_CAPTURE=off` or `record` gives the recording backend; so does a Flutter test binding (`flutter test`, `integration_test`), the web, or any platform other than Linux; otherwise the platform channel. |

#### `class MouseCaptureBackendChoice`

Which backend `chooseDefault` picked, and why: `reason` (`test binding`, `LUMINA_MOUSE_CAPTURE=off`, `web`, `not Linux` or `platform channel`), `usesPlatform`, and `createBackend()`, which returns a fresh backend of the chosen kind.

### `lib/src/mouse_capture_backend.dart`

#### `abstract class MouseCaptureBackend`

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `support` | `Future<MouseCaptureSupport> support()` | What this backend can do on this machine. |
| `capture` | `Future<bool> capture({Offset? centre})` | Captures the pointer. `centre` is in the Flutter view's logical coordinates: on X11 the pointer is warped there, on Wayland it is where the pointer reappears when released. Returns whether a capture was requested. |
| `release` | `Future<void> release()` | Releases the pointer; a no-op when not captured. |
| `events` | `Stream<MouseCaptureEvent> get events` | Motion, lock confirmations and losses. |

#### `enum MouseCaptureBackendKind`

`wayland` (pointer constraints and relative pointer on GDK's connection), `x11` (seat grab with warp-to-centre), `unsupported` (no way to capture, or the plugin is not built into this app), `disabled` (the native side refused because `LUMINA_MOUSE_CAPTURE` is `off` or `record`), `recording` (requests are recorded, the pointer is never touched).

#### `class MouseCaptureSupport`

`kind`; `pointerLock`, whether a capture really holds the pointer (it cannot leave the window, and clicks land where it is held); `relativeMotion`, whether `MouseCaptureMotion` events carry the mouse's movement; `detail`, why, in words. `MouseCaptureSupport.none` is the unsupported value.

#### `sealed class MouseCaptureEvent`

- `MouseCaptureMotion(dx, dy)`: the mouse moved by (`dx`, `dy`) logical pixels while captured, however far the held pointer is from any edge.
- `MouseCaptureLocked()`: the platform confirmed the lock (Wayland's `locked` event).
- `MouseCaptureLost()`: the capture ended without being asked: the window lost focus, the compositor broke the lock, or the window went away.

### `lib/src/method_channel_backend.dart`

#### `class MethodChannelMouseCaptureBackend`

The native Linux backend (`linux/lumina_mouse_capture_plugin.cc`). The `lumina_mouse_capture` method channel answers `support` with `{kind, pointerLock, relativeMotion, detail}`, `capture` with a bool (optional `{x, y}`), and `release`; the `lumina_mouse_capture/events` event channel sends `{type: motion, dx, dy}`, `{type: locked}` and `{type: lost}`. A missing plugin (an app that was not rebuilt, a platform without it) is reported as `unsupported`, never thrown.

### `lib/src/recording_backend.dart`

#### `class RecordingMouseCaptureBackend`

A backend that never touches the pointer: it records what was asked, and `emitMotion` / `emitLost` drive the same event path the native side does.

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| constructor | `RecordingMouseCaptureBackend({bool simulateLock = false})` | With `simulateLock`, `support` reports a lock with relative motion and each capture is confirmed with `MouseCaptureLocked`; without it, it behaves like the hidden-cursor fallback of a platform without a lock. |
| `requests` | `final List<String> requests` | Every request, in order: `capture(640.0,360.0)`, `capture()`, `release`. |
| `lastCentre` | `Offset? lastCentre` | The centre of the last capture request. |
| `isCaptured` | `bool get isCaptured` | Whether a capture is in force (requested and not released or lost). |
| `emitMotion` | `void emitMotion(double dx, double dy)` | Reports a relative movement, as the compositor would. |
| `emitLost` | `void emitLost()` | Reports that the capture was taken away (focus loss, Alt+Tab). |

## Development

```bash
flutter test test/mouse_capture_test.dart
```

`example/` captures the pointer through the real plugin (C captures at the window centre, F4 releases, a click captures again) and prints every capture event as a JSON line on stdout. `tool/nested_compositor/` checks the native side without touching the desktop: `nested_session.py` starts an isolated, headless GNOME Shell (private D-Bus, software rendering, input through Mutter's RemoteDesktop API), and `build_probe.sh` builds `capture_probe`, the capture core in a plain GTK window. The engine's input smoke test drives the example app inside the same nested session.

---

[Previous: flutter_gstreamer](flutter_gstreamer.md) | [Up: Lumina tools documentation](../README.md) | [Next: lumina_smoke](lumina_smoke.md)
