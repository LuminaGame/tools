#include "assimp_bridge.h"
#include <assimp/Importer.hpp>
#include <assimp/Exporter.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <assimp/version.h>
#include <assimp/config.h>
#include <assimp/metadata.h>
#include <assimp/material.h>
#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>

#ifdef FLUTTER_ASSIMP_EXTRA_IMPORTERS
// Importers Filament's Assimp build leaves out, compiled by the hook from the
// same checkout.
#include "Collada/ColladaLoader.h"
#include "3DS/3DSLoader.h"
#include "Ply/PlyLoader.h"
#include "X/XFileImporter.h"
#include "STL/STLLoader.h"
#endif

// Per-thread strings behind trivially destructible thread_local pointers: a
// thread_local std::string would need __cxa_thread_atexit, which the static
// libc++abi is linked in without (the hook lists it before this object).
static thread_local std::string* t_last_error = nullptr;
static thread_local std::string* t_last_report = nullptr;

static std::string& lastError() {
    if (!t_last_error) t_last_error = new std::string();
    return *t_last_error;
}

static std::string& lastReport() {
    if (!t_last_report) t_last_report = new std::string("{}");
    return *t_last_report;
}

namespace {

const unsigned int kDefaultFlags = aiProcess_Triangulate |
                                   aiProcess_GenSmoothNormals |
                                   aiProcess_JoinIdenticalVertices |
                                   aiProcess_CalcTangentSpace |
                                   aiProcess_ImproveCacheLocality |
                                   aiProcess_SortByPType |
                                   aiProcess_GenUVCoords |
                                   aiProcess_TransformUVCoords;

// ---------------------------------------------------------------------------
// Tiny JSON writer (the report is flat enough not to need rapidjson's DOM).

class Json {
public:
    std::string out;

