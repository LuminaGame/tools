[English](../en/flutter_gstreamer.md)

# flutter_gstreamer

`flutter_gstreamer`, sistemde kurulu GStreamer 1.x için run time'da yüklenen saf Dart bir FFI binding'idir. Lumina'nın smoke test'leri videolarını in-process encode etmek ve sonucu probe etmek için bunu kullanır.

## Lumina'daki yeri

`flutter_filament`, `lumina` ve `lumina_ui`, `SmokeArtifacts` yardımcıları için `flutter_gstreamer`'a bağımlıdır: smoke testler videolarını `ffmpeg` ya da `gst-launch-1.0` process'i başlatmadan, frame'leri in-process encode ederek kaydeder ve sonucu probe eder. GStreamer kurulu değilse `SmokeArtifacts` `ffmpeg`'e geri döner. Paket saf Dart'tır (native build adımı yok, link-time dependency yok) ve `dart test`, `flutter test` ile desktop uygulamalarda çalışır.

```yaml
dependencies:
  flutter_gstreamer:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_gstreamer
```

## Gereksinimler

Base ve good plugin set'leriyle kurulu bir GStreamer 1.x. Kullanılan element'ler: `appsrc` (base/app), `videoconvert` (base), `pngdec` (good/png), `vp8enc` (good/vpx), `webmmux` (good/matroska) ve `filesink` (core). Windows 11 + GStreamer 1.28.6 (MSVC x86_64) ile test edildi; Linux ve macOS lookup'ları yazıldı ama test edilmedi.

## Kullanım

```dart
import 'package:flutter_gstreamer/flutter_gstreamer.dart';

final gst = GStreamer.init();               // yoksa GStreamerNotFoundException fırlatır
print(gst.versionString);                   // GStreamer 1.28.6
GStreamer.isAvailable();                    // exception fırlatmayan kontrol
gst.hasElement('vp8enc');

// PNG frame'ler -> VP8 / WebM, 30 fps (300 frame = tam 10.0 s)
VideoEncoder.encodePngFrames(pngs, out: File('smoke.webm'));

// Streaming, raw RGBA
final enc = VideoEncoder.rgba(width: 1024, height: 768, out: file, frameRate: const FrameRate(30));
enc.addFrame(rgba);                         // tekrarla
enc.finish();

// Probe (GstDiscoverer)
final info = MediaProbe.probe(file);
info.durationSeconds; info.width; info.height; info.fps;
info.containerType;                         // video/webm
info.videoCodec;                            // video/x-vp8

// Herhangi bir pipeline
final p = GstPipeline.parse('videotestsrc num-buffers=30 ! vp8enc ! webmmux ! filesink name=out');
p.element('out')!.set('location', path);    // property string formundan, quoting gerekmez
p.play();
p.waitForEos();                             // bus ERROR / timeout'ta GStreamerException
p.dispose();
```

`dart run example/encode_webm.dart [out.webm]`, üretilen 10 s'lik PNG frame'lerini VP8 WebM'e encode eder ve sonucu probe eder.

## API referansı

Dosya yolları `flutter_gstreamer/` paket dizinine görelidir. Raw ffigen binding'leri (`GStreamerBindings` ve C struct/sabitleri) `package:flutter_gstreamer/bindings.dart` içindedir; prefix ile import edin.

### `lib/src/gstreamer.dart`

#### `class GStreamer`

