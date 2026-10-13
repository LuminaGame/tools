// C API of flutter_jolt (see jolt_c.h).

#include "jolt_c.h"

#if defined(_WIN32)
#include <windows.h>
#elif !defined(__EMSCRIPTEN__)
#include <pthread.h>
#endif

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Body/BodyLockMulti.h>
#include <Jolt/Physics/Collision/AABoxCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/HeightFieldShape.h>
#include <Jolt/Physics/Collision/Shape/OffsetCenterOfMassShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/Collision/Shape/ScaledShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/SimShapeFilter.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Constraints/SwingTwistConstraint.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/SoftBody/SoftBodyContactListener.h>
#include <Jolt/Physics/SoftBody/SoftBodyCreationSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>
#include <Jolt/Physics/SoftBody/SoftBodySharedSettings.h>
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <condition_variable>
#include <functional>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>
#include <unordered_set>
#include <vector>

using namespace JPH;

namespace {

// --- Process-wide setup ---------------------------------------------------------

std::once_flag g_init_once;

#ifdef JPH_ENABLE_ASSERTS
// A build of Jolt with asserts (diagnostics only) logs every failed assert to
// stderr and to the file JOLT_ASSERT_LOG names, then continues.
bool logAssert(const char* expression, const char* message, const char* file, uint line) {
  char text[1024];
  std::snprintf(text, sizeof(text), "Jolt assert: %s (%s) at %s:%u\n", expression, message != nullptr ? message : "",
                file, line);
  std::fputs(text, stderr);
  std::fflush(stderr);
  if (const char* path = std::getenv("JOLT_ASSERT_LOG")) {
    if (FILE* f = std::fopen(path, "a")) {
      std::fputs(text, f);
      std::fclose(f);
    }
  }
  return false;
}
#endif

void ensureJolt() {
  std::call_once(g_init_once, [] {
#ifdef JPH_ENABLE_ASSERTS
    AssertFailed = logAssert;
#endif
    RegisterDefaultAllocator();
    Factory::sInstance = new Factory();
    RegisterTypes();
  });
}

// A shape whose user data is this value is a container (compound, decorator):
// the sub-shape filter only judges leaves.
constexpr uint64 kContainerUserData = 0xFFFFFFFFull;

// --- Layers: one for things that move, one for things that do not -----------------

namespace Layers {
constexpr ObjectLayer kNonMoving = 0;
constexpr ObjectLayer kMoving = 1;
constexpr ObjectLayer kCount = 2;
}  // namespace Layers

namespace BroadPhaseLayers {
const BroadPhaseLayer kNonMoving(0);
const BroadPhaseLayer kMoving(1);
constexpr uint kCount = 2;
}  // namespace BroadPhaseLayers

class LayerInterface final : public BroadPhaseLayerInterface {
 public:
  uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::kCount; }
  BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer layer) const override {
    return layer == Layers::kNonMoving ? BroadPhaseLayers::kNonMoving : BroadPhaseLayers::kMoving;
  }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
  const char* GetBroadPhaseLayerName(BroadPhaseLayer layer) const override {
    return layer == BroadPhaseLayers::kNonMoving ? "NON_MOVING" : "MOVING";
  }
#endif
};

class ObjectVsBroadPhaseFilter final : public ObjectVsBroadPhaseLayerFilter {
 public:
  bool ShouldCollide(ObjectLayer layer, BroadPhaseLayer broad) const override {
    return layer == Layers::kMoving || broad == BroadPhaseLayers::kMoving;
  }
};

class ObjectPairFilter final : public ObjectLayerPairFilter {
 public:
  bool ShouldCollide(ObjectLayer a, ObjectLayer b) const override {
    return a == Layers::kMoving || b == Layers::kMoving;
  }
};

ObjectLayer layerFor(EMotionType type) {
  return type == EMotionType::Static ? Layers::kNonMoving : Layers::kMoving;
}

// --- Per-body filter data ----------------------------------------------------

struct BodyData {
  bool used = false;
  uint64 owner = 0;
  bool collidesWithOwner = false;
  bool clothCollider = false;
  float selfCollision = 0.0f;  // a cloth's self-collision distance (m), 0: off
  uint32_t selfCollisionBody = 0;  // its full body id
  std::vector<uint16> profiles;
  float friction = 0.7f;
  float staticFriction = 0.7f;
  float restitution = 0.1f;
  int32_t frictionMode = 0;
  int32_t restitutionMode = 0;
};

float combine(float a, float b, int32_t mode) {
  switch (mode) {
    case 1:
      return std::min(a, b);
    case 2:
      return a * b;
    case 3:
      return std::max(a, b);
    default:
      return 0.5f * (a + b);
  }
}

uint64 pairKey(BodyID a, BodyID b) {
  uint32 x = a.GetIndexAndSequenceNumber(), y = b.GetIndexAndSequenceNumber();
  if (x > y) std::swap(x, y);
  return (uint64(x) << 32) | uint64(y);
}

Vec3 vec3(const float* v) { return Vec3(v[0], v[1], v[2]); }
Quat quat(const float* q) {
  Quat r(q[0], q[1], q[2], q[3]);
  return r.LengthSq() > 0.0f ? r.Normalized() : Quat::sIdentity();
}
void store(Vec3Arg v, float* out) {
  out[0] = v.GetX();
  out[1] = v.GetY();
  out[2] = v.GetZ();
}

}  // namespace


// --- Stepping thread -------------------------------------------------------------

#if defined(__EMSCRIPTEN__)
// WebAssembly (single-threaded, no SharedArrayBuffer): the step runs on the
// calling thread, whose stack the module sets large enough (STACK_SIZE in
// tool/web/build_jolt_wasm.sh).
class Stepper {
 public:
  void run(const std::function<void()>& work) { work(); }
};
#else
// Runs the world's steps on a thread of its own with a large stack. The narrow
// phase (GJK/EPA, convex hull contacts) and the solver can use far more stack
// than the thread that calls in has to spare: a Dart mutator thread runs with
// a small stack whose neighbouring memory the VM owns, and a deep Jolt step on
// it corrupted the VM. The caller blocks until the step is done.
class Stepper {
 public:
  static constexpr size_t kStackBytes = 16u << 20;

  Stepper() {
#if defined(_WIN32)
    handle_ = CreateThread(nullptr, kStackBytes, &Stepper::entry, this, STACK_SIZE_PARAM_IS_A_RESERVATION, nullptr);
#else
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, kStackBytes);
    pthread_create(&thread_, &attr, &Stepper::entryPosix, this);
    pthread_attr_destroy(&attr);
#endif
  }

  ~Stepper() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      quit_ = true;
    }
    wake_.notify_all();
#if defined(_WIN32)
    WaitForSingleObject(handle_, INFINITE);
    CloseHandle(handle_);
#else
    pthread_join(thread_, nullptr);
#endif
  }

  /// Runs [work] on the stepping thread and returns when it finished.
  void run(const std::function<void()>& work) {
    std::unique_lock<std::mutex> lock(mutex_);
    work_ = &work;
    finished_ = false;
    wake_.notify_all();
    done_.wait(lock, [this] { return finished_; });
    work_ = nullptr;
  }

 private:
  void loop() {
    std::unique_lock<std::mutex> lock(mutex_);
    for (;;) {
      wake_.wait(lock, [this] { return quit_ || (work_ != nullptr && !finished_); });
      if (quit_) return;
      const std::function<void()>* work = work_;
      lock.unlock();
      (*work)();
      lock.lock();
      finished_ = true;
      done_.notify_all();
    }
  }

#if defined(_WIN32)
  static DWORD WINAPI entry(LPVOID self) {
    static_cast<Stepper*>(self)->loop();
    return 0;
  }
  HANDLE handle_ = nullptr;
#else
  static void* entryPosix(void* self) {
    static_cast<Stepper*>(self)->loop();
    return nullptr;
  }
  pthread_t thread_{};
#endif
  std::mutex mutex_;
  std::condition_variable wake_;
  std::condition_variable done_;
  const std::function<void()>* work_ = nullptr;
  bool finished_ = true;
  bool quit_ = false;
};
#endif

// --- World ----------------------------------------------------------------------

struct JoltShape {
  RefConst<Shape> shape;
};

struct JoltConstraint {
  Ref<TwoBodyConstraint> constraint;
  bool hinge = false;
};

struct JoltWorld : public ContactListener, public SimShapeFilter, public SoftBodyContactListener {
  std::unique_ptr<TempAllocatorImpl> temp;
  std::unique_ptr<JobSystem> jobs;
  // The thread steps run on; stopped first in jolt_world_destroy.
  std::unique_ptr<Stepper> stepper;
  LayerInterface layers;
  ObjectVsBroadPhaseFilter objectVsBroadPhase;
  ObjectPairFilter objectPair;
  PhysicsSystem system;

  std::vector<BodyData> bodies;  // by BodyID index
  std::unordered_set<uint64> ignored;
  std::vector<uint8_t> matrix;
  uint32_t profileCount = 0;

  std::mutex contactsMutex;
  std::vector<JoltContact> contacts;
  std::vector<JoltConstraint*> constraints;

  BodyData& data(BodyID id) {
    const uint32 index = id.GetIndex();
    if (index >= bodies.size()) bodies.resize(index + 1);
    return bodies[index];
  }
  const BodyData* find(const Body& body) const {
    const uint32 index = body.GetID().GetIndex();
    return index < bodies.size() && bodies[index].used ? &bodies[index] : nullptr;
  }