    void raw(const char* s) { out += s; }
    void str(const std::string& s) {
        out += '"';
        for (unsigned char c : s) {
            switch (c) {
                case '"': out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default:
                    if (c < 0x20) {
                        char buf[8];
                        snprintf(buf, sizeof buf, "\\u%04x", c);
                        out += buf;
                    } else {
                        out += static_cast<char>(c);
                    }
            }
        }
        out += '"';
    }
    void num(double v) {
        if (!std::isfinite(v)) { out += "null"; return; }
        char buf[40];
        snprintf(buf, sizeof buf, "%.9g", v);
        out += buf;
    }
    void key(const char* k) {
        comma();
        str(k);
        out += ':';
        mFresh = true;
    }
    void open(char c) { comma(); out += c; mFresh = true; }
    void close(char c) { out += c; mFresh = false; }
    void comma() {
        if (!mFresh && !out.empty() && out.back() != '[' && out.back() != '{') out += ',';
        mFresh = false;
    }
    void value(double v) { comma(); num(v); }
    void value(const std::string& s) { comma(); str(s); }
    void boolean(bool b) { comma(); raw(b ? "true" : "false"); }

private:
    bool mFresh = true;
};

// ---------------------------------------------------------------------------
// Source metadata.

bool metaNumber(const aiMetadata* md, const char* key, double& out) {
    if (!md) return false;
    for (unsigned int i = 0; i < md->mNumProperties; ++i) {
        if (strcmp(md->mKeys[i].C_Str(), key) != 0) continue;
        const aiMetadataEntry& e = md->mValues[i];
        if (!e.mData) return false;
        switch (e.mType) {
            case AI_BOOL: out = *static_cast<bool*>(e.mData) ? 1.0 : 0.0; return true;
            case AI_INT32: out = *static_cast<int32_t*>(e.mData); return true;
            case AI_UINT64: out = static_cast<double>(*static_cast<uint64_t*>(e.mData)); return true;
            case AI_FLOAT: out = *static_cast<float*>(e.mData); return true;
            case AI_DOUBLE: out = *static_cast<double*>(e.mData); return true;
            default: return false;
        }
    }
    return false;
}

const char* kAxisNames[] = {"X", "Y", "Z"};

std::string axisLabel(int axis, int sign) {
    if (axis < 0 || axis > 2) return "?";
    return std::string(sign < 0 ? "-" : "+") + kAxisNames[axis];
}

// ---------------------------------------------------------------------------
// Unit/axis normalization: every node, vertex, bind matrix and key is
// re-expressed in glTF's basis (metres, +Y up, +Z front). With A = s·C (C the
// basis rotation, s metres per source unit) a local transform L becomes
// A·L·A⁻¹ — rotation C·R·Cᵀ, translation s·C·t — so the hierarchy, bone names
// and bone orientations relative to the new axes are kept.

struct Normalization {
    bool applied = false;
    bool axesFound = false;
    bool unitFound = false;
    int upAxis = 1, upSign = 1, frontAxis = 2, frontSign = 1, coordAxis = 0, coordSign = 1;
    double unitScaleFactor = 1.0; // source centimetres per unit
    ai_real scale = 1;            // metres per source unit
    aiMatrix3x3 C;                // identity
};

void conjugate(aiMatrix4x4& m, const aiMatrix3x3& C, const aiMatrix3x3& CT, ai_real s) {
    aiMatrix3x3 R(m);
    aiVector3D t(m.a4, m.b4, m.c4);
    aiMatrix3x3 R2 = C * R * CT;
    aiVector3D t2 = (C * t) * s;
    aiMatrix4x4 out(R2);
    out.a4 = t2.x;
    out.b4 = t2.y;
    out.c4 = t2.z;
    m = out;
}

void conjugateNodes(aiNode* node, const aiMatrix3x3& C, const aiMatrix3x3& CT, ai_real s) {
    if (!node) return;
    conjugate(node->mTransformation, C, CT, s);
    for (unsigned int i = 0; i < node->mNumChildren; ++i) {
        conjugateNodes(node->mChildren[i], C, CT, s);
    }
}

void transformVectors(aiVector3D* v, unsigned int n, const aiMatrix3x3& C, ai_real s) {
    if (!v) return;
    for (unsigned int i = 0; i < n; ++i) v[i] = (C * v[i]) * s;
}

Normalization normalize(aiScene* scene, bool apply) {
    Normalization n;
    double up = 0, upSign = 0, front = 0, frontSign = 0, coord = 0, coordSign = 0, unit = 0;
    const aiMetadata* md = scene->mMetaData;
    n.axesFound = metaNumber(md, "UpAxis", up) && metaNumber(md, "UpAxisSign", upSign) &&
                  metaNumber(md, "FrontAxis", front) && metaNumber(md, "FrontAxisSign", frontSign);
    if (metaNumber(md, "CoordAxis", coord)) n.coordAxis = static_cast<int>(coord);
    if (metaNumber(md, "CoordAxisSign", coordSign)) n.coordSign = coordSign < 0 ? -1 : 1;
    n.unitFound = metaNumber(md, "UnitScaleFactor", unit) && unit > 0;
    if (n.axesFound) {
        n.upAxis = static_cast<int>(up);
        n.upSign = upSign < 0 ? -1 : 1;
        n.frontAxis = static_cast<int>(front);
        n.frontSign = frontSign < 0 ? -1 : 1;
        if (n.upAxis < 0 || n.upAxis > 2 || n.frontAxis < 0 || n.frontAxis > 2 || n.upAxis == n.frontAxis) {
            n.axesFound = false; // malformed: keep the axes as imported
        }
    }
    if (n.unitFound) {
        n.unitScaleFactor = unit;
        n.scale = static_cast<ai_real>(unit / 100.0);
    }
    if (n.axesFound) {
        aiVector3D u(0, 0, 0), f(0, 0, 0);
        u[n.upAxis] = static_cast<ai_real>(n.upSign);
        f[n.frontAxis] = static_cast<ai_real>(n.frontSign);
        const aiVector3D r = u ^ f; // right-handed: (u × f, u, f) → (+X, +Y, +Z)
        n.C = aiMatrix3x3(r.x, r.y, r.z, u.x, u.y, u.z, f.x, f.y, f.z);
    }
    if (!apply || (!n.axesFound && !n.unitFound)) return n;

    const aiMatrix3x3& C = n.C;
    aiMatrix3x3 CT = C;
    CT.Transpose();
    const ai_real s = n.scale;

    conjugateNodes(scene->mRootNode, C, CT, s);

    for (unsigned int m = 0; m < scene->mNumMeshes; ++m) {
        aiMesh* mesh = scene->mMeshes[m];
        transformVectors(mesh->mVertices, mesh->mNumVertices, C, s);
        transformVectors(mesh->mNormals, mesh->mNumVertices, C, 1);
        transformVectors(mesh->mTangents, mesh->mNumVertices, C, 1);
        transformVectors(mesh->mBitangents, mesh->mNumVertices, C, 1);
        for (unsigned int a = 0; a < mesh->mNumAnimMeshes; ++a) {
            aiAnimMesh* am = mesh->mAnimMeshes[a];
            transformVectors(am->mVertices, am->mNumVertices, C, s);
            transformVectors(am->mNormals, am->mNumVertices, C, 1);
            transformVectors(am->mTangents, am->mNumVertices, C, 1);
            transformVectors(am->mBitangents, am->mNumVertices, C, 1);
        }
        for (unsigned int b = 0; b < mesh->mNumBones; ++b) {
            conjugate(mesh->mBones[b]->mOffsetMatrix, C, CT, s);
        }
    }

    aiQuaternion qc(C);
    aiQuaternion qcInv = qc;
    qcInv.Conjugate();
    for (unsigned int a = 0; a < scene->mNumAnimations; ++a) {
        aiAnimation* anim = scene->mAnimations[a];
        for (unsigned int c = 0; c < anim->mNumChannels; ++c) {
            aiNodeAnim* ch = anim->mChannels[c];
            for (unsigned int k = 0; k < ch->mNumPositionKeys; ++k) {
                ch->mPositionKeys[k].mValue = (C * ch->mPositionKeys[k].mValue) * s;
            }
            for (unsigned int k = 0; k < ch->mNumRotationKeys; ++k) {
                aiQuaternion q = qc * ch->mRotationKeys[k].mValue * qcInv;
                ch->mRotationKeys[k].mValue = q.Normalize();
            }
            for (unsigned int k = 0; k < ch->mNumScalingKeys; ++k) {
                const aiVector3D sc = ch->mScalingKeys[k].mValue;
                aiVector3D out;
                for (unsigned int i = 0; i < 3; ++i) {
                    out[i] = std::fabs(C[i][0]) * sc.x + std::fabs(C[i][1]) * sc.y + std::fabs(C[i][2]) * sc.z;
                }
                ch->mScalingKeys[k].mValue = out;
            }
        }
    }

    for (unsigned int i = 0; i < scene->mNumCameras; ++i) {
        aiCamera* cam = scene->mCameras[i];
        cam->mPosition = (C * cam->mPosition) * s;
        cam->mUp = C * cam->mUp;
        cam->mLookAt = C * cam->mLookAt;
    }
    for (unsigned int i = 0; i < scene->mNumLights; ++i) {
        aiLight* light = scene->mLights[i];
        light->mPosition = (C * light->mPosition) * s;
        light->mDirection = C * light->mDirection;
        light->mUp = C * light->mUp;
    }
    n.applied = true;
    return n;
}

// ---------------------------------------------------------------------------
// Unreal collision hulls.

const char* collisionShape(const char* name) {
    if (!name) return nullptr;
    struct Prefix { const char* prefix; const char* shape; };
    static const Prefix prefixes[] = {
        {"UCX_", "convex"}, {"UBX_", "box"}, {"USP_", "sphere"}, {"UCP_", "capsule"},
    };
    for (const Prefix& p : prefixes) {
        bool match = true;
        for (int i = 0; i < 4 && match; ++i) {
            match = name[i] != '\0' && std::toupper(static_cast<unsigned char>(name[i])) == p.prefix[i];
        }
        if (match) return p.shape;
    }
    return nullptr;
}

struct Hull {
    std::string name;
    std::string shape;
    unsigned int mesh = 0;
    aiMatrix4x4 world;
};

void findCollision(aiNode* node, const aiMatrix4x4& parentWorld, aiScene* scene,
                   std::vector<Hull>& hulls, std::vector<bool>& drop) {
    const aiMatrix4x4 world = parentWorld * node->mTransformation;
    const char* nodeShape = collisionShape(node->mName.C_Str());
    for (unsigned int i = 0; i < node->mNumMeshes; ++i) {
        const unsigned int m = node->mMeshes[i];
        if (m >= scene->mNumMeshes || drop[m]) continue;
        const char* meshShape = collisionShape(scene->mMeshes[m]->mName.C_Str());
        const char* shape = nodeShape ? nodeShape : meshShape;
        if (!shape) continue;
        drop[m] = true;
        Hull h;
        h.name = nodeShape ? node->mName.C_Str() : scene->mMeshes[m]->mName.C_Str();
        h.shape = shape;
        h.mesh = m;
        h.world = world;
        hulls.push_back(h);
    }
    for (unsigned int c = 0; c < node->mNumChildren; ++c) {
        findCollision(node->mChildren[c], world, scene, hulls, drop);
    }
}

// Drops mesh references in [node]'s subtree, and collision nodes left empty.
void pruneNodes(aiNode* node, const std::vector<int>& remap) {
    if (node->mNumMeshes > 0) {
        std::vector<unsigned int> kept;
        for (unsigned int i = 0; i < node->mNumMeshes; ++i) {
            const int to = remap[node->mMeshes[i]];
            if (to >= 0) kept.push_back(static_cast<unsigned int>(to));
        }
        delete[] node->mMeshes;
        node->mMeshes = nullptr;
        node->mNumMeshes = static_cast<unsigned int>(kept.size());
        if (!kept.empty()) {
            node->mMeshes = new unsigned int[kept.size()];
            std::memcpy(node->mMeshes, kept.data(), kept.size() * sizeof(unsigned int));
        }
    }
    unsigned int w = 0;
    for (unsigned int c = 0; c < node->mNumChildren; ++c) {
        aiNode* child = node->mChildren[c];
        pruneNodes(child, remap);
        if (collisionShape(child->mName.C_Str()) && child->mNumMeshes == 0 && child->mNumChildren == 0) {
            delete child;
            continue;
        }
        node->mChildren[w++] = child;
    }
    node->mNumChildren = w;
}

void stripCollision(aiScene* scene, Json& report) {
    std::vector<bool> drop(scene->mNumMeshes, false);
    std::vector<Hull> hulls;
    if (scene->mRootNode) findCollision(scene->mRootNode, aiMatrix4x4(), scene, hulls, drop);
    // A collision mesh no node draws is still dropped.
    for (unsigned int m = 0; m < scene->mNumMeshes; ++m) {
        if (drop[m]) continue;
        const char* shape = collisionShape(scene->mMeshes[m]->mName.C_Str());
        if (!shape) continue;
        drop[m] = true;
        Hull h;
        h.name = scene->mMeshes[m]->mName.C_Str();
        h.shape = shape;
        h.mesh = m;
        hulls.push_back(h);
    }

    report.key("collision");
    report.open('[');
    for (const Hull& h : hulls) {
        const aiMesh* mesh = scene->mMeshes[h.mesh];
        report.open('{');
        report.key("name"); report.value(h.name);
        report.key("shape"); report.value(h.shape);
        report.key("vertex_count"); report.value(mesh->mNumVertices);
        report.key("face_count"); report.value(mesh->mNumFaces);
        aiVector3D lo(1e30f, 1e30f, 1e30f), hi(-1e30f, -1e30f, -1e30f);
        std::vector<aiVector3D> points;
        points.reserve(mesh->mNumVertices);
        for (unsigned int v = 0; v < mesh->mNumVertices; ++v) {
            const aiVector3D p = h.world * mesh->mVertices[v];
            points.push_back(p);
            lo.x = std::min(lo.x, p.x); lo.y = std::min(lo.y, p.y); lo.z = std::min(lo.z, p.z);
            hi.x = std::max(hi.x, p.x); hi.y = std::max(hi.y, p.y); hi.z = std::max(hi.z, p.z);
        }
        if (!points.empty()) {
            report.key("min");
            report.open('['); report.value(lo.x); report.value(lo.y); report.value(lo.z); report.close(']');
            report.key("max");
            report.open('['); report.value(hi.x); report.value(hi.y); report.value(hi.z); report.close(']');
        }
        report.key("points");
        report.open('[');
        for (const aiVector3D& p : points) {
            report.value(std::round(p.x * 1e4) / 1e4);
            report.value(std::round(p.y * 1e4) / 1e4);
            report.value(std::round(p.z * 1e4) / 1e4);
        }
        report.close(']');
        // Faces as indices into `points` (polygons fanned), so a consumer can
        // split a UCX_ mesh into its disconnected convex pieces.
        report.key("triangles");
        report.open('[');
        for (unsigned int f = 0; f < mesh->mNumFaces; ++f) {
            const aiFace& face = mesh->mFaces[f];
            for (unsigned int k = 2; k < face.mNumIndices; ++k) {
                report.value(face.mIndices[0]);
                report.value(face.mIndices[k - 1]);
                report.value(face.mIndices[k]);
            }
        }
        report.close(']');
        report.close('}');
    }
    report.close(']');

    if (hulls.empty()) return;

    // Materials only the hulls used go with them.
    std::vector<bool> usedBefore(scene->mNumMaterials, false), usedAfter(scene->mNumMaterials, false);
    for (unsigned int m = 0; m < scene->mNumMeshes; ++m) {
        const unsigned int mat = scene->mMeshes[m]->mMaterialIndex;
        if (mat < scene->mNumMaterials) {
            usedBefore[mat] = true;
            if (!drop[m]) usedAfter[mat] = true;
        }
    }

    std::vector<int> remap(scene->mNumMeshes, -1);
    unsigned int kept = 0;
    for (unsigned int m = 0; m < scene->mNumMeshes; ++m) {
        if (drop[m]) {
            delete scene->mMeshes[m];
            scene->mMeshes[m] = nullptr;
        } else {
            remap[m] = static_cast<int>(kept);
            scene->mMeshes[kept++] = scene->mMeshes[m];
        }
    }
    scene->mNumMeshes = kept;
    if (scene->mRootNode) pruneNodes(scene->mRootNode, remap);

    std::vector<int> matRemap(scene->mNumMaterials, -1);
    unsigned int keptMats = 0;
    for (unsigned int i = 0; i < scene->mNumMaterials; ++i) {
        if (usedBefore[i] && !usedAfter[i]) {
            delete scene->mMaterials[i];
            scene->mMaterials[i] = nullptr;
        } else {
            matRemap[i] = static_cast<int>(keptMats);
            scene->mMaterials[keptMats++] = scene->mMaterials[i];
        }
    }
    scene->mNumMaterials = keptMats;
    for (unsigned int m = 0; m < scene->mNumMeshes; ++m) {
        const unsigned int mat = scene->mMeshes[m]->mMaterialIndex;
        if (mat < matRemap.size() && matRemap[mat] >= 0) {
            scene->mMeshes[m]->mMaterialIndex = static_cast<unsigned int>(matRemap[mat]);
        }
    }
}

// ---------------------------------------------------------------------------

void countNodes(const aiNode* node, unsigned int& n) {
    if (!node) return;
    ++n;
    for (unsigned int i = 0; i < node->mNumChildren; ++i) countNodes(node->mChildren[i], n);
}

// ---------------------------------------------------------------------------
// Material details: what Assimp read for every material, in
// scene order (= the glTF exporter's material order, after the collision
// strip). The glTF exporter reduces a Phong material to base colour plus a
// roughness guess; the importer maps the FBX values to PBR itself.

const char* shadingLabel(int mode) {
    switch (mode) {
        case aiShadingMode_Flat: return "flat";
        case aiShadingMode_Gouraud: return "lambert";
        case aiShadingMode_Phong: return "phong";
        case aiShadingMode_Blinn: return "blinn";
        case aiShadingMode_Toon: return "toon";
        case aiShadingMode_OrenNayar: return "oren_nayar";
        case aiShadingMode_Minnaert: return "minnaert";
        case aiShadingMode_CookTorrance: return "cook_torrance";
        case aiShadingMode_NoShading: return "unlit";
        case aiShadingMode_Fresnel: return "fresnel";
        default: return "unknown";
    }
}

const char* textureTypeLabel(aiTextureType t) {
    switch (t) {
        case aiTextureType_DIFFUSE: return "diffuse";
        case aiTextureType_SPECULAR: return "specular";
        case aiTextureType_AMBIENT: return "ambient";
        case aiTextureType_EMISSIVE: return "emissive";
        case aiTextureType_HEIGHT: return "height";
        case aiTextureType_NORMALS: return "normals";
        case aiTextureType_SHININESS: return "shininess";
        case aiTextureType_OPACITY: return "opacity";
        case aiTextureType_DISPLACEMENT: return "displacement";
        case aiTextureType_LIGHTMAP: return "lightmap";
        case aiTextureType_REFLECTION: return "reflection";
        case aiTextureType_BASE_COLOR: return "base_color";
        case aiTextureType_NORMAL_CAMERA: return "normal_camera";
        case aiTextureType_EMISSION_COLOR: return "emission_color";
        case aiTextureType_METALNESS: return "metalness";
        case aiTextureType_DIFFUSE_ROUGHNESS: return "roughness";
        case aiTextureType_AMBIENT_OCCLUSION: return "ambient_occlusion";
        default: return "unknown";
    }
}

void writeMaterialDetails(const aiScene* scene, Json& report) {
    report.key("material_details");
    report.open('[');
    for (unsigned int i = 0; i < scene->mNumMaterials; ++i) {
        const aiMaterial* mat = scene->mMaterials[i];
        report.open('{');
        aiString name;
        report.key("name");
        report.value(mat->Get(AI_MATKEY_NAME, name) == AI_SUCCESS ? std::string(name.C_Str()) : std::string());
        int shading = 0;
        if (mat->Get(AI_MATKEY_SHADING_MODEL, shading) == AI_SUCCESS) {
            report.key("shading_model");
            report.value(std::string(shadingLabel(shading)));
        }
        auto color = [&](const char* key, const char* k, unsigned int t, unsigned int idx) {
            aiColor4D c;
            if (aiGetMaterialColor(mat, k, t, idx, &c) != AI_SUCCESS) return;
            report.key(key);
            report.open('[');
            report.value(c.r); report.value(c.g); report.value(c.b);
            report.close(']');
        };
        auto scalar = [&](const char* key, const char* k, unsigned int t, unsigned int idx) {
            ai_real v;
            if (mat->Get(k, t, idx, v) != AI_SUCCESS) return;
            report.key(key);
            report.value(v);
        };
        color("diffuse", AI_MATKEY_COLOR_DIFFUSE);
        color("emissive", AI_MATKEY_COLOR_EMISSIVE);
        color("specular", AI_MATKEY_COLOR_SPECULAR);
        color("ambient", AI_MATKEY_COLOR_AMBIENT);
        color("transparent", AI_MATKEY_COLOR_TRANSPARENT);
        color("reflective", AI_MATKEY_COLOR_REFLECTIVE);
        scalar("shininess", AI_MATKEY_SHININESS);
        scalar("shininess_strength", AI_MATKEY_SHININESS_STRENGTH);
        scalar("opacity", AI_MATKEY_OPACITY);
        scalar("transparency_factor", AI_MATKEY_TRANSPARENCYFACTOR);
        scalar("reflectivity", AI_MATKEY_REFLECTIVITY);
        scalar("bump_scaling", AI_MATKEY_BUMPSCALING);
        // PBR values some exporters write as raw FBX properties (Maya
        // Stingray PBS / Arnold, 3ds Max Physical).
        scalar("raw_emissive_factor", "$raw.EmissiveFactor", 0, 0);
        scalar("raw_metalness", "$raw.Maya|metallic", 0, 0);
        scalar("raw_roughness", "$raw.Maya|roughness", 0, 0);
        scalar("raw_max_metalness", "$raw.3dsMax|Parameters|metalness", 0, 0);
        scalar("raw_max_roughness", "$raw.3dsMax|Parameters|roughness", 0, 0);

        report.key("textures");
        report.open('[');
        for (int t = aiTextureType_DIFFUSE; t < AI_TEXTURE_TYPE_MAX; ++t) {
            const aiTextureType type = static_cast<aiTextureType>(t);
            const unsigned int count = mat->GetTextureCount(type);
            for (unsigned int n = 0; n < count; ++n) {
                aiString path;
                unsigned int uv = 0;
                if (mat->GetTexture(type, n, &path, nullptr, &uv) != AI_SUCCESS) continue;
                const std::string p = path.C_Str();
                const bool embedded = (!p.empty() && p[0] == '*') || scene->GetEmbeddedTexture(p.c_str()) != nullptr;
                report.open('{');
                report.key("type"); report.value(std::string(textureTypeLabel(type)));
                report.key("path"); report.value(p);
                report.key("embedded"); report.boolean(embedded);
                report.key("uv"); report.value(uv);
                report.close('}');
            }
        }
        report.close(']');
        report.close('}');
    }
    report.close(']');
}

// Normalizes/strips [scene] per [options] and writes the report.
void processScene(aiScene* scene, unsigned int options) {
    Json report;
    report.open('{');

    // Source metadata as read, before anything changes it.
    report.key("source_metadata");
    report.open('{');
    static const char* keys[] = {
        "UpAxis", "UpAxisSign", "FrontAxis", "FrontAxisSign", "CoordAxis", "CoordAxisSign",
        "OriginalUpAxis", "OriginalUpAxisSign", "UnitScaleFactor", "OriginalUnitScaleFactor",
        "FrameRate", "CustomFrameRate",
    };
    for (const char* k : keys) {
        double v;
        if (metaNumber(scene->mMetaData, k, v)) {
            report.key(k);
            report.value(v);
        }
    }
    report.close('}');

    const Normalization n = normalize(scene, (options & ASSIMP_CONVERT_NORMALIZE) != 0);
    report.key("normalized"); report.boolean(n.applied);
    report.key("unit_scale"); report.value(n.applied ? n.scale : 1.0);
    if (n.axesFound) {
        report.key("up_axis"); report.value(axisLabel(n.upAxis, n.upSign));
        report.key("front_axis"); report.value(axisLabel(n.frontAxis, n.frontSign));
        report.key("coord_axis"); report.value(axisLabel(n.coordAxis, n.coordSign));
    }
    report.key("axis_rows");
    report.open('[');
    for (unsigned int r = 0; r < 3; ++r) {
        report.open('[');
        for (unsigned int c = 0; c < 3; ++c) report.value(n.applied ? n.C[r][c] : (r == c ? 1.0 : 0.0));
        report.close(']');
    }
    report.close(']');

    if (options & ASSIMP_CONVERT_STRIP_COLLISION) {
        stripCollision(scene, report);
    }

    report.key("takes");
    report.open('[');
    for (unsigned int a = 0; a < scene->mNumAnimations; ++a) {
        const aiAnimation* anim = scene->mAnimations[a];
        const double tps = anim->mTicksPerSecond != 0 ? anim->mTicksPerSecond : 25.0;
        report.open('{');
        report.key("name"); report.value(std::string(anim->mName.C_Str()));
        report.key("channels"); report.value(anim->mNumChannels);
        report.key("duration_seconds"); report.value(anim->mDuration / tps);
        report.key("ticks_per_second"); report.value(anim->mTicksPerSecond);
        report.close('}');
    }
    report.close(']');

    unsigned int skinned = 0, bones = 0, nodes = 0;
    for (unsigned int m = 0; m < scene->mNumMeshes; ++m) {
        if (scene->mMeshes[m]->mNumBones > 0) ++skinned;
        bones += scene->mMeshes[m]->mNumBones;
    }
    countNodes(scene->mRootNode, nodes);
    report.key("meshes"); report.value(scene->mNumMeshes);
    report.key("skinned_meshes"); report.value(skinned);
    report.key("bone_references"); report.value(bones);
    report.key("materials"); report.value(scene->mNumMaterials);
    writeMaterialDetails(scene, report);
    report.key("nodes"); report.value(nodes);
    report.close('}');
    lastReport() = report.out;
}

void configure(Assimp::Importer& importer) {
    // Pivot helper nodes ("<bone>_$AssimpFbx$_Rotation", …) would rename the
    // bones animations target; bake pivots into the node transforms instead.
    importer.SetPropertyBool(AI_CONFIG_IMPORT_FBX_PRESERVE_PIVOTS, false);
#ifdef FLUTTER_ASSIMP_EXTRA_IMPORTERS
    // The importer owns (and deletes) what it is given.
    importer.RegisterLoader(new Assimp::ColladaLoader());
    importer.RegisterLoader(new Assimp::Discreet3DSImporter());
    importer.RegisterLoader(new Assimp::PLYImporter());
    importer.RegisterLoader(new Assimp::XFileImporter());
    importer.RegisterLoader(new Assimp::STLImporter());
#endif
}

}  // namespace