GStreamer'ı yükler ve `gst_init_check` + `gst_pb_utils_init` çalıştırır.

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `init` | `static GStreamer init({String? root})` | GStreamer'ı yükler (bkz. [GStreamer'ın arandığı yerler](#gstreamerın-arandığı-yerler); `root` aramayı tek bir kuruluma sınırlar) ve başlatır. Idempotent'tir: sonraki çağrılar aynı instance'ı döndürür; yüklü olandan farklı bir `root` istemek `StateError` fırlatır. GStreamer yüklenemezse `GStreamerNotFoundException`, yüklenip başlatılamazsa `GStreamerException` fırlatır. Başarısızlık hiçbir şeyi cache'lemez. |
| `isAvailable` | `static bool isAvailable({String? root})` | `init`'in başarılı olup olmadığı, exception fırlatmadan. |
| `isInitialized` | `static bool get isInitialized` | `init`'in bu isolate'te başarılı olup olmadığı. |
| `instance` | `static GStreamer get instance` | Başlatılmış instance; ilk kullanımda varsayılan lookup ile başlatır. |
| `libraries` | `final GStreamerLibraries libraries` | Açılan shared library'ler. |
| `bindings` | `final GStreamerBindings bindings` | Açılan kütüphaneler üzerindeki raw binding'ler. |
| `version` | `GStreamerVersion get version` | `gst_version`. |
| `versionString` | `String get versionString` | `gst_version_string`, örneğin `GStreamer 1.28.6`. |
| `hasElement` | `bool hasElement(String factoryName)` | Bir element factory'sinin (örneğin `vp8enc`) kayıtlı, yani plugin'inin kurulu ve bulunmuş olup olmadığı. |
| `missingElements` | `List<String> missingElements(Iterable<String> factoryNames)` | `factoryNames` içinden `hasElement`'in bulamadıkları. |
| `requireElements` | `void requireElements(Iterable<String> factoryNames, {String? purpose})` | Eksik element'leri ve plugin'lerin nerede arandığını belirten bir `GStreamerException` fırlatır. |

### `lib/src/libraries.dart`

#### `class GStreamerLibraries`

GStreamer shared library'lerini bulur ve açar: `gstreamer-1.0`, `gstapp-1.0`, `gstpbutils-1.0`, `gobject-2.0` ve `glib-2.0`.

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `open` | `static GStreamerLibraries open({String? root})` | Kütüphaneleri aşağıdaki arama sırasıyla bulur ve açar. Hiçbiri bulunamazsa ya da yüklenemezse `GStreamerNotFoundException` fırlatır. |
| `root` | `final String? root` | Kütüphanelerin geldiği kurulum kökü; sistem loader'ı bulduysa null. |
| `paths` | `final List<String> paths` | Açılan kütüphane dosyaları (sistem loader'ı için yalın adlar). |
| `bindings` | `late final GStreamerBindings bindings` | Açılan kütüphanelerdeki tüm sembolleri çözen raw binding'ler. |

Kök, bir kurulum prefix'i (`bin/` ve `lib/` içerir) ya da kütüphane klasörünün kendisidir. Bir kök kullanıldığında kütüphane klasörü process `PATH`'ine eklenir (Windows; DLL'ler `LOAD_WITH_ALTERED_SEARCH_PATH` ile yüklenir) ve zaten ayarlı değillerse `GST_PLUGIN_SYSTEM_PATH` → `<root>/lib/gstreamer-1.0`, `GST_PLUGIN_SCANNER` → `<root>/libexec/gstreamer-1.0/gst-plugin-scanner` olur; böylece aynı kurulumun plugin'leri bulunur. `GST_PLUGIN_PATH`'e dokunulmaz.

### `lib/src/pipeline.dart`

#### `enum GstState`

GStreamer değerleriyle `voidPending`, `nullState`, `ready`, `paused`, `playing`; `GstState.fromValue(int)`.

#### `class GstBusMessage`

Bir pipeline'ın bus'ından alınan mesaj: `type`, `typeName`, `source` (mesajı gönderen element), `error`, `debug` ve `isEos`, `isError`, `isWarning` getter'ları.

#### `class GstPipeline`

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `parse` | `factory GstPipeline.parse(String description, {GStreamer? gstreamer})` | `gst_parse_launch`: metin tanımından bir pipeline kurar. |
| `element` | `GstElement? element(String name)` | Pipeline'ın adlandırılmış bir element'i ya da null. |
| `appSrc` | `GstAppSrc appSrc(String name)` | Adlandırılmış bir `appsrc` element'i. |
| `setState` | `void setState(GstState state)` | `state`'i ister. Değişiklik başarısız olursa (varsa bus hatasıyla birlikte) `GStreamerException` fırlatır; asenkron bir değişiklik beklenmez. |
| `play` / `pause` / `stop` | `void play()`, `void pause()`, `void stop()` | `playing`, `paused` ve `nullState` kısayolları. `stop` cihazları ve dosyaları bırakır (bir filesink dosyasını kapatır). |
| `state` | `GstState get state` | Mevcut state (bekleyen bir değişikliği beklemez). |
| `sendEos` | `void sendEos()` | Pipeline'a bir end-of-stream event'i gönderir (kendiliğinden bitmeyen kaynaklar için). |
| `pop` | `GstBusMessage? pop({...})` | Bir `GstMessageType` maskesine (varsayılan: hepsi) uyan sonraki bus mesajını, bir timeout'a kadar bekleyerek alır (null: bekleme). |
| `waitForEos` | `void waitForEos({Duration timeout = const Duration(minutes: 10)})` | End-of-stream'i bekler. Bir ERROR mesajında (gönderen element'i adlandırarak) ya da timeout dolduğunda `GStreamerException` fırlatır. |
| `throwIfError` | `void throwIfError()` | Bus'ta zaten bekleyen ilk ERROR mesajını fırlatır (beklemez). |
| `dispose` | `void dispose()` | Pipeline'ı durdurur; onu, bus'ını ve `element` ile verilen her element'i serbest bırakır. İki kez çağrılması güvenlidir. |

#### `class GstElement`

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `name` | `final String name` | Element adı. |
| `set` | `void set(String property, String value)` | Bir property'yi `gst-launch`'taki gibi string formundan ayarlar (quoting gerekmez). |
| `setAll` | `void setAll(Map<String, String> properties)` | Birden fazla property ayarlar. |

#### `class GstAppSrc`

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `element` | `final GstElement element` | Alttaki element. |
| `setCaps` | `void setCaps(String caps)` | Gönderilen buffer'ların caps'ini ayarlar. |
| `pushBuffer` | `void pushBuffer(Uint8List data, {int? ptsNs, int? durationNs})` | İsteğe bağlı presentation timestamp ve süreyle bir buffer gönderir. |
| `endOfStream` | `void endOfStream()` | Stream'in sonunu bildirir. |

### `lib/src/video_encoder.dart`

#### `enum VideoInput`, `enum VideoFormat`

`VideoInput.png` tam PNG dosyaları alır (tüm frame'ler aynı boyutta, `pngdec` ile decode edilir); `VideoInput.rgba` sıkı paketlenmiş 8-bit RGBA pikselleri alır, frame başına `width * height * 4` bayt. Tek çıktı formatı `VideoFormat.webmVp8`'dir: WebM (`webmmux`) içinde VP8 (`vp8enc`).

#### `class FrameRate`

Tam rasyonel bir frame rate: `FrameRate(numerator, [denominator = 1])`, `FrameRate.fromFps(double)`, `fps` ve `index` numaralı frame'in sunum zamanı olan `timestampNs(int index)`.

#### `class Vp8Quality`

`vp8enc` ayarları: `cqLevel` (6), `minQuantizer` (0), `maxQuantizer` (16), `targetBitrate` (20000000), `deadline` (1000000), `cpuUsed` (2), `keyframeMaxDistance` (150) ve `threads`; `properties` bunları `end-usage=cq` ile `vp8enc` property'leri olarak verir. Varsayılan olan `Vp8Quality.smoke`, Lumina'nın smoke video ayarıdır; ffmpeg karşılığı `libvpx -crf 6 -b:v 20M -qmin 0 -qmax 16 -quality good -cpu-used 2 -g 150`.

#### `class VideoEncoder`

Frame'leri `appsrc ! (pngdec !) videoconvert ! vp8enc ! webmmux ! filesink` ile in-process encode eder. `i` numaralı frame `FrameRate.timestampNs(i)` ile damgalanır; böylece `n` frame tam olarak `n / fps` saniye oynar.

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `png` | `factory VideoEncoder.png({required File out, FrameRate frameRate = const FrameRate(30), VideoFormat format, Vp8Quality quality = Vp8Quality.smoke, GStreamer? gstreamer})` | PNG dosyaları alan bir encoder. |
| `rgba` | `factory VideoEncoder.rgba({required int width, required int height, required File out, ...})` | `width` x `height` boyutunda raw RGBA frame'ler alan bir encoder. |
| `requiredElements` | `static List<String> requiredElements(VideoInput input, [VideoFormat format])` | `input` için bir encoder'ın ihtiyaç duyduğu GStreamer element'leri. |
| `input`, `out`, `frameRate` | alanlar | Encoder'ın yapılandırması. |
| `frameCount` | `int get frameCount` | Şimdiye kadar eklenen frame sayısı. |
| `addFrame` | `void addFrame(Uint8List frame)` | Bir frame ekler. |
| `finish` | `void finish({Duration timeout = const Duration(minutes: 10)})` | Stream'i bitirir ve muxer `out`'u yazıp kapatana kadar (`timeout`'a kadar) bekler. Pipeline hatası, timeout ya da boş çıktıda `GStreamerException`, hiç frame eklenmemişse `StateError` fırlatır. |
| `abort` | `void abort()` | Dosyayı bitirmeden durur; dosya eksik kalır. |
| `encodePngFrames` | `static void encodePngFrames(Iterable<Uint8List> pngFrames, {required File out, ...})` | PNG frame'lerini tek seferde encode eder. |
| `encodeRgbaFrames` | `static void encodeRgbaFrames(Iterable<Uint8List> rgbaFrames, {required int width, required int height, required File out, ...})` | RGBA frame'lerini tek seferde encode eder. |

### `lib/src/media_probe.dart`

#### `class MediaProbe`

`static MediaInfo probe(File file, {Duration timeout = const Duration(seconds: 30), GStreamer? gstreamer})`, bir medya dosyasını GStreamer'ın `GstDiscoverer`'ı ile okur (senkron, FFmpeg gerekmez). Dosya yoksa ya da okunabilir bir medya değilse `GStreamerException` fırlatır.

#### `class MediaInfo`

`durationNs`, `duration`, `durationSeconds`, `seekable`, `containerCaps`, `videoCaps`, `width`, `height`, `frameRateNumerator`, `frameRateDenominator`, `fps`, `videoBitrate`, `audioStreams` ve türetilmiş `containerType` (örneğin `video/webm`) ile `videoCodec` (örneğin `video/x-vp8`).

### `lib/src/exceptions.dart`

- `GStreamerNotFoundException(message, {searched, cause})`: GStreamer kütüphaneleri bulunamadı ya da yüklenemedi. `searched` denenenleri sırayla listeler; bir kütüphane bulunup yüklenemediyse `cause` loader hatasıdır. Başka bir encoder'a geri dönmek ya da atlamak için yakalayın.
- `GStreamerException(message, {debug, source})`: bir GStreamer çağrısı başarısız oldu (başlatma, parse edilemeyen bir pipeline tanımı, eksik bir element, bus'ta bir ERROR mesajı, bir timeout ya da discoverer'ın okuyamadığı bir dosya). `source`, hatayı gönderen element'i adlandırır.

## GStreamer'ın arandığı yerler

1. Açık bir `root` (`GStreamer.init(root: ...)`), yalnızca o.
2. `FLUTTER_GSTREAMER_ROOT`, `GSTREAMER_1_0_ROOT_MSVC_X86_64`, `GSTREAMER_1_0_ROOT_MINGW_X86_64`, `GSTREAMER_1_0_ROOT_X86_64`.
3. Varsayılan kurulumlar. Windows: `%LOCALAPPDATA%\Programs\gstreamer\1.0\msvc_x86_64` (kullanıcıya özel), `%ProgramFiles%\gstreamer\1.0\msvc_x86_64`, `C:\gstreamer\1.0\msvc_x86_64` (ve `mingw_x86_64` varyantları). macOS: `/Library/Frameworks/GStreamer.framework/Versions/1.0`, `/opt/homebrew`, `/usr/local`.
4. Windows: `gstreamer-1.0-0.dll` içeren her `PATH` klasörü. Linux ve macOS: sistem loader'ı (`libgstreamer-1.0.so.0`, ...).

## Geliştirme

`lib/src/bindings/gstreamer.g.dart` üretilmiş bir dosyadır ve commit'lenir. `tool/ffigen.dart` içindeki sembol listeleri değişince:

```bash
LIBCLANG_PATH=/path/to/libclang.dll dart run tool/ffigen.dart
```

Header'lar `GSTREAMER_INCLUDE_ROOT`'tan, yoksa bulunan kurulumun `include/` klasöründen (Windows kurulumları header'larla gelir), o da yoksa `/usr/include`'dan (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`) okunur.

Testler gerçek GStreamer kurulumunu kullanır (mock yok):

```bash
dart test test/loader_test.dart test/gstreamer_test.dart test/video_encoder_test.dart
```

---

[Önceki: flutter_riglogic](flutter_riglogic.md) | [Üst: Lumina tools dokümantasyonu](../README.tr.md) | [Sonraki: lumina_mouse_capture](lumina_mouse_capture.md)
