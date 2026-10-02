[English](../en/flutter_kimodo.md)

# flutter_kimodo

NVIDIA'nın Kimodo metinden hareket modelinin GGML portu [kimodo.cpp](https://github.com/localai-org/kimodo.cpp) için
Dart FFI binding'leri. "a person walks forward and waves" gibi bir prompt, Kimodo'nun 30 eklemli SOMA iskeletinde 30 fps
bir harekete dönüşür. Lumina Kimodo eklentisi bunu skeletal mesh'lere retarget eder; bu paket yalnızca üretir.

## İçerik

| Parça | Yer | Görevi |
|---|---|---|
| Hazır runtime | `third_party/kimodo/prebuilt/<VERSION>/<os>-x64/` (gitignore'da) | `kimodo.dll` / `libkimodo.so` ve ggml backend'leri; sabitlenmiş commit'ten `tool/build_kimodo.*` build eder |
| Ek giriş noktaları | `native/kimodo_lumina.{h,cpp}` | kimodo kütüphanesinin **içine** derlenir: çok promptlu diziler (`kimodo_lumina_generate_sequence`), backend seçimi (`kimodo_lumina_configure`), build'deki backend'ler |
| Yükleyici wrapper | `src/flutter_kimodo.{h,c}` | native-assets hook'u build eder; kimodo'yu çalışma anında kendi klasöründen yükler ve çağrıları ona iletir; Vulkan cihazlarını listeler |
| Dart API | `lib/flutter_kimodo.dart` | `KimodoRuntime`, `KimodoModel`, `KimodoMotion`, `KimodoModelFiles`, `KimodoPrebuilt` |

Wrapper'ın kimodo'ya link-time bağımlılığı yoktur: Windows, path ile yüklenen bir DLL'in kendi import'larını yanında
aramaz; bu yüzden wrapper `kimodo.dll`'i değiştirilmiş arama yoluyla yükler ve ggml DLL'leri aynı klasörden bulunur.
Hook runtime'ı wrapper'ın yanına kopyalar ve her kütüphaneyi paketlenen bir code asset olarak bildirir; böylece
`flutter test`, `flutter run` ve build edilen uygulamalar onu taşır.

## Runtime'ı build etmek

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_kimodo.ps1 [-Vulkan auto|on|off] [-Clean]
```

```bash
bash tool/build_kimodo.sh [--vulkan auto|on|off] [--clean]
```

Script `tool/kimodo/UPSTREAM` (repository + commit) ve ggml submodule'ünü `third_party/kimodo/src` altına çeker,
`tool/kimodo/CMakeLists.txt` üzerinden build eder (CMake ≥ 3.25, Ninja; Windows: Visual Studio 2022 x64, dinamik CRT
`/MD`), kütüphaneleri, `kimodo.lib`'i, header'ları, lisansları ve `lumina-kimodo.json` (köken bilgisi) dosyasını
toplar, `third_party/kimodo/dist/kimodo-<VERSION>-<os>-x64.{zip,tar.gz}` arşivini `.sha256` dosyasıyla birlikte
paketler ve hook'un okuduğu klasöre kurar. İlk CPU build'i birkaç dakika sürer.

- **Vulkan**: `auto`, [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) kuruluysa (`VULKAN_SDK`, `glslc`) ggml Vulkan
  backend'ini build eder, değilse yalnızca CPU backend'ini; `on` SDK yoksa hata verir.
- **Sürüm**: `tool/kimodo/VERSION` (`<commit>-lumina.<n>`). Commit, `native/kimodo_lumina.cpp`, build flag'leri ya da
  toolchain değişince `-lumina.N` sonekini artırın.
- **Build yerine indirmek**: `dart run tool/fetch_prebuilt.dart`, `dist/` içindeki arşivi (yerel build) kurar ya da
  tools repository'sinin `kimodo-<VERSION>` release'inden `kimodo-<VERSION>-<os>-x64.*` dosyasını indirir, SHA-256'sını
  doğrular ve klasörü yazdırır.

Hook klasörü önce `kimodo_dir` user-define'ından (workspace root pubspec, ona göre relative), sonra `LUMINA_KIMODO_DIR`
değişkeninden (yalnızca hook doğrudan çalıştırılınca), sonra yukarıdaki paket varsayılanından alır; hiçbirinde
kütüphane yoksa bu talimatlarla hata verir.

## Model dosyaları

Ağırlıklar paketin ya da herhangi bir Lumina repository'sinin parçası **değildir**: birkaç GB'tır ve lisansları (SOMA
modeli için NVIDIA Open Model License, metin kodlayıcı için Meta Llama 3 Community License) kullanıcının kabulünü
gerektirir. Onları Kimodo eklentisi indirir. `KimodoModelFiles.find(dir)` şunları bulur:

- `kimodo-soma-rp-v1.1-f32.gguf` (hareket modeli, yaklaşık 1,1 GB);
- `Llama-3-Kimodo-Q4_K_M.gguf` (varsayılan, yaklaşık 5 GB) ya da `Llama-3-Kimodo-Q8_0.gguf` (yaklaşık 8 GB); aynı
  klasörde `tokenizer.gguf` ile.

`KimodoModelFiles.defaultDirectory()`: `KIMODO_MODELS_DIR`, yoksa `<Lumina verisi>/plugin_data/lumina_plugin_kimodo/models`.

## Kullanım

```dart
import 'package:flutter_kimodo/flutter_kimodo.dart';

final files = KimodoModelFiles.find(KimodoModelFiles.defaultDirectory())!;
final model = await KimodoModel.load(
  motionGguf: files.motion,
  textGguf: files.text,
  backend: const KimodoBackend(vulkanDeviceName: 'RTX PRO 2000'),
);
final walk = await model.generate(
  'a person walks forward',
  frames: 150, // 5 sn; en çok 300
  options: const KimodoGenerationOptions(seed: 7, diffusionSteps: 100, textCfg: 2),
);
final sequence = await model.generateSequence(const [
  KimodoSegment('a person walks forward', 90),
  KimodoSegment('a person sits down on a chair', 120),
], transitionFrames: 5);
await model.dispose();
```

- `KimodoModel` kendi isolate'inde yaşar: yükleme ve üretim saniyeler (GPU) ile dakikalar (CPU) arasında bloklar, bu
  yüzden çağıranın isolate'inde asla çalışmaz. İstekler sırayla, teker teker çalışır.
- `KimodoMotion`: `frames`, `joints` (30), `localRotationsXyzw` (`[frames, joints, 4]`, parent-local, birim = dinlenme
  T-pozu), `rootPositions` (`[frames, 3]`, kalça, metre). Koordinatlar: Y yukarı, +Z ileri; kök X = Z = 0'da, +Z'ye
  bakarak başlar; 30 fps.
- Hatalar kimodo'nun nedenini taşıyan `KimodoException`'lardır, örneğin
  `Loading the Kimodo model failed: cannot open GGUF file (motion: …)`.

## Cihaz seçimi

kimodo.cpp backend'ini environment'tan okur; ggml ise Vulkan cihaz listesini süreç başına bir kez, ilk model
yüklemesinde okur. `KimodoRuntime.configure(KimodoBackend(...))` (`KimodoModel.load` çağırır) bunları ondan önce ayarlar:

| `KimodoBackend` | Etkisi |
|---|---|
| `device: KimodoDevice.auto` | Build'de Vulkan varsa ve bir cihaz bulunursa Vulkan, yoksa CPU |
| `device: KimodoDevice.cpu` | `KIMODO_BACKEND=cpu` |
| `threads: n` | `KIMODO_THREADS=n` (0 = tüm çekirdekler) |
| `vulkanDeviceName: 'RTX PRO 2000'` | adı bunu içeren ilk cihaz, `vkEnumeratePhysicalDevices` sırasındaki index'iyle (`GGML_VK_VISIBLE_DEVICES`) |

`KimodoBackend.fromEnvironment()` (varsayılan) `KIMODO_DEVICE`, `KIMODO_THREADS` ve `KIMODO_VULKAN_DEVICE` değişkenlerini,
sonra `FILAMENT_GPU`'yu okur; böylece kimodo, Lumina'nın render ettiği GPU'da çalışır. `KimodoRuntime.vulkanDevices()`
cihazları sistemin Vulkan loader'ı üzerinden listeler (SDK gerekmez). Sonraki bir `configure` CPU / Vulkan seçimini ve
thread sayısını değiştirir, cihazı değiştirmez.

## Testler

```bash
flutter test test/kimodo_runtime_test.dart test/kimodo_model_test.dart test/kimodo_prebuilt_test.dart
```

Gerçek native kütüphaneyi çağırırlar. Üretim testleri GGUF dosyaları `KIMODO_MODELS_DIR` (ya da eklentinin model
klasörü) içinde olana kadar atlanır, dosyalar gelince çalışır. Binding'ler ffigen tarzında yazılmıştır;
`dart run tool/ffigen.dart` ile yeniden üretilir (libclang gerekir); `test/bindings_lockstep_test.dart` onları
header'larla uyumlu tutar.

## Lisanslar

Paket, repository gibi GPL-3.0'dır. Hazır runtime `licenses/` altında kimodo.cpp (Apache-2.0, NOTICE ile) ve ggml
(MIT) lisanslarını taşır; `src/kimodo/kimodo_capi.h` kimodo.cpp'den alınmıştır (Apache-2.0). Model ağırlıkları asla
paketlenmez.

---

[Önceki: flutter_riglogic](flutter_riglogic.md) · [İçindekiler](../README.tr.md)