  bool profilesBlock(const BodyData* a, uint64 shapeA, const BodyData* b, uint64 shapeB) const {
    if (a == nullptr || b == nullptr || profileCount == 0) return true;
    const uint32 pa = shapeA < a->profiles.size() ? a->profiles[shapeA] : 0xFFFF;
    const uint32 pb = shapeB < b->profiles.size() ? b->profiles[shapeB] : 0xFFFF;
    if (pa >= profileCount || pb >= profileCount) return true;
    return matrix[pa * profileCount + pb] != 0;
  }

  // SimShapeFilter: profiles per leaf, owners and ignored pairs per body.
  bool ShouldCollide(const Body& body1, const Shape* shape1, const SubShapeID&, const Body& body2,
                     const Shape* shape2, const SubShapeID&) const override {
    const BodyData* a = find(body1);
    const BodyData* b = find(body2);
    if (a != nullptr && b != nullptr) {
      // Soft bodies decide about their owner in OnSoftBodyContactValidate.
      if (a->owner != 0 && a->owner == b->owner && !body1.IsSoftBody() && !body2.IsSoftBody()) {
        const bool bothBodies = !body1.IsStatic() && !body2.IsStatic();
        if (!(bothBodies && a->collidesWithOwner && b->collidesWithOwner)) return false;
      }
      if (!ignored.empty() && ignored.count(pairKey(body1.GetID(), body2.GetID())) != 0) return false;
    }
    const uint64 u1 = shape1->GetUserData(), u2 = shape2->GetUserData();
    if (u1 == kContainerUserData || u2 == kContainerUserData) return true;
    return profilesBlock(a, u1, b, u2);
  }

  void settle(const Body& body1, const Body& body2, const ContactManifold& manifold, ContactSettings& settings,
              bool persisted) {
    const BodyData* a = find(body1);
    const BodyData* b = find(body2);
    if (a != nullptr && b != nullptr) {
      const int32_t fMode = std::max(a->frictionMode, b->frictionMode);
      const int32_t rMode = std::max(a->restitutionMode, b->restitutionMode);
      // Static friction while the surfaces barely slide, dynamic otherwise.
      const Vec3 n = manifold.mWorldSpaceNormal;
      const RVec3 p = manifold.GetWorldSpaceContactPointOn1(0);
      Vec3 rel = body2.GetPointVelocity(p) - body1.GetPointVelocity(p);
      rel -= n * rel.Dot(n);
      const bool resting = rel.LengthSq() < 0.01f * 0.01f;
      settings.mCombinedFriction = resting ? combine(a->staticFriction, b->staticFriction, fMode)
                                           : combine(a->friction, b->friction, fMode);
      settings.mCombinedRestitution = combine(a->restitution, b->restitution, rMode);
    }
    JoltContact c{};
    c.body_a = body1.GetID().GetIndexAndSequenceNumber();
    c.body_b = body2.GetID().GetIndexAndSequenceNumber();
    c.shape_a = uint32(body1.GetShape()->GetSubShapeUserData(manifold.mSubShapeID1));
    c.shape_b = uint32(body2.GetShape()->GetSubShapeUserData(manifold.mSubShapeID2));
    Vec3 point = Vec3::sZero();
    const uint count = manifold.mRelativeContactPointsOn1.size();
    for (uint i = 0; i < count; ++i) point += Vec3(manifold.GetWorldSpaceContactPointOn1(i));
    // The normal impulse that stops the bodies approaching at the contact
    // (with restitution), through the centres of mass: an estimate for hit
    // events, read from the two bodies only.
    const float inv1 = body1.IsDynamic() ? body1.GetMotionProperties()->GetInverseMass() : 0.0f;
    const float inv2 = body2.IsDynamic() ? body2.GetMotionProperties()->GetInverseMass() : 0.0f;
    float impulse = 0.0f;
    if (count > 0 && inv1 + inv2 > 0.0f) {
      const RVec3 mean(point / float(count));
      const float approach = (body2.GetPointVelocity(mean) - body1.GetPointVelocity(mean)).Dot(manifold.mWorldSpaceNormal);
      if (approach < 0.0f) impulse = -(1.0f + settings.mCombinedRestitution) * approach / (inv1 + inv2);
    }
    if (count > 0) point /= float(count);
    store(point, c.point);
    store(manifold.mWorldSpaceNormal, c.normal);
    c.impulse = impulse;
    c.penetration = manifold.mPenetrationDepth;
    c.point_count = int32_t(count);
    c.persisted = persisted;
    std::lock_guard<std::mutex> lock(contactsMutex);
    contacts.push_back(c);
  }

  // A cloth ignores the other bodies of its owner (a character's own
  // capsule) except those marked as its colliders (the limb capsules).
  SoftBodyValidateResult OnSoftBodyContactValidate(const Body& softBody, const Body& other,
                                                   SoftBodyContactSettings&) override {
    const BodyData* a = find(softBody);
    const BodyData* b = find(other);
    if (a != nullptr && b != nullptr && a->owner != 0 && a->owner == b->owner && !b->clothCollider) {
      return SoftBodyValidateResult::RejectContact;
    }
    return SoftBodyValidateResult::AcceptContact;
  }

  void OnContactAdded(const Body& body1, const Body& body2, const ContactManifold& manifold,
                      ContactSettings& settings) override {
    settle(body1, body2, manifold, settings, false);
  }
  void OnContactPersisted(const Body& body1, const Body& body2, const ContactManifold& manifold,
                          ContactSettings& settings) override {
    settle(body1, body2, manifold, settings, true);
  }
};

namespace {

JoltShape* wrap(const ShapeSettings::ShapeResult& result, bool container) {
  if (result.HasError()) return nullptr;
  auto* out = new JoltShape();
  out->shape = result.Get();
  if (container) const_cast<Shape*>(out->shape.GetPtr())->SetUserData(kContainerUserData);
  return out;
}

BodyInterface& bodies(JoltWorld* w) { return w->system.GetBodyInterface(); }

BodyID bodyId(uint32_t id) { return BodyID(id); }

}  // namespace

// Collects the user data of the bodies a broad phase query finds.
namespace {
template <class Base, class Result>
class UserDataCollector final : public Base {
 public:
  UserDataCollector(BodyInterface& bodies, uint64_t* out, uint32_t max) : mBodies(bodies), mOut(out), mMax(max) {}
  void AddHit(const Result& result) override {
    if (mCount < mMax) mOut[mCount] = mBodies.GetUserData(bodyOf(result));
    ++mCount;
  }
  uint32_t mCount = 0;

 private:
  static BodyID bodyOf(const BroadPhaseCastResult& r) { return r.mBodyID; }
  static BodyID bodyOf(const BodyID& r) { return r; }
  BodyInterface& mBodies;
  uint64_t* mOut;
  uint32_t mMax;
};
}  // namespace

extern "C" {

int32_t jolt_version(void) { return JPH_VERSION_MAJOR * 10000 + JPH_VERSION_MINOR * 100 + JPH_VERSION_PATCH; }

uint32_t jolt_invalid_body_id(void) { return BodyID::cInvalidBodyID; }

JoltWorld* jolt_world_create(const JoltWorldSettings* settings) {
  ensureJolt();
  JoltWorldSettings s{};
  if (settings != nullptr) s = *settings;
  const uint maxBodies = s.max_bodies != 0 ? s.max_bodies : 65536;
  const uint maxPairs = s.max_body_pairs != 0 ? s.max_body_pairs : 65536;
  const uint maxContacts = s.max_contact_constraints != 0 ? s.max_contact_constraints : 16384;
  const uint tempBytes = s.temp_allocator_bytes != 0 ? s.temp_allocator_bytes : 16u * 1024u * 1024u;
  int threads = s.worker_threads;
  if (threads < 0) threads = std::max(1, int(std::thread::hardware_concurrency()) - 1);

  auto* w = new JoltWorld();
  w->temp = std::make_unique<TempAllocatorImpl>(tempBytes);
#if defined(__EMSCRIPTEN__)
  (void)threads;
  w->jobs = std::make_unique<JobSystemSingleThreaded>(cMaxPhysicsJobs);
#else
  w->jobs = std::make_unique<JobSystemThreadPool>(cMaxPhysicsJobs, cMaxPhysicsBarriers, threads);
#endif
  w->system.Init(maxBodies, 0, maxPairs, maxContacts, w->layers, w->objectVsBroadPhase, w->objectPair);
  w->system.SetContactListener(w);
  w->system.SetSimShapeFilter(w);
  w->system.SetSoftBodyContactListener(w);
  w->stepper = std::make_unique<Stepper>();
  return w;
}

void jolt_world_destroy(JoltWorld* world) {
  if (world == nullptr) return;
  world->stepper.reset();
  for (JoltConstraint* c : world->constraints) {
    world->system.RemoveConstraint(c->constraint);
    delete c;
  }
  world->constraints.clear();
  BodyIDVector ids;
  world->system.GetBodies(ids);
  BodyInterface& bi = bodies(world);
  if (!ids.empty()) {
    bi.RemoveBodies(ids.data(), int(ids.size()));
    bi.DestroyBodies(ids.data(), int(ids.size()));
  }
  delete world;
}

void jolt_world_set_gravity(JoltWorld* world, float x, float y, float z) { world->system.SetGravity(Vec3(x, y, z)); }

void jolt_world_get_gravity(JoltWorld* world, float* out3) { store(world->system.GetGravity(), out3); }

void jolt_world_get_solver_settings(JoltWorld* world, JoltSolverSettings* out) {
  const PhysicsSettings& p = world->system.GetPhysicsSettings();
  out->velocity_steps = int32_t(p.mNumVelocitySteps);
  out->position_steps = int32_t(p.mNumPositionSteps);
  out->baumgarte = p.mBaumgarte;
  out->speculative_contact_distance = p.mSpeculativeContactDistance;
  out->penetration_slop = p.mPenetrationSlop;
  out->time_before_sleep = p.mTimeBeforeSleep;
  out->point_velocity_sleep_threshold = p.mPointVelocitySleepThreshold;
  out->allow_sleeping = p.mAllowSleeping;
}

void jolt_world_set_solver_settings(JoltWorld* world, const JoltSolverSettings* s) {
  PhysicsSettings p = world->system.GetPhysicsSettings();
  p.mNumVelocitySteps = uint(std::max(1, s->velocity_steps));
  p.mNumPositionSteps = uint(std::max(0, s->position_steps));
  p.mBaumgarte = s->baumgarte;
  p.mSpeculativeContactDistance = s->speculative_contact_distance;
  p.mPenetrationSlop = s->penetration_slop;
  p.mTimeBeforeSleep = s->time_before_sleep;
  p.mPointVelocitySleepThreshold = s->point_velocity_sleep_threshold;
  p.mAllowSleeping = s->allow_sleeping;
  world->system.SetPhysicsSettings(p);
}

// --- Cloth self-collision -------------------------------------------------

static SoftBodyMotionProperties* softBody(Body& body);

// The point of triangle abc closest to p, as barycentric weights (u, v, w)
// of a, b, c (Ericson, Real-Time Collision Detection 5.1.5).
static Vec3 closestOnTriangle(Vec3 p, Vec3 a, Vec3 b, Vec3 c, float& u, float& v, float& w) {
  const Vec3 ab = b - a, ac = c - a, ap = p - a;
  const float d1 = ab.Dot(ap), d2 = ac.Dot(ap);
  if (d1 <= 0.0f && d2 <= 0.0f) { u = 1; v = 0; w = 0; return a; }
  const Vec3 bp = p - b;
  const float d3 = ab.Dot(bp), d4 = ac.Dot(bp);
  if (d3 >= 0.0f && d4 <= d3) { u = 0; v = 1; w = 0; return b; }
  const float vc = d1 * d4 - d3 * d2;
  if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f) {
    const float t = d1 / (d1 - d3);
    u = 1 - t; v = t; w = 0;
    return a + ab * t;
  }
  const Vec3 cp = p - c;
  const float d5 = ab.Dot(cp), d6 = ac.Dot(cp);
  if (d6 >= 0.0f && d5 <= d6) { u = 0; v = 0; w = 1; return c; }
  const float vb = d5 * d2 - d1 * d6;
  if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f) {
    const float t = d2 / (d2 - d6);
    u = 1 - t; v = 0; w = t;
    return a + ac * t;
  }
  const float va = d3 * d6 - d5 * d4;
  if (va <= 0.0f && (d4 - d3) >= 0.0f && (d5 - d6) >= 0.0f) {
    const float t = (d4 - d3) / ((d4 - d3) + (d5 - d6));
    u = 0; v = 1 - t; w = t;
    return b + (c - b) * t;
  }
  const float denom = 1.0f / (va + vb + vc);
  v = vb * denom; w = vc * denom; u = 1 - v - w;
  return a + ab * v + ac * w;
}

