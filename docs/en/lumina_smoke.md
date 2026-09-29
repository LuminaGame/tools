[Türkçe](../tr/lumina_smoke.md)

# lumina_smoke

`lumina_smoke` is the smoke-test system of the Lumina packages: the evidence a smoke test publishes (PNG screenshots and VP8/WebM videos with a sidecar JSON), the rules every smoke video is checked against, the recorders that capture a running scenario, and the runner that executes `flutter test` on the right GPU and writes a linked HTML report. It is engine-independent: `flutter_filament`, `lumina` and `lumina_ui` depend on it, not the other way round.

It is engine-independent: nothing here depends on `flutter_filament`, `lumina` or `lumina_ui`; they depend on it. Videos are encoded and measured in-process with [`flutter_gstreamer`](flutter_gstreamer.md) and fall back to `ffmpeg` / `ffprobe` where GStreamer is not installed.

| Library | What it holds | Needs |
|---|---|---|
| `package:lumina_smoke/lumina_smoke.dart` | `SmokeArtifacts`, `SmokeVideo` / `SmokeVideoInfo`, `SmokeVideoRecorder`, `SmokeWebm`, `SmokePng`, `SmokeTools`, `SmokeTempDirs` | `dart:io` |
| `package:lumina_smoke/flutter.dart` | the above plus `SmokeRecorder` (records a running app) and `SmokeCapture` (widget / integration-test PNGs) | `flutter_test` |
| `package:lumina_smoke/report.dart` | `runSmokeReport` / `smokeReportMain`, `SmokeReportConfig`, `TestCategories`, `SmokeReportGenerator`, the live `SmokeDashboardServer` | `dart:io` (runs under `dart run`) |

```yaml
dependencies:
  lumina_smoke:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: lumina_smoke
```

## Requirements

- Flutter SDK with Dart `^3.12.0`.
- A video encoder: GStreamer 1.x with the base and good plugin sets (see `flutter_gstreamer`), or `ffmpeg` with libvpx. `ffmpeg` / `ffprobe` are started by name from the `PATH`; `LUMINA_SMOKE_FFMPEG` / `LUMINA_SMOKE_FFPROBE` name the executables instead.

## Artifacts

```dart
import 'package:lumina_smoke/lumina_smoke.dart';

SmokeArtifacts.saveScreenshot('camera: dolly in', png, usedAssets: ['Props/Barrels/empty_barrel.glb']);
SmokeArtifacts.saveVideo('camera: dolly in', webmBytes);                 // measured, then checked
SmokeArtifacts.saveVideoFromPngFrames('camera: dolly in', pngFrames, fps: 30);

final recorder = SmokeVideoRecorder(width: 1366, height: 768, testName: 'camera: dolly in');
for (final rgba in frames) {
  recorder.addFrame(rgba);                                               // streamed to a temp file
}
SmokeArtifacts.saveVideo('camera: dolly in', recorder.finish());
```

- Files go to `build/smoke_artifacts/` of the package under test, or to `LUMINA_SMOKE_OUT` (the runner sets it). `outputDirOverride` / `overrideDirForTesting` point a harness test at its own directory; `clear()` only works there, never on the shared directory.
- Every artifact has a sidecar `<sanitized name>.json` recording the **declared test name** (`test`), the files (`file`, `screenshot`, `video`, relative to the sidecar), the video's `durationSeconds`, `fps`, `width`, `height` (and `frameCount`), the real 3D assets used (`usedAssets`, plus every `recordAsset`), optional `metrics`, the `backend` the runner names and `savedAt`. The report matches artifacts to tests through it, never through file times.
- `testAssetsDir` is `LUMINA_TEST_ASSETS`, else the first `test-assets/` folder found walking up from the package.

### The smoke-video rules

Every smoke video shows the scenario as it runs: at least **10 s** long, at least **1024×768**, at least **30 fps** of real frames, and no frame held longer than **2 s**. `saveVideo*`, `SmokeVideoRecorder` and `SmokeRecorder` refuse a video that breaks a rule (a `StateError` naming the test) before anything is written; the report marks one it finds with red badges and counts it as a failure. A video is measured with GStreamer's discoverer, then `ffprobe`, then its WebM header.

## Recording a Flutter app

