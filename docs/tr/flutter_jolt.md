[English](../en/flutter_jolt.md)

# flutter_jolt

`flutter_jolt`, [Jolt Physics](https://github.com/jrouwe/JoltPhysics) (MIT) kütüphanesini Dart FFI ile bağlar: rigid body'ler, şekiller, constraint'ler, temaslar ve ray cast'lerle native bir fizik dünyası. Lumina motoru onu native masaüstünde fizik backend'i olarak kullanır (motorun `docs/tr/lumina/physics.md` sayfasına bakın); web'de bir WebAssembly modülü olarak çalışır (aşağıda Web'e bakın); saf Dart çözücü yedek olarak kalır. Birimler Jolt'unkilerdir: metre, kilogram, saniye, radyan; dünyanın tercih ettiği bir yukarı ekseni yoktur. Dosya yolları `flutter_jolt/` paket klasörüne göredir.

**Bu sayfada:**

- [Native build](#native-build)
- [Native C köprüsü](#native-c-köprüsü)
- [Dart API](#dart-api)
- [Çarpışma filtreleme](#çarpışma-filtreleme)
- [Web (WebAssembly)](#web-webassembly)
- [Sınırlar](#sınırlar)

## Native build

Jolt vendored değildir, indirilir. `tool/jolt_version.txt` sürümü sabitler (tag `v5.6.0` ve commit'i); `tool/build_jolt.bat` (Windows, Visual Studio 2022, Visual Studio'nun CMake ve Ninja'sı) ve `tool/build_jolt.sh` (Linux, lumina repo'sundaki paketli libc++ ile clang, `-fPIC`) onu gitignore'daki `third_party/jolt/src` klasörüne klonlar, başka bir commit'i reddeder, `Jolt` static kütüphanesini build eder ve kendi kendine yeten bir build klasörü yazar:

| Yol | İçerik |
|---|---|
| `third_party/jolt/include/Jolt/...` | header'lar |
| `third_party/jolt/lib/Jolt.lib` / `libJolt.a` | static kütüphane (Windows'ta `/MT` static CRT) |
| `third_party/jolt/jolt_defines.txt` | kütüphanenin derlendiği `JPH_*` define'ları (`tool/write_jolt_defines.dart` CMake'in `compile_commands.json` dosyasından okur) |
| `third_party/jolt/VERSION` | tag ve commit |

Build seçenekleri: tek hassasiyet, platformlar arası determinizm yok (aynı binary deterministiktir; replay ve testler için bu yeterli), 16 bit object layer, C++ exception ve RTTI açık, debug renderer, profiler, object stream ve GPU compute yok, x86-64 SSE4.2 tabanı (AVX yok, oyunlar eski CPU'larda da çalışır), link-time optimizasyon yok. `--clean` önce klasörü siler.

`hook/build.dart`, `src/jolt_c.cpp` dosyasını `jolt_defines.txt` içindeki define'larla birebir (x64'te clang/gcc ile bunların gerektirdiği komut seti bayraklarıyla da, `joltIsaFlags`: `-msse4.1`, `-msse4.2 -mpopcnt`, …; Jolt'un başlıkları bu intrinsic'leri satır içi kullanır) derleyip `flutter_jolt` dinamik kütüphanesini (code asset `package:flutter_jolt/src/jolt_native.dart`) üretir ve static kütüphaneyi link eder. Build klasörü şuradan gelir (`lib/src/hook/jolt_dir.dart`):

1. `LUMINA_JOLT_DIR` (yalnızca hook doğrudan çalıştırıldığında; hook runner `LUMINA_*` değişkenlerini aktarmaz);
2. uygulamanın workspace root pubspec'indeki `jolt_dir` user-define'ı (`hooks: user_defines: flutter_jolt: jolt_dir: <yol>`), kütüphaneyi içeriyorsa;
3. paketteki `third_party/jolt`.

Hiçbiri kütüphane içermiyorsa hook bir not yazar ve **code asset üretmez**: paket yine derlenir, `JoltPhysics.isAvailable` false olur ve çağıranlar yedeğe geçer. Linux'ta hook paketli libc++'ı (`libcxx_dir`) ister.

## Native C köprüsü

`src/jolt_c.h` C API'sini bildirir (`jolt_*`, `JOLT_C_EXPORT` ile export edilir); `tool/ffigen.dart` `@Native` binding'lerini `lib/src/jolt_bindings.g.dart` dosyasına üretir (libclang gerekir; klasörünü `LIBCLANG_PATH` verir). Gruplar:

- **Dünya**: `jolt_world_create` (body / çift / temas kapasiteleri, worker thread'ler), `jolt_world_destroy`, yerçekimi, çözücü ayarları (hız / konum adımları, Baumgarte, spekülatif temas mesafesi, penetrasyon payı, uyku süresi ve eşiği), `jolt_world_step` (Jolt'un update hata bitlerini döndürür; adım, çağıran beklerken dünyanın 16 MB yığınlı kendi adım thread'inde çalışır, çünkü Jolt'un narrow phase'i bir Dart mutator thread'inin yığınından fazlasına ihtiyaç duyabilir), broad phase optimizasyonu, body sayıları.
- **Şekiller** (referans sayımlı, `jolt_shape_release` ile bırakılır): kutu, küre, kapsül (Y ekseni), silindir (Y ekseni), convex hull, height field (satır öncelikli örnekler, `jolt_heightfield_no_collision()` delikleri, yaklaşık 1 mm hassasiyet), ölçekli, döndürülmüş/kaydırılmış, kütle merkezi kaydırılmış, static compound; `jolt_shape_set_user_data` temaslar ve ray isabetleri için bir yaprağı adlandırır.
- **Body'ler**: `JoltBodySettings` ile `jolt_body_create` (hareket tipi, poz, hızlar, user data, sürtünme, sekme, sönüm, yerçekimi çarpanı, kütle ve atalet override'ı, izinli DOF'lar, sürekli çarpışma, sensör), silme, sahip ve profiller (filtreleme), combine modlu malzeme, şekil, kütle özellikleri, hareket tipi, sönüm, yerçekimi çarpanı, CCD, transform, hız, kinematik hareket, kuvvet, tork, impuls, aktivasyon; `jolt_world_get_body_states` birçok body'yi tek çağrıda okur (`JOLT_BODY_STATE_STRIDE` double: kütle merkezi, dönüş, doğrusal ve açısal hız, aktif, şekil orijini).
- **Temaslar**: `jolt_world_get_contacts` son adımın eklenen ve süren temaslarını body sırasına göre döndürür: iki body ve yaprak user data'ları, ortalama nokta, normal (A body'sinden B'ye), tahmini bir normal impuls (çözücü çalışmadan önceki hızlardan, body'lerin temasta yaklaşmasını esneklikle birlikte durduran, kütle merkezlerinden geçen impuls), penetrasyon ve nokta sayısı.
- **Kumaş (soft body)**: `jolt_cloth_settings_init`, `jolt_soft_body_create` (köşeler, ters kütleler (0 bir köşeyi sabitler), üçgenler; kenar, kayma ve bükülme compliance'ları, dihedral ya da mesafe bükülmesi, sabit köşelere uzun menzilli bağlar (tether), iterasyonlar, sönüm, sürtünme, köşe yarıçapı), `jolt_soft_body_get_vertices` (dünya konumları), `jolt_soft_body_set_vertex` (bir köşeyi taşı ya da sabitle), `jolt_soft_body_set_inverse_mass` (olduğu yerde sabitle ya da serbest bırak), `jolt_soft_body_drive_vertices` (sabit köşeleri bir sonraki adımda hedeflere taşı; bir sabit yeniden sürülene kadar o hızı korur), `jolt_soft_body_get_local_vertices` (konumlar ve alan ağırlıklı normaller, çağıranın bir çerçevesinde, örn. bir bileşenin santimetreleri), `jolt_soft_body_apply_wind` (aerodinamik: her yüz, göreli rüzgârın ona çarpan kısmı kadar normali boyunca itilir). Bir soft body'yi köşelerinin yakınında kurun (`position` merkezlerinde): body orijininden uzak köşeler kumaşı kararsız yaptı; çok hafif köşelerde neredeyse rijit compliance'lar da öyle (compliance'ları ters kütleyle ölçekleyin).
- **Skinli kumaş** (giysiler): bir `JoltClothSkin` ile `jolt_skinned_cloth_create` (ters bind matrisleri, köşe başına dört eklem ve ağırlık, köşe başına en büyük mesafe ve backstop), `jolt_soft_body_skin` (her adımda dünyadaki eklem matrisleri, ilkinde sert skin), `jolt_body_set_cloth_collider` (bir kumaş, `jolt_body_set_owner` ile verilen sahibinin collider'ları dışındaki body'lerini yok sayar). Dart: `createCloth(..., skin: JoltClothSkin(...))`, `skinCloth`, `setBodyClothCollider`.
- **Kumaşı taşımak** (katı bir hareket boyunca): `jolt_soft_body_carry` (dünyada bir 4x4 fark ve 0..1 bir miktar: her serbest köşe, hareketin onu götürdüğü yere giden yolun o payı kadar ilerler ve hızı o kadar döner; `include_pinned` sabit köşeleri de, bir ışınlanma için yolun tamamı kadar taşır). Dart: `carryCloth(body, delta, amount, includePinned:)`. Lumina bunu bir kumaşın atalet ölçeği ve ışınlanmaları için kullanır.
- **Geniş faz vekilleri** (sahne sorguları): `jolt_world_add_box_proxy` / `jolt_world_set_box_proxy` (eksene hizalı bir kutuyu temsil eden, user data taşıyan statik bir kutu body), `jolt_world_broad_phase_ray`, `jolt_world_broad_phase_box_cast` ve `jolt_world_broad_phase_box` (sınırlarına bir parçanın, hareket eden bir kutunun ya da bir kutunun değdiği her body'nin user data'sı; vekiller hareket ettikten sonra `jolt_world_optimize_broad_phase` ağacı yeniden kurana dek bir üst küme). Dart: `addBoxProxy`, `setBoxProxy`, `broadPhaseRay`, `broadPhaseBoxCast`, `broadPhaseBox`. Lumina'nın çarpışma subsystem'i bunları kendine ait bir dünyada kullanır.
- **Kendisiyle çarpışma**: `jolt_soft_body_set_self_collision(world, body, distance)`: her adımdan sonra kumaşın kendi üçgenlerinden birine `distance`'tan (m) daha yakın bir köşe dışarı itilir (üçgen de barisentrik ağırlıklarıyla geri) ve ona yaklaşması durdurulur; dinlenme pozunda o üçgene o kadar yakın olan köşe (komşuları) atlanır. En uzun kenar boyutunda hücrelerden oluşan bir ızgara üzerinde tek geçiş; 441 köşeli bir örtü için adım başına yaklaşık 0.3 ms. Dart: `setClothSelfCollision(body, distance)` (0 kapatır).
- **Sorgular**: `jolt_world_cast_ray`.
- **Constraint'ler**: `jolt_constraint_swing_twist` (çerçevenin X ekseni etrafında twist, düzlem ekseni Y, normal ve düzlem yarı konileri, twist aralığı, sürtünme torku) ve `jolt_constraint_hinge` (`-π ≤ min ≤ 0 ≤ max ≤ π` içinde limitler), çerçeveler her body'nin kütle merkezine göre; limitler, sürtünme torku, hız motoru (`jolt_constraint_set_velocity_motor`), konum motoru (`jolt_constraint_set_position_motor`: hedef dönüşe doğru frekansı ve sönüm oranı verilen bir yay; menteşe X etrafındaki açıyı okur), constraint'in adası için çözücü iterasyonları (`jolt_constraint_set_solver_steps`), etkinleştirme, impulslar.

## Dart API

`package:flutter_jolt/flutter_jolt.dart`:

- `JoltPhysics`: `isAvailable` (kütüphaneyi bir kez yoklar, hiç hata fırlatmaz), `version` (`5.6.0`), `ensureAvailable()`.
- `JoltWorld({maxBodies, maxBodyPairs, maxContactConstraints, workerThreads, gravity})`: `gravity`, `solverSettings` (`JoltSolverSettings`), `step(dt, collisionSteps:)`, `createBody(shape, JoltBodySettings)` → body id, `destroyBody` (önce constraint'lerini kaldırır), `setBodyOwner`, `setBodyProfiles`, `setBodyMaterial`, `setBodyShape`, `setBodyMassProperties`, `setBodyMotionType`, `setBodyDamping`, `setBodyGravityFactor`, `setBodyContinuousCollision`, `setBodyTransform`, `setBodyVelocity`, `moveKinematic`, `addForce` / `addTorque` / `addImpulse` / `addAngularImpulse`, `activateBody` / `deactivateBody` / `isBodyActive`, `bodyMass`, `bodyState` / `readBodyStates` + `stateAt` / `stateBuffer`, `contacts()`, `castRay`, `setProfileMatrix`, `ignorePair`, `addSwingTwist` / `addHinge` / `removeConstraint` (bir `JoltConstraint`'in `setLimits`, `maxFrictionTorque`, `setVelocityMotor`, `setPositionMotor`, `setSolverSteps`, `enabled`, `lambdas` üyeleri vardır), `dispose()`.
- `JoltShape`: `box`, `sphere`, `capsule`, `cylinder`, `convexHull`, `heightField`, `scaled`, `rotatedTranslated`, `offsetCenterOfMass`, `compound`; `userData`, `centerOfMass`, `volume`, `localBounds`, `release()` (unutulan bir şekli `NativeFinalizer` serbest bırakır).
- Kumaş (`JoltWorldCloth` extension'ı, `lib/src/jolt_cloth.dart`): `createCloth(vertices, triangles, inverseMasses:, position:, rotation:, settings: JoltClothSettings(...))`, `clothVertexCount`, `clothVertices` (dünya konumları bir `Float32List`'e), `setClothVertex`, `setClothInverseMass`, `driveClothVertices`, `clothLocalVertices`, `applyClothWind`; `JoltClothBend`, `JoltClothTethers`.
- `JoltBodySettings`, `JoltBodyState`, `JoltContact`, `JoltRayHit`, `JoltMotionType`, `JoltDofs`, `JoltCombineMode`, `JoltSwingTwistSettings` / `JoltHingeSettings` ile `JoltConstraint`.

```dart
if (JoltPhysics.isAvailable) {
  final world = JoltWorld(workerThreads: 2);
  final ground = JoltShape.box(Vector3(50, 0.5, 50));
  world.createBody(ground, JoltBodySettings(motionType: JoltMotionType.static_, position: Vector3(0, -0.5, 0)));
  ground.release();
  final box = JoltShape.box(Vector3.all(0.5));
  final id = world.createBody(box, JoltBodySettings(position: Vector3(0, 2.5, 0), mass: 10));
  box.release();
  for (var i = 0; i < 120; i++) {
    world.step(1 / 120);
  }
  print(world.bodyState(id).centerOfMass); // zeminde duruyor
  world.dispose();
}
```

## Çarpışma filtreleme

Bir `SimShapeFilter` narrow phase'den önce karar verir; filtrelenen çiftler hiçbir maliyet getirmez:

- **Profiller**: bir body'nin her yaprağının bir profil indeksi vardır (`setBodyProfiles`, yaprağın user data'sına göre); iki yaprak ancak `setProfileMatrix` profillerinin birbirini blokladığını söylüyorsa temas eder. Matrisin dışındaki bir indeks her şeyi bloklar. Lumina çarpışma kanallarını ve cevaplarını profillere eşler.
- **Sahipler**: aynı sıfır olmayan sahibe sahip body'ler (`setBodyOwner`) ancak ikisi de dinamik ya da kinematikse ve ikisi de izin veriyorsa (`collidesWithOwner`) çarpışır; o sahibin static bir body'siyle asla çarpışmaz.
- **Yok sayılan çiftler**: `ignorePair(a, b)` (Jolt constraint'li body'leri çarpıştırmaya devam eder; bir eklemin çiftini yok sayın).

Malzemeler: yüzeyler neredeyse kaymıyorsa (1 cm/s altı) statik sürtünme, aksi halde dinamik sürtünme birleştirilir; iki body'nin büyük combine modu kazanır (average < min < multiply < max).

## Web (WebAssembly)

Web aynı C API'sini tek bir WebAssembly modülü olarak çalıştırır: `web/flutter_jolt.{js,wasm}` (gitignore'da):

- **Build**: `tool/web/build_jolt_wasm.sh` (emsdk, varsayılan `~/emsdk` yoksa `EMSDK=...`, ve define yazıcı için `PATH`'te bir Dart SDK) sabitlenen Jolt sürümünü `third_party/jolt-wasm/` içine indirir, Jolt'un kendi wasm32 bayraklarıyla (`USE_WASM_SIMD`: Emscripten'in SSE 4.2 öykünmesiyle WASM SIMD, istisnasız) build eder ve `src/jolt_c.cpp`'yi modüle link eder: tek iş parçacıklı (`SharedArrayBuffer` yok, yani COOP/COEP başlıkları gerekmez), 16 MB yığın, büyüyen bellek, 64 bit değerler için BigInt, başlıktaki her `jolt_*` fonksiyonu dışa aktarılmış. `OPT=-O1` daha hızlı link eder. Emscripten altında bir dünya çağıran iş parçacığında Jolt'un tek iş parçacıklı iş sistemiyle adımlanır.
- **Dart**: sarmalayıcılar `lib/src/jolt_ffi.dart`, `jolt_ffi_package.dart` ve `jolt_c.dart`'ı import eder; bunlar native'de `dart:ffi`, `package:ffi` ve ffigen bağlamalarını, web'de `lib/src/web_ffi/` (modülün belleği üzerinde bir `dart:ffi` / `package:ffi` katmanı, flutter_filament'inkinden uyarlandı) ile `lib/src/jolt_bindings.web.g.dart`'ı dışa aktarır. `dart run tool/ffigen_web.dart` o dosyayı ffigen çıktısından üretir (`tool/ffigen.dart`'tan sonra çalıştırın; aksi halde `test/web/bindings_lockstep_test.dart` başarısız olur).
- **Açılış**: `await JoltPhysics.ensureInitialized(moduleUrl: 'flutter_jolt.js')` modülü yükler (native'de hiçbir şey yapmaz); o zamana kadar `JoltPhysics.isAvailable` false'tur. Lumina motoru bir web oyunu yüklenirken onu `LuminaPhysicsSubsystem.prepareJolt()` ile çağırır ve web build'i iki dosyayı oyunun `index.html`'inin yanına koyar.
- **Testler**: `node --test test/web/module_test.mjs` (her export, bir kutu üzerinde duran bir küre); `test/web/browser_tests_test.dart`, `test/web/browser_main.dart`'ı dart2js ile derler, modülün yanında sunar ve dünya, şekil, constraint, kumaş ve geniş faz test dosyalarını `test/support/test_api.dart` üzerinden (native'de `flutter_test`, web'de küçük bir tarayıcı koşucusu) headless Chrome'da çalıştırır ve süreleri raporlar. Windows geliştirme makinesinde `flutter test --platform chrome` sayfasına hiç bağlanamıyor (önemsiz bir testte bile), bu yüzden süit Chrome'u kendisi sürer.
- **Ölçülen** (Chrome 155, bu makine): modül 1.40 MB wasm ve 19 KB JavaScript'tir ve yaklaşık 40 ms'de yüklenir; 29 testin hepsi geçer; durmuş 200 kutuluk bir yığının bir adımı tek iş parçacığında yaklaşık 0.3 ms sürer.

## Sınırlar

- Temas impulsları o adım için tahmindir (dönme terimleri yok), çözülmüş impulslar değildir.
- Height field'lar blok başına örnek başına yaklaşık 8 bit tutar (metre ölçekli arazide birkaç milimetre) ve yalnızca static'tir.
- Windows x64 ve Linux x64'te (Ubuntu, clang 21) ve WebAssembly olarak (tek iş parçacıklı) build edildi ve test edildi; Android, macOS ve iOS henüz build edilmiyor.

---

[Önceki: flutter_riglogic](flutter_riglogic.md) · [Sonraki: flutter_kimodo](flutter_kimodo.md)
