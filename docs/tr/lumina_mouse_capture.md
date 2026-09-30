[English](../en/lumina_mouse_capture.md)

# lumina_mouse_capture

`lumina_mouse_capture`, Lumina oyunları ve Play-In-Editor için pointer'ı capture eden bir Flutter plugin'idir: mouse oyundayken pointer gizlenir ve yerinde tutulur, mouse ise relative hareketi bildirmeye devam eder.

## Lumina'daki yeri

`lumina` ve `lumina_ui`, Play-In-Editor'da çalışan ya da yayınlanmış bir oyun mouse'u ele aldığında bu plugin'i kullanır: pointer gizlenir ve yerinde tutulur, mouse ise ne kadar hareket ettiğini bildirmeye devam eder. Her test, smoke test ve harness çalıştırması bunun yerine bir recording backend kullanır; böylece hiçbir çalıştırma makinenin başındaki kişinin pointer'ını kilitleyemez, grab edemez ya da warp edemez.

```yaml
dependencies:
  lumina_mouse_capture:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: lumina_mouse_capture
```

## Platformlar

- **Wayland**: GDK'nın kendi Wayland bağlantısı üzerinde `zwp_pointer_constraints_v1.lock_pointer` (one-shot) ve `zwp_relative_pointer_v1.relative_motion`.
- **X11**: toplevel pencerede seat grab, merkeze warp ve offset'i okuyup geri warp eden 4 ms'lik bir poll.
- **Windows**: hareket için raw mouse input (`WM_INPUT`); imleç gizlenir ve capture merkezinde bir piksele clip edilir (`ClipCursor`); focus kaybı, minimize ve pencerenin kapanması pointer'ı geri verir.
- **Diğer platformlar ve web**: capture yok; yerine recording backend cevap verir.

Linux implementasyonu (`linux/`, GTK) GTK 3 ve Wayland pointer lock için `wayland-client`, `wayland-scanner` ve `wayland-protocols` (pointer-constraints ve relative-pointer) gerektirir. Bunlar yoksa plugin yine build olur ve Wayland desteği olmadığını bildirir.

### Windows

`windows/`, top-level pencere için raw mouse input kaydeder (legacy mouse mesajları açık kalır; Flutter tıklamaları ve tekerleği almaya devam eder) ve bunu bir top-level window proc delegate'i üzerinden alır. `capture` sırasında imlecin nerede olduğunu hatırlar, imleci gizler ve istenen merkezde bir piksele clip eder (view'in DPI'ı ile ölçeklenen logical view koordinatları, virtual-screen koordinatlarında; böylece her monitörde çalışır). `WM_INPUT` raporları her message-loop turunda tek bir `motion` event'i olur, logical piksel cinsinden; bunlar ivmelendirilmemiş cihaz sayımlarıdır (varsayılan pointer hızında yaklaşık bir fiziksel piksel). Absolute cihazlar (remote desktop, tablet, bazı sanal makineler) konum bildirir; bunlar delta'ya çevrilir. Capture için pencerenin foreground'da olması gerekir. Deaktivasyon (`WM_ACTIVATE`, `WM_ACTIVATEAPP`) capture'ı `focus` nedenli bir `lost` ile, minimize `minimized` ile, pencerenin yok edilmesi `window` ile bitirir; ekran ve DPI değişiklikleri clip'i taşır. Her bitiş (release, kayıp, plugin teardown) clip'i kaldırır, imleci gösterir, eski yerine koyar ve raw input kaydını tam bir kez siler. Plugin tuşlarla ilgilenmez (Escape ile bırakma yok): tuşlar oyunun ya da Play-In-Editor'ın. Native taraf, Linux'ta olduğu gibi `LUMINA_MOUSE_CAPTURE=off|record` varken capture yapmayı reddeder.

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

## API referansı

Dosya yolları `lumina_mouse_capture/` paket dizinine görelidir.

### `lib/lumina_mouse_capture.dart`

#### `abstract final class LuminaMouseCapture`

