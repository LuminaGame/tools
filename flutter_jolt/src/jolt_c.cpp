// C API of flutter_jolt (see jolt_c.h).

#include "jolt_c.h"

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Body/BodyLockMulti.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/EstimateCollisionResponse.h>
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
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <thread>
#include <unordered_set>
#include <vector>

using namespace JPH;

namespace {

// --- Process-wide setup ---------------------------------------------------------

std::once_flag g_init_once;

void ensureJolt() {
  std::call_once(g_init_once, [] {
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

// --- World ----------------------------------------------------------------------

struct JoltShape {
  RefConst<Shape> shape;
};

struct JoltConstraint {
  Ref<TwoBodyConstraint> constraint;
  bool hinge = false;
};

struct JoltWorld : public ContactListener, public SimShapeFilter {
  std::unique_ptr<TempAllocatorImpl> temp;
  std::unique_ptr<JobSystem> jobs;
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
      if (a->owner != 0 && a->owner == b->owner) {
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
    CollisionEstimationResult estimate;
    EstimateCollisionResponse(body1, body2, manifold, estimate, settings.mCombinedFriction,
                              settings.mCombinedRestitution);
    JoltContact c{};
    c.body_a = body1.GetID().GetIndexAndSequenceNumber();
    c.body_b = body2.GetID().GetIndexAndSequenceNumber();
    c.shape_a = uint32(body1.GetShape()->GetSubShapeUserData(manifold.mSubShapeID1));
    c.shape_b = uint32(body2.GetShape()->GetSubShapeUserData(manifold.mSubShapeID2));
    Vec3 point = Vec3::sZero();
    float impulse = 0.0f;
    const uint count = manifold.mRelativeContactPointsOn1.size();
    for (uint i = 0; i < count; ++i) {
      point += Vec3(manifold.GetWorldSpaceContactPointOn1(i));
      if (i < estimate.mContactImpulse.size()) impulse += estimate.mContactImpulse[i];
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
  w->jobs = std::make_unique<JobSystemThreadPool>(cMaxPhysicsJobs, cMaxPhysicsBarriers, threads);
  w->system.Init(maxBodies, 0, maxPairs, maxContacts, w->layers, w->objectVsBroadPhase, w->objectPair);
  w->system.SetContactListener(w);
  w->system.SetSimShapeFilter(w);
  return w;
}

void jolt_world_destroy(JoltWorld* world) {
  if (world == nullptr) return;
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

int32_t jolt_world_step(JoltWorld* world, float dt, int32_t collision_steps) {
  {
    std::lock_guard<std::mutex> lock(world->contactsMutex);
    world->contacts.clear();
  }
  const EPhysicsUpdateError error =
      world->system.Update(dt, std::max(1, collision_steps), world->temp.get(), world->jobs.get());
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
