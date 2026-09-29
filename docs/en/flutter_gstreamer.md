[Türkçe](../tr/flutter_gstreamer.md)

# flutter_gstreamer

`flutter_gstreamer` is a pure-Dart FFI binding to a system GStreamer 1.x install, loaded at run time. Lumina's smoke tests use it to encode their videos in-process and to probe the result.

## Place in Lumina

`flutter_filament`, `lumina` and `lumina_ui` depend on `flutter_gstreamer` for their `SmokeArtifacts` helpers: smoke tests record their videos by encoding frames in-process instead of spawning `ffmpeg` or `gst-launch-1.0`, and probe the result. When GStreamer is not installed, `SmokeArtifacts` falls back to `ffmpeg`. The package is pure Dart (no native build step, no link-time dependency) and works in `dart test`, `flutter test` and desktop apps.

```yaml
dependencies:
  flutter_gstreamer:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_gstreamer
```

## Requirements

A GStreamer 1.x install with the base and good plugin sets. The elements used are `appsrc` (base/app), `videoconvert` (base), `pngdec` (good/png), `vp8enc` (good/vpx), `webmmux` (good/matroska) and `filesink` (core). Tested on Windows 11 with GStreamer 1.28.6 (MSVC x86_64); the Linux and macOS lookups are implemented but untested.

## Usage