Process genelindeki mouse capture seam'i.

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `environmentVariable` | `static const String environmentVariable = 'LUMINA_MOUSE_CAPTURE'` | Her capture'ı pointer'dan uzak tutmak için `off` (ya da `record`) değerine ayarlanır. Test harness'ları bunu export eder; native plugin de kontrol eder. |
| `backend` | `static MouseCaptureBackend get backend` / `set backend(...)` | Her çağıranın kullandığı backend. İlk okuma varsayılan backend'i oluşturur (platform backend'inde bir hot restart'ın geride bıraktığı capture'ı da bırakır); bir backend atamak onu değiştirir. |
| `defaultBackendReason` | `static String? get defaultBackendReason` | Varsayılan backend'in neden seçildiği; bir backend atandıysa null. |
| `chooseDefault` | `static MouseCaptureBackendChoice chooseDefault({Map<String, String>? environment, bool? isTestBinding, TargetPlatform? platform, bool isWeb})` | Varsayılan kural: `LUMINA_MOUSE_CAPTURE=off` ya da `record` recording backend'i verir; bir Flutter test binding'i (`flutter test`, `integration_test`), web ya da Linux ve Windows dışındaki her platform da öyle; diğer durumlarda platform channel. |

#### `class MouseCaptureBackendChoice`

`chooseDefault`'un hangi backend'i neden seçtiği: `reason` (`test binding`, `LUMINA_MOUSE_CAPTURE=off`, `web`, `unsupported platform` ya da `platform channel`), `usesPlatform` ve seçilen türde yeni bir backend döndüren `createBackend()`.

### `lib/src/mouse_capture_backend.dart`

#### `abstract class MouseCaptureBackend`

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| `support` | `Future<MouseCaptureSupport> support()` | Bu backend'in bu makinede neler yapabildiği. |
| `capture` | `Future<bool> capture({Offset? centre})` | Pointer'ı capture eder. `centre`, Flutter view'inin logical koordinatlarındadır: X11'de pointer oraya warp edilir, Wayland'de bırakıldığında pointer'ın yeniden göründüğü yerdir, Windows'ta imleç orada tutulur (ve bırakılınca eski yerine döner). Bir capture istenip istenmediğini döndürür. |
| `release` | `Future<void> release()` | Pointer'ı bırakır; capture yoksa bir şey yapmaz. |
| `events` | `Stream<MouseCaptureEvent> get events` | Hareket, lock onayları ve kayıplar. |

#### `enum MouseCaptureBackendKind`

`wayland` (GDK bağlantısı üzerinde pointer constraints ve relative pointer), `x11` (merkeze warp'lı seat grab), `windows` (imleci gizlenip capture merkezine clip edilen raw input), `unsupported` (capture yolu yok ya da plugin bu uygulamaya build edilmemiş), `disabled` (`LUMINA_MOUSE_CAPTURE` `off` ya da `record` olduğu için native taraf reddetti), `recording` (istekler kaydedilir, pointer'a hiç dokunulmaz).

#### `class MouseCaptureSupport`

`kind`; `pointerLock`, bir capture'ın pointer'ı gerçekten tutup tutmadığı (pencereden çıkamaz ve tıklamalar tutulduğu yere düşer); `relativeMotion`, `MouseCaptureMotion` event'lerinin mouse hareketini taşıyıp taşımadığı; `detail`, nedenini kelimelerle. `MouseCaptureSupport.none` desteklenmeyen değerdir.

#### `sealed class MouseCaptureEvent`

- `MouseCaptureMotion(dx, dy)`: capture sırasında mouse (`dx`, `dy`) logical piksel hareket etti; tutulan pointer'ın kenarlara uzaklığından bağımsızdır.
- `MouseCaptureLocked()`: platform lock'u onayladı (Wayland'in `locked` event'i).
- `MouseCaptureLost([String? reason])`: capture istenmeden bitti: pencere focus'u kaybetti, compositor lock'u kırdı ya da pencere kapandı. `reason` Windows'ta `focus`, `minimized` ya da `window`, Linux'ta null'dır; eşitliğe dahildir.

### `lib/src/method_channel_backend.dart`

#### `class MethodChannelMouseCaptureBackend`