// Keeps the vertices of one cloth at least distance away from its own
// triangles (one pass over a grid of cells): a vertex closer than that to a
// triangle it is not part of is pushed out, the triangle back by its
// barycentric weights, and their approaching velocity is removed. A vertex
// that close to the triangle at rest is its neighbour and skipped.
static void selfCollide(JoltWorld* world, BodyID id, float distance) {
  BodyLockWrite lock(world->system.GetBodyLockInterface(), id);
  if (!lock.Succeeded()) return;
  SoftBodyMotionProperties* mp = softBody(lock.GetBody());
  if (mp == nullptr) return;
  const uint32_t n = uint32_t(mp->GetVertices().size());
  const auto& rest = mp->GetSettings()->mVertices;
  const auto& faces = mp->GetFaces();
  if (n < 4 || rest.size() != n || faces.empty()) return;
  // Cells as large as the longest edge (at least the distance), so a
  // triangle's box spans few of them.
  float cell = distance;
  for (const SoftBodySharedSettings::Face& f : faces) {
    for (int k = 0; k < 3; ++k) {
      const Vec3 e = mp->GetVertex(f.mVertex[k]).mPosition - mp->GetVertex(f.mVertex[(k + 1) % 3]).mPosition;
      cell = std::max(cell, e.Length());
    }
  }
  const float inv = 1.0f / cell;
  auto key = [](int64_t x, int64_t y, int64_t z) { return uint64_t((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)); };
  auto coord = [&](float v) { return int64_t(std::floor(v * inv)); };
  const float skip2 = (1.5f * distance) * (1.5f * distance);
  // Vertices sorted by cell; each triangle looks at the cells its box
  // (grown by the distance) covers.
  std::vector<std::pair<uint64_t, uint32_t>> cells(n);
  {
    for (uint32_t i = 0; i < n; ++i) {
      const Vec3 p = mp->GetVertex(i).mPosition;
      cells[i] = {key(coord(p.GetX()), coord(p.GetY()), coord(p.GetZ())), i};
    }
    std::sort(cells.begin(), cells.end());
    for (const SoftBodySharedSettings::Face& f : faces) {
      SoftBodyVertex& a = mp->GetVertex(f.mVertex[0]);
      SoftBodyVertex& b = mp->GetVertex(f.mVertex[1]);
      SoftBodyVertex& c = mp->GetVertex(f.mVertex[2]);
      const Vec3 lo = Vec3::sMin(Vec3::sMin(a.mPosition, b.mPosition), c.mPosition) - Vec3::sReplicate(distance);
      const Vec3 hi = Vec3::sMax(Vec3::sMax(a.mPosition, b.mPosition), c.mPosition) + Vec3::sReplicate(distance);
      for (int64_t x = coord(lo.GetX()); x <= coord(hi.GetX()); ++x)
        for (int64_t y = coord(lo.GetY()); y <= coord(hi.GetY()); ++y)
          for (int64_t z = coord(lo.GetZ()); z <= coord(hi.GetZ()); ++z) {
            const uint64_t k = key(x, y, z);
            auto it = std::lower_bound(cells.begin(), cells.end(), std::make_pair(k, uint32_t(0)));
            for (; it != cells.end() && it->first == k; ++it) {
              const uint32_t i = it->second;
              if (f.mVertex[0] == i || f.mVertex[1] == i || f.mVertex[2] == i) continue;
              SoftBodyVertex& p = mp->GetVertex(i);
              float u, v, w;
              const Vec3 q = closestOnTriangle(p.mPosition, a.mPosition, b.mPosition, c.mPosition, u, v, w);
              const Vec3 delta = p.mPosition - q;
              const float len2 = delta.LengthSq();
              if (len2 >= distance * distance) continue;
              float ru, rv, rw;
              const Vec3 rp(rest[i].mPosition);
              const Vec3 rq = closestOnTriangle(rp, Vec3(rest[f.mVertex[0]].mPosition), Vec3(rest[f.mVertex[1]].mPosition),
                                                Vec3(rest[f.mVertex[2]].mPosition), ru, rv, rw);
              if ((rp - rq).LengthSq() < skip2) continue;
              // Weighted like a point on the triangle with its vertices' masses.
              const float wt = u * u * a.mInvMass + v * v * b.mInvMass + w * w * c.mInvMass;
              const float total = p.mInvMass + wt;
              if (total <= 0.0f) continue;
              const float len = std::sqrt(len2);
              Vec3 normal;
              if (len > 1.0e-6f) {
                normal = delta / len;
              } else {
                normal = (b.mPosition - a.mPosition).Cross(c.mPosition - a.mPosition).NormalizedOr(Vec3::sAxisY());
                if (normal.Dot(p.mVelocity - (a.mVelocity * u + b.mVelocity * v + c.mVelocity * w)) > 0.0f) normal = -normal;
              }
              const float lambda = (distance - len) / total;
              p.mPosition += normal * (lambda * p.mInvMass);
              a.mPosition -= normal * (lambda * u * a.mInvMass);
              b.mPosition -= normal * (lambda * v * b.mInvMass);
              c.mPosition -= normal * (lambda * w * c.mInvMass);
              const Vec3 vt = a.mVelocity * u + b.mVelocity * v + c.mVelocity * w;
              const float approach = normal.Dot(p.mVelocity - vt);
              if (approach < 0.0f) {
                const float impulse = -approach / total;
                p.mVelocity += normal * (impulse * p.mInvMass);
                a.mVelocity -= normal * (impulse * u * a.mInvMass);
                b.mVelocity -= normal * (impulse * v * b.mInvMass);
                c.mVelocity -= normal * (impulse * w * c.mInvMass);
              }
            }
          }
    }
  }
}

static void selfCollideCloths(JoltWorld* world) {
  for (const BodyData& data : world->bodies) {
    if (!data.used || data.selfCollision <= 0.0f) continue;
    selfCollide(world, BodyID(data.selfCollisionBody), data.selfCollision);
  }
}

int32_t jolt_world_step(JoltWorld* world, float dt, int32_t collision_steps) {
  {
    std::lock_guard<std::mutex> lock(world->contactsMutex);
    world->contacts.clear();
  }
  EPhysicsUpdateError error = EPhysicsUpdateError::None;
  const int steps = std::max(1, collision_steps);
  world->stepper->run([&] {
    error = world->system.Update(dt, steps, world->temp.get(), world->jobs.get());
    selfCollideCloths(world);
  });
  // Contacts in body order, so the same input reports them the same way
  // whatever thread found them first.
  std::sort(world->contacts.begin(), world->contacts.end(), [](const JoltContact& x, const JoltContact& y) {
    if (x.body_a != y.body_a) return x.body_a < y.body_a;
    if (x.body_b != y.body_b) return x.body_b < y.body_b;
    if (x.shape_a != y.shape_a) return x.shape_a < y.shape_a;
    return x.shape_b < y.shape_b;
  });
  return int32_t(error);
}

