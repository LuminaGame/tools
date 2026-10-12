[English](../en/flutter_jolt.md)

# flutter_jolt

`flutter_jolt`, [Jolt Physics](https://github.com/jrouwe/JoltPhysics) (MIT) kütüphanesini Dart FFI ile bağlar: rigid body'ler, şekiller, constraint'ler, temaslar ve ray cast'lerle native bir fizik dünyası. Lumina motoru onu native masaüstünde fizik backend'i olarak kullanır (motorun `docs/tr/lumina/physics.md` sayfasına bakın); saf Dart çözücü web için ve yedek olarak kalır. Birimler Jolt'unkilerdir: metre, kilogram, saniye, radyan; dünyanın tercih ettiği bir yukarı ekseni yoktur. Dosya yolları `flutter_jolt/` paket klasörüne göredir.

**Bu sayfada:**

- [Native build](#native-build)
- [Native C köprüsü](#native-c-köprüsü)
- [Dart API](#dart-api)
- [Çarpışma filtreleme](#çarpışma-filtreleme)
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

`hook/build.dart`, `src/jolt_c.cpp` dosyasını `jolt_defines.txt` içindeki define'larla birebir derleyip `flutter_jolt` dinamik kütüphanesini (code asset `package:flutter_jolt/src/jolt_native.dart`) üretir ve static kütüphaneyi link eder. Build klasörü şuradan gelir (`lib/src/hook/jolt_dir.dart`):

1. `LUMINA_JOLT_DIR` (yalnızca hook doğrudan çalıştırıldığında; hook runner `LUMINA_*` değişkenlerini aktarmaz);
2. uygulamanın workspace root pubspec'indeki `jolt_dir` user-define'ı (`hooks: user_defines: flutter_jolt: jolt_dir: <yol>`), kütüphaneyi içeriyorsa;
3. paketteki `third_party/jolt`.

Hiçbiri kütüphane içermiyorsa hook bir not yazar ve **code asset üretmez**: paket yine derlenir, `JoltPhysics.isAvailable` false olur ve çağıranlar yedeğe geçer. Linux'ta hook paketli libc++'ı (`libcxx_dir`) ister.

## Native C köprüsü

`src/jolt_c.h` C API'sini bildirir (`jolt_*`, `JOLT_C_EXPORT` ile export edilir); `tool/ffigen.dart` `@Native` binding'lerini `lib/src/jolt_bindings.g.dart` dosyasına üretir (libclang gerekir; klasörünü `LIBCLANG_PATH` verir). Gruplar:

- **Dünya**: `jolt_world_create` (body / çift / temas kapasiteleri, worker thread'ler), `jolt_world_destroy`, yerçekimi, çözücü ayarları (hız / konum adımları, Baumgarte, spekülatif temas mesafesi, penetrasyon payı, uyku süresi ve eşiği), `jolt_world_step` (Jolt'un update hata bitlerini döndürür), broad phase optimizasyonu, body sayıları.
- **Şekiller** (referans sayımlı, `jolt_shape_release` ile bırakılır): kutu, küre, kapsül (Y ekseni), silindir (Y ekseni), convex hull, height field (satır öncelikli örnekler, `jolt_heightfield_no_collision()` delikleri, yaklaşık 1 mm hassasiyet), ölçekli, döndürülmüş/kaydırılmış, kütle merkezi kaydırılmış, static compound; `jolt_shape_set_user_data` temaslar ve ray isabetleri için bir yaprağı adlandırır.
- **Body'ler**: `JoltBodySettings` ile `jolt_body_create` (hareket tipi, poz, hızlar, user data, sürtünme, sekme, sönüm, yerçekimi çarpanı, kütle ve atalet override'ı, izinli DOF'lar, sürekli çarpışma, sensör), silme, sahip ve profiller (filtreleme), combine modlu malzeme, şekil, kütle özellikleri, hareket tipi, sönüm, yerçekimi çarpanı, CCD, transform, hız, kinematik hareket, kuvvet, tork, impuls, aktivasyon; `jolt_world_get_body_states` birçok body'yi tek çağrıda okur (`JOLT_BODY_STATE_STRIDE` double: kütle merkezi, dönüş, doğrusal ve açısal hız, aktif, şekil orijini).
- **Temaslar**: `jolt_world_get_contacts` son adımın eklenen ve süren temaslarını body sırasına göre döndürür: iki body ve yaprak user data'ları, ortalama nokta, normal (A body'sinden B'ye), Jolt'un tahmini normal impulsu (`EstimateCollisionResponse`), penetrasyon ve nokta sayısı.
- **Sorgular**: `jolt_world_cast_ray`.
- **Constraint'ler**: `jolt_constraint_swing_twist` (çerçevenin X ekseni etrafında twist, düzlem ekseni Y, normal ve düzlem yarı konileri, twist aralığı, sürtünme torku) ve `jolt_constraint_hinge` (`-π ≤ min ≤ 0 ≤ max ≤ π` içinde limitler), çerçeveler her body'nin kütle merkezine göre; limitler, sürtünme torku, hız motoru (`jolt_constraint_set_velocity_motor`), konum motoru (`jolt_constraint_set_position_motor`: hedef dönüşe doğru frekansı ve sönüm oranı verilen bir yay; menteşe X etrafındaki açıyı okur), constraint'in adası için çözücü iterasyonları (`jolt_constraint_set_solver_steps`), etkinleştirme, impulslar.

## Dart API

`package:flutter_jolt/flutter_jolt.dart`:

- `JoltPhysics`: `isAvailable` (kütüphaneyi bir kez yoklar, hiç hata fırlatmaz), `version` (`5.6.0`), `ensureAvailable()`.
- `JoltWorld({maxBodies, maxBodyPairs, maxContactConstraints, workerThreads, gravity})`: `gravity`, `solverSettings` (`JoltSolverSettings`), `step(dt, collisionSteps:)`, `createBody(shape, JoltBodySettings)` → body id, `destroyBody` (önce constraint'lerini kaldırır), `setBodyOwner`, `setBodyProfiles`, `setBodyMaterial`, `setBodyShape`, `setBodyMassProperties`, `setBodyMotionType`, `setBodyDamping`, `setBodyGravityFactor`, `setBodyContinuousCollision`, `setBodyTransform`, `setBodyVelocity`, `moveKinematic`, `addForce` / `addTorque` / `addImpulse` / `addAngularImpulse`, `activateBody` / `deactivateBody` / `isBodyActive`, `bodyMass`, `bodyState` / `readBodyStates` + `stateAt` / `stateBuffer`, `contacts()`, `castRay`, `setProfileMatrix`, `ignorePair`, `addSwingTwist` / `addHinge` / `removeConstraint` (bir `JoltConstraint`'in `setLimits`, `maxFrictionTorque`, `setVelocityMotor`, `setPositionMotor`, `setSolverSteps`, `enabled`, `lambdas` üyeleri vardır), `dispose()`.
- `JoltShape`: `box`, `sphere`, `capsule`, `cylinder`, `convexHull`, `heightField`, `scaled`, `rotatedTranslated`, `offsetCenterOfMass`, `compound`; `userData`, `centerOfMass`, `volume`, `localBounds`, `release()` (unutulan bir şekli `NativeFinalizer` serbest bırakır).
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

## Sınırlar

- Temas impulsları Jolt'un o adım için tahminidir, çözülmüş impuls değildir.
- Height field'lar blok başına örnek başına yaklaşık 8 bit tutar (metre ölçekli arazide birkaç milimetre) ve yalnızca static'tir.
- Windows x64'te build edildi ve test edildi; Linux script'i aynısını yapar. Android, macOS, iOS ve web (WebAssembly) henüz build edilmiyor.

---

[Önceki: flutter_riglogic](flutter_riglogic.md) · [Sonraki: flutter_kimodo](flutter_kimodo.md)