```dart
import 'package:flutter_gstreamer/flutter_gstreamer.dart';

final gst = GStreamer.init();               // throws GStreamerNotFoundException if absent
print(gst.versionString);                   // GStreamer 1.28.6
GStreamer.isAvailable();                    // non-throwing check
gst.hasElement('vp8enc');

// PNG frames -> VP8 / WebM, 30 fps (300 frames = exactly 10.0 s)
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

`dart run example/encode_webm.dart [out.webm]` encodes 10 s of generated PNG frames into a VP8 WebM and probes it.

## API reference

File paths are relative to the `flutter_gstreamer/` package directory. The raw ffigen bindings (`GStreamerBindings` and the C structs and constants) are in `package:flutter_gstreamer/bindings.dart`; import it with a prefix.

### `lib/src/gstreamer.dart`

#### `class GStreamer`

Loads GStreamer and runs `gst_init_check` + `gst_pb_utils_init`.

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `init` | `static GStreamer init({String? root})` | Loads GStreamer (see [where GStreamer is looked for](#where-gstreamer-is-looked-for); `root` restricts the search to one install) and initialises it. Idempotent: later calls return the same instance; asking for a different `root` than the one loaded throws a `StateError`. Throws `GStreamerNotFoundException` when GStreamer cannot be loaded and `GStreamerException` when it loads but fails to initialise. A failure caches nothing. |
| `isAvailable` | `static bool isAvailable({String? root})` | Whether `init` succeeds, without throwing. |
| `isInitialized` | `static bool get isInitialized` | Whether `init` has succeeded in this isolate. |
| `instance` | `static GStreamer get instance` | The initialised instance; initialises with the default lookup on first use. |
| `libraries` | `final GStreamerLibraries libraries` | The opened shared libraries. |
| `bindings` | `final GStreamerBindings bindings` | Raw bindings over the opened libraries. |
| `version` | `GStreamerVersion get version` | `gst_version`. |
| `versionString` | `String get versionString` | `gst_version_string`, for example `GStreamer 1.28.6`. |
| `hasElement` | `bool hasElement(String factoryName)` | Whether an element factory (for example `vp8enc`) is registered, that is its plugin is installed and was found. |
| `missingElements` | `List<String> missingElements(Iterable<String> factoryNames)` | The entries of `factoryNames` that `hasElement` does not find. |
| `requireElements` | `void requireElements(Iterable<String> factoryNames, {String? purpose})` | Throws a `GStreamerException` naming the missing elements and where plugins were looked for. |

### `lib/src/libraries.dart`

#### `class GStreamerLibraries`

Finds and opens the GStreamer shared libraries: `gstreamer-1.0`, `gstapp-1.0`, `gstpbutils-1.0`, `gobject-2.0` and `glib-2.0`.

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `open` | `static GStreamerLibraries open({String? root})` | Finds and opens the libraries in the search order below. Throws `GStreamerNotFoundException` when none are found or they fail to load. |
| `root` | `final String? root` | The install root the libraries came from, or null when the system loader found them. |
| `paths` | `final List<String> paths` | The library files (or bare names for the system loader) that were opened. |
| `bindings` | `late final GStreamerBindings bindings` | Raw bindings resolving every symbol across the opened libraries. |

A root is an install prefix (holding `bin/` and `lib/`) or the library folder itself. When a root is used, its library folder goes on the process `PATH` (Windows; DLLs are loaded with `LOAD_WITH_ALTERED_SEARCH_PATH`), and, unless already set, `GST_PLUGIN_SYSTEM_PATH` points at `<root>/lib/gstreamer-1.0` and `GST_PLUGIN_SCANNER` at `<root>/libexec/gstreamer-1.0/gst-plugin-scanner`, so the plugins of that same install are found. `GST_PLUGIN_PATH` is left alone.

### `lib/src/pipeline.dart`

#### `enum GstState`

`voidPending`, `nullState`, `ready`, `paused`, `playing`, with their GStreamer values; `GstState.fromValue(int)`.

#### `class GstBusMessage`

A message popped from a pipeline's bus: `type`, `typeName`, `source` (the posting element), `error`, `debug`, and the `isEos`, `isError` and `isWarning` getters.

#### `class GstPipeline`

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `parse` | `factory GstPipeline.parse(String description, {GStreamer? gstreamer})` | `gst_parse_launch`: builds a pipeline from its textual description. |
| `element` | `GstElement? element(String name)` | A named element of the pipeline, or null. |
| `appSrc` | `GstAppSrc appSrc(String name)` | A named `appsrc` element. |
| `setState` | `void setState(GstState state)` | Requests `state`. Throws a `GStreamerException` (with the bus error, if any) when the change fails; an asynchronous change is not waited for. |
| `play` / `pause` / `stop` | `void play()`, `void pause()`, `void stop()` | Shorthands for `playing`, `paused` and `nullState`. `stop` releases devices and files (a filesink closes its file). |
| `state` | `GstState get state` | The current state (does not wait for a pending change). |
| `sendEos` | `void sendEos()` | Sends an end-of-stream event into the pipeline (for sources that do not end by themselves). |
| `pop` | `GstBusMessage? pop({...})` | Pops the next bus message matching a `GstMessageType` mask (all by default), waiting up to a timeout (null: do not wait). |
| `waitForEos` | `void waitForEos({Duration timeout = const Duration(minutes: 10)})` | Waits for end-of-stream. Throws a `GStreamerException` for an ERROR message (naming the element that posted it) or when the timeout passes. |
| `throwIfError` | `void throwIfError()` | Throws the first ERROR message already on the bus, if any (does not wait). |
| `dispose` | `void dispose()` | Stops the pipeline and releases it, its bus and every element handed out by `element`. Safe to call twice. |

#### `class GstElement`

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `name` | `final String name` | The element name. |
| `set` | `void set(String property, String value)` | Sets a property from its string form, as `gst-launch` would (no quoting). |
| `setAll` | `void setAll(Map<String, String> properties)` | Sets several properties. |

#### `class GstAppSrc`

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `element` | `final GstElement element` | The underlying element. |
| `setCaps` | `void setCaps(String caps)` | Sets the caps of the pushed buffers. |
| `pushBuffer` | `void pushBuffer(Uint8List data, {int? ptsNs, int? durationNs})` | Pushes one buffer with an optional presentation timestamp and duration. |
| `endOfStream` | `void endOfStream()` | Signals the end of the stream. |

### `lib/src/video_encoder.dart`

#### `enum VideoInput`, `enum VideoFormat`

`VideoInput.png` takes complete PNG files (all frames the same size, decoded by `pngdec`); `VideoInput.rgba` takes tightly packed 8-bit RGBA pixels, `width * height * 4` bytes per frame. `VideoFormat.webmVp8` is the only output format: VP8 (`vp8enc`) in WebM (`webmmux`).

#### `class FrameRate`

An exact rational frame rate: `FrameRate(numerator, [denominator = 1])`, `FrameRate.fromFps(double)`, `fps`, and `timestampNs(int index)`, the presentation time of frame `index`.

#### `class Vp8Quality`

The `vp8enc` settings: `cqLevel` (6), `minQuantizer` (0), `maxQuantizer` (16), `targetBitrate` (20000000), `deadline` (1000000), `cpuUsed` (2), `keyframeMaxDistance` (150) and `threads`; `properties` gives them as `vp8enc` properties with `end-usage=cq`. `Vp8Quality.smoke`, the default, is the Lumina smoke-video setting, the counterpart of ffmpeg `libvpx -crf 6 -b:v 20M -qmin 0 -qmax 16 -quality good -cpu-used 2 -g 150`.

#### `class VideoEncoder`

Encodes frames in-process through `appsrc ! (pngdec !) videoconvert ! vp8enc ! webmmux ! filesink`. Frame `i` is stamped with `FrameRate.timestampNs(i)`, so `n` frames play for exactly `n / fps` seconds.

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `png` | `factory VideoEncoder.png({required File out, FrameRate frameRate = const FrameRate(30), VideoFormat format, Vp8Quality quality = Vp8Quality.smoke, GStreamer? gstreamer})` | An encoder taking PNG files. |
| `rgba` | `factory VideoEncoder.rgba({required int width, required int height, required File out, ...})` | An encoder taking raw RGBA frames of `width` x `height`. |
| `requiredElements` | `static List<String> requiredElements(VideoInput input, [VideoFormat format])` | The GStreamer elements an encoder for `input` needs. |
| `input`, `out`, `frameRate` | fields | The encoder's configuration. |
| `frameCount` | `int get frameCount` | Frames added so far. |
| `addFrame` | `void addFrame(Uint8List frame)` | Adds one frame. |
| `finish` | `void finish({Duration timeout = const Duration(minutes: 10)})` | Ends the stream and waits (up to `timeout`) until the muxer has written and closed `out`. Throws a `GStreamerException` on a pipeline error, a timeout or an empty output, and a `StateError` when no frame was added. |
| `abort` | `void abort()` | Stops without finishing the file, which is left incomplete. |
| `encodePngFrames` | `static void encodePngFrames(Iterable<Uint8List> pngFrames, {required File out, ...})` | One-shot encode of PNG frames. |
| `encodeRgbaFrames` | `static void encodeRgbaFrames(Iterable<Uint8List> rgbaFrames, {required int width, required int height, required File out, ...})` | One-shot encode of RGBA frames. |

### `lib/src/media_probe.dart`

#### `class MediaProbe`

`static MediaInfo probe(File file, {Duration timeout = const Duration(seconds: 30), GStreamer? gstreamer})` reads a media file with GStreamer's `GstDiscoverer` (synchronous, no FFmpeg needed). Throws a `GStreamerException` when the file is missing or not readable media.

#### `class MediaInfo`

`durationNs`, `duration`, `durationSeconds`, `seekable`, `containerCaps`, `videoCaps`, `width`, `height`, `frameRateNumerator`, `frameRateDenominator`, `fps`, `videoBitrate`, `audioStreams`, and the derived `containerType` (for example `video/webm`) and `videoCodec` (for example `video/x-vp8`).

### `lib/src/exceptions.dart`

- `GStreamerNotFoundException(message, {searched, cause})`: GStreamer's libraries could not be found or loaded. `searched` lists what was tried, in order; `cause` is the loader error when a library was found but failed to load. Catch it to fall back to another encoder or to skip.
- `GStreamerException(message, {debug, source})`: a GStreamer call failed (initialisation, a pipeline description that does not parse, a missing element, an ERROR message on the bus, a timeout, or a file the discoverer cannot read). `source` names the element that posted the error.

## Where GStreamer is looked for

1. An explicit `root` (`GStreamer.init(root: ...)`), and only that one.
2. `FLUTTER_GSTREAMER_ROOT`, `GSTREAMER_1_0_ROOT_MSVC_X86_64`, `GSTREAMER_1_0_ROOT_MINGW_X86_64`, `GSTREAMER_1_0_ROOT_X86_64`.
3. Default installs. Windows: `%LOCALAPPDATA%\Programs\gstreamer\1.0\msvc_x86_64` (per user), `%ProgramFiles%\gstreamer\1.0\msvc_x86_64`, `C:\gstreamer\1.0\msvc_x86_64` (and the `mingw_x86_64` variants). macOS: `/Library/Frameworks/GStreamer.framework/Versions/1.0`, `/opt/homebrew`, `/usr/local`.
4. Windows: every `PATH` folder holding `gstreamer-1.0-0.dll`. Linux and macOS: the system loader (`libgstreamer-1.0.so.0`, ...).

## Development

`lib/src/bindings/gstreamer.g.dart` is generated and committed. After changing the symbol lists in `tool/ffigen.dart`:

```bash
LIBCLANG_PATH=/path/to/libclang.dll dart run tool/ffigen.dart
```

Headers come from `GSTREAMER_INCLUDE_ROOT`, else the found install's `include/` (Windows installs ship them), else `/usr/include` (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`).

Tests use the real GStreamer install (no mocks):

```bash
dart test test/loader_test.dart test/gstreamer_test.dart test/video_encoder_test.dart
```

---

[Previous: flutter_riglogic](flutter_riglogic.md) | [Up: Lumina tools documentation](../README.md) | [Next: lumina_mouse_capture](lumina_mouse_capture.md)