void jolt_world_optimize_broad_phase(JoltWorld* world) { world->system.OptimizeBroadPhase(); }

uint32_t jolt_world_body_count(JoltWorld* world) { return world->system.GetNumBodies(); }

uint32_t jolt_world_active_body_count(JoltWorld* world) {
  return world->system.GetNumActiveBodies(EBodyType::RigidBody);
}

void jolt_world_set_profile_matrix(JoltWorld* world, const uint8_t* matrix, uint32_t count) {
  world->matrix.assign(matrix, matrix + size_t(count) * count);
  world->profileCount = count;
}

void jolt_world_ignore_pair(JoltWorld* world, uint32_t body_a, uint32_t body_b, bool ignore) {
  const uint64 key = pairKey(bodyId(body_a), bodyId(body_b));
  if (ignore) {
    world->ignored.insert(key);
  } else {
    world->ignored.erase(key);
  }
}

// --- Shapes -------------------------------------------------------------------

JoltShape* jolt_shape_box(float hx, float hy, float hz, float convex_radius) {
  ensureJolt();
  const float smallest = std::min(hx, std::min(hy, hz));
  const float radius = std::max(0.0f, std::min(convex_radius, smallest));
  BoxShapeSettings settings(Vec3(hx, hy, hz), radius);
  return wrap(settings.Create(), false);
}

JoltShape* jolt_shape_sphere(float radius) {
  ensureJolt();
  SphereShapeSettings settings(radius);
  return wrap(settings.Create(), false);
}

JoltShape* jolt_shape_capsule(float half_height_of_cylinder, float radius) {
  ensureJolt();
  if (half_height_of_cylinder <= 0.0f) return jolt_shape_sphere(radius);
  CapsuleShapeSettings settings(half_height_of_cylinder, radius);
  return wrap(settings.Create(), false);
}

JoltShape* jolt_shape_cylinder(float half_height, float radius, float convex_radius) {
  ensureJolt();
  const float r = std::max(0.0f, std::min(convex_radius, std::min(half_height, radius)));
  CylinderShapeSettings settings(half_height, radius, r);
  return wrap(settings.Create(), false);
}

JoltShape* jolt_shape_convex_hull(const float* points, uint32_t count, float max_convex_radius) {
  ensureJolt();
  if (count < 4) return nullptr;
  Array<Vec3> pts;
  pts.reserve(count);
  for (uint32_t i = 0; i < count; ++i) pts.push_back(vec3(points + 3 * i));
  ConvexHullShapeSettings settings(pts, std::max(0.0f, max_convex_radius));
  return wrap(settings.Create(), false);
}

float jolt_heightfield_no_collision(void) { return HeightFieldShapeConstants::cNoCollisionValue; }

JoltShape* jolt_shape_height_field(const float* samples, uint32_t sample_count, const float* offset3,
                                   const float* scale3) {
  ensureJolt();
  if (sample_count < 2) return nullptr;
  HeightFieldShapeSettings settings(samples, vec3(offset3), vec3(scale3), sample_count);
  // Jolt needs sample_count / block size >= 2: small fields use a small block.
  settings.mBlockSize = sample_count >= 8 ? 4 : 2;
  // Jolt stores each sample in at most 8 bits relative to its block's range;
  // ask for millimetre precision (it settles for 8 bits when that is coarser).
  settings.mBitsPerSample = settings.CalculateBitsPerSampleForError(0.001f);
  return wrap(settings.Create(), false);
}

JoltShape* jolt_shape_scaled(JoltShape* inner, float sx, float sy, float sz) {
  ScaledShapeSettings settings(inner->shape, Vec3(sx, sy, sz));
  return wrap(settings.Create(), true);
}

JoltShape* jolt_shape_rotated_translated(JoltShape* inner, const float* position3, const float* rotation4) {
  RotatedTranslatedShapeSettings settings(vec3(position3), quat(rotation4), inner->shape);
  return wrap(settings.Create(), true);
}

JoltShape* jolt_shape_offset_center_of_mass(JoltShape* inner, const float* offset3) {
  OffsetCenterOfMassShapeSettings settings(vec3(offset3), inner->shape);
  return wrap(settings.Create(), true);
}

JoltShape* jolt_shape_static_compound(JoltShape* const* shapes, const float* positions, const float* rotations,
                                      uint32_t count) {
  if (count == 0) return nullptr;
  StaticCompoundShapeSettings settings;
  for (uint32_t i = 0; i < count; ++i) {
    settings.AddShape(vec3(positions + 3 * i), quat(rotations + 4 * i), shapes[i]->shape);
  }
  return wrap(settings.Create(), true);
}

void jolt_shape_set_user_data(JoltShape* shape, uint64_t user_data) {
  const_cast<Shape*>(shape->shape.GetPtr())->SetUserData(user_data);
}

void jolt_shape_center_of_mass(JoltShape* shape, float* out3) { store(shape->shape->GetCenterOfMass(), out3); }

float jolt_shape_volume(JoltShape* shape) { return shape->shape->GetVolume(); }

void jolt_shape_local_bounds(JoltShape* shape, float* out6) {
  const AABox box = shape->shape->GetLocalBounds();
  store(box.mMin, out6);
  store(box.mMax, out6 + 3);
}

void jolt_shape_release(JoltShape* shape) { delete shape; }

// --- Bodies -------------------------------------------------------------------

void jolt_body_settings_init(JoltBodySettings* s) {
  std::memset(s, 0, sizeof(JoltBodySettings));
  s->motion_type = JOLT_MOTION_DYNAMIC;
  s->rotation[3] = 1.0f;
  s->friction = 0.2f;
  s->restitution = 0.0f;
  s->linear_damping = 0.05f;
  s->angular_damping = 0.05f;
  s->gravity_factor = 1.0f;
  s->allowed_dofs = JOLT_DOF_ALL;
  s->start_active = true;
}

uint32_t jolt_body_create(JoltWorld* world, JoltShape* shape, const JoltBodySettings* s) {
  const EMotionType type = s->motion_type == JOLT_MOTION_STATIC      ? EMotionType::Static
                           : s->motion_type == JOLT_MOTION_KINEMATIC ? EMotionType::Kinematic
                                                                     : EMotionType::Dynamic;
  BodyCreationSettings settings(shape->shape, RVec3(vec3(s->position)), quat(s->rotation), type, layerFor(type));
  settings.mLinearVelocity = vec3(s->linear_velocity);
  settings.mAngularVelocity = vec3(s->angular_velocity);
  settings.mUserData = s->user_data;
  settings.mFriction = s->friction;
  settings.mRestitution = s->restitution;
  settings.mLinearDamping = s->linear_damping;
  settings.mAngularDamping = s->angular_damping;
  settings.mGravityFactor = s->gravity_factor;
  settings.mIsSensor = s->is_sensor;
  settings.mMotionQuality = s->continuous_collision ? EMotionQuality::LinearCast : EMotionQuality::Discrete;
  settings.mAllowDynamicOrKinematic = type != EMotionType::Static;
  settings.mMaxLinearVelocity = 500.0f;
  settings.mAllowedDOFs = EAllowedDOFs(s->allowed_dofs != 0 ? s->allowed_dofs : JOLT_DOF_ALL);
  if (s->mass > 0.0f && type == EMotionType::Dynamic) {
    const float* m = s->inertia;
    const bool hasInertia = m[0] > 0.0f || m[4] > 0.0f || m[8] > 0.0f;
    // Without an inertia, Jolt scales the shape's own inertia to the mass.
    settings.mOverrideMassProperties =
        hasInertia ? EOverrideMassProperties::MassAndInertiaProvided : EOverrideMassProperties::CalculateInertia;
    settings.mMassPropertiesOverride.mMass = s->mass;
    if (hasInertia) {
      settings.mMassPropertiesOverride.mInertia =
          Mat44(Vec4(m[0], m[3], m[6], 0), Vec4(m[1], m[4], m[7], 0), Vec4(m[2], m[5], m[8], 0), Vec4(0, 0, 0, 1));
    }
  }
  BodyInterface& bi = bodies(world);
  const BodyID id = bi.CreateAndAddBody(settings, s->start_active && type != EMotionType::Static
                                                      ? EActivation::Activate
                                                      : EActivation::DontActivate);
  if (id.IsInvalid()) return BodyID::cInvalidBodyID;
  BodyData& d = world->data(id);
  d = BodyData();
  d.used = true;
  d.friction = d.staticFriction = s->friction;
  d.restitution = s->restitution;
  return id.GetIndexAndSequenceNumber();
}

void jolt_body_destroy(JoltWorld* world, uint32_t body) {
  const BodyID id = bodyId(body);
  BodyInterface& bi = bodies(world);
  if (!bi.IsAdded(id)) return;
  for (auto it = world->ignored.begin(); it != world->ignored.end();) {
    const uint64 key = *it;
    if (uint32(key >> 32) == body || uint32(key) == body) {
      it = world->ignored.erase(it);
    } else {
      ++it;
    }
  }
  bi.RemoveBody(id);
  bi.DestroyBody(id);
  if (id.GetIndex() < world->bodies.size()) world->bodies[id.GetIndex()] = BodyData();
}

void jolt_body_set_owner(JoltWorld* world, uint32_t body, uint64_t owner, bool collides_with_owner) {
  BodyData& d = world->data(bodyId(body));
  d.owner = owner;
  d.collidesWithOwner = collides_with_owner;
}

void jolt_body_set_profiles(JoltWorld* world, uint32_t body, const uint16_t* profiles, uint32_t count) {
  BodyData& d = world->data(bodyId(body));
  d.profiles.assign(profiles, profiles + count);
}

