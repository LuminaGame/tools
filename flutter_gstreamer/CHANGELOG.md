# Changelog

## 0.1.0

- First version: dynamic loading of GStreamer 1.x (Windows / Linux / macOS lookup; tested on Windows with GStreamer 1.28.6).
- ffigen-generated bindings for the core, app and pbutils API used (`tool/ffigen.dart`).
- `GStreamer`, `GStreamerLibraries`, `GstPipeline`, `GstElement`, `GstAppSrc`.
- `VideoEncoder`: PNG or RGBA frames → VP8 / WebM in-process, exact frame timestamps, Lumina smoke-video quality settings (`Vp8Quality.smoke`).
- `MediaProbe`: duration, frame size, frame rate, container and codec via `GstDiscoverer`.
- `GStreamerNotFoundException` / `GStreamerException`.
