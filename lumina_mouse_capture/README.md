[Türkçe](README.tr.md)

# lumina_mouse_capture

Pointer capture for Lumina games and Play-In-Editor: while a game owns the mouse, the pointer is hidden and held in place, and the mouse keeps reporting how far it moved.

- **Wayland**: `zwp_pointer_constraints_v1.lock_pointer` (one-shot) and `zwp_relative_pointer_v1.relative_motion`, bound on GDK's own Wayland connection.
- **X11**: a seat grab on the toplevel window, a warp to the centre, and a 4 ms poll that reads the offset and warps back.
- **Other platforms and the web**: no capture; a recording backend answers instead.

It is a Flutter plugin with a Linux implementation (`linux/`, GTK).

## Requirements

- Flutter SDK with Dart `^3.12.0`.
- Linux: GTK 3 (as for any Flutter Linux app). For Wayland pointer lock also `wayland-client`, `wayland-scanner` and `wayland-protocols` (pointer-constraints and relative-pointer); without them the plugin still builds and reports no Wayland support.

```yaml
dependencies:
  lumina_mouse_capture:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: lumina_mouse_capture
```

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

### The recording backend

`LuminaMouseCapture.chooseDefault` picks `RecordingMouseCaptureBackend`, which records requests and never touches the pointer, when:

- `LUMINA_MOUSE_CAPTURE` is `off` or `record` (the native side also refuses to lock under this variable);
- a Flutter test binding is running (`flutter test`, `integration_test`);
- the app runs on the web or not on Linux.

Otherwise it uses `MethodChannelMouseCaptureBackend`. Tests can assign their own backend (`LuminaMouseCapture.backend = RecordingMouseCaptureBackend()`) and feed it events with `emitMotion(dx, dy)` / `emitLost()`.

## Development

```bash
flutter test test/mouse_capture_test.dart
```

`example/` captures the pointer through the real plugin (C captures at the window centre, F4 releases, a click captures again) and prints every capture event as a JSON line on stdout. `tool/nested_compositor/` checks the native side for real without touching the desktop: `nested_session.py` starts an isolated, headless GNOME Shell (private D-Bus, software rendering, input through Mutter's RemoteDesktop API) and `build_probe.sh` builds `capture_probe`, the capture core in a plain GTK window. The engine's input smoke test drives the example app inside the same nested session.

## License

GPL-3.0 (see [LICENSE](LICENSE)).