void jolt_body_set_material(JoltWorld* world, uint32_t body, float friction, float static_friction, float restitution,
                            int32_t friction_mode, int32_t restitution_mode) {
  BodyData& d = world->data(bodyId(body));
  d.friction = friction;
  d.staticFriction = static_friction;
  d.restitution = restitution;
  d.frictionMode = friction_mode;
  d.restitutionMode = restitution_mode;
  BodyInterface& bi = bodies(world);
  bi.SetFriction(bodyId(body), friction);
  bi.SetRestitution(bodyId(body), restitution);
}

void jolt_body_set_shape(JoltWorld* world, uint32_t body, JoltShape* shape, bool update_mass) {
  bodies(world).SetShape(bodyId(body), shape->shape, update_mass, EActivation::Activate);
}

void jolt_body_set_mass_properties(JoltWorld* world, uint32_t body, float mass, const float* m, int32_t allowed_dofs) {
  BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
  if (!lock.Succeeded()) return;
  Body& b = lock.GetBody();
  MotionProperties* mp = b.GetMotionPropertiesUnchecked();
  if (mp == nullptr) return;
  MassProperties props;
  props.mMass = mass;
  props.mInertia =
      Mat44(Vec4(m[0], m[3], m[6], 0), Vec4(m[1], m[4], m[7], 0), Vec4(m[2], m[5], m[8], 0), Vec4(0, 0, 0, 1));
  mp->SetMassProperties(EAllowedDOFs(allowed_dofs != 0 ? allowed_dofs : JOLT_DOF_ALL), props);
}

void jolt_body_set_motion_type(JoltWorld* world, uint32_t body, int32_t motion_type, bool activate) {
  const EMotionType type = motion_type == JOLT_MOTION_STATIC      ? EMotionType::Static
                           : motion_type == JOLT_MOTION_KINEMATIC ? EMotionType::Kinematic
                                                                  : EMotionType::Dynamic;
  BodyInterface& bi = bodies(world);
  bi.SetMotionType(bodyId(body), type, activate ? EActivation::Activate : EActivation::DontActivate);
  bi.SetObjectLayer(bodyId(body), layerFor(type));
}

void jolt_body_set_damping(JoltWorld* world, uint32_t body, float linear, float angular) {
  BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
  if (!lock.Succeeded()) return;
  MotionProperties* mp = lock.GetBody().GetMotionPropertiesUnchecked();
  if (mp == nullptr) return;
  mp->SetLinearDamping(linear);
  mp->SetAngularDamping(angular);
}

void jolt_body_set_gravity_factor(JoltWorld* world, uint32_t body, float factor) {
  bodies(world).SetGravityFactor(bodyId(body), factor);
}

void jolt_body_set_continuous_collision(JoltWorld* world, uint32_t body, bool enabled) {
  bodies(world).SetMotionQuality(bodyId(body), enabled ? EMotionQuality::LinearCast : EMotionQuality::Discrete);
}

void jolt_body_set_transform(JoltWorld* world, uint32_t body, const float* position3, const float* rotation4,
                             bool activate) {
  bodies(world).SetPositionAndRotation(bodyId(body), RVec3(vec3(position3)), quat(rotation4),
                                       activate ? EActivation::Activate : EActivation::DontActivate);
}

void jolt_body_set_velocity(JoltWorld* world, uint32_t body, const float* linear3, const float* angular3) {
  bodies(world).SetLinearAndAngularVelocity(bodyId(body), vec3(linear3), vec3(angular3));
}

void jolt_body_move_kinematic(JoltWorld* world, uint32_t body, const float* position3, const float* rotation4,
                              float dt) {
  bodies(world).MoveKinematic(bodyId(body), RVec3(vec3(position3)), quat(rotation4), dt);
}

void jolt_body_add_force(JoltWorld* world, uint32_t body, const float* force3) {
  bodies(world).AddForce(bodyId(body), vec3(force3));
}

void jolt_body_add_force_at(JoltWorld* world, uint32_t body, const float* force3, const float* point3) {
  bodies(world).AddForce(bodyId(body), vec3(force3), RVec3(vec3(point3)));
}

void jolt_body_add_torque(JoltWorld* world, uint32_t body, const float* torque3) {
  bodies(world).AddTorque(bodyId(body), vec3(torque3));
}

void jolt_body_add_impulse(JoltWorld* world, uint32_t body, const float* impulse3) {
  bodies(world).AddImpulse(bodyId(body), vec3(impulse3));
}

void jolt_body_add_impulse_at(JoltWorld* world, uint32_t body, const float* impulse3, const float* point3) {
  bodies(world).AddImpulse(bodyId(body), vec3(impulse3), RVec3(vec3(point3)));
}

void jolt_body_add_angular_impulse(JoltWorld* world, uint32_t body, const float* impulse3) {
  bodies(world).AddAngularImpulse(bodyId(body), vec3(impulse3));
}

void jolt_body_activate(JoltWorld* world, uint32_t body) { bodies(world).ActivateBody(bodyId(body)); }

void jolt_body_deactivate(JoltWorld* world, uint32_t body) { bodies(world).DeactivateBody(bodyId(body)); }

bool jolt_body_is_active(JoltWorld* world, uint32_t body) { return bodies(world).IsActive(bodyId(body)); }

static void writeState(const Body& b, double* out) {
  const RVec3 com = b.GetCenterOfMassPosition();
  const Quat q = b.GetRotation();
  const Vec3 v = b.GetLinearVelocity();
  const Vec3 w = b.GetAngularVelocity();
  const RVec3 origin = b.GetPosition();
  out[0] = com.GetX();
  out[1] = com.GetY();
  out[2] = com.GetZ();
  out[3] = q.GetX();
  out[4] = q.GetY();
  out[5] = q.GetZ();
  out[6] = q.GetW();
  out[7] = v.GetX();
  out[8] = v.GetY();
  out[9] = v.GetZ();
  out[10] = w.GetX();
  out[11] = w.GetY();
  out[12] = w.GetZ();
  out[13] = b.IsActive() ? 1.0 : 0.0;
  out[14] = origin.GetX();
  out[15] = origin.GetY();
  out[16] = origin.GetZ();
}

void jolt_body_get_state(JoltWorld* world, uint32_t body, double* out) {
  jolt_world_get_body_states(world, &body, 1, out);
}

void jolt_world_get_body_states(JoltWorld* world, const uint32_t* ids, uint32_t count, double* out) {
  const BodyLockInterfaceNoLock& locks = world->system.GetBodyLockInterfaceNoLock();
  for (uint32_t i = 0; i < count; ++i) {
    double* o = out + size_t(i) * JOLT_BODY_STATE_STRIDE;
    BodyLockRead lock(locks, bodyId(ids[i]));
    if (!lock.Succeeded()) {
      std::fill(o, o + JOLT_BODY_STATE_STRIDE, 0.0);
      o[6] = 1.0;
      continue;
    }
    writeState(lock.GetBody(), o);
  }
}

float jolt_body_get_mass(JoltWorld* world, uint32_t body) {
  BodyLockRead lock(world->system.GetBodyLockInterface(), bodyId(body));
  if (!lock.Succeeded()) return 0.0f;
  const Body& b = lock.GetBody();
  if (!b.IsDynamic()) return 0.0f;
  const float inv = b.GetMotionProperties()->GetInverseMass();
  return inv > 0.0f ? 1.0f / inv : 0.0f;
}

uint64_t jolt_body_get_user_data(JoltWorld* world, uint32_t body) { return bodies(world).GetUserData(bodyId(body)); }

// --- Contacts -----------------------------------------------------------------

uint32_t jolt_world_contact_count(JoltWorld* world) { return uint32_t(world->contacts.size()); }

uint32_t jolt_world_get_contacts(JoltWorld* world, JoltContact* out, uint32_t max) {
  const uint32_t n = std::min<uint32_t>(max, uint32_t(world->contacts.size()));
  if (n > 0) std::memcpy(out, world->contacts.data(), sizeof(JoltContact) * n);
  return n;
}

// --- Queries ------------------------------------------------------------------

// --- Broad phase proxies ------------------------------------------------------

static Vec3 halfOf(const float* min3, const float* max3) {
  // A flat box (a plane) still has a little thickness.
  return Vec3::sMax((vec3(max3) - vec3(min3)) * 0.5f, Vec3::sReplicate(1.0e-4f));
}

uint32_t jolt_world_add_box_proxy(JoltWorld* world, const float* min3, const float* max3, uint64_t user_data) {
  const Vec3 centre = (vec3(min3) + vec3(max3)) * 0.5f;
  BodyCreationSettings s(new BoxShape(halfOf(min3, max3), 0.0f), RVec3(centre), Quat::sIdentity(),
                         EMotionType::Static, Layers::kNonMoving);
  s.mUserData = user_data;
  const BodyID id = bodies(world).CreateAndAddBody(s, EActivation::DontActivate);
  if (id.IsInvalid()) return 0xFFFFFFFFu;
  BodyData& d = world->data(id);
  d = BodyData();
  d.used = true;
  return id.GetIndexAndSequenceNumber();
}

void jolt_world_set_box_proxy(JoltWorld* world, uint32_t body, const float* min3, const float* max3) {
  BodyInterface& bi = bodies(world);
  const BodyID id = bodyId(body);
  const Vec3 half = halfOf(min3, max3);
  const RefConst<Shape> shape = bi.GetShape(id);
  if (shape == nullptr) return;
  const AABox local = shape->GetLocalBounds();
  if (!local.GetExtent().IsClose(half, 1.0e-10f)) {
    bi.SetShape(id, new BoxShape(half, 0.0f), false, EActivation::DontActivate);
  }
  bi.SetPosition(id, RVec3((vec3(min3) + vec3(max3)) * 0.5f), EActivation::DontActivate);
}


