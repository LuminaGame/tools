[English](README.md)

# flutter_kimodo

NVIDIA Kimodo'nun GGML portu [kimodo.cpp](https://github.com/localai-org/kimodo.cpp) için Dart FFI binding'leri: metin
promptları, Kimodo'nun 30 eklemli SOMA iskeletinde 30 fps hareketlere dönüşür; CPU ya da Vulkan GPU üzerinde, arka plan
isolate'inde üretilir.

- `tool/build_kimodo.ps1` / `tool/build_kimodo.sh` sabitlenmiş kimodo.cpp commit'ini (`tool/kimodo/UPSTREAM`)
  `third_party/kimodo/prebuilt/<VERSION>/<os>-x64` klasörüne ve `.sha256` ile doğrulanan bir arşive build eder;
  `tool/fetch_prebuilt.dart` bunun yerine bir arşivi kurar.
- Native-assets hook'u yükleyici wrapper'ı (`src/flutter_kimodo.c`) build eder ve kimodo ile ggml kütüphanelerini
  yanına paketler.
- `KimodoModel.load(...)`, `generate(prompt, frames: …)`, `generateSequence([...])` → `KimodoMotion` (eklem ve kare
  başına yerel XYZW rotasyonlar, kök konumları).

Model ağırlıkları dahil değildir: kendi lisanslarıyla ayrıca indirilir. Dokümantasyon:
[docs/tr/flutter_kimodo.md](../docs/tr/flutter_kimodo.md).
