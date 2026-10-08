// Compiled by hook/build.dart when it builds the vendored Assimp: that build
// disables Assimp's glTF importers, whose switch also hides the glTF headers
// the glTF 2 exporter needs. Lift it for this translation unit only.
#undef ASSIMP_BUILD_NO_GLTF_IMPORTER
#include "glTF2/glTF2Exporter.cpp"
