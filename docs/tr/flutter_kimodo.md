[English](../en/flutter_kimodo.md)

# flutter_kimodo

NVIDIA'nın Kimodo metinden hareket modelinin GGML portu [kimodo.cpp](https://github.com/localai-org/kimodo.cpp) için
Dart FFI binding'leri. "a person walks forward and waves" gibi bir prompt, Kimodo'nun 30 eklemli SOMA iskeletinde 30 fps
bir harekete dönüşür. Lumina Kimodo eklentisi bunu skeletal mesh'lere retarget eder; bu paket yalnızca üretir.

## İçerik

| Parça | Yer | Görevi |
|---|---|---|
| Hazır runtime | `third_party/kimodo/prebuilt/<VERSION>/<os>-x64/` (gitignore'da) | `kimodo.dll` / `libkimodo.so` ve ggml backend'leri; sabitlenmiş commit'ten `tool/build_kimodo.*` build eder |
| Ek giriş noktaları | `native/kimodo_lumina.{h,cpp}` | kimodo kütüphanesinin **içine** derlenir: çok promptlu diziler (`kimodo_lumina_generate_sequence`), kısıtlı üretim (`kimodo_lumina_generate_constrained`), backend seçimi (`kimodo_lumina_configure`), build'deki backend'ler |
| Yükleyici wrapper | `src/flutter_kimodo.{h,c}` | native-assets hook'u build eder; kimodo'yu çalışma anında kendi klasöründen yükler ve çağrıları ona iletir; Vulkan cihazlarını listeler |
| Dart API | `lib/flutter_kimodo.dart` | `KimodoRuntime`, `KimodoModel`, `KimodoMotion`, `KimodoConstraints`, `KimodoSkeleton`, `KimodoModelFiles`, `KimodoPrebuilt` |

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

Script `tool/kimodo/UPSTREAM` (repository + commit) ve ggml submodule'ünü `third_party/kimodo/src` altına çeker, `tool/kimodo/patches/*.patch` dosyalarını sırayla uygular (temiz bir LF
checkout üzerinde; onları zaten içeren bir checkout korunur),
`tool/kimodo/CMakeLists.txt` üzerinden build eder (CMake ≥ 3.25, Ninja; Windows: Visual Studio 2022 x64, dinamik CRT
`/MD`), kütüphaneleri, `kimodo.lib`'i, header'ları, lisansları ve `lumina-kimodo.json` (köken bilgisi) dosyasını
toplar, `third_party/kimodo/dist/kimodo-<VERSION>-<os>-x64.{zip,tar.gz}` arşivini `.sha256` dosyasıyla birlikte
paketler ve hook'un okuduğu klasöre kurar. İlk CPU build'i birkaç dakika sürer.

- **Vulkan**: `auto`, [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) kuruluysa (`VULKAN_SDK`, `glslc`) ggml Vulkan
  backend'ini build eder, değilse yalnızca CPU backend'ini; `on` SDK yoksa hata verir.
- **Sürüm**: `tool/kimodo/VERSION` (`<commit>-lumina.<n>`). Commit, bir patch, `native/kimodo_lumina.cpp`, build flag'leri
  ya da toolchain değişince `-lumina.N` sonekini artırın. Hook `VERSION`'a bağlıdır, artırmak onu yeniden çalıştırır.
  `5679ff1-lumina.2`, `patches/0001-constrained-generation.patch`'i ekler (tek prompt ve diziler için kısıt
  tensörleri, kütüphane içinde normalize edilir).
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

## Kısıtlar

Kimodo gürültüyü giderirken kısıtlara uyabilir: zeminde bir kök yolu, belirli karelerde uç efektörler (eller, ayaklar,
kalça) ve tüm vücut anahtar kareleri. `KimodoConstraints`, NVIDIA Kimodo'nun kısıt setlerinin listesidir (Python
referansındaki `kimodo.constraints`); kareler üretilen zaman çizelgesinin tamamı üzerinden sayılır:

| Dart | Upstream | Her karede sabitlediği |
|---|---|---|
| `KimodoRoot2DConstraint(frames, points, headings?)` | `Root2DConstraintSet` | yumuşatılmış kökün zemin konumu (x, z) ve verilirse yönü (radyan, 0 = +Z'ye bakış) |
| `KimodoEndEffectorConstraint.leftHand / rightHand / leftFoot / rightFoot(frames, poses)`, `KimodoEndEffectorConstraint(joints: [...])` | `EndEffectorConstraintSet` ve alt sınıfları | zincirin eklem konumları (el + orta parmak ucu, ayak + parmak), ilk eklemin rotasyonu, pozun yumuşatılmış kökü, pelvis yüksekliği ve yönü |
| `KimodoFullBodyConstraint(frames, poses)` | `FullBodyConstraintSet` | tüm eklem konumları, yumuşatılmış kök, pelvis yüksekliği ve yön |

```dart
final skeleton = KimodoSkeleton.soma30;
final base = await model.generate('a person stands and looks around', frames: 90);
final pose = skeleton.motionPose(base, 60); // global konumlar + rotasyonlar
final raised = pose.translated(0, 0.25, 0); // ya da yalnızca el zincirini taşıyın
final motion = await model.generate(
  'a person stands and looks around',
  frames: 90,
  constraints: KimodoConstraints([
    KimodoRoot2DConstraint(frames: [0, 89], points: [(x: 0, z: 0), (x: 1.5, z: 1.0)]),
    KimodoEndEffectorConstraint.leftHand(frames: [60], poses: [raised]),
  ]),
  options: const KimodoGenerationOptions(constraintCfg: 2),
);
```

- `generateSequence(segments, constraints: ...)` kısıtları birleşik zaman çizelgesi üzerinden alır (segmentlerin
  kareleri art arda); her segment, upstream'in `_multiprompt`'u gibi, geçiş satırlarından sonra kendi karelerinin
  satırlarıyla koşullanır.
- `KimodoConstraints.encode(frames)` koşullama tensörlerini hareket temsilinin özellik düzeninde kurar (yumuşatılmış
  kök, yön, yumuşatılmış köke göre eklem konumları, global 6D rotasyonlar; normalize edilmemiş): upstream
  `KimodoMotionRep.create_conditions` düzeni. Aynı kare (ve eklem) için sonraki set öncekinin değerini değiştirir.
  kimodo.cpp onları checkpoint'in istatistikleriyle normalize eder.
- `KimodoSkeleton.soma30` adları, ebeveynleri, dinlenme ofsetlerini, kalçaları ve uç efektör zincirlerini taşır;
  `pose(...)` / `motionPose(motion, frame)` forward kinematics ile bir `KimodoPose` üretir (global konumlar ve satır
  öncelikli rotasyon matrisleri; `translated`, `turned`).
- **Eşlik**: `test/fixtures/constraints_parity.json`, Python referansının rastgele pozlarda kök yolları, her uç
  efektör, tüm vücut anahtarları ve çakışan setler için kurduğu tensörleri tutar;
  `tool/kimodo/constraints_parity_fixture.py` (`KIMODO_UPSTREAM_DIR` bir `nv-tlabs/kimodo` checkout'unu gösterirken)
  onu yazar, test her değeri karşılaştırır.
- C yüzeyi `kimodo_lumina_generate_constrained`'dır (promptlar, kareler, geçiş, `[sum(frames), motion_dim]` boyutlu
  `observed_motion` ve `motion_mask`, maske değerleri 0 ya da 1; üretimden önce doğrulanır).

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
flutter test test/kimodo_constraints_test.dart
```

Gerçek native kütüphaneyi çağırırlar. `kimodo_constraints_test.dart` kodlamayı Python referansının fixture'ıyla
karşılaştırır ve ağırlıklarla 3 m'lik bir kök yolunun hedefin 0,3 m yakınında bittiğini, sol el hedefine 0,1 m
içinde ulaşıldığını ve kısıtların bir dizinin ikinci promptunu da yönlendirdiğini doğrular. Üretim testleri GGUF dosyaları `KIMODO_MODELS_DIR` (ya da eklentinin model
klasörü) içinde olana kadar atlanır, dosyalar gelince çalışır. Binding'ler ffigen tarzında yazılmıştır;
`dart run tool/ffigen.dart` ile yeniden üretilir (libclang gerekir); `test/bindings_lockstep_test.dart` onları
header'larla uyumlu tutar.

## Lisanslar

Paket, repository gibi GPL-3.0'dır. Hazır runtime `licenses/` altında kimodo.cpp (Apache-2.0, NOTICE ile) ve ggml
(MIT) lisanslarını taşır; `src/kimodo/kimodo_capi.h` kimodo.cpp'den alınmıştır (Apache-2.0). Model ağırlıkları asla
paketlenmez.

---

[Önceki: flutter_riglogic](flutter_riglogic.md) · [İçindekiler](../README.tr.md)