uint32_t jolt_world_broad_phase_ray(JoltWorld* world, const float* origin3, const float* delta3, uint64_t* out,
                                    uint32_t max) {
  UserDataCollector<RayCastBodyCollector, BroadPhaseCastResult> collector(world->system.GetBodyInterfaceNoLock(), out,
                                                                          max);
  world->system.GetBroadPhaseQuery().CastRay(RayCast(vec3(origin3), vec3(delta3)), collector);
  return collector.mCount;
}

uint32_t jolt_world_broad_phase_box_cast(JoltWorld* world, const float* min3, const float* max3, const float* delta3,
                                         uint64_t* out, uint32_t max) {
  UserDataCollector<CastShapeBodyCollector, BroadPhaseCastResult> collector(world->system.GetBodyInterfaceNoLock(),
                                                                            out, max);
  AABoxCast cast;
  cast.mBox = AABox(vec3(min3), vec3(max3));
  cast.mDirection = vec3(delta3);
  world->system.GetBroadPhaseQuery().CastAABox(cast, collector);
  return collector.mCount;
}

uint32_t jolt_world_broad_phase_box(JoltWorld* world, const float* min3, const float* max3, uint64_t* out,
                                    uint32_t max) {
  UserDataCollector<CollideShapeBodyCollector, BodyID> collector(world->system.GetBodyInterfaceNoLock(), out, max);
  world->system.GetBroadPhaseQuery().CollideAABox(AABox(vec3(min3), vec3(max3)), collector);
  return collector.mCount;
}

bool jolt_world_cast_ray(JoltWorld* world, const float* origin3, const float* direction3, JoltRayHit* out) {
  const RRayCast ray(RVec3(vec3(origin3)), vec3(direction3));
  RayCastResult hit;
  if (!world->system.GetNarrowPhaseQuery().CastRay(ray, hit)) return false;
  out->body = hit.mBodyID.GetIndexAndSequenceNumber();
  out->fraction = hit.mFraction;
  const RVec3 point = ray.GetPointOnRay(hit.mFraction);
  store(Vec3(point), out->point);
  BodyLockRead lock(world->system.GetBodyLockInterface(), hit.mBodyID);
  if (lock.Succeeded()) {
    const Body& b = lock.GetBody();
    store(b.GetWorldSpaceSurfaceNormal(hit.mSubShapeID2, point), out->normal);
    out->shape = uint32_t(b.GetShape()->GetSubShapeUserData(hit.mSubShapeID2));
  } else {
    out->normal[0] = out->normal[2] = 0.0f;
    out->normal[1] = 1.0f;
    out->shape = 0;
  }
  return true;
}

// --- Soft bodies (cloth) ---------------------------------------------------------

void jolt_cloth_settings_init(JoltClothSettings* s) {
  std::memset(s, 0, sizeof(JoltClothSettings));
  s->edge_compliance = 0.0f;
  s->shear_compliance = 1.0e-5f;
  s->bend_compliance = 1.0e-3f;
  s->bend_type = 2;
  s->lra_type = 1;
  s->lra_max_distance_multiplier = 1.0f;
  s->iterations = 8;
  s->linear_damping = 0.1f;
  s->max_linear_velocity = 100.0f;
  s->friction = 0.5f;
  s->restitution = 0.0f;
  s->pressure = 0.0f;
  s->vertex_radius = 0.01f;
  s->gravity_factor = 1.0f;
  s->update_position = true;
  s->allow_sleeping = true;
  s->double_sided = true;
}

static uint32_t createSoftBody(JoltWorld* world, const float* positions, const float* inverse_masses,
                               uint32_t vertex_count, const uint32_t* indices, uint32_t index_count,
                               const float* position3, const float* rotation4, const JoltClothSettings* s,
                               const JoltClothSkin* skin, uint64_t user_data) {
  if (vertex_count < 3 || index_count < 3) return BodyID::cInvalidBodyID;
  Ref<SoftBodySharedSettings> shared = new SoftBodySharedSettings();
  shared->mVertices.reserve(vertex_count);
  for (uint32_t i = 0; i < vertex_count; ++i) {
    SoftBodySharedSettings::Vertex v(Float3(positions[3 * i], positions[3 * i + 1], positions[3 * i + 2]));
    v.mInvMass = inverse_masses != nullptr ? std::max(0.0f, inverse_masses[i]) : 1.0f;
    shared->mVertices.push_back(v);
  }
  for (uint32_t i = 0; i + 2 < index_count; i += 3) {
    SoftBodySharedSettings::Face f(indices[i], indices[i + 1], indices[i + 2]);
    if (f.mVertex[0] >= vertex_count || f.mVertex[1] >= vertex_count || f.mVertex[2] >= vertex_count) continue;
    if (f.IsDegenerate()) continue;
    shared->AddFace(f);
  }
  if (shared->mFaces.empty()) return BodyID::cInvalidBodyID;
  auto compliance = [](float value) { return value < 0.0f ? FLT_MAX : value; };
  const SoftBodySharedSettings::ELRAType lra = s->lra_type == 2   ? SoftBodySharedSettings::ELRAType::GeodesicDistance
                                               : s->lra_type == 1 ? SoftBodySharedSettings::ELRAType::EuclideanDistance
                                                                  : SoftBodySharedSettings::ELRAType::None;
  const SoftBodySharedSettings::VertexAttributes attributes(compliance(s->edge_compliance),
                                                            compliance(s->shear_compliance),
                                                            compliance(s->bend_compliance), lra,
                                                            std::max(1.0f, s->lra_max_distance_multiplier));
  const SoftBodySharedSettings::EBendType bend = s->bend_type == 2   ? SoftBodySharedSettings::EBendType::Dihedral
                                                 : s->bend_type == 1 ? SoftBodySharedSettings::EBendType::Distance
                                                                     : SoftBodySharedSettings::EBendType::None;
  shared->CreateConstraints(&attributes, 1, bend);
  if (skin != nullptr && skin->joint_count > 0) {
    for (uint32_t j = 0; j < skin->joint_count; ++j) {
      const float* m = skin->inverse_binds + 16 * j;
      shared->mInvBindMatrices.push_back(SoftBodySharedSettings::InvBind(
          j, Mat44(Vec4(m[0], m[1], m[2], m[3]), Vec4(m[4], m[5], m[6], m[7]), Vec4(m[8], m[9], m[10], m[11]),
                   Vec4(m[12], m[13], m[14], m[15]))));
    }
    for (uint32_t i = 0; i < vertex_count; ++i) {
      SoftBodySharedSettings::Skinned skinned(i, std::max(0.0f, skin->max_distances[i]),
                                              skin->backstop_distances != nullptr ? skin->backstop_distances[i] : FLT_MAX,
                                              skin->backstop_radius);
      uint32_t used = 0;
      for (uint32_t k = 0; k < 4; ++k) {
        const float w = skin->weights[4 * i + k];
        const uint32_t joint = skin->joints[4 * i + k];
        if (w <= 0.0f || joint >= skin->joint_count) continue;
        skinned.mWeights[used++] = SoftBodySharedSettings::SkinWeight(joint, w);
      }
      if (used == 0) continue;
      skinned.NormalizeWeights();
      shared->mSkinnedConstraints.push_back(skinned);
    }
    shared->CalculateSkinnedConstraintNormals();
  }
  shared->Optimize();

  SoftBodyCreationSettings settings(shared, RVec3(vec3(position3)), quat(rotation4), Layers::kMoving);
  settings.mUserData = user_data;
  settings.mNumIterations = std::max<uint32_t>(1, s->iterations);
  settings.mLinearDamping = s->linear_damping;
  settings.mMaxLinearVelocity = s->max_linear_velocity;
  settings.mFriction = s->friction;
  settings.mRestitution = s->restitution;
  settings.mPressure = s->pressure;
  settings.mVertexRadius = s->vertex_radius;
  settings.mGravityFactor = s->gravity_factor;
  settings.mUpdatePosition = s->update_position;
  settings.mAllowSleeping = s->allow_sleeping;
  settings.mFacesDoubleSided = s->double_sided;
  const BodyID id = bodies(world).CreateAndAddSoftBody(settings, EActivation::Activate);
  if (id.IsInvalid()) return BodyID::cInvalidBodyID;
  BodyData& d = world->data(id);
  d = BodyData();
  d.used = true;
  return id.GetIndexAndSequenceNumber();
}

uint32_t jolt_soft_body_create(JoltWorld* world, const float* positions, const float* inverse_masses,
                               uint32_t vertex_count, const uint32_t* indices, uint32_t index_count,
                               const float* position3, const float* rotation4, const JoltClothSettings* s,
                               uint64_t user_data) {
  return createSoftBody(world, positions, inverse_masses, vertex_count, indices, index_count, position3, rotation4, s,
                        nullptr, user_data);
}

uint32_t jolt_skinned_cloth_create(JoltWorld* world, const float* positions, const float* inverse_masses,
                                   uint32_t vertex_count, const uint32_t* indices, uint32_t index_count,
                                   const float* position3, const float* rotation4, const JoltClothSettings* s,
                                   const JoltClothSkin* skin, uint64_t user_data) {
  return createSoftBody(world, positions, inverse_masses, vertex_count, indices, index_count, position3, rotation4, s,
                        skin, user_data);
}

static SoftBodyMotionProperties* softBody(Body& body) {
  return body.IsSoftBody() ? static_cast<SoftBodyMotionProperties*>(body.GetMotionPropertiesUnchecked()) : nullptr;
}

uint32_t jolt_soft_body_vertex_count(JoltWorld* world, uint32_t body) {
  BodyLockRead lock(world->system.GetBodyLockInterface(), bodyId(body));
  if (!lock.Succeeded() || !lock.GetBody().IsSoftBody()) return 0;
  return uint32_t(static_cast<const SoftBodyMotionProperties*>(lock.GetBody().GetMotionPropertiesUnchecked())
                      ->GetVertices()
                      .size());
}

