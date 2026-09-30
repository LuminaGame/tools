[English](README.md)

# lumina_mouse_capture

Lumina oyunları ve Play-In-Editor için pointer capture: mouse oyundayken pointer gizlenir ve yerinde tutulur, mouse ise ne kadar hareket ettiğini bildirmeye devam eder.

- **Wayland**: GDK'nın kendi Wayland bağlantısı üzerinde `zwp_pointer_constraints_v1.lock_pointer` (one-shot) ve `zwp_relative_pointer_v1.relative_motion`.
- **X11**: toplevel pencerede seat grab, merkeze warp ve offset'i okuyup geri warp eden 4 ms'lik bir poll.
- **Windows**: hareket için raw mouse input (`WM_INPUT`); imleç gizlenir ve capture merkezinde bir piksele clip edilir (`ClipCursor`); focus kaybı, minimize ve pencerenin kapanması pointer'ı geri verir.
- **Diğer platformlar ve web**: capture yok; yerine bir recording backend cevap verir.

Linux (`linux/`, GTK) ve Windows (`windows/`, Win32) implementasyonları olan bir Flutter plugin'idir.

## Gereksinimler

- Dart `^3.12.0` içeren Flutter SDK.
- Windows: Windows 10 ya da sonrası ve C++ workload'lu Visual Studio 2022 (her Flutter Windows uygulamasında olduğu gibi).
- Linux: GTK 3 (her Flutter Linux uygulamasında olduğu gibi). Wayland pointer lock için ayrıca `wayland-client`, `wayland-scanner` ve `wayland-protocols` (pointer-constraints ve relative-pointer); bunlar yoksa plugin yine build olur ve Wayland desteği olmadığını bildirir.

```yaml
dependencies:
  lumina_mouse_capture:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: lumina_mouse_capture
```

## Kullanım

Her şey tek bir seam'den geçer: `LuminaMouseCapture.backend`.

```dart
import 'package:lumina_mouse_capture/lumina_mouse_capture.dart';

final capture = LuminaMouseCapture.backend;

final support = await capture.support();
// support.kind: wayland, x11, windows, unsupported, disabled ya da recording
// support.pointerLock / support.relativeMotion / support.detail

final sub = capture.events.listen((event) {
  switch (event) {
    case MouseCaptureMotion(:final dx, :final dy):
      // capture sırasında relative hareket
    case MouseCaptureLocked():
      // compositor lock'u onayladı
    case MouseCaptureLost(:final reason):
      // focus kaybı ya da compositor capture'ı bitirdi (Windows: reason
      // focus, minimized ya da window)
  }
});

await capture.capture(centre: const Offset(640, 360)); // logical view koordinatları
// ...
await capture.release();
await sub.cancel();
```

`support.relativeMotion` false ise delta'ları kendi pointer event'lerinizden okuyun. `support.pointerLock` true ise tıklamalar pointer'ın tutulduğu yere düşer; bu yüzden host, capture sırasında kendi UI'ını korumalıdır.

### Recording backend

`LuminaMouseCapture.chooseDefault` şu durumlarda request'leri kaydeden ve pointer'a hiç dokunmayan `RecordingMouseCaptureBackend`'i seçer:

- `LUMINA_MOUSE_CAPTURE` değeri `off` ya da `record` ise (native taraf da bu değişken varken lock yapmayı reddeder);
- bir Flutter test binding'i çalışıyorsa (`flutter test`, `integration_test`);
- uygulama web'de ya da Linux ve Windows dışında bir platformda çalışıyorsa.

Diğer durumlarda `MethodChannelMouseCaptureBackend` kullanılır. Test'ler kendi backend'lerini atayabilir (`LuminaMouseCapture.backend = RecordingMouseCaptureBackend()`) ve `emitMotion(dx, dy)` / `emitLost([reason])` ile event besleyebilir.

## Development

```bash
flutter test test/mouse_capture_test.dart test/windows_native_test.dart
```

`example/`, pointer'ı gerçek plugin üzerinden capture eder (C pencere merkezinde capture eder, F4 bırakır, bir tıklama yeniden capture eder) ve her capture event'ini stdout'a bir JSON satırı olarak yazar. `tool/nested_compositor/` native tarafı masaüstüne dokunmadan gerçekten test eder: `nested_session.py` izole, headless bir GNOME Shell başlatır (private D-Bus, software rendering, input Mutter'ın RemoteDesktop API'si üzerinden) ve `build_probe.sh`, capture core'unu sade bir GTK penceresinde çalıştıran `capture_probe`'u build eder. Engine'in input smoke test'i example uygulamasını aynı nested session içinde çalıştırır.

Windows'ta `test/windows_native_test.dart`, `windows/test/`'i CMake ile (`PATH`'ten ya da Visual Studio'dan) build eder ve capture state machine'ini sahte bir OS katmanına karşı çalıştırır: test executable'ı Win32 katmanını link etmez, bu yüzden pointer'ı clip edemez, gizleyemez ya da hareket ettiremez. `example/` içinde `flutter build windows` plugin'i derler. `example/integration_test/real_pointer_capture_test.dart` gerçek plugin'i gerçek pointer üzerinde test eder ve yalnızca isteğe bağlıdır: `LUMINA_MOUSE_CAPTURE_REAL_TEST=1` olmadıkça atlanır ve makinenin başındaki kişi tarafından çalıştırılmak içindir:

```powershell
cd example
$env:LUMINA_MOUSE_CAPTURE_REAL_TEST = '1'
flutter test integration_test/real_pointer_capture_test.dart -d windows --dart-define=LUMINA_MOUSE_CAPTURE_REAL_TEST=1
```

Her adımı yazdırır (pencereye tıkla, mouse'u hareket ettir, Alt+Tab ile başka pencereye geç) ve her capture'dan sonra en geç 15 saniye içinde pointer'ı bırakır.

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)).
