[Türkçe](README.tr.md)

# flutter_gstreamer

Dart FFI bindings to [GStreamer](https://gstreamer.freedesktop.org/) 1.x, loaded **dynamically at run time** (no native build step, no link-time dependency). Lumina uses it to encode smoke-test videos from PNG/RGBA frames in-process instead of spawning `ffmpeg` / `gst-launch-1.0`.

Pure Dart: works in `dart test`, `flutter test` and apps (desktop).

## Requirements

A GStreamer 1.x install with the base and good plugin sets (`vp8enc`, `webmmux`, `pngdec`, ...); see [Where GStreamer is looked for](#where-gstreamer-is-looked-for). Nothing else: no C toolchain, no Filament.

```yaml
dependencies:
  flutter_gstreamer:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_gstreamer
```

`dart run example/encode_webm.dart [out.webm]` encodes 10 s of generated PNG frames into a VP8 WebM and probes it.

## API

```dart
import 'package:flutter_gstreamer/flutter_gstreamer.dart';

final gst = GStreamer.init();               // throws GStreamerNotFoundException if absent
print(gst.versionString);                   // GStreamer 1.28.6
GStreamer.isAvailable();                    // non-throwing check
gst.hasElement('vp8enc');

// PNG frames → VP8 / WebM, 30 fps (300 frames = exactly 10.0 s)
VideoEncoder.encodePngFrames(pngs, out: File('smoke.webm'));

// Streaming, raw RGBA
final enc = VideoEncoder.rgba(width: 1024, height: 768, out: file, frameRate: const FrameRate(30));
enc.addFrame(rgba);                         // repeat
enc.finish();

// Probe (GstDiscoverer)
final info = MediaProbe.probe(file);
info.durationSeconds; info.width; info.height; info.fps;
info.containerType;                         // video/webm
info.videoCodec;                            // video/x-vp8

// Any pipeline
final p = GstPipeline.parse('videotestsrc num-buffers=30 ! vp8enc ! webmmux ! filesink name=out');
p.element('out')!.set('location', path);    // property from its string form, no quoting
p.play();
p.waitForEos();                             // GStreamerException on a bus ERROR / timeout
p.dispose();
```

| Type | Purpose |
|---|---|
| `GStreamer` | load + `gst_init_check`, version, `hasElement` / `requireElements`, raw `bindings` |
| `GStreamerLibraries` | finds and opens the shared libraries; `root` = one specific install |
| `GstPipeline`, `GstElement`, `GstAppSrc` | `gst_parse_launch`, properties, states, bus messages, EOS, appsrc buffers with PTS/duration |
| `VideoEncoder`, `FrameRate`, `Vp8Quality` | `appsrc ! (pngdec !) videoconvert ! vp8enc ! webmmux ! filesink` |
| `MediaProbe`, `MediaInfo` | duration, size, frame rate, container / codec caps |
| `GStreamerNotFoundException` | GStreamer cannot be found or loaded (catch it to fall back or skip) |
| `GStreamerException` | parse errors, missing elements, bus errors, timeouts, unreadable files |

`Vp8Quality.smoke` (the default) is the Lumina smoke-video setting: `end-usage=cq cq-level=6 min-quantizer=0 max-quantizer=16 target-bitrate=20000000 deadline=1000000 cpu-used=2 keyframe-max-dist=150`, the counterpart of ffmpeg `libvpx -crf 6 -b:v 20M -qmin 0 -qmax 16 -quality good -cpu-used 2 -g 150`.

The raw ffigen bindings (`GStreamerBindings` and the C structs/constants) are in `package:flutter_gstreamer/bindings.dart`; import it with a prefix.

## Where GStreamer is looked for

1. An explicit `root` (`GStreamer.init(root: ...)`) — only that one.
2. `FLUTTER_GSTREAMER_ROOT`, `GSTREAMER_1_0_ROOT_MSVC_X86_64`, `GSTREAMER_1_0_ROOT_MINGW_X86_64`, `GSTREAMER_1_0_ROOT_X86_64`.
3. Default installs — Windows: `%LOCALAPPDATA%\Programs\gstreamer\1.0\msvc_x86_64` (per-user), `%ProgramFiles%\gstreamer\1.0\msvc_x86_64`, `C:\gstreamer\1.0\msvc_x86_64` (+ `mingw_x86_64`); macOS: `/Library/Frameworks/GStreamer.framework/Versions/1.0`, `/opt/homebrew`, `/usr/local`.
4. Windows: `PATH` folders holding `gstreamer-1.0-0.dll`; Linux/macOS: the system loader (`libgstreamer-1.0.so.0`, ...).

Libraries opened: `gstreamer-1.0`, `gstapp-1.0`, `gstpbutils-1.0`, `gobject-2.0`, `glib-2.0`. For a root install, its `bin` goes on the process `PATH` (Windows; DLLs are loaded with `LOAD_WITH_ALTERED_SEARCH_PATH`), and unless already set, `GST_PLUGIN_SYSTEM_PATH` → `<root>/lib/gstreamer-1.0` and `GST_PLUGIN_SCANNER` → `<root>/libexec/gstreamer-1.0/gst-plugin-scanner`. `GST_PLUGIN_PATH` is left alone.

Needed plugins: `appsrc` (base/app), `videoconvert` (base), `pngdec` (good/png), `vp8enc` (good/vpx), `webmmux` (good/matroska), `filesink` (core); `requireElements` names the missing ones.

Tested on Windows 11 with GStreamer 1.28.6 (MSVC x86_64). The Linux and macOS lookups are implemented but **untested**.

## Regenerating the bindings

`lib/src/bindings/gstreamer.g.dart` is generated and committed. After changing the symbol lists in `tool/ffigen.dart`:

```bash
LIBCLANG_PATH=/path/to/libclang.dll dart run tool/ffigen.dart
```

Headers come from `GSTREAMER_INCLUDE_ROOT`, else the found install's `include/` (Windows installs ship them), else `/usr/include` (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`). Without LLVM, `pip install --target <dir> libclang` provides `<dir>/clang/native/libclang.dll`.

## Tests

```bash
dart test test/loader_test.dart test/gstreamer_test.dart test/video_encoder_test.dart
```

They use the real GStreamer install (no mocks): 300 generated PNG frames → WebM, probed for 10.0 s / size / 30 fps / VP8-in-WebM, cross-checked with `ffprobe` when present.

## License

This package is GPL-3.0 (the LuminaGame/tools repository license). GStreamer itself is LGPL-2.1+; this package only loads the user's installed GStreamer libraries dynamically and does not ship or statically link them. The generated bindings file declares GStreamer's public C API.