extern "C" {

ASSIMP_EXPORT const char* assimp_get_version() {
    // The "revision" is the git commit Assimp was built from, not a number.
    static std::string ver = [] {
        char buf[64];
        snprintf(buf, sizeof buf, "%u.%u (commit %08x)", aiGetVersionMajor(), aiGetVersionMinor(),
                 aiGetVersionRevision());
        return std::string(buf);
    }();
    return ver.c_str();
}

ASSIMP_EXPORT const char* assimp_get_last_error() {
    return lastError().c_str();
}

ASSIMP_EXPORT const char* assimp_get_last_report() {
    return lastReport().c_str();
}

ASSIMP_EXPORT const char* assimp_get_import_extensions() {
    static std::string list = [] {
        Assimp::Importer importer;
        configure(importer);
        std::string out;
        importer.GetExtensionList(out);
        return out;
    }();
    return list.c_str();
}

ASSIMP_EXPORT void assimp_free_blob(uint8_t* blob) {
    if (blob) {
        free(blob);
    }
}

ASSIMP_EXPORT int assimp_convert_file_to_glb_ex(
    const char* input_path,
    const char* output_path,
    unsigned int post_process_flags,
    unsigned int options
) {
    lastReport() = "{}";
    if (!input_path || !output_path) {
        lastError() = "Null input or output path";
        return 0;
    }
    if (post_process_flags == 0) {
        post_process_flags = kDefaultFlags;
        if (options != 0) post_process_flags |= aiProcess_LimitBoneWeights;
    }

    Assimp::Importer importer;
    configure(importer);
    if (!importer.ReadFile(input_path, post_process_flags)) {
        lastError() = importer.GetErrorString();
        return 0;
    }
    std::unique_ptr<aiScene> scene(importer.GetOrphanedScene());
    if (!scene) {
        lastError() = "Importer returned no scene";
        return 0;
    }
    processScene(scene.get(), options);

    Assimp::Exporter exporter;
    aiReturn ret = exporter.Export(scene.get(), "glb2", output_path);
    if (ret != aiReturn_SUCCESS) {
        lastError() = exporter.GetErrorString();
        return 0;
    }
    return 1;
}

ASSIMP_EXPORT int assimp_convert_memory_to_glb_ex(
    const uint8_t* in_bytes,
    size_t in_len,
    const char* format_hint,
    uint8_t** out_bytes,
    size_t* out_len,
    unsigned int post_process_flags,
    unsigned int options
) {
    lastReport() = "{}";
    if (!in_bytes || in_len == 0 || !out_bytes || !out_len) {
        lastError() = "Invalid arguments to memory conversion";
        return 0;
    }
    if (post_process_flags == 0) {
        post_process_flags = kDefaultFlags;
        if (options != 0) post_process_flags |= aiProcess_LimitBoneWeights;
    }

    Assimp::Importer importer;
    configure(importer);
    const char* hint = format_hint ? format_hint : "";
    if (!importer.ReadFileFromMemory(in_bytes, in_len, post_process_flags, hint)) {
        lastError() = importer.GetErrorString();
        return 0;
    }
    std::unique_ptr<aiScene> scene(importer.GetOrphanedScene());
    if (!scene) {
        lastError() = "Importer returned no scene";
        return 0;
    }
    processScene(scene.get(), options);

    Assimp::Exporter exporter;
    const aiExportDataBlob* blob = exporter.ExportToBlob(scene.get(), "glb2");
    if (!blob) {
        lastError() = exporter.GetErrorString();
        return 0;
    }

    *out_len = blob->size;
    *out_bytes = (uint8_t*)malloc(blob->size);
    if (!*out_bytes) {
        lastError() = "Out of memory allocating blob output";
        return 0;
    }
    memcpy(*out_bytes, blob->data, blob->size);
    return 1;
}

ASSIMP_EXPORT int assimp_convert_file_to_glb(
    const char* input_path,
    const char* output_path,
    unsigned int post_process_flags
) {
    return assimp_convert_file_to_glb_ex(input_path, output_path, post_process_flags, 0);
}

ASSIMP_EXPORT int assimp_convert_memory_to_glb(
    const uint8_t* in_bytes,
    size_t in_len,
    const char* format_hint,
    uint8_t** out_bytes,
    size_t* out_len,
    unsigned int post_process_flags
) {
    return assimp_convert_memory_to_glb_ex(in_bytes, in_len, format_hint, out_bytes, out_len, post_process_flags, 0);
}

}
