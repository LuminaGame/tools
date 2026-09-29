[English](../en/lumina_smoke-api.md)

# lumina_smoke API

`lumina_smoke` sınıf referansı: `package:lumina_smoke/lumina_smoke.dart` (artifact'ler, video kuralları ve probe, recorder'lar, encoder'lar), `package:lumina_smoke/flutter.dart` (`SmokeRecorder`, `SmokeCapture`) ve `package:lumina_smoke/report.dart` (`smokeReportMain`, `SmokeReportConfig`, generator, modeller ve dashboard sunucusu). Dosya yolları `lumina_smoke/` paket dizinine görelidir.

**Bu sayfada:**

- [`lib/src/artifacts.dart`](#libsrcartifactsdart)
- [`lib/src/flutter/capture.dart`](#libsrcfluttercapturedart)
- [`lib/src/flutter/recorder.dart`](#libsrcflutterrecorderdart)
- [`lib/src/png.dart`](#libsrcpngdart)
- [`lib/src/report/ansi.dart`](#libsrcreportansidart)
- [`lib/src/report/categories.dart`](#libsrcreportcategoriesdart)
- [`lib/src/report/config.dart`](#libsrcreportconfigdart)
- [`lib/src/report/dashboard_server.dart`](#libsrcreportdashboard_serverdart)
- [`lib/src/report/generator.dart`](#libsrcreportgeneratordart)
- [`lib/src/report/html.dart`](#libsrcreporthtmldart)
- [`lib/src/report/model.dart`](#libsrcreportmodeldart)
- [`lib/src/report/paths.dart`](#libsrcreportpathsdart)
- [`lib/src/report/process_groups.dart`](#libsrcreportprocess_groupsdart)
- [`lib/src/report/run_mode.dart`](#libsrcreportrun_modedart)
- [`lib/src/report/runner.dart`](#libsrcreportrunnerdart)
- [`lib/src/temp_dirs.dart`](#libsrctemp_dirsdart)
- [`lib/src/tools.dart`](#libsrctoolsdart)
- [`lib/src/video.dart`](#libsrcvideodart)
- [`lib/src/video_recorder.dart`](#libsrcvideo_recorderdart)
- [`lib/src/webm.dart`](#libsrcwebmdart)

## `lib/src/artifacts.dart`

### `abstract final class SmokeArtifacts`

Publishes smoke-test evidence: PNG screenshots and VP8 / WebM videos, each with a sidecar JSON (`<sanitized name>.json`) that records the **declared test name** the report matches it to (never file times), the files, the video's measurements, the real 3D assets the scenario loaded (`usedAssets`) and optional `metrics`.

Artifacts go to [dir]: `build/smoke_artifacts/` of the package under test, or `LUMINA_SMOKE_OUT` (the report runner sets it). Every video is checked against the smoke-video rules before anything is written: at least [minimumVideoSeconds] long, [minimumVideoWidth] × [minimumVideoHeight], [minimumVideoFps] fps, no frame held longer than [maximumFrameHoldSeconds].

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `outputDirOverride` | `static String? outputDirOverride` | An in-process artifact directory for tests of the harness itself; wins over the environment. [clear] only works while it is set. |
| `testAssetsDirOverride` | `static String? testAssetsDirOverride` | An in-process test-assets directory; wins over `LUMINA_TEST_ASSETS`. |
| `overrideDirForTesting` | `static void overrideDirForTesting(Directory? d)` | Sets (or, with null, clears) [outputDirOverride]. |
| `packageRoot` | `static Directory get packageRoot` | The package under test: the nearest directory holding a `pubspec.yaml`, walking up from the working directory. |
| `dir` | `static Directory get dir` | The artifact directory, created on first use: [outputDirOverride], else `LUMINA_SMOKE_OUT` (or the older `LUMINA_UI_SMOKE_OUT` / `FILAMENT_SMOKE_OUT`), else `<package>/build/smoke_artifacts`. |
| `testAssetsDir` | `static Directory get testAssetsDir` | The shared real 3D test assets (`test-assets/`): [testAssetsDirOverride], else `LUMINA_TEST_ASSETS`, else the first `test-assets` directory found walking up from the package under test. |
| `sanitizeTestName` | `static String sanitizeTestName(String testName)` | A test name as a file name: lower case, every run of other characters than `a-z0-9` one `_`, no leading or trailing `_`. |
| `recordAsset` | `static void recordAsset(String path)` | Records a real 3D asset the running scenario loaded; every later save adds the recorded set to its sidecar's `usedAssets`. |
| `recordedAssets` | `static List<String> get recordedAssets` | The assets recorded so far with [recordAsset], in insertion order. |
| `resetRecordedAssets` | `static void resetRecordedAssets()` | Forgets the recorded assets (call between independent scenarios). |
| `minimumVideoSeconds` | `static const double minimumVideoSeconds` | Every smoke video runs at least this long. |
| `maximumFrameHoldSeconds` | `static const double maximumFrameHoldSeconds` | Longest time one frame may stay on screen, in seconds: a video must show the scenario happening, never one frame stretched. |
| `minimumVideoFps` | `static const double minimumVideoFps` | Every smoke video plays at least this many real frames per second: a 10 s video is at least 300 rendered frames. |
| `minimumVideoWidth` | `static const int minimumVideoWidth` | Every smoke video is at least [minimumVideoWidth] × [minimumVideoHeight]. |
| `minimumVideoHeight` | `static const int minimumVideoHeight` | See [minimumVideoWidth]. |
| `framesDurationSeconds` | `static double framesDurationSeconds(int frameCount, double fps)` | Playback length of [frameCount] frames at [fps]. |
| `framesForSeconds` | `static int framesForSeconds(double fps, {double seconds = minimumVideoSeconds})` | Frames needed at [fps] for a video of at least [seconds]. |
| `checkVideoDuration` | `static void checkVideoDuration(String testName, int frameCount, double fps)` | Throws a [StateError] naming [testName] when [frameCount] frames at [fps] run shorter than [minimumVideoSeconds], hold each frame longer than [maximumFrameHoldSeconds] or play slower than [minimumVideoFps]. |
| `checkVideoFps` | `static void checkVideoFps(String testName, double fps)` | Throws a [StateError] naming [testName] when [fps] is under [minimumVideoFps] (allowing [SmokeVideo.fpsTolerance]). |
| `checkVideoSize` | `static void checkVideoSize(String testName, int width, int height)` | Throws a [StateError] naming [testName] when a [width] × [height] video is smaller than [minimumVideoWidth] × [minimumVideoHeight]. |
| `checkFramesMove` | `static void checkFramesMove(String testName, List<Uint8List> pngFrames, double fps)` | Throws a [StateError] when a run of byte-identical consecutive frames in [pngFrames] stays on screen longer than [maximumFrameHoldSeconds] at [fps] (a frozen scenario padded out to the minimum length). |
| `encodePng` | `static Uint8List encodePng(int w, int h, Uint8List rgba, {bool flipY = false, bool bgra = false})` | Encodes [w] × [h] RGBA8 (or, with [bgra], BGRA8) pixels as a PNG; [flipY] flips GL-style bottom-up rows. |
| `encodeRgbaToPng` | `static Uint8List encodeRgbaToPng(Uint8List rawPixels, int width, int height, {bool flipY = false, bool bgra =...` | [encodePng] with the pixels first. |
| `pngSize` | `static (int, int)? pngSize(Uint8List png)` | Width and height from a PNG's IHDR chunk; null when [png] is not a PNG. |
| `vp8QualitySettings` | `static const List<String> vp8QualitySettings` | See [SmokeWebm.vp8QualitySettings]. |
| `ffmpegVp8QualitySettings` | `static const List<String> ffmpegVp8QualitySettings` | See [SmokeWebm.ffmpegVp8QualitySettings]. |
| `videoEncoderAvailable` | `static bool get videoEncoderAvailable` | Whether a video encoder is available: GStreamer or ffmpeg. |
| `gstreamerEncoderAvailable` | `static bool get gstreamerEncoderAvailable` | Whether GStreamer encodes RGBA frames in-process here. |
| `encodeWebmFromPngFrames` | `static Uint8List encodeWebmFromPngFrames(List<Uint8List> pngFrames, {double fps = minimumVideoFps})` | See [SmokeWebm.encodePngFrames]. |
| `encodeRawRgbaToWebm` | `static ProcessResult encodeRawRgbaToWebm({required String rawFrames, required String out, required int width,...` | See [SmokeWebm.encodeRawRgba]. |
| `encodeWebmFromRawFile` | `static Uint8List encodeWebmFromRawFile(File rawFrames, {required int width, required int height, required int...` | See [SmokeWebm.encodeRawFile]. |
| `encodeWebmFromRgbaFrames` | `static Uint8List encodeWebmFromRgbaFrames({required int width, required int height, required List<Uint8List> f...` | Encodes RGBA frames, played at [fps] (or each shown [frameDurationMs]), into a WebM at their own resolution through a [SmokeVideoRecorder], so the smoke-video rules apply and a breach throws a [StateError] naming [testName]. For long or large recordings, use a [SmokeVideoRecorder] directly: it streams the frames instead of holding them all. |
| `probeVideo` | `static ({double? seconds, int? width, int? height, double? fps})? probeVideo(String path)` | Playback length, frame size and average frame rate of the video at [path] (see [SmokeVideo.probe]); null when nothing could be read. |
| `probeVideoSeconds` | `static double? probeVideoSeconds(String path)` | Playback length of the video at [path] in seconds, or null. |
| `videoDurationSeconds` | `static double? videoDurationSeconds(File video)` | A video's length in seconds, or null when it cannot be read. |
| `videoFramesPerSecond` | `static double? videoFramesPerSecond(File video)` | A video's frame rate, or null when it cannot be read. |
| `videoFrameSize` | `static (int, int)? videoFrameSize(File video)` | A video's frame size, or null when it cannot be read. |
| `saveScreenshot` | `static File saveScreenshot(String testName, Uint8List pngBytes, {List<String>? usedAssets, Map<String, Object?...` | Writes a PNG as `<sanitized name>.png` in [dir] and merges its sidecar. |
| `saveScreenshotToDir` | `static File saveScreenshotToDir(String testName, Uint8List pngBytes, Directory targetDir, {List<String>? usedA...` | [saveScreenshot] into [targetDir]. |
| `saveVideoFromPngFrames` | `static File saveVideoFromPngFrames(String testName, List<Uint8List> pngFrames, {double fps = minimumVideoFps,...` | Encodes PNG frames into a WebM and saves it like [saveVideo], recording `frameCount` and `fps`. |
| `saveVideo` | `static File saveVideo(String testName, Uint8List videoBytes, {String extension = 'webm', List<String>? usedAss...` | Writes an encoded video (WebM by default, MP4 with [extension]) as `<sanitized name>.<extension>` in [dir] and merges its sidecar. |
| `saveEncodedVideo` | `static File saveEncodedVideo(String testName, Uint8List videoBytes, {String extension = 'webm', List<String>?...` | [saveVideo] under its older name. |
| `saveVideoToDir` | `static File saveVideoToDir(String testName, Uint8List videoBytes, Directory targetDir, {String extension = 'we...` | [saveVideo] into [targetDir]. |
| `annotate` | `static void annotate(String testName, Map<String, Object?> fields, {Directory? targetDir})` | Adds [fields] to the sidecar of [testName] in [targetDir] (default [dir]), e.g. how long a recording stayed still. |
| `clear` | `static void clear()` | Wipes every file from the artifact directory, only while [outputDirOverride] is set. |
| `clearDir` | `static void clearDir(Directory targetDir)` | Deletes everything inside [targetDir]. |
| `ffmpegPath` | `static String? get ffmpegPath` | The ffmpeg / ffprobe the smoke system falls back to (see [SmokeTools]). |
| `ffprobePath` | `static String? get ffprobePath` |  |

## `lib/src/flutter/capture.dart`

### `abstract final class SmokeCapture`

PNG captures of a running Flutter app in widget and integration tests.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `captureWidgetPng` | `static Future<Uint8List> captureWidgetPng(WidgetTester tester, Finder repaintBoundary, {double pixelRatio = 1....` | The PNG of the [RenderRepaintBoundary] [repaintBoundary] finds, at [pixelRatio]. |
| `captureIntegrationPng` | `static Future<Uint8List> captureIntegrationPng(Object binding, WidgetTester tester, {Finder? boundary}) async` | A frame of an integration test: [boundary] (or the first [RepaintBoundary]) through [captureWidgetPng], else the binding's own screenshot. |

## `lib/src/flutter/recorder.dart`

### `class SmokeRecorder`

Records a smoke scenario as it runs: real frames of the app captured at a fixed rate while the test drives it. Every smoke video is at least 10 s of the scenario happening, 1024×768 or larger, at 30 fps.

Frames go straight to a temporary raw file (a 1600×1000 frame is 6 MB), at full resolution and 30 fps, and are encoded to high-quality WebM on [save].

**Yapıcı Metotlar (Constructors):**

- `SmokeRecorder(this.tester, {required this.boundary, this.frameInterval = const Duration(microseconds: 33333), // 30 fps this.pixelRatio = 1.0,})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `tester` | `final WidgetTester tester` |  |
| `boundary` | `final Finder boundary` |  |
| `frameInterval` | `final Duration frameInterval` | Time between captured frames, and so each frame's length in the video. |
| `pixelRatio` | `final double pixelRatio` | Capture scale relative to the window's logical size: at least 1.0, and raised so a frame is never smaller than [SmokeArtifacts.minimumVideoWidth] × [SmokeArtifacts.minimumVideoHeight] (the UI is re-rasterised, so text stays sharp). |
| `tempPrefix` | `static const String tempPrefix` | The prefix of every recorder's temporary directory. |
| `longestStill` | `Duration get longestStill` | The longest stretch of byte-identical frames recorded so far: how long the video shows one unchanging picture (never more than [SmokeVideo.maximumFrameHoldSeconds]). |
| `frameCount` | `int get frameCount` |  |
| `recorded` | `Duration get recorded` | Length of the video recorded so far. |
| `capture` | `Future<void> capture() async` | Captures the current frame of the app. |
| `captureIfChanged` | `Future<bool> captureIfChanged()` | Captures the current frame only if it differs from the last one captured. For long waits recorded as a time-lapse: a still screen adds nothing, so it is never padded out with copies of the same frame. Returns whether a frame was added. |
| `hold` | `Future<void> hold(Duration duration) async` | Keeps the app running for [duration] in real time, capturing a frame every [frameInterval]: the scenario's time on screen. |
| `typeText` | `Future<void> typeText(Finder field, String text, {Duration perCharacter = const Duration(milliseconds: 100)})...` | Types [text] into [field] the way a user does, one character at a time, with the field updating on video as it goes. Each prefix goes through [WidgetTester.enterText], so the field's `onChanged` fires per keystroke. |
| `drag` | `Future<void> drag(Offset from, Offset to, {int steps = 30, PointerDeviceKind kind = PointerDeviceKind.mouse, i...` | Drags a pointer from [from] to [to] in [steps] moves, recording every step: the drag plays out on video at the pace a hand would move. |
| `save` | `File save(String testName, {List<String>? usedAssets})` | Encodes the recording and saves it as [testName]'s video. Throws when it is shorter than [SmokeArtifacts.minimumVideoSeconds] or smaller than [SmokeArtifacts.minimumVideoWidth] × [SmokeArtifacts.minimumVideoHeight]. |

## `lib/src/png.dart`

### `abstract final class SmokePng`

A dependency-free RGBA8 / BGRA8 to PNG encoder (no filtering, zlib level 6) and a PNG header reader.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `encode` | `static Uint8List encode(int w, int h, Uint8List rgba, {bool flipY = false, bool bgra = false})` | Encodes [w] × [h] RGBA8 pixels as a PNG. [flipY] flips the rows (for GL-style bottom-up readbacks); [bgra] swaps the red and blue channels of a BGRA8 buffer. |
| `size` | `static (int, int)? size(Uint8List png)` | Width and height from a PNG's IHDR chunk; null when [png] is not a PNG. |

## `lib/src/report/ansi.dart`

**Üst düzey fonksiyonlar ve değişkenler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `escapeHtml` | `String escapeHtml(String text)` | [text] with `&`, `<`, `>`, `"` and `'` escaped. |
| `ansiToHtml` | `String ansiToHtml(String text)` | Console output with its ANSI colour codes (a logger's `\x1B[36m[INFO]`, flutter test's red failures) turned into coloured spans, and HTML escaped. SGR codes set colour and style; every other escape sequence (cursor moves, line erases) is dropped, as a terminal would not show it either. |

## `lib/src/report/categories.dart`

### `class TestCategories`

How a package groups its tests into report pages ("categories"): one per module or feature area, in report order.

A test's category comes from its file (`suite`, a path) and then its name:

1. [pathRules]: the first whose text the normalised path contains, and [namePrefixes]: the first the lower-cased name starts with; 2. [folders]: a folder (under the last `/test/`) that decides whatever the file is called; 3. the file name's keywords (see [longestMatch]); 4. [fallbackFolders]: a folder that decides when the file name does not; 5. the test name's keywords; 6. [other].

Paths are compared with `/` separators and lower-cased, so a Windows suite path (`C:\…\test\smoke\x_test.dart`) is grouped like a POSIX one.

**Yapıcı Metotlar (Constructors):**

- `const TestCategories(this.categories, {this.longestMatch = false, this.folders = const {}, this.fallbackFolders = const {}, this.pathRules = const {}, this.name...`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `categories` | `final List<(String, List<String>)> categories` | The categories in report order, each with its keywords. |
| `longestMatch` | `final bool longestMatch` | How keywords match. `false`: the first category with a keyword the text contains wins. `true`: a keyword matches only at the start of a word of the `_`-separated text (`pawn` matches `pawn_input`, not `spawn_actor`) and the longest matching keyword wins, a tie going to the earlier category. |
| `folders` | `final Map<String, String> folders` | Test folders that decide the category whatever the file is called. |
| `fallbackFolders` | `final Map<String, String> fallbackFolders` | Test folders that decide only when the file name does not. |
| `pathRules` | `final Map<String, String> pathRules` | Path fragments (lower case, `/`-separated) that decide first. |
| `namePrefixes` | `final Map<String, String> namePrefixes` | Test-name prefixes (lower case) that decide first. |
| `other` | `final String other` | The category of a test nothing matches. |
| `names` | `List<String> get names` | The category names in report order. |
| `categoryOf` | `String categoryOf(String suite, String name)` | The category of the test [name] in the file [suite]. |
| `orderOf` | `int orderOf(String category)` | Position of [category] in the report; unknown ones ([other]) go last. |

## `lib/src/report/config.dart`

### `class SmokeBackend`

A GPU backend the smoke targets run on, each run writing into its own `<artifacts>/<name>/` folder.

**Yapıcı Metotlar (Constructors):**

- `const SmokeBackend(this.name, {this.environment = const {}})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `name` | `final String name` | The folder name and the report's backend tag (`opengl`, `vulkan`). |
| `environment` | `final Map<String, String> environment` | Extra environment of this backend's runs (e.g. the variable that selects it). |

### `class SmokeReportConfig`

What a package's `tool/smoke_report.dart` tells the shared runner and report generator.

**Yapıcı Metotlar (Constructors):**

- `const SmokeReportConfig({required this.title, this.tag, this.dashboardTitle, this.categories = const TestCategories([]), this.categoryNote = 'One page per categ...`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `title` | `final String title` | The report's title (`Lumina Engine Smoke & Test Report`). |
| `tag` | `final String? tag` | A short tag next to the title (`Core Engine`). |
| `dashboardTitle` | `final String? dashboardTitle` | The live dashboard's title; [title] when null. |
| `categories` | `final TestCategories categories` | How tests are grouped into pages. |
| `categoryNote` | `final String categoryNote` | The note above the index's category table. |
| `failingCategoriesFirst` | `final bool failingCategoriesFirst` | Whether categories with failures come first in the index and the page navigation (else the [categories] order alone). |
| `orphanCategory` | `final String? orphanCategory` | When set, every artifact that matches no test goes on this one page; otherwise each goes to the category its name (and file) falls in. |
| `smokeDirs` | `final List<String> smokeDirs` | The folders (relative to the package) whose tests are smoke tests: run one file at a time (`--concurrency=1`), after the unit tests, on every backend. The default run (no targets) runs these. |
| `extraSmokeTargets` | `final List<String> extraSmokeTargets` | Further smoke files or folders, run with the smoke tests when they exist. |
| `integrationDirs` | `final List<String> integrationDirs` | Integration-test folders (`integration_test`): their files run one by one on the host's desktop device. |
| `integrationSmokeDirs` | `final List<String> integrationSmokeDirs` | The smoke folders among [integrationDirs] (`integration_test/smoke`), run by the default smoke run. |
| `backends` | `final List<SmokeBackend> backends` | GPU backends. Empty: one run, artifacts straight into the artifact directory. Otherwise the first backend runs every target and the others the smoke targets, each into `<artifacts>/<backend>/`. |
| `environment` | `final Map<String, String> environment` | Extra environment of every run. |
| `gpuName` | `final String gpuName` | The GPU every run is pinned to, by name (`FILAMENT_GPU`): under PRIME offload the Vulkan device order changes, so an index would pick another card. |
| `cudaDevice` | `final String cudaDevice` | `CUDA_VISIBLE_DEVICES` of every run. |
| `gpuLabel` | `final String gpuLabel` | The GPU as the report names it. |
| `configDirVariable` | `final String? configDirVariable` | When set, every run gets this variable pointing at a throwaway directory, so the tests' editor configuration (recent projects, settings) never touches the user's own. |
| `scenarioKeywords` | `final List<String> scenarioKeywords` | Module words that tie a `Scenario NN` artifact to the `Scenario NN` test of the same module when the names differ otherwise (e.g. `static_mesh`, `camera`): both the artifact name and the test name or file must contain one. |
| `categoryOf` | `String categoryOf(String suite, String name)` | The category of the test [name] in the file [suite]. |
| `categoryOrder` | `int categoryOrder(String category)` | Where [category] goes in the report. |

## `lib/src/report/dashboard_server.dart`

### `class SmokeDashboardServer`

Live interactive dashboard HTTP server for smoke test execution.

Serves: - GET / : Single Page Application with live metrics, test list, log streaming, interactive video player, and screenshot lightbox. - GET /api/stream : Server-Sent Events (SSE) broadcasting test events in real time. - GET /api/state : JSON snapshot of current run state. - GET /artifacts/* : Serves images, videos (with HTTP Range support), and sidecars. - POST /api/stop : Gracefully stops the server.

**Yapıcı Metotlar (Constructors):**

- `SmokeDashboardServer({this.requestedPort = 8088, required this.artifactsDir, this.title = 'Lumina Smoke Test Studio',})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `requestedPort` | `final int requestedPort` |  |
| `artifactsDir` | `final Directory artifactsDir` |  |
| `title` | `final String title` |  |
| `actualPort` | `int? actualPort` |  |
| `isRunning` | `bool isRunning` |  |
| `startTimeMs` | `final int startTimeMs` |  |
| `endTimeMs` | `int? endTimeMs` |  |
| `exitCode` | `int? exitCode` |  |
| `activeTest` | `Map<String, dynamic>? activeTest` |  |
| `activeTestLogs` | `final List<String> activeTestLogs` |  |
| `tests` | `final Map<dynamic, Map<String, dynamic>> tests` |  |
| `testOrder` | `final List<dynamic> testOrder` |  |
| `url` | `String get url` |  |
| `start` | `Future<int> start() async` | Starts the HTTP server on [requestedPort] (or next available port). |
| `handleMachineEvent` | `void handleMachineEvent(Map<String, dynamic> event)` | Ingests a raw event from `flutter test --machine`. |
| `handleRawLog` | `void handleRawLog(String line)` | Appends raw output lines (e.g. build logs). |
| `onSuiteDone` | `void onSuiteDone({required int exitCode})` | Marks entire run as completed. |
| `getSnapshot` | `Map<String, dynamic> getSnapshot()` | Snapshot representing all current tests and statistics. |
| `waitIfInteractive` | `Future<void> waitIfInteractive() async` | If interactive, keeps server running so user can inspect results. |
| `stop` | `Future<void> stop() async` | Gracefully closes server. |

## `lib/src/report/generator.dart`

### `class SmokeReportGenerator`

Turns `flutter test --machine` events and the artifact directory into a [SmokeReportModel], and the model into HTML pages.

Events may carry the runner's tags: `run` (the `flutter test` process, whose test ids start from 0 again), `target` / `targets` (what it ran), `filter` (its scenario filter, e.g. `--plain-name x`) and `backend`. Untagged events (a canned stream) are one run.

**Yapıcı Metotlar (Constructors):**

- `SmokeReportGenerator(this.config)`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `config` | `final SmokeReportConfig config` |  |
| `html` | `final SmokeReportHtml html` |  |
| `processEvents` | `SmokeReportModel processEvents(List<Map<String, dynamic>> events, {Directory? artifactsDir, DateTime? timestam...` | Builds the report of [events], matching every PNG and video under [artifactsDir] (recursively) to a test through its sidecar's declared name. |
| `scanArtifacts` | `List<ArtifactGroup> scanArtifacts(Directory base)` | Every sidecar under [base] (recursively) with its PNG and video, plus one group per file base name for the media no sidecar names. A folder named like a configured backend tags its artifacts with that backend; otherwise a sidecar's own `backend` does. |
| `bestTestFor` | `TestResultItem? bestTestFor(String artifactName, String? backend, List<TestResultItem> tests)` | The test an artifact saved as [artifactName] (on [backend]) belongs to, or null: an exact full or leaf name first, then the same name ignoring case and punctuation, then the longest test name the artifact name extends (`<test name> (<detail>)`, `<test name>: <step>`), then one name containing the other, then the same `Scenario NN` of the same module, and last a test of the file the artifact is named after (`<file>_smoke_test: <step>`). |
| `matchScore` | `int matchScore(TestResultItem test, String artifactName)` | How well the artifact name [artifactName] matches [test] (0: not at all). |
| `renderPages` | `Map<String, String> renderPages(SmokeReportModel model, {String reportDir = 'build'})` | The report as pages keyed by their path relative to [reportDir]: the index `smoke_report.html` and `smoke_report/<slug>.html` per category. Every PNG and video is linked relative to its page (never embedded). |
| `renderHtml` | `String renderHtml(SmokeReportModel model)` | The index page. |
| `renderCategoryHtml` | `String renderCategoryHtml(SmokeReportModel model, String category, {String reportDir = 'build'})` | One category's page. |
| `writeReport` | `File writeReport(SmokeReportModel model, File reportFile)` | Writes [renderPages] under [reportFile] (the index) and its sibling `<name without .html>/` folder, removing pages of categories that no longer exist. Returns the index. |
| `categorySlug` | `static String categorySlug(String category)` | File name (under the report's folder) of a category's page. |
| `testAnchor` | `static String testAnchor(TestResultItem test)` | Anchor of a test's card on its category page. |
| `orphanAnchor` | `static String orphanAnchor(OrphanedArtifact orphan)` | Anchor of an unmatched artifact's card on its category page. |

### `class ArtifactGroup`

A sidecar (or a set of files no sidecar names) found under the artifact directory.

**Yapıcı Metotlar (Constructors):**

- `ArtifactGroup({required this.title, required this.testName, required this.backend})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `title` | `final String title` |  |
| `testName` | `final String? testName` | The declared test name from the sidecar; null for media without one. |
| `backend` | `final String? backend` | From the folder, else the sidecar; null when unknown. |
| `media` | `final List<ReportMedia> media` |  |
| `usedAssets` | `final List<String> usedAssets` |  |

**Üst düzey fonksiyonlar ve değişkenler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `runOf` | `int runOf(Map<String, dynamic> e)` | The run an event belongs to (0 when untagged). |
| `backendOf` | `String? backendOf(Map<String, dynamic> e)` | The backend an event ran on (`backend`, or the older `__backend`). |
| `smokeRunKey` | `String? smokeRunKey(Map<String, dynamic> e)` | What an event's run ran, for merging: its target, backend and scenario filter. Null for untagged events. |
| `targetsOf` | `List<String> targetsOf(Map<String, dynamic> e)` | The targets a run's events name (`targets`, else `target`). |
| `smokeEventsKeptOnMerge` | `List<Map<String, dynamic>> smokeEventsKeptOnMerge(List<Map<String, dynamic>> previous, {required Set<String> r...` | The earlier events a merging run keeps: targets being re-run are replaced (a filtered re-run replaces only the same filter's earlier run), older runs of any target are replaced, and a run none of whose targets exists any more (a deleted or renamed smoke file, or a mistyped target such as a `--plain-name` value taken for a file) is dropped, so its result cannot sit in the merged report forever. |

## `lib/src/report/html.dart`

### `class SmokeReportHtml`

The report's HTML: an index page and one page per category, every PNG and video linked relative to the page it is on, never embedded.

**Yapıcı Metotlar (Constructors):**

- `SmokeReportHtml(this.config)`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `config` | `final SmokeReportConfig config` |  |
| `categorySlug` | `static String categorySlug(String category)` | File name (under the report's folder) of a category's page. |
| `testAnchor` | `static String testAnchor(TestResultItem test)` | Anchor of a test's card on its category page. |
| `orphanAnchor` | `static String orphanAnchor(OrphanedArtifact orphan)` | Anchor of an unmatched artifact's card on its category page. |
| `renderPages` | `Map<String, String> renderPages(SmokeReportModel model, {String reportDir = 'build'})` | The index plus one page per category, keyed by path relative to [reportDir]. |
| `renderIndex` | `String renderIndex(SmokeReportModel model)` | The index page: overall totals, the failing tests (each linking to its card) and one row per category linking to `smoke_report/<slug>.html`. |
| `renderCategory` | `String renderCategory(SmokeReportModel model, String category, {String reportDir = 'build'})` | One category's page: its tests' cards (media, coloured console output, badges, zoom modal), the unmatched artifacts of that category, a link back to the index and a navigation bar to the sibling categories. |

## `lib/src/report/model.dart`

### `class ReportMedia`

One PNG or video linked from the report (never embedded: the report is shared together with its `build/smoke_artifacts/` folder).

**Yapıcı Metotlar (Constructors):**

- `ReportMedia({required this.fileName, required this.mimeType, required this.path, required this.relativePath, this.label, this.video, this.savedAt = 0, this.miss...`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `fileName` | `final String fileName` | The file's name. |
| `mimeType` | `final String mimeType` |  |
| `path` | `final String path` | Absolute path of the file; the report links it relative to the page it is on. |
| `relativePath` | `final String relativePath` | The path under the artifact directory, `/`-separated. |
| `label` | `final String? label` | The declared test name the file was saved under (its sidecar's `test`); null for a file no sidecar names. |
| `video` | `final SmokeVideoInfo? video` | What was measured of a video; null for an image. |
| `savedAt` | `final int savedAt` | When the sidecar was written (milliseconds since the epoch); orders a test's gallery the way the scenario saved it. |
| `missing` | `final bool missing` | A sidecar names the file, but it is not there. |
| `isVideo` | `bool get isVideo` |  |
| `isImage` | `bool get isImage` |  |
| `videoSeconds` | `double? get videoSeconds` | Length of a video in seconds; null for an image or an unmeasured video. |
| `isShortVideo` | `bool get isShortVideo` | A video under the minimum length, or of unknown length. |
| `isSmallVideo` | `bool get isSmallVideo` | A video under the minimum size, or of unknown size. |
| `isSlowVideo` | `bool get isSlowVideo` | A video under the minimum frame rate, or of unknown rate. |
| `breaksVideoRule` | `bool get breaksVideoRule` | Whether this video breaks any of the smoke-video minimums. |
| `violations` | `List<String> get violations` | The rules this video breaks, as `3.0 s < 10 s` etc. |
| `mimeFor` | `static String? mimeFor(String name)` | The MIME type of a PNG, WebM or MP4 file name; null for anything else. |
| `load` | `static ReportMedia? load(File file, {required String relativePath, String? label, SmokeVideoInfo declared = co...` | [file] as report media (a video measured with [SmokeVideo.probe], with [declared] filling what the probe cannot read); null for a file that is neither PNG nor video. |

### `mixin MediaHolder`

Media, asset badges and the video verdict shared by test cards and the cards of artifacts that match no test.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `media` | `final List<ReportMedia> media` |  |
| `usedAssets` | `final List<String> usedAssets` |  |
| `screenshots` | `List<ReportMedia> get screenshots` |  |
| `videos` | `List<ReportMedia> get videos` |  |
| `shortVideos` | `List<ReportMedia> get shortVideos` |  |
| `smallVideos` | `List<ReportMedia> get smallVideos` |  |
| `slowVideos` | `List<ReportMedia> get slowVideos` |  |
| `badVideos` | `List<ReportMedia> get badVideos` | Videos that break a smoke-video rule (too short, too small or too slow). |
| `hasPng` | `bool get hasPng` |  |
| `hasVideo` | `bool get hasVideo` |  |
| `addMedia` | `void addMedia(ReportMedia item)` | Adds [item] unless the same file is already there, keeping save order. |
| `addAssets` | `void addAssets(Iterable<String> assets)` |  |
| `screenshotPath` | `String? get screenshotPath` | The first screenshot's absolute path (the report shows them all). |
| `videoPath` | `String? get videoPath` | The first video's absolute path (the report shows them all). |
| `videoType` | `String? get videoType` |  |

### `class TestResultItem`

One test of the run, with the artifacts matched to it.

**Yapıcı Metotlar (Constructors):**

- `TestResultItem({required this.id, required this.name, required this.suite, required this.startTimeMs, this.leafName, this.backend, this.run = 0, this.category =...`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `id` | `final String id` |  |
| `name` | `String name` |  |
| `leafName` | `String? leafName` | [name] without its enclosing groups (the name passed to `test()`). |
| `suite` | `String suite` | The test file's path as `flutter test` reported it. |
| `backend` | `final String? backend` | The GPU backend it ran on; null for a package without backends. |
| `run` | `final int run` | The runner invocation (`flutter test` process) it belongs to. |
| `startTimeMs` | `int startTimeMs` |  |
| `durationMs` | `int durationMs` |  |
| `status` | `String status` | 'passed', 'failed', 'skipped' or 'running'. |
| `error` | `String? error` |  |
| `stackTrace` | `String? stackTrace` |  |
| `prints` | `final List<String> prints` |  |
| `category` | `String category` | The page it is on. |
| `isFailure` | `bool get isFailure` |  |
| `isSkipped` | `bool get isSkipped` |  |
| `isPassed` | `bool get isPassed` |  |
| `isSmoke` | `bool get isSmoke` | Whether it is a smoke test: in a smoke folder or file, named so, or carrying artifacts. |

### `class OrphanedArtifact`

Artifacts whose sidecar names no test of the report (or files no sidecar names), shown as their own card.

**Yapıcı Metotlar (Constructors):**

- `OrphanedArtifact({required this.testName, this.backend, this.category = 'Other'})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `testName` | `final String testName` | The declared test name, or the file name without its extension. |
| `backend` | `final String? backend` |  |
| `category` | `String category` | The page it is on. |
| `fileName` | `String get fileName` | The files on this card. |

### `class SmokeReportModel`

Everything a report shows.

**Yapıcı Metotlar (Constructors):**

- `SmokeReportModel({required this.tests, required this.orphanedArtifacts, required this.categories, required this.totalCount, required this.passedCount, required...`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `tests` | `final List<TestResultItem> tests` | Failures first, then passed, then skipped; by name within each. |
| `orphanedArtifacts` | `final List<OrphanedArtifact> orphanedArtifacts` |  |
| `categories` | `final List<String> categories` | The report's pages, in order. |
| `totalCount` | `final int totalCount` |  |
| `passedCount` | `final int passedCount` |  |
| `failedCount` | `final int failedCount` | Failed tests plus unmatched artifact cards with a video that breaks a smoke-video rule. |
| `skippedCount` | `final int skippedCount` |  |
| `shortVideoCount` | `final int shortVideoCount` | Videos under the minimum length, size and frame rate. |
| `smallVideoCount` | `final int smallVideoCount` |  |
| `slowVideoCount` | `final int slowVideoCount` |  |
| `artifactCount` | `final int artifactCount` |  |
| `wallDurationMs` | `final int wallDurationMs` |  |
| `timestamp` | `final DateTime timestamp` |  |
| `exitCode` | `final int exitCode` | 1 when a test of the counted runs failed, a counted run crashed, or a counted video breaks a rule; else 0. |
| `dartVersion` | `final String dartVersion` |  |
| `hasFailures` | `bool get hasFailures` |  |
| `badVideos` | `List<ReportMedia> get badVideos` | Every video that breaks a rule, with where it is. |

## `lib/src/report/paths.dart`

**Üst düzey fonksiyonlar ve değişkenler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `normalizeSmokePath` | `String normalizeSmokePath(String path)` | [path] absolute, normalised, with `/` separators and no trailing `/` (lower-cased on Windows, whose paths are case-insensitive), so prefix checks such as "inside `test/smoke`" hold on every platform. |
| `isSmokePathWithin` | `bool isSmokePathWithin(String path, String dir)` | Whether [path] is [dir] or inside it (both normalised with [normalizeSmokePath]). |
| `slashPath` | `String slashPath(String path)` | [path] with `/` separators (a Windows listing says `\`). |
| `artifactHref` | `String artifactHref(String artifactPath, String pageDir)` | The URL a page written into [pageDir] uses for the artifact at [artifactPath]: relative when both are on the same root (`../smoke_artifacts/a%20b.png`), else an absolute `file://` URI. Every path segment is percent-encoded (artifact names carry spaces and `#`). |

## `lib/src/report/process_groups.dart`

### `abstract final class SmokeProcessGroups`

Child processes of the report runner that can never outlive it: on Linux every `flutter test` run leads its own process group (via `setsid`), and the groups are killed on SIGINT / SIGTERM and before the runner exits, so no `flutter_tester` is left behind even after the flutter tool itself has exited. Elsewhere the child is started normally (`flutter` is a `.bat` on Windows, found only through the shell).

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `start` | `static Future<Process> start(String executable, List<String> arguments, {Map<String, String>? environment, Str...` | Starts [executable] with [arguments], leading its own process group on Linux (`setsid` execs in place, so the pid is the group id). |
| `signalAll` | `static void signalAll(ProcessSignal signal)` | Sends [signal] to every child group; a group that is already gone is ignored. |
| `killChildrenOnSignals` | `static void killChildrenOnSignals()` | On SIGINT / SIGTERM, terminates the child groups (SIGKILL after a grace period) and exits. Linux only; a no-op elsewhere. |
| `exitKillingChildren` | `static Never exitKillingChildren(int code)` | Kills whatever is still in a child group (an orphan of a finished run) and exits with [code]. |

## `lib/src/report/run_mode.dart`

### `class SmokeRunMode`

How a report run treats the report already in `build/`, and what it runs.

- Named test files or folders run alone and **merge**: every other file's artifacts and results stay, the re-run files' results are replaced. - A whole-suite run (no targets: the smoke folders; `--all` adds `test/` and the integration tests, `--unit-only` runs `test/`, `--integration-only` the integration smoke folders) **wipes** `build/smoke_artifacts/`, the report pages and the events file first. - `--fresh` / `--clean` wipe on purpose, even for named files. - `--merge` merges a whole-suite run; `--no-clean` / `--keep-old` keep the old files without merging their results; `--report-only` re-renders the report from the events file and touches nothing else. - `flutter test`'s scenario filters (`--plain-name`, `--name` / `-n`, `--tags` / `-t`, `--exclude-tags` / `-x`, with their value) are forwarded to every run as [filters], never taken for a target; a filtered run replaces only the scenarios it ran. - `--no-dashboard` starts no live dashboard; `--no-wait` does not keep it open at the end; `--events-file=<path>` names the events file.

**Yapıcı Metotlar (Constructors):**

- `const SmokeRunMode({required this.wipe, required this.merge, required this.targets, required this.filters, this.reportOnly = false, this.smokeOnly = true, this....`
- `factory SmokeRunMode.parse(List<String> args)`: Parses the runner's command line.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `wipe` | `final bool wipe` |  |
| `merge` | `final bool merge` |  |
| `targets` | `final List<String> targets` | The test files and folders named on the command line. |
| `filters` | `final List<String> filters` | The scenario filters, forwarded to `flutter test`. |
| `reportOnly` | `final bool reportOnly` |  |
| `smokeOnly` | `final bool smokeOnly` | No targets and neither `--all` nor `--unit-only`: the smoke folders. |
| `all` | `final bool all` |  |
| `unitOnly` | `final bool unitOnly` |  |
| `integrationOnly` | `final bool integrationOnly` |  |
| `noDashboard` | `final bool noDashboard` |  |
| `noWait` | `final bool noWait` |  |
| `eventsFile` | `final String? eventsFile` |  |
| `filter` | `String? get filter` | The filters as one string, telling a filtered run apart from a whole-file run of the same target; null without filters. |

### `enum SmokePhaseKind`

What one `flutter test` process runs.

**Değerler:**

- `unit`: Unit tests, with `flutter test`'s default concurrency.
- `smoke`: Smoke tests, one file at a time (`--concurrency=1`): the GPU and the machine are shared.
- `integration`: One integration-test file on the host's desktop device.

### `class SmokeRunPhase`

One `flutter test` process of a run.

**Yapıcı Metotlar (Constructors):**

- `const SmokeRunPhase(this.kind, this.targets, {this.backend})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `kind` | `final SmokePhaseKind kind` |  |
| `targets` | `final List<String> targets` |  |
| `backend` | `final SmokeBackend? backend` | The backend it runs on; null for a package without backends. |
| `flutterArgs` | `List<String> flutterArgs(List<String> filters)` | `flutter` arguments for this phase with [filters]. |
| `desktopDevice` | `static String get desktopDevice` | The host's desktop device for integration tests. |

**Üst düzey fonksiyonlar ve değişkenler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `smokeRunMode` | `SmokeRunMode smokeRunMode(List<String> args)` | [SmokeRunMode.parse]. |
| `planSmokeRuns` | `List<SmokeRunPhase> planSmokeRuns(SmokeRunMode mode, SmokeReportConfig config, {String? packageDir})` | The `flutter test` processes [mode] runs for a package configured by [config], in order: per backend the unit targets, then the smoke targets; then every integration file on its own. Unit targets run on the first backend only; smoke targets on every backend. `test` is expanded into its entries so the smoke folders run apart from the unit tests. Paths are relative to [packageDir] (the working directory by default). |

## `lib/src/report/runner.dart`

### `class SmokeReportPaths`

Where a report run reads and writes, from the environment: `LUMINA_SMOKE_OUT` (artifacts), `LUMINA_SMOKE_REPORT_OUT` (the index page), `LUMINA_SMOKE_EVENTS_OUT` (the events file), each also accepted under its older `FILAMENT_SMOKE_*` / `LUMINA_UI_SMOKE_*` name, defaulting to `build/smoke_artifacts`, `build/smoke_report.html` and `build/smoke_report.events.jsonl` of the working directory.

**Yapıcı Metotlar (Constructors):**

- `SmokeReportPaths({required this.artifactsDir, required this.reportFile, required this.eventsFile})`
- `factory SmokeReportPaths.fromEnvironment({String? eventsFile, Map<String, String>? environment})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `artifactsDir` | `final Directory artifactsDir` |  |
| `reportFile` | `final File reportFile` |  |
| `eventsFile` | `final File eventsFile` |  |
| `pagesDir` | `Directory get pagesDir` | The folder of the category pages next to [reportFile]. |

**Üst düzey fonksiyonlar ve değişkenler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `runSmokeReport` | `Future<int> runSmokeReport(List<String> args, SmokeReportConfig config, {SmokeReportPaths? paths, String? pack...` | `dart run tool/smoke_report.dart [targets…] [flags…]` for a package configured by [config]: runs the tests with `flutter test --machine`, on the configured GPU, and writes the report. Returns the exit code (0 when every counted test passed and every counted video meets the rules). See [SmokeRunMode] for the flags. [paths] replaces the ones from the environment; [packageDir] is the package whose tests run (the working directory by default). |
| `smokeReportMain` | `Future<Never> smokeReportMain(List<String> args, SmokeReportConfig config) async` | [runSmokeReport], then exit with its code, killing any child process left behind: the whole body of a package's `tool/smoke_report.dart`. |
| `smokeRunEnvironment` | `Map<String, String> smokeRunEnvironment(SmokeReportConfig config, {SmokeBackend? backend, required String arti...` | The environment of a run: the GPU it is pinned to (by name, and on Linux the PRIME offload variables), the artifact directory, the test assets, the backend and a throwaway configuration directory, plus the package's own [SmokeReportConfig.environment]. |
| `runFlutterMachine` | `Future<int> runFlutterMachine(List<String> args, Map<String, String> environment, {required void Function(Map<...` | Runs `flutter` with [args] and [environment], passing every `flutter test --machine` event to [onEvent] and every other line to the console (and [dashboard]). Both output streams are drained before it returns: a fast run's whole JSON output can arrive after the process exits. A run that exits non-zero without a `done` event gets one with `success: false`, so a crash is never mistaken for a pass. |
| `readSmokeEvents` | `List<Map<String, dynamic>> readSmokeEvents(File file)` | The events of an events file (one JSON object per line; bad lines are skipped). |
| `isSmokeTarget` | `bool isSmokeTarget(String target, SmokeReportConfig config)` | Whether [target] (a path relative to the package) is one of the smoke folders of [config] or inside one. |

## `lib/src/temp_dirs.dart`

### `abstract final class SmokeTempDirs`

Temporary directories of recordings a killed run left behind.

A recording streams its raw frames (≈ 4 MB each at 1366×768) into the system temp directory; a test process killed before its teardown leaves them there, and a few of them fill a per-user temp quota, after which no process can even start.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `purgeStale` | `static void purgeStale(String prefix, {Duration olderThan = const Duration(minutes: 30), bool force = false})` | Deletes the system temp directories whose name starts with [prefix] and in which nothing was written for [olderThan], once per prefix and process. A live recording appends to its frames file every frame, so it is never taken for a stale one. Directories another user owns, or that are deleted concurrently, are skipped. |
| `isStale` | `static bool isStale(Directory dir, DateTime cutoff)` | Whether nothing in [dir] was modified after [cutoff]: every file in it (recursively) is older, or, for an empty directory, the directory itself. |

## `lib/src/tools.dart`

### `abstract final class SmokeTools`

Where the `ffmpeg` / `ffprobe` executables the smoke system falls back to (when GStreamer is not installed) are found.

`LUMINA_SMOKE_FFMPEG` / `LUMINA_SMOKE_FFPROBE` (or the older `FILAMENT_SMOKE_FFMPEG` / `FILAMENT_SMOKE_FFPROBE`) name an executable file; otherwise ffprobe is looked for next to that ffmpeg, then each tool by its bare name on the PATH.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `ffmpeg` | `static String? get ffmpeg` | The ffmpeg to start, or null when there is none. |
| `ffprobe` | `static String? get ffprobe` | The ffprobe to start, or null when there is none. |
| `resetForTesting` | `static void resetForTesting()` | Forgets the resolved paths (tests that change the environment). |

## `lib/src/video.dart`

### `class SmokeVideoInfo`

What [SmokeVideo] measured of one video file.

**Yapıcı Metotlar (Constructors):**

- `const SmokeVideoInfo({this.seconds, this.width, this.height, this.fps})`

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `seconds` | `final double? seconds` | Length in seconds, or null when it could not be read. |
| `width` | `final int? width` | Frame size in pixels, or null when it could not be read. |
| `height` | `final int? height` |  |
| `fps` | `final double? fps` | Frames per second, or null when it could not be read. |
| `isComplete` | `bool get isComplete` | Whether every field is known. |
| `isEmpty` | `bool get isEmpty` | Whether nothing is known. |
| `orElse` | `SmokeVideoInfo orElse(SmokeVideoInfo other)` | This, with the fields it lacks taken from [other]. |
| `isTooShort` | `bool get isTooShort` | Whether this video is under the minimum length (or its length is unknown). |
| `isTooSmall` | `bool get isTooSmall` | Whether this video is under the minimum frame size (or its size is unknown). |
| `isTooSlow` | `bool get isTooSlow` | Whether this video is under the minimum frame rate (or its rate is unknown). |
| `breaksRule` | `bool get breaksRule` | Whether this video breaks any of the smoke-video minimums. |
| `describe` | `String get describe` | `10.00 s, 1024×768, 30 fps`, with `… unknown` for what was not read. |

### `abstract final class SmokeVideo`

The smoke-video rules and how a video is measured.

Every smoke video shows the scenario as it runs: at least [minimumSeconds] long, [minimumWidth] × [minimumHeight] or larger, [minimumFps] real frames per second or more, and no frame held longer than [maximumFrameHoldSeconds].

Plain Dart on purpose (`dart:io` and flutter_gstreamer's `dart:ffi`): the report runner uses it under `dart run`.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `minimumSeconds` | `static const double minimumSeconds` | Every smoke video runs at least this long. |
| `minimumWidth` | `static const int minimumWidth` | Every smoke video is at least this wide… |
| `minimumHeight` | `static const int minimumHeight` | …and at least this tall. |
| `minimumFps` | `static const int minimumFps` | Every smoke video plays at least this many frames per second, each a real frame of the running scene. |
| `fpsTolerance` | `static const double fpsTolerance` | Frame-rate slack for rates stored as a rounded frame duration (a 33 ms frame is 30.3 fps) or as NTSC 29.97. |
| `defaultWidth` | `static const int defaultWidth` | The size smoke renders default to: 16:9 at [minimumHeight]. |
| `defaultHeight` | `static const int defaultHeight` |  |
| `maximumFrameHoldSeconds` | `static const double maximumFrameHoldSeconds` | The longest a single frame may stay on screen: a video is frames captured while the scene runs, never one frame stretched. |
| `toleranceSeconds` | `static const double toleranceSeconds` | Container rounding: a 10 s encode reads back as 9.999999 s. |
| `isTooShort` | `static bool isTooShort(double seconds)` | Whether [seconds] is under [minimumSeconds], allowing [toleranceSeconds]. |
| `isTooSlow` | `static bool isTooSlow(double fps)` | Whether [fps] is under [minimumFps], allowing [fpsTolerance]. |
| `isTooSmall` | `static bool isTooSmall(int width, int height)` | Whether a [width] × [height] frame is under [minimumWidth] × [minimumHeight]. |
| `gstreamerAvailable` | `static bool get gstreamerAvailable` | Whether GStreamer loads in this process (then its discoverer measures videos before ffprobe is tried). |
| `probe` | `static SmokeVideoInfo probe(File file)` | Measures the video in [file]: GStreamer's discoverer (flutter_gstreamer's `MediaProbe`, in-process) when GStreamer is installed, then ffprobe, then what a WebM declares in its header (Segment Info Duration, Video PixelWidth / PixelHeight, DefaultDuration). The first complete answer wins; otherwise the fields are merged in that order. |
| `probeBytes` | `static SmokeVideoInfo probeBytes(Uint8List bytes, {String extension = 'webm'})` | [probe] for bytes not yet on disk, written to a temporary `.[extension]` file first. |
| `webmInfo` | `static SmokeVideoInfo webmInfo(Uint8List bytes)` | The Duration, and the first video track's pixel size and frame rate (DefaultDuration), a WebM / Matroska stream declares in its header; fields it does not declare are null. |

## `lib/src/video_recorder.dart`

### `class SmokeVideoRecorder`

Records a smoke video frame by frame while the scenario runs, then encodes it with [SmokeWebm.vp8QualitySettings] at the frames' own resolution.

Frames stream to a temporary file instead of piling up in memory, so a long recording costs one frame of heap. The smoke-video rules are enforced with a [StateError] naming [testName]: the constructor refuses a size under [SmokeVideo.minimumWidth] × [SmokeVideo.minimumHeight] or a rate under [SmokeVideo.minimumFps], and [finish] a video under [SmokeVideo.minimumSeconds] or one holding a frame longer than [SmokeVideo.maximumFrameHoldSeconds].

**Yapıcı Metotlar (Constructors):**

- `SmokeVideoRecorder({required this.width, required this.height, int fps = SmokeVideo.minimumFps, int? frameDurationMs, this.testName,})`: A recorder for [width] × [height] frames played at [fps] frames per second or, when [frameDurationMs] is given, each shown that many milliseconds (1000 / [frameDurationMs] fps).

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `purgeStaleSmokeTempDirs` | `static void purgeStaleSmokeTempDirs({Duration olderThan = const Duration(minutes: 30)})` | Deletes `smoke_*` temp directories in which nothing was written for [olderThan], once per process (see [SmokeTempDirs.purgeStale]). |
| `width` | `final int width` |  |
| `height` | `final int height` |  |
| `testName` | `final String? testName` |  |
| `framesPerSecond` | `double get framesPerSecond` | Frames per second the video plays at. |
| `frameCount` | `int get frameCount` | Frames recorded so far. |
| `seconds` | `double get seconds` | The length of the video so far, in seconds. |
| `longestStillSeconds` | `double get longestStillSeconds` | The longest stretch one unchanged frame stays on screen so far, in seconds. |
| `addFrame` | `void addFrame(Uint8List rgba)` | Appends one RGBA8 frame of [width] × [height]. [rgba] is copied, so a reused read-back buffer is fine. |
| `finish` | `Uint8List finish()` | Checks the smoke-video rules and encodes the recording to WebM bytes. |
| `discard` | `void discard()` | Deletes the temporary recording; safe to call more than once. |
| `sameBytes` | `static bool sameBytes(Uint8List a, Uint8List b)` | Whether [a] and [b] hold the same bytes (compared eight at a time when both are 8-byte aligned). |

## `lib/src/webm.dart`

### `abstract final class SmokeWebm`

VP8 / WebM encoding of smoke frames: in-process with GStreamer (flutter_gstreamer, [Vp8Quality.smoke]) where it is installed, else with `ffmpeg` (libvpx) using the same quality settings.

**Üyeler:**

| Üye | İmza | Açıklama |
| :--- | :--- | :--- |
| `vp8QualitySettings` | `static const List<String> vp8QualitySettings` | The VP8 encoder settings every smoke video is encoded with: constant quality near-lossless (quantizer 0–16, cq-level 6) at up to 20 Mbit/s, good-quality mode (`deadline=1000000`, `cpu-used=2`), never the realtime `deadline=1`, which is the lowest quality, and a keyframe at least every 150 frames. The same as flutter_gstreamer's [Vp8Quality.smoke]. |
| `ffmpegVp8QualitySettings` | `static const List<String> ffmpegVp8QualitySettings` | The ffmpeg (libvpx) counterpart of [vp8QualitySettings], used where GStreamer is not installed. |
| `gstreamerEncodesPng` | `static bool get gstreamerEncodesPng` | Whether GStreamer loads with every element the in-process PNG-frame encoder needs (pngdec, vp8enc, webmmux, …). |
| `gstreamerEncodesRgba` | `static bool get gstreamerEncodesRgba` | Whether GStreamer loads with every element the in-process RGBA encoder needs (appsrc, videoconvert, vp8enc, webmmux, filesink). |
| `available` | `static bool get available` | Whether any encoder is available: GStreamer or ffmpeg. |
| `encodeRawRgba` | `static ProcessResult encodeRawRgba({required String rawFrames, required String out, required int width, requir...` | Encodes the back-to-back RGBA frames in the file [rawFrames] into a VP8 WebM at [out], played at [rateNumerator] / [rateDenominator] fps (an exact rational rate, so the video runs exactly frames / rate). A GStreamer failure comes back as a non-zero exit code with the error as stderr. Throws a [ProcessException] when GStreamer is missing and ffmpeg cannot be started. |
| `encodeRawFile` | `static Uint8List encodeRawFile(File rawFrames, {required int width, required int height, required int frameDur...` | Encodes a file of back-to-back [width] × [height] RGBA frames into WebM bytes, each frame shown [frameDurationMs] (or at [framesPerSecond] when given). Throws a [StateError] when encoding fails: a smoke video is real frames or nothing, never a synthetic stand-in. |
| `encodePngFrames` | `static Uint8List encodePngFrames(List<Uint8List> pngFrames, {double fps = 30})` | Encodes PNG frames of one resolution into WebM bytes at [fps], at that resolution (no scaling; ffmpeg pads an odd side by one pixel, GStreamer keeps it). Throws a [StateError] when no encoder is available or encoding fails. |

---

[Önceki: lumina_smoke](lumina_smoke.md) | [Üst: Lumina tools dokümantasyonu](../README.tr.md)