uint32_t jolt_soft_body_get_vertices(JoltWorld* world, uint32_t body, float* out, uint32_t max) {
  BodyLockRead lock(world->system.GetBodyLockInterface(), bodyId(body));
  if (!lock.Succeeded() || !lock.GetBody().IsSoftBody()) return 0;
  const Body& b = lock.GetBody();
  const auto* mp = static_cast<const SoftBodyMotionProperties*>(b.GetMotionPropertiesUnchecked());
  const RMat44 com = b.GetCenterOfMassTransform();
  const uint32_t n = std::min<uint32_t>(max, uint32_t(mp->GetVertices().size()));
  for (uint32_t i = 0; i < n; ++i) store(Vec3(com * mp->GetVertex(i).mPosition), out + 3 * i);
  return n;
}

void jolt_soft_body_set_vertex(JoltWorld* world, uint32_t body, uint32_t index, const float* position3,
                               float inverse_mass) {
  {
    BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
    if (!lock.Succeeded()) return;
    Body& b = lock.GetBody();
    SoftBodyMotionProperties* mp = softBody(b);
    if (mp == nullptr || index >= mp->GetVertices().size()) return;
    SoftBodyVertex& v = mp->GetVertex(index);
    v.mPosition = Vec3(b.GetCenterOfMassTransform().Inversed() * RVec3(vec3(position3)));
    v.mPreviousPosition = v.mPosition;
    v.mVelocity = Vec3::sZero();
    v.mInvMass = std::max(0.0f, inverse_mass);
  }
  bodies(world).ActivateBody(bodyId(body));
}

void jolt_soft_body_apply_wind(JoltWorld* world, uint32_t body, const float* wind3, float drag, float dt) {
  {
    BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
    if (!lock.Succeeded()) return;
    Body& b = lock.GetBody();
    SoftBodyMotionProperties* mp = softBody(b);
    if (mp == nullptr) return;
    // Vertex velocities are in the body's (centre of mass) frame.
    const Vec3 wind = b.GetRotation().Conjugated() * vec3(wind3);
    const float k = std::min(1.0f, std::max(0.0f, drag * dt));
    auto& vertices = mp->GetVertices();
    // Aerodynamic drag: each face is pushed along its normal by the part of
    // the relative wind that hits it (a face edge-on to the wind feels
    // nothing), so cloth billows and flutters instead of moving as a block.
    std::vector<Vec3> push(vertices.size(), Vec3::sZero());
    std::vector<float> faces(vertices.size(), 0.0f);
    for (const SoftBodySharedSettings::Face& f : mp->GetFaces()) {
      const SoftBodyVertex& a = vertices[f.mVertex[0]];
      const SoftBodyVertex& b2 = vertices[f.mVertex[1]];
      const SoftBodyVertex& c = vertices[f.mVertex[2]];
      Vec3 n = (b2.mPosition - a.mPosition).Cross(c.mPosition - a.mPosition);
      const float len = n.Length();
      if (len < 1.0e-12f) continue;
      n /= len;
      const Vec3 relative = wind - (a.mVelocity + b2.mVelocity + c.mVelocity) / 3.0f;
      const Vec3 dv = n * (relative.Dot(n) * k);
      for (uint32 i = 0; i < 3; ++i) {
        push[f.mVertex[i]] += dv;
        faces[f.mVertex[i]] += 1.0f;
      }
    }
    for (size_t i = 0; i < vertices.size(); ++i) {
      SoftBodyVertex& v = vertices[i];
      if (v.mInvMass > 0.0f && faces[i] > 0.0f) v.mVelocity += push[i] / faces[i];
    }
  }
  bodies(world).ActivateBody(bodyId(body));
}

void jolt_soft_body_drive_vertices(JoltWorld* world, uint32_t body, const uint32_t* indices, const float* targets,
                                   uint32_t count, float dt) {
  if (dt <= 0.0f) return;
  {
    BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
    if (!lock.Succeeded()) return;
    Body& b = lock.GetBody();
    SoftBodyMotionProperties* mp = softBody(b);
    if (mp == nullptr) return;
    const RMat44 toLocal = b.GetCenterOfMassTransform().InversedRotationTranslation();
    const uint32_t n = uint32_t(mp->GetVertices().size());
    for (uint32_t i = 0; i < count; ++i) {
      if (indices[i] >= n) continue;
      SoftBodyVertex& v = mp->GetVertex(indices[i]);
      if (v.mInvMass > 0.0f) continue;
      const Vec3 target = Vec3(toLocal * RVec3(vec3(targets + 3 * i)));
      v.mVelocity = (target - v.mPosition) / dt;
    }
  }
  bodies(world).ActivateBody(bodyId(body));
}

uint32_t jolt_soft_body_get_local_vertices(JoltWorld* world, uint32_t body, const float* m, float* out_positions,
                                           float* out_normals, uint32_t max) {
  BodyLockRead lock(world->system.GetBodyLockInterface(), bodyId(body));
  if (!lock.Succeeded() || !lock.GetBody().IsSoftBody()) return 0;
  const Body& b = lock.GetBody();
  const auto* mp = static_cast<const SoftBodyMotionProperties*>(b.GetMotionPropertiesUnchecked());
  const auto& vertices = mp->GetVertices();
  const uint32_t n = std::min<uint32_t>(max, uint32_t(vertices.size()));
  // Area-weighted vertex normals in the body frame.
  std::vector<Vec3> normals(vertices.size(), Vec3::sZero());
  for (const SoftBodySharedSettings::Face& f : mp->GetFaces()) {
    const Vec3 x0 = vertices[f.mVertex[0]].mPosition;
    const Vec3 n0 = (vertices[f.mVertex[1]].mPosition - x0).Cross(vertices[f.mVertex[2]].mPosition - x0);
    for (uint32 k = 0; k < 3; ++k) normals[f.mVertex[k]] += n0;
  }
  const Mat44 local(Vec4(m[0], m[1], m[2], m[3]), Vec4(m[4], m[5], m[6], m[7]), Vec4(m[8], m[9], m[10], m[11]),
                    Vec4(m[12], m[13], m[14], m[15]));
  const Mat44 com = b.GetCenterOfMassTransform();
  const Mat44 full = local * com;
  for (uint32_t i = 0; i < n; ++i) {
    store(full * vertices[i].mPosition, out_positions + 3 * i);
    Vec3 nrm = full.Multiply3x3(normals[i]);
    const float len = nrm.Length();
    nrm = len > 1.0e-12f ? nrm / len : Vec3::sAxisY();
    store(nrm, out_normals + 3 * i);
  }
  return n;
}

void jolt_soft_body_skin(JoltWorld* world, uint32_t body, const float* joint_world16, uint32_t count,
                         bool hard_skin_all) {
  {
    BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
    if (!lock.Succeeded()) return;
    Body& b = lock.GetBody();
    SoftBodyMotionProperties* mp = softBody(b);
    if (mp == nullptr || count == 0) return;
    const RMat44 com = b.GetCenterOfMassTransform();
    const Mat44 offset = com.InversedRotationTranslation();
    std::vector<Mat44> pose(count);
    for (uint32_t i = 0; i < count; ++i) {
      const float* m = joint_world16 + 16 * i;
      pose[i] = offset * Mat44(Vec4(m[0], m[1], m[2], m[3]), Vec4(m[4], m[5], m[6], m[7]),
                               Vec4(m[8], m[9], m[10], m[11]), Vec4(m[12], m[13], m[14], m[15]));
    }
    mp->SetEnableSkinConstraints(true);
    mp->SkinVertices(com, pose.data(), count, hard_skin_all, *world->temp);
  }
  bodies(world).ActivateBody(bodyId(body));
}

void jolt_soft_body_set_self_collision(JoltWorld* world, uint32_t body, float distance) {
  BodyData& data = world->data(bodyId(body));
  data.selfCollision = std::max(0.0f, distance);
  data.selfCollisionBody = body;
}

void jolt_body_set_cloth_collider(JoltWorld* world, uint32_t body, bool cloth_collider) {
  world->data(bodyId(body)).clothCollider = cloth_collider;
}

void jolt_soft_body_carry(JoltWorld* world, uint32_t body, const float* m, float amount, bool include_pinned) {
  if (!(amount > 0.0f)) return;
  amount = std::min(amount, 1.0f);
  {
    BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
    if (!lock.Succeeded()) return;
    Body& b = lock.GetBody();
    SoftBodyMotionProperties* mp = softBody(b);
    if (mp == nullptr) return;
    const Mat44 com = Mat44(b.GetCenterOfMassTransform());
    const Mat44 delta(Vec4(m[0], m[1], m[2], m[3]), Vec4(m[4], m[5], m[6], m[7]), Vec4(m[8], m[9], m[10], m[11]),
                      Vec4(m[12], m[13], m[14], m[15]));
    // The motion in the body frame, where the vertices live.
    const Mat44 local = com.InversedRotationTranslation() * delta * com;
    const uint32_t n = uint32_t(mp->GetVertices().size());
    for (uint32_t i = 0; i < n; ++i) {
      SoftBodyVertex& v = mp->GetVertex(i);
      if (v.mInvMass <= 0.0f) {
        if (include_pinned) v.mPosition = local * v.mPosition;
        continue;
      }
      v.mPosition += (local * v.mPosition - v.mPosition) * amount;
      v.mVelocity += (local.Multiply3x3(v.mVelocity) - v.mVelocity) * amount;
    }
  }
  bodies(world).ActivateBody(bodyId(body));
}