```dart
import 'package:lumina_smoke/flutter.dart';

final rec = SmokeRecorder(tester, boundary: find.byKey(boundaryKey));
await rec.hold(const Duration(seconds: 2));      // the opening state
await tester.tap(find.text('Play'));             // a step
await rec.hold(const Duration(milliseconds: 1500));
rec.save('pie: plays');                          // throws under 10 s

final png = await SmokeCapture.captureWidgetPng(tester, find.byKey(boundaryKey));
```

Frames are captured at 30 fps at no less than 1024×768 and streamed to a temporary file; recordings a killed run left behind are purged.

## The report runner

A package keeps a tiny `tool/smoke_report.dart` with its configuration:

```dart
import 'package:lumina_smoke/report.dart';

const config = SmokeReportConfig(
  title: 'My Smoke & Test Report',
  categories: TestCategories([
    ('Camera', ['camera']),
    ('Materials', ['material']),
  ]),
  backends: [SmokeBackend('opengl'), SmokeBackend('vulkan')], // optional
);

Future<void> main(List<String> args) => smokeReportMain(args, config);
```

```bash
dart run tool/smoke_report.dart                                  # the smoke folders, from a clean build/
dart run tool/smoke_report.dart --all                            # test/, the smokes and the integration tests
dart run tool/smoke_report.dart test/smoke/camera_smoke_test.dart --plain-name 'dolly'
dart run tool/smoke_report.dart <target> --fresh                 # a targeted run that starts clean
dart run tool/smoke_report.dart --report-only                    # re-render from the events file
```

| Flag | Effect |
|---|---|
| *(targets)* | Test files or folders to run; a targeted run **merges** into the existing report (other files' results and artifacts stay, the re-run files' are replaced). |
| `--plain-name`, `--name` / `-n`, `--tags` / `-t`, `--exclude-tags` / `-x` | Forwarded to `flutter test`, never taken for a target; a filtered run replaces only the scenarios it ran. |
| `--fresh` / `--clean` | Wipe `build/smoke_artifacts/`, the report pages and the events file first, even for a targeted run. |
| `--merge` | Merge a whole-suite run instead of wiping. |
| `--no-clean` / `--keep-old` | Keep the old files without merging their results. |
| `--report-only` | Re-render the report from the events file (`--events-file=<path>`); touches nothing else. |
| `--all`, `--unit-only`, `--integration-only`, `--smoke-only` | What a run without targets runs (default: the smoke folders). |
| `--no-dashboard`, `--no-wait` | No live dashboard server; do not keep it open at the end. |

- Unit tests run first with `flutter test`'s default concurrency, then the smoke files one at a time (`--concurrency=1`), then each integration test on the desktop device. With backends, the first backend runs everything and the others the smoke targets, each into `build/smoke_artifacts/<backend>/`.
- Every run is pinned to the GPU by name (`FILAMENT_GPU`, default `RTX PRO 2000`) and `CUDA_VISIBLE_DEVICES` (default `1`), plus the PRIME offload variables on Linux; it gets `LUMINA_SMOKE_OUT`, `LUMINA_TEST_ASSETS`, a throwaway `LUMINA_CONFIG_DIR` and the package's own `environment`.
- On Linux each `flutter test` leads its own process group, killed on SIGINT / SIGTERM and before the runner exits, so no `flutter_tester` outlives it.
- The report is `build/smoke_report.html` (`LUMINA_SMOKE_REPORT_OUT`) plus one page per category in `build/smoke_report/`. Every PNG and video is **linked** relative to its page, never embedded: copy `build/smoke_report*` together with `build/smoke_artifacts/` to share it. The events are kept in `build/smoke_report.events.jsonl` (`LUMINA_SMOKE_EVENTS_OUT`).
- Artifacts match their test by the declared name: the exact name (or the name inside its group), then the name ignoring case and punctuation, then a name the artifact name extends (`<test> (GPU A)`), then one containing the other, then the same `Scenario NN` of the same module, then a test of the file the artifact is named after. Artifacts that match no test get their own cards.

## Development

```bash
flutter test test/artifacts_test.dart     # each test file on its own
flutter analyze
```

`test/runner_test.dart` runs the runner for real on `test/fixtures/report_fixture.dart` (a nested `flutter test`).

The full class reference is on the [lumina_smoke API](lumina_smoke-api.md) page.

---

[Previous: lumina_mouse_capture](lumina_mouse_capture.md) | [Up: Lumina tools documentation](../README.md) | [Next: lumina_smoke API](lumina_smoke-api.md)