Native backend (`linux/lumina_mouse_capture_plugin.cc`, `windows/lumina_mouse_capture_plugin.cpp`). `lumina_mouse_capture` method channel'ı `support`'a `{kind, pointerLock, relativeMotion, detail}`, `capture`'a bir bool (isteğe bağlı `{x, y}`) ile ve `release`'e cevap verir; `lumina_mouse_capture/events` event channel'ı `{type: motion, dx, dy}`, `{type: locked}` ve `{type: lost}` gönderir (Windows `reason` ekler). Eksik bir plugin (yeniden build edilmemiş bir uygulama, plugin'i olmayan bir platform) exception fırlatılmadan `unsupported` olarak bildirilir.

### `lib/src/recording_backend.dart`

#### `class RecordingMouseCaptureBackend`

Pointer'a hiç dokunmayan bir backend: isteneni kaydeder; `emitMotion` / `emitLost` ise native tarafın kullandığı aynı event yolunu çalıştırır.

| Üye | İmza | Görevi |
| :--- | :--- | :--- |
| constructor | `RecordingMouseCaptureBackend({bool simulateLock = false})` | `simulateLock` ile `support` relative hareketli bir lock bildirir ve her capture `MouseCaptureLocked` ile onaylanır; o olmadan lock'u olmayan bir platformun gizli imleç fallback'i gibi davranır. |
| `requests` | `final List<String> requests` | Her istek, sırayla: `capture(640.0,360.0)`, `capture()`, `release`. |
| `lastCentre` | `Offset? lastCentre` | Son capture isteğinin merkezi. |
| `isCaptured` | `bool get isCaptured` | Bir capture'ın yürürlükte olup olmadığı (istendi ve bırakılmadı ya da kaybedilmedi). |
| `emitMotion` | `void emitMotion(double dx, double dy)` | Compositor'ın yapacağı gibi relative bir hareket bildirir. |
| `emitLost` | `void emitLost([String? reason])` | Capture'ın alındığını bildirir (focus kaybı, Alt+Tab); platform bir neden verdiyse onunla. |

## Geliştirme

```bash
flutter test test/mouse_capture_test.dart test/windows_native_test.dart
```

`example/`, pointer'ı gerçek plugin üzerinden capture eder (C pencere merkezinde capture eder, F4 bırakır, bir tıklama yeniden capture eder) ve her capture event'ini stdout'a bir JSON satırı olarak yazar. `tool/nested_compositor/` native tarafı masaüstüne dokunmadan test eder: `nested_session.py` izole, headless bir GNOME Shell başlatır (private D-Bus, software rendering, input Mutter'ın RemoteDesktop API'si üzerinden) ve `build_probe.sh`, capture core'unu sade bir GTK penceresinde çalıştıran `capture_probe`'u build eder. Engine'in input smoke testi example uygulamasını aynı nested session içinde çalıştırır.

Windows'ta `test/windows_native_test.dart`, `windows/test/`'i CMake ile (`PATH`'ten ya da Visual Studio'dan) build eder ve capture state machine'ini sahte bir OS katmanına karşı çalıştırır: test executable'ı Win32 katmanını link etmez, bu yüzden pointer'ı clip edemez, gizleyemez ya da hareket ettiremez. `example/` içinde `flutter build windows` plugin'i derler. `example/integration_test/real_pointer_capture_test.dart` gerçek plugin'i gerçek pointer üzerinde test eder ve yalnızca isteğe bağlıdır: `LUMINA_MOUSE_CAPTURE_REAL_TEST=1` olmadıkça atlanır ve makinenin başındaki kişi tarafından çalıştırılmak içindir:

```powershell
cd example
$env:LUMINA_MOUSE_CAPTURE_REAL_TEST = '1'
flutter test integration_test/real_pointer_capture_test.dart -d windows --dart-define=LUMINA_MOUSE_CAPTURE_REAL_TEST=1
```

Her adımı yazdırır (pencereye tıkla, mouse'u hareket ettir, Alt+Tab ile başka pencereye geç) ve her capture'dan sonra en geç 15 saniye içinde pointer'ı bırakır.

---

[Önceki: flutter_gstreamer](flutter_gstreamer.md) | [Üst: Lumina tools dokümantasyonu](../README.tr.md) | [Sonraki: lumina_smoke](lumina_smoke.md)