void jolt_soft_body_set_inverse_mass(JoltWorld* world, uint32_t body, uint32_t index, float inverse_mass) {
  {
    BodyLockWrite lock(world->system.GetBodyLockInterface(), bodyId(body));
    if (!lock.Succeeded()) return;
    SoftBodyMotionProperties* mp = softBody(lock.GetBody());
    if (mp == nullptr || index >= mp->GetVertices().size()) return;
    SoftBodyVertex& v = mp->GetVertex(index);
    v.mInvMass = std::max(0.0f, inverse_mass);
    if (v.mInvMass == 0.0f) v.mVelocity = Vec3::sZero();
  }
  bodies(world).ActivateBody(bodyId(body));
}

// --- Constraints --------------------------------------------------------------

static JoltConstraint* addConstraint(JoltWorld* world, uint32_t body_a, uint32_t body_b,
                                     const TwoBodyConstraintSettings& settings, bool hinge) {
  BodyID ids[2] = {bodyId(body_a), bodyId(body_b)};
  BodyLockMultiWrite lock(world->system.GetBodyLockInterface(), ids, 2);
  Body* a = lock.GetBody(0);
  Body* b = lock.GetBody(1);
  if (a == nullptr || b == nullptr) return nullptr;
  auto* c = new JoltConstraint();
  c->constraint = settings.Create(*a, *b);
  c->hinge = hinge;
  world->system.AddConstraint(c->constraint);
  world->constraints.push_back(c);
  return c;
}

JoltConstraint* jolt_constraint_swing_twist(JoltWorld* world, uint32_t body_a, uint32_t body_b,
                                            const JoltSwingTwistSettings* s) {
  SwingTwistConstraintSettings settings;
  settings.mSpace = EConstraintSpace::LocalToBodyCOM;
  settings.mPosition1 = RVec3(vec3(s->position_a));
  settings.mTwistAxis1 = vec3(s->twist_axis_a).Normalized();
  settings.mPlaneAxis1 = vec3(s->plane_axis_a).Normalized();
  settings.mPosition2 = RVec3(vec3(s->position_b));
  settings.mTwistAxis2 = vec3(s->twist_axis_b).Normalized();
  settings.mPlaneAxis2 = vec3(s->plane_axis_b).Normalized();
  settings.mNormalHalfConeAngle = s->normal_half_cone;
  settings.mPlaneHalfConeAngle = s->plane_half_cone;
  settings.mTwistMinAngle = s->twist_min;
  settings.mTwistMaxAngle = s->twist_max;
  settings.mMaxFrictionTorque = s->max_friction_torque;
  settings.mSwingMotorSettings = MotorSettings(0.0f, 0.0f, 0.0f, 0.0f);
  settings.mTwistMotorSettings = MotorSettings(0.0f, 0.0f, 0.0f, 0.0f);
  return addConstraint(world, body_a, body_b, settings, false);
}

JoltConstraint* jolt_constraint_hinge(JoltWorld* world, uint32_t body_a, uint32_t body_b, const JoltHingeSettings* s) {
  HingeConstraintSettings settings;
  settings.mSpace = EConstraintSpace::LocalToBodyCOM;
  settings.mPoint1 = RVec3(vec3(s->position_a));
  settings.mHingeAxis1 = vec3(s->hinge_axis_a).Normalized();
  settings.mNormalAxis1 = vec3(s->normal_axis_a).Normalized();
  settings.mPoint2 = RVec3(vec3(s->position_b));
  settings.mHingeAxis2 = vec3(s->hinge_axis_b).Normalized();
  settings.mNormalAxis2 = vec3(s->normal_axis_b).Normalized();
  if (s->limit_min <= s->limit_max) {
    settings.mLimitsMin = std::min(0.0f, std::max(-JPH_PI, s->limit_min));
    settings.mLimitsMax = std::max(0.0f, std::min(JPH_PI, s->limit_max));
  } else {
    settings.mLimitsMin = -JPH_PI;
    settings.mLimitsMax = JPH_PI;
  }
  settings.mMaxFrictionTorque = s->max_friction_torque;
  settings.mMotorSettings = MotorSettings(0.0f, 0.0f, 0.0f, 0.0f);
  return addConstraint(world, body_a, body_b, settings, true);
}

void jolt_constraint_destroy(JoltWorld* world, JoltConstraint* constraint) {
  if (constraint == nullptr) return;
  auto& list = world->constraints;
  auto it = std::find(list.begin(), list.end(), constraint);
  if (it == list.end()) return;
  list.erase(it);
  world->system.RemoveConstraint(constraint->constraint);
  delete constraint;
}

void jolt_constraint_set_enabled(JoltConstraint* constraint, bool enabled) {
  constraint->constraint->SetEnabled(enabled);
}

void jolt_constraint_set_max_friction_torque(JoltConstraint* constraint, float torque) {
  if (constraint->hinge) {
    static_cast<HingeConstraint*>(constraint->constraint.GetPtr())->SetMaxFrictionTorque(torque);
  } else {
    static_cast<SwingTwistConstraint*>(constraint->constraint.GetPtr())->SetMaxFrictionTorque(torque);
  }
}

void jolt_constraint_set_solver_steps(JoltConstraint* constraint, uint32_t velocity_steps, uint32_t position_steps) {
  constraint->constraint->SetNumVelocityStepsOverride(std::min<uint32_t>(velocity_steps, 255));
  constraint->constraint->SetNumPositionStepsOverride(std::min<uint32_t>(position_steps, 255));
}

void jolt_constraint_set_limits(JoltConstraint* constraint, float normal_half_cone, float plane_half_cone,
                                float twist_min, float twist_max) {
  if (constraint->hinge) {
    auto* h = static_cast<HingeConstraint*>(constraint->constraint.GetPtr());
    if (twist_min <= twist_max) {
      h->SetLimits(std::min(0.0f, std::max(-JPH_PI, twist_min)), std::max(0.0f, std::min(JPH_PI, twist_max)));
    } else {
      h->SetLimits(-JPH_PI, JPH_PI);
    }
    return;
  }
  auto* s = static_cast<SwingTwistConstraint*>(constraint->constraint.GetPtr());
  s->SetNormalHalfConeAngle(normal_half_cone);
  s->SetPlaneHalfConeAngle(plane_half_cone);
  s->SetTwistMinAngle(twist_min);
  s->SetTwistMaxAngle(twist_max);
}

void jolt_constraint_set_velocity_motor(JoltConstraint* constraint, const float* angular_velocity3, float max_torque) {
  const bool on = max_torque > 0.0f;
  if (constraint->hinge) {
    auto* h = static_cast<HingeConstraint*>(constraint->constraint.GetPtr());
    h->GetMotorSettings().SetTorqueLimit(on ? max_torque : 0.0f);
    h->SetMotorState(on ? EMotorState::Velocity : EMotorState::Off);
    if (on) h->SetTargetAngularVelocity(angular_velocity3[0]);
    return;
  }
  auto* s = static_cast<SwingTwistConstraint*>(constraint->constraint.GetPtr());
  s->GetSwingMotorSettings().SetTorqueLimit(on ? max_torque : 0.0f);
  s->GetTwistMotorSettings().SetTorqueLimit(on ? max_torque : 0.0f);
  s->SetSwingMotorState(on ? EMotorState::Velocity : EMotorState::Off);
  s->SetTwistMotorState(on ? EMotorState::Velocity : EMotorState::Off);
  if (on) s->SetTargetAngularVelocityCS(vec3(angular_velocity3));
}

void jolt_constraint_set_position_motor(JoltConstraint* constraint, const float* target4, float frequency,
                                       float damping, float max_torque) {
  const bool on = max_torque > 0.0f;
  const Quat target = quat(target4);
  if (constraint->hinge) {
    auto* h = static_cast<HingeConstraint*>(constraint->constraint.GetPtr());
    MotorSettings& m = h->GetMotorSettings();
    m.mSpringSettings = SpringSettings(ESpringMode::FrequencyAndDamping, frequency, damping);
    m.SetTorqueLimit(on ? max_torque : 0.0f);
    h->SetMotorState(on ? EMotorState::Position : EMotorState::Off);
    if (on) {
      // The angle about the hinge (X) axis of the target rotation.
      h->SetTargetAngle(2.0f * std::atan2(target.GetX(), target.GetW()));
    }
    return;
  }
  auto* s = static_cast<SwingTwistConstraint*>(constraint->constraint.GetPtr());
  for (MotorSettings* m : {&s->GetSwingMotorSettings(), &s->GetTwistMotorSettings()}) {
    m->mSpringSettings = SpringSettings(ESpringMode::FrequencyAndDamping, frequency, damping);
    m->SetTorqueLimit(on ? max_torque : 0.0f);
  }
  s->SetSwingMotorState(on ? EMotorState::Position : EMotorState::Off);
  s->SetTwistMotorState(on ? EMotorState::Position : EMotorState::Off);
  if (on) s->SetTargetOrientationCS(target);
}

void jolt_constraint_get_lambdas(JoltConstraint* constraint, float* out2) {
  if (constraint->hinge) {
    auto* h = static_cast<HingeConstraint*>(constraint->constraint.GetPtr());
    out2[0] = h->GetTotalLambdaPosition().Length();
    out2[1] = h->GetTotalLambdaRotationLimits();
    return;
  }
  auto* s = static_cast<SwingTwistConstraint*>(constraint->constraint.GetPtr());
  out2[0] = s->GetTotalLambdaPosition().Length();
  out2[1] = std::sqrt(s->GetTotalLambdaTwist() * s->GetTotalLambdaTwist() +
                      s->GetTotalLambdaSwingY() * s->GetTotalLambdaSwingY() +
                      s->GetTotalLambdaSwingZ() * s->GetTotalLambdaSwingZ());
}

}  // extern "C"
