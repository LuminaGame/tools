[English](README.md)

# flutter_gstreamer

[GStreamer](https://gstreamer.freedesktop.org/) 1.x için Dart FFI binding'leri. Kütüphaneler **run time'da dinamik olarak** yüklenir (native build adımı yok, link-time dependency yok). Lumina bunu smoke test videolarını PNG/RGBA frame'lerden `ffmpeg` / `gst-launch-1.0` process'i başlatmadan, in-process encode etmek için kullanır.

Saf Dart'tır: `dart test`, `flutter test` ve desktop uygulamalarda çalışır.

## Gereksinimler

Base ve good plugin set'leriyle (`vp8enc`, `webmmux`, `pngdec`, ...) kurulu bir GStreamer 1.x; bkz. [GStreamer'ın arandığı yerler](#gstreamerın-arandığı-yerler). Başka bir şey gerekmez: C toolchain ya da Filament yok.

```yaml
dependencies:
  flutter_gstreamer:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_gstreamer
```

`dart run example/encode_webm.dart [out.webm]`, üretilen 10 s'lik PNG frame'lerini VP8 WebM'e encode eder ve sonucu probe eder.

## API

```dart
import 'package:flutter_gstreamer/flutter_gstreamer.dart';

final gst = GStreamer.init();               // yoksa GStreamerNotFoundException fırlatır
print(gst.versionString);                   // GStreamer 1.28.6
GStreamer.isAvailable();                    // exception fırlatmayan kontrol
gst.hasElement('vp8enc');

// PNG frame'ler → VP8 / WebM, 30 fps (300 frame = tam 10.0 s)
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

| Tip | Görevi |
|---|---|
| `GStreamer` | yükleme + `gst_init_check`, version, `hasElement` / `requireElements`, raw `bindings` |
| `GStreamerLibraries` | shared library'leri bulur ve açar; `root` = belirli tek bir kurulum |
| `GstPipeline`, `GstElement`, `GstAppSrc` | `gst_parse_launch`, property'ler, state'ler, bus message'ları, EOS, PTS/duration'lı appsrc buffer'ları |
| `VideoEncoder`, `FrameRate`, `Vp8Quality` | `appsrc ! (pngdec !) videoconvert ! vp8enc ! webmmux ! filesink` |
| `MediaProbe`, `MediaInfo` | duration, boyut, frame rate, container / codec caps |
| `GStreamerNotFoundException` | GStreamer bulunamadı ya da yüklenemedi (fallback ya da skip için yakalayın) |
| `GStreamerException` | parse hataları, eksik element'ler, bus hataları, timeout'lar, okunamayan dosyalar |

`Vp8Quality.smoke` (varsayılan) Lumina'nın smoke video ayarıdır: `end-usage=cq cq-level=6 min-quantizer=0 max-quantizer=16 target-bitrate=20000000 deadline=1000000 cpu-used=2 keyframe-max-dist=150`; ffmpeg karşılığı `libvpx -crf 6 -b:v 20M -qmin 0 -qmax 16 -quality good -cpu-used 2 -g 150`.

Raw ffigen binding'leri (`GStreamerBindings` ve C struct/sabitleri) `package:flutter_gstreamer/bindings.dart` içindedir; prefix ile import edin.

## GStreamer'ın arandığı yerler

1. Açık bir `root` (`GStreamer.init(root: ...)`) — yalnızca o.
2. `FLUTTER_GSTREAMER_ROOT`, `GSTREAMER_1_0_ROOT_MSVC_X86_64`, `GSTREAMER_1_0_ROOT_MINGW_X86_64`, `GSTREAMER_1_0_ROOT_X86_64`.
3. Varsayılan kurulumlar — Windows: `%LOCALAPPDATA%\Programs\gstreamer\1.0\msvc_x86_64` (per-user), `%ProgramFiles%\gstreamer\1.0\msvc_x86_64`, `C:\gstreamer\1.0\msvc_x86_64` (+ `mingw_x86_64`); macOS: `/Library/Frameworks/GStreamer.framework/Versions/1.0`, `/opt/homebrew`, `/usr/local`.
4. Windows: `gstreamer-1.0-0.dll` içeren `PATH` klasörleri; Linux/macOS: sistem loader'ı (`libgstreamer-1.0.so.0`, ...).

Açılan kütüphaneler: `gstreamer-1.0`, `gstapp-1.0`, `gstpbutils-1.0`, `gobject-2.0`, `glib-2.0`. Root'lu bir kurulumda `bin` process `PATH`'ine eklenir (Windows; DLL'ler `LOAD_WITH_ALTERED_SEARCH_PATH` ile yüklenir) ve zaten set edilmemişlerse `GST_PLUGIN_SYSTEM_PATH` → `<root>/lib/gstreamer-1.0`, `GST_PLUGIN_SCANNER` → `<root>/libexec/gstreamer-1.0/gst-plugin-scanner` olur. `GST_PLUGIN_PATH`'e dokunulmaz.

Gerekli plugin'ler: `appsrc` (base/app), `videoconvert` (base), `pngdec` (good/png), `vp8enc` (good/vpx), `webmmux` (good/matroska), `filesink` (core); `requireElements` eksik olanları adıyla bildirir.

Windows 11 + GStreamer 1.28.6 (MSVC x86_64) ile test edildi. Linux ve macOS lookup'ları yazıldı ama **test edilmedi**.

## Binding'leri yeniden üretmek

`lib/src/bindings/gstreamer.g.dart` üretilmiş dosyadır ve commit'lenir. `tool/ffigen.dart` içindeki sembol listeleri değişince:

```bash
LIBCLANG_PATH=/path/to/libclang.dll dart run tool/ffigen.dart
```

Header'lar `GSTREAMER_INCLUDE_ROOT`'tan, yoksa bulunan kurulumun `include/` klasöründen (Windows kurulumları header'larla gelir), o da yoksa `/usr/include`'dan (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`) okunur. LLVM kurulu değilse `pip install --target <dir> libclang` komutu `<dir>/clang/native/libclang.dll` sağlar.

## Test'ler

```bash
dart test test/loader_test.dart test/gstreamer_test.dart test/video_encoder_test.dart
```

Gerçek GStreamer kurulumunu kullanırlar (mock yok): üretilen 300 PNG frame → WebM; 10.0 s / boyut / 30 fps / WebM içinde VP8 olarak probe edilir, `ffprobe` varsa onunla da çapraz kontrol edilir.

## Lisans

Bu paket GPL-3.0'dır (LuminaGame/tools repository lisansı). GStreamer'ın kendisi LGPL-2.1+'dır; bu paket yalnızca kullanıcının kurulu GStreamer kütüphanelerini dinamik olarak yükler, onları dağıtmaz ya da statik link etmez. Üretilen binding dosyası GStreamer'ın public C API'sini deklare eder.
