[English](README.md)

# lumina_smoke

[Lumina](https://github.com/LuminaGame/lumina) paketlerinin smoke test sistemi tek bir yerde: bir smoke test'in yayımladığı kanıt (sidecar JSON'lu PNG screenshot'lar ve VP8/WebM videolar), her smoke video'nun uyması gereken kurallar, çalışan bir senaryoyu kaydeden recorder'lar ve `flutter test`'i doğru GPU'da çalıştırıp link'li bir HTML rapor yazan runner.

Engine'den bağımsızdır: buradaki hiçbir şey `flutter_filament`, `lumina` ya da `lumina_ui`'ye bağlı değildir; onlar bu pakete bağlıdır. Videolar [`flutter_gstreamer`](../flutter_gstreamer/) ile process içinde encode edilir ve ölçülür; GStreamer kurulu değilse `ffmpeg` / `ffprobe` kullanılır.

| Library | İçeriği | Gereken |
|---|---|---|
| `package:lumina_smoke/lumina_smoke.dart` | `SmokeArtifacts`, `SmokeVideo` / `SmokeVideoInfo`, `SmokeVideoRecorder`, `SmokeWebm`, `SmokePng`, `SmokeTools`, `SmokeTempDirs` | `dart:io` |
| `package:lumina_smoke/flutter.dart` | yukarıdakiler, artı `SmokeRecorder` (çalışan bir app'i kaydeder) ve `SmokeCapture` (widget / integration test PNG'leri) | `flutter_test` |
| `package:lumina_smoke/report.dart` | `runSmokeReport` / `smokeReportMain`, `SmokeReportConfig`, `TestCategories`, `SmokeReportGenerator`, canlı `SmokeDashboardServer` | `dart:io` (`dart run` ile çalışır) |

```yaml
dependencies:
  lumina_smoke:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: lumina_smoke
```

## Gereksinimler

- Dart `^3.12.0` ile Flutter SDK.
- Bir video encoder: base ve good plugin set'leriyle GStreamer 1.x (bkz. `flutter_gstreamer`) ya da libvpx'li `ffmpeg`. `ffmpeg` / `ffprobe` `PATH` üzerinden adıyla başlatılır; `LUMINA_SMOKE_FFMPEG` / `LUMINA_SMOKE_FFPROBE` bunun yerine executable'ları belirtir.

## Artifact'ler

```dart
import 'package:lumina_smoke/lumina_smoke.dart';

SmokeArtifacts.saveScreenshot('camera: dolly in', png, usedAssets: ['Props/Barrels/empty_barrel.glb']);
SmokeArtifacts.saveVideo('camera: dolly in', webmBytes);                 // önce ölçülür, sonra kontrol edilir
SmokeArtifacts.saveVideoFromPngFrames('camera: dolly in', pngFrames, fps: 30);

final recorder = SmokeVideoRecorder(width: 1366, height: 768, testName: 'camera: dolly in');
for (final rgba in frames) {
  recorder.addFrame(rgba);                                               // geçici bir dosyaya stream edilir
}
SmokeArtifacts.saveVideo('camera: dolly in', recorder.finish());
```

- Dosyalar test edilen paketin `build/smoke_artifacts/` klasörüne ya da `LUMINA_SMOKE_OUT`'a (runner bunu ayarlar) yazılır. `outputDirOverride` / `overrideDirForTesting` bir harness test'ini kendi klasörüne yönlendirir; `clear()` yalnızca orada çalışır, paylaşılan klasörde asla.
- Her artifact'in bir sidecar'ı vardır: `<sanitized name>.json`. İçinde **tanımlanan test adı** (`test`), dosyalar (`file`, `screenshot`, `video`; sidecar'a göre relative), video'nun `durationSeconds`, `fps`, `width`, `height` (ve `frameCount`) değerleri, kullanılan gerçek 3D asset'ler (`usedAssets`, artı her `recordAsset`), isteğe bağlı `metrics`, runner'ın söylediği `backend` ve `savedAt` bulunur. Rapor artifact'leri test'lerle bununla eşleştirir, asla dosya zamanlarıyla değil.
- `testAssetsDir`: `LUMINA_TEST_ASSETS`, yoksa paketten yukarı doğru bulunan ilk `test-assets/` klasörü.

### Smoke video kuralları

Her smoke video senaryoyu çalışırken gösterir: en az **10 s** uzunluk, en az **1024×768**, en az **30 fps** gerçek frame, ve hiçbir frame **2 s**'den uzun ekranda kalmaz. `saveVideo*`, `SmokeVideoRecorder` ve `SmokeRecorder` bir kuralı çiğneyen video'yu hiçbir şey yazılmadan reddeder (test'i adıyla anan bir `StateError`); rapor bulduğu böyle bir video'yu kırmızı badge'lerle işaretler ve failure sayar. Video önce GStreamer'ın discoverer'ı, sonra `ffprobe`, sonra WebM header'ı ile ölçülür.

## Bir Flutter app'ini kaydetmek

```dart
import 'package:lumina_smoke/flutter.dart';

final rec = SmokeRecorder(tester, boundary: find.byKey(boundaryKey));
await rec.hold(const Duration(seconds: 2));      // açılış durumu
await tester.tap(find.text('Play'));             // bir adım
await rec.hold(const Duration(milliseconds: 1500));
rec.save('pie: plays');                          // 10 s'nin altında throw eder

final png = await SmokeCapture.captureWidgetPng(tester, find.byKey(boundaryKey));
```

Frame'ler 30 fps'te, en az 1024×768'de yakalanır ve geçici bir dosyaya stream edilir; öldürülmüş bir run'ın bıraktığı kayıtlar temizlenir.

## Report runner

Her paket, konfigürasyonunu içeren küçük bir `tool/smoke_report.dart` tutar:

```dart
import 'package:lumina_smoke/report.dart';

const config = SmokeReportConfig(
  title: 'My Smoke & Test Report',
  categories: TestCategories([
    ('Camera', ['camera']),
    ('Materials', ['material']),
  ]),
  backends: [SmokeBackend('opengl'), SmokeBackend('vulkan')], // isteğe bağlı
);

Future<void> main(List<String> args) => smokeReportMain(args, config);
```

```bash
dart run tool/smoke_report.dart                                  # smoke klasörleri, temiz bir build/ ile
dart run tool/smoke_report.dart --all                            # test/, smoke'lar ve integration test'ler
dart run tool/smoke_report.dart test/smoke/camera_smoke_test.dart --plain-name 'dolly'
dart run tool/smoke_report.dart <target> --fresh                 # temiz başlayan targeted run
dart run tool/smoke_report.dart --report-only                    # events dosyasından yeniden render
```

| Flag | Etkisi |
|---|---|
| *(target'lar)* | Çalıştırılacak test dosyaları ya da klasörleri; targeted run mevcut rapora **merge** edilir (diğer dosyaların sonuçları ve artifact'leri kalır, yeniden çalışan dosyalarınkiler değişir). |
| `--plain-name`, `--name` / `-n`, `--tags` / `-t`, `--exclude-tags` / `-x` | `flutter test`'e iletilir, asla target sanılmaz; filtreli run yalnızca çalıştırdığı senaryoların yerini alır. |
| `--fresh` / `--clean` | Önce `build/smoke_artifacts/`, rapor sayfaları ve events dosyası silinir, targeted run'da bile. |
| `--merge` | Tüm suite run'ını silmek yerine merge eder. |
| `--no-clean` / `--keep-old` | Eski dosyaları tutar, sonuçlarını merge etmez. |
| `--report-only` | Raporu events dosyasından (`--events-file=<path>`) yeniden render eder; başka hiçbir şeye dokunmaz. |
| `--all`, `--unit-only`, `--integration-only`, `--smoke-only` | Target'sız bir run'ın ne çalıştırdığı (varsayılan: smoke klasörleri). |
| `--no-dashboard`, `--no-wait` | Canlı dashboard server yok; sonunda açık tutulmaz. |

- Önce unit test'ler `flutter test`'in varsayılan concurrency'siyle, sonra smoke dosyaları tek tek (`--concurrency=1`), sonra her integration test desktop device'ta çalışır. Backend'ler varsa ilk backend her şeyi, diğerleri smoke target'larını çalıştırır; her biri `build/smoke_artifacts/<backend>/` klasörüne yazar.
- Her run GPU'ya adıyla (`FILAMENT_GPU`, varsayılan `RTX PRO 2000`) ve `CUDA_VISIBLE_DEVICES` (varsayılan `1`) ile sabitlenir, Linux'ta PRIME offload değişkenleri de eklenir; ayrıca `LUMINA_SMOKE_OUT`, `LUMINA_TEST_ASSETS`, geçici bir `LUMINA_CONFIG_DIR` ve paketin kendi `environment`'ı verilir.
- Linux'ta her `flutter test` kendi process group'unu yönetir; bu group'lar SIGINT / SIGTERM'de ve runner çıkmadan önce öldürülür, böylece hiçbir `flutter_tester` geride kalmaz.
- Rapor `build/smoke_report.html` (`LUMINA_SMOKE_REPORT_OUT`) artı `build/smoke_report/` içinde kategori başına bir sayfadır. Her PNG ve video sayfasına göre relative olarak **link'lenir**, asla embed edilmez: paylaşmak için `build/smoke_report*`'u `build/smoke_artifacts/` ile birlikte kopyalayın. Event'ler `build/smoke_report.events.jsonl`'de (`LUMINA_SMOKE_EVENTS_OUT`) tutulur.
- Artifact'ler test'lerine tanımlanan adla eşleşir: önce birebir ad (ya da group içindeki ad), sonra büyük/küçük harf ve noktalama farkı gözetmeyen ad, sonra artifact adının uzattığı bir ad (`<test> (GPU A)`), sonra biri diğerini içeren ad, sonra aynı modülün aynı `Scenario NN`'i, en son da artifact'in adını aldığı dosyanın bir test'i. Hiçbir test'le eşleşmeyen artifact'ler kendi kartlarını alır.

## Geliştirme

```bash
flutter test test/artifacts_test.dart     # her test dosyası kendi başına
flutter analyze
```

`test/runner_test.dart`, runner'ı `test/fixtures/report_fixture.dart` üzerinde gerçekten çalıştırır (iç içe bir `flutter test`).

## Lisans

GPL-3.0 ([LICENSE](LICENSE) dosyasına bakın).
