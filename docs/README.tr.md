[English](README.md)

# Lumina tools dokümantasyonu

Bu, tools repository'sinin referans dokümantasyonudur: Lumina oyun motorunun ve editörü Lumina Studio'nun üzerine kurulduğu native ve FFI paketleri. Model içe aktarma (`flutter_assimp`), yüz rig'i hesaplama (`flutter_riglogic`), in-process video encode (`flutter_gstreamer`), smoke test sistemi (`lumina_smoke`) ve pointer capture (`lumina_mouse_capture`) konularını kapsar. Kurulum, gereksinimler ve native-assets hook ayarları repository'nin [README](../README.tr.md) dosyasında anlatılır.

## Nereden başlamalı

- **Oyun geliştiriciler** bu paketlerle yalnızca dolaylı olarak, engine üzerinden karşılaşır. [Lumina dokümantasyonu](https://github.com/LuminaGame/lumina/tree/main/docs) ile başlayın; oyununuz mouse'u capture ediyorsa [lumina_mouse_capture](tr/lumina_mouse_capture.md) sayfasını okuyun.
- **Editör ve eklenti geliştiriciler**: content browser modelleri [flutter_assimp](tr/flutter_assimp.md) ile içe aktarır; [flutter_riglogic](tr/flutter_riglogic.md) ise skeletal mesh ve animasyon editörlerinde MetaHuman yüzlerini yönetir.
- **Engine katkıcıları**: dört sayfanın hepsi; OpenRigLogic'i build etmek ve hook'ları Filament'a yönlendirmek için de repository [README](../README.tr.md) dosyası. Smoke testler ve kanıtları üzerinde çalışırken [lumina_smoke](tr/lumina_smoke.md) ve [flutter_gstreamer](tr/flutter_gstreamer.md) önem kazanır.

## İçindekiler

- [flutter_assimp](tr/flutter_assimp.md) - Assimp ile model içe aktarma: 40+ formattan binary glTF'e (GLB).
- [flutter_riglogic](tr/flutter_riglogic.md) - MetaHuman RigLogic: DNA dosyaları ve yüz rig'i hesaplama.
- [flutter_kimodo](tr/flutter_kimodo.md) - kimodo.cpp: NVIDIA Kimodo ile metinden hareket üretimi, CPU ya da Vulkan.
- [flutter_gstreamer](tr/flutter_gstreamer.md) - GStreamer binding'leri: in-process video encode ve medya probe.
- [lumina_mouse_capture](tr/lumina_mouse_capture.md) - Linux'ta relative hareketli pointer capture (Wayland ve X11).
- [lumina_smoke](tr/lumina_smoke.md) - Smoke test sistemi: artifact'ler, video kuralları, recorder'lar ve rapor çalıştırıcısı.
- [lumina_smoke API](tr/lumina_smoke-api.md) - Artifact, video, recorder ve rapor kütüphanelerinin sınıf referansı.

## İlgili dokümantasyon

- [Lumina dokümantasyonu](https://github.com/LuminaGame/lumina/tree/main/docs): mimari, başlangıç ve engine ile editörün API referansı.
- [plugins](https://github.com/LuminaGame/plugins) ve [marketplace](https://github.com/LuminaGame/marketplace).

---

[Sonraki: flutter_assimp](tr/flutter_assimp.md)
