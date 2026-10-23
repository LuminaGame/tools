// C API of flutter_jolt: a Jolt Physics world for Dart FFI.
//
// Units are Jolt's: metres, kilograms, seconds, radians. The world has no
// preferred up axis; the caller sets gravity. Quaternions are (x, y, z, w).
//
// Bodies are named by their Jolt BodyID value (uint32). Shapes are reference
// counted: every jolt_shape_* constructor returns a handle the caller owns
// and releases with jolt_shape_release (a body or a compound keeps its own
// reference). Constraints are handles owned by their world.
//
// Collision filtering is two-level:
//   * profiles: every sub-shape of a body has a profile index
//     (jolt_body_set_profiles); a contact between two sub-shapes exists only
//     when the world's profile matrix (jolt_world_set_profile_matrix) says
//     the two profiles block each other. A profile index outside the matrix
//     blocks everything.
//   * groups: a body has an owner id (0 = none). Two bodies of the same owner
//     collide only when both allow it (jolt_body_set_owner), and a pair
//     listed with jolt_world_ignore_pair never collides.
#ifndef FLUTTER_JOLT_C_H
#define FLUTTER_JOLT_C_H

#include <stdbool.h>
#include <stdint.h>

#if defined(_WIN32)
#define JOLT_C_EXPORT __declspec(dllexport)
#else
#define JOLT_C_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JoltWorld JoltWorld;
typedef struct JoltShape JoltShape;
typedef struct JoltConstraint JoltConstraint;

// --- Library ------------------------------------------------------------------

/// The Jolt version this library was built from: major * 10000 + minor * 100 + patch.
JOLT_C_EXPORT int32_t jolt_version(void);

/// The invalid body id (Jolt's BodyID::cInvalidBodyID).
JOLT_C_EXPORT uint32_t jolt_invalid_body_id(void);

// --- World --------------------------------------------------------------------

typedef struct JoltWorldSettings {
  uint32_t max_bodies;          // 0 = 65536
  uint32_t max_body_pairs;      // 0 = 65536
  uint32_t max_contact_constraints;  // 0 = 16384
  int32_t worker_threads;       // < 0 = hardware threads - 1, 0 = single threaded
  uint32_t temp_allocator_bytes;  // 0 = 16 MB
} JoltWorldSettings;

JOLT_C_EXPORT JoltWorld* jolt_world_create(const JoltWorldSettings* settings);
JOLT_C_EXPORT void jolt_world_destroy(JoltWorld* world);
JOLT_C_EXPORT void jolt_world_set_gravity(JoltWorld* world, float x, float y, float z);
JOLT_C_EXPORT void jolt_world_get_gravity(JoltWorld* world, float* out3);

/// Simulation quality: solver iterations, sleep thresholds, allowed
/// penetration and speculative contact distance (metres).
typedef struct JoltSolverSettings {
  int32_t velocity_steps;              // Jolt default 10
  int32_t position_steps;              // Jolt default 2
  float baumgarte;                     // Jolt default 0.2
  float speculative_contact_distance;  // Jolt default 0.02 m
  float penetration_slop;              // Jolt default 0.02 m
  float time_before_sleep;             // Jolt default 0.5 s
  float point_velocity_sleep_threshold;  // Jolt default 0.03 m/s
  bool allow_sleeping;
} JoltSolverSettings;

JOLT_C_EXPORT void jolt_world_get_solver_settings(JoltWorld* world, JoltSolverSettings* out);
JOLT_C_EXPORT void jolt_world_set_solver_settings(JoltWorld* world, const JoltSolverSettings* settings);

/// Advances the world by dt seconds in collision_steps sub-steps. Returns
/// Jolt's EPhysicsUpdateError bits (0 = no error).
JOLT_C_EXPORT int32_t jolt_world_step(JoltWorld* world, float dt, int32_t collision_steps);

/// Rebuilds the broad phase tree (after adding many bodies at once).
JOLT_C_EXPORT void jolt_world_optimize_broad_phase(JoltWorld* world);

JOLT_C_EXPORT uint32_t jolt_world_body_count(JoltWorld* world);
JOLT_C_EXPORT uint32_t jolt_world_active_body_count(JoltWorld* world);

/// count x count bytes, row major: matrix[a * count + b] != 0 when a sub-shape
/// of profile a and one of profile b block each other.
JOLT_C_EXPORT void jolt_world_set_profile_matrix(JoltWorld* world, const uint8_t* matrix, uint32_t count);

/// Bodies a and b never collide (true) or follow the other rules again (false).
JOLT_C_EXPORT void jolt_world_ignore_pair(JoltWorld* world, uint32_t body_a, uint32_t body_b, bool ignore);

// --- Shapes -------------------------------------------------------------------

/// A box of half extents (metres) with rounded edges of convex_radius
/// (clamped to the smallest half extent).
JOLT_C_EXPORT JoltShape* jolt_shape_box(float hx, float hy, float hz, float convex_radius);
JOLT_C_EXPORT JoltShape* jolt_shape_sphere(float radius);
/// A capsule along local Y: half_height of the cylinder part (without the caps).
JOLT_C_EXPORT JoltShape* jolt_shape_capsule(float half_height_of_cylinder, float radius);
/// A cylinder along local Y.
JOLT_C_EXPORT JoltShape* jolt_shape_cylinder(float half_height, float radius, float convex_radius);
/// The convex hull of count points (xyz triples); null when no hull exists.
JOLT_C_EXPORT JoltShape* jolt_shape_convex_hull(const float* points, uint32_t count, float max_convex_radius);
/// A static height field of sample_count x sample_count heights, row major:
/// vertex (x, y) is at offset + scale * (x, samples[y * sample_count + x], y).
/// A height of jolt_heightfield_no_collision() is a hole.
JOLT_C_EXPORT JoltShape* jolt_shape_height_field(const float* samples, uint32_t sample_count, const float* offset3,
                                                 const float* scale3);
JOLT_C_EXPORT float jolt_heightfield_no_collision(void);
/// inner scaled by (sx, sy, sz).
JOLT_C_EXPORT JoltShape* jolt_shape_scaled(JoltShape* inner, float sx, float sy, float sz);
/// inner placed at position3 / rotation4 in the new shape's frame.
JOLT_C_EXPORT JoltShape* jolt_shape_rotated_translated(JoltShape* inner, const float* position3, const float* rotation4);
/// inner with its centre of mass moved by offset3.
JOLT_C_EXPORT JoltShape* jolt_shape_offset_center_of_mass(JoltShape* inner, const float* offset3);
/// A static compound of count shapes, each at positions[3i] / rotations[4i].
JOLT_C_EXPORT JoltShape* jolt_shape_static_compound(JoltShape* const* shapes, const float* positions,
                                                    const float* rotations, uint32_t count);
/// The user data of a shape (a compound's child index is read with
/// jolt_body_sub_shape_user_data on a contact).
JOLT_C_EXPORT void jolt_shape_set_user_data(JoltShape* shape, uint64_t user_data);
JOLT_C_EXPORT void jolt_shape_center_of_mass(JoltShape* shape, float* out3);
JOLT_C_EXPORT float jolt_shape_volume(JoltShape* shape);
/// Local bounds: min xyz, max xyz.
JOLT_C_EXPORT void jolt_shape_local_bounds(JoltShape* shape, float* out6);
JOLT_C_EXPORT void jolt_shape_release(JoltShape* shape);

// --- Bodies -------------------------------------------------------------------

enum {
  JOLT_MOTION_STATIC = 0,
  JOLT_MOTION_KINEMATIC = 1,
  JOLT_MOTION_DYNAMIC = 2,
};

/// Bits of JoltBodySettings.allowed_dofs (Jolt's EAllowedDOFs).
enum {
  JOLT_DOF_TRANSLATION_X = 1,
  JOLT_DOF_TRANSLATION_Y = 2,
  JOLT_DOF_TRANSLATION_Z = 4,
  JOLT_DOF_ROTATION_X = 8,
  JOLT_DOF_ROTATION_Y = 16,
  JOLT_DOF_ROTATION_Z = 32,
  JOLT_DOF_ALL = 63,
};

typedef struct JoltBodySettings {
  int32_t motion_type;
  float position[3];        // the shape's origin in the world
  float rotation[4];
  float linear_velocity[3];
  float angular_velocity[3];
  uint64_t user_data;
  float friction;
  float restitution;
  float linear_damping;
  float angular_damping;
  float gravity_factor;
  /// > 0: mass (kg) and inertia (kg m^2, 3x3 row major about the centre of
  /// mass, body axes) replace the ones Jolt computes from the shape. An
  /// all-zero inertia diagonal keeps the shape's inertia scaled to the mass.
  float mass;
  float inertia[9];
  int32_t allowed_dofs;     // 0 = JOLT_DOF_ALL
  bool continuous_collision;  // linear cast motion quality
  bool start_active;
  bool is_sensor;
} JoltBodySettings;

/// Fills settings with Jolt's defaults (a dynamic body at the origin).
JOLT_C_EXPORT void jolt_body_settings_init(JoltBodySettings* settings);
/// Creates and adds a body; returns its id, or jolt_invalid_body_id() when
/// the world is full.
JOLT_C_EXPORT uint32_t jolt_body_create(JoltWorld* world, JoltShape* shape, const JoltBodySettings* settings);
JOLT_C_EXPORT void jolt_body_destroy(JoltWorld* world, uint32_t body);

/// Owner id (0 = none) and whether the body collides with the other bodies of
/// its owner that allow it too.
JOLT_C_EXPORT void jolt_body_set_owner(JoltWorld* world, uint32_t body, uint64_t owner, bool collides_with_owner);
/// The profile of each sub-shape: profiles[i] for the sub-shape whose user
/// data is i (a single shape has user data 0 unless set).
JOLT_C_EXPORT void jolt_body_set_profiles(JoltWorld* world, uint32_t body, const uint16_t* profiles, uint32_t count);
/// Friction (dynamic, static) and restitution with their combine modes
/// (0 average, 1 min, 2 multiply, 3 max; the larger mode of the two bodies wins).
JOLT_C_EXPORT void jolt_body_set_material(JoltWorld* world, uint32_t body, float friction, float static_friction,
                                          float restitution, int32_t friction_mode, int32_t restitution_mode);

JOLT_C_EXPORT void jolt_body_set_shape(JoltWorld* world, uint32_t body, JoltShape* shape, bool update_mass);
JOLT_C_EXPORT void jolt_body_set_mass_properties(JoltWorld* world, uint32_t body, float mass, const float* inertia9,
                                                 int32_t allowed_dofs);
JOLT_C_EXPORT void jolt_body_set_motion_type(JoltWorld* world, uint32_t body, int32_t motion_type, bool activate);
JOLT_C_EXPORT void jolt_body_set_damping(JoltWorld* world, uint32_t body, float linear, float angular);
JOLT_C_EXPORT void jolt_body_set_gravity_factor(JoltWorld* world, uint32_t body, float factor);
JOLT_C_EXPORT void jolt_body_set_continuous_collision(JoltWorld* world, uint32_t body, bool enabled);

/// Places the shape origin at position3 / rotation4 (no velocity change).
JOLT_C_EXPORT void jolt_body_set_transform(JoltWorld* world, uint32_t body, const float* position3,
                                           const float* rotation4, bool activate);
JOLT_C_EXPORT void jolt_body_set_velocity(JoltWorld* world, uint32_t body, const float* linear3, const float* angular3);
/// Moves a kinematic body to the target over dt seconds (it gets the velocity).
JOLT_C_EXPORT void jolt_body_move_kinematic(JoltWorld* world, uint32_t body, const float* position3,
                                            const float* rotation4, float dt);
JOLT_C_EXPORT void jolt_body_add_force(JoltWorld* world, uint32_t body, const float* force3);
JOLT_C_EXPORT void jolt_body_add_force_at(JoltWorld* world, uint32_t body, const float* force3, const float* point3);
JOLT_C_EXPORT void jolt_body_add_torque(JoltWorld* world, uint32_t body, const float* torque3);
JOLT_C_EXPORT void jolt_body_add_impulse(JoltWorld* world, uint32_t body, const float* impulse3);
JOLT_C_EXPORT void jolt_body_add_impulse_at(JoltWorld* world, uint32_t body, const float* impulse3,
                                            const float* point3);
JOLT_C_EXPORT void jolt_body_add_angular_impulse(JoltWorld* world, uint32_t body, const float* impulse3);
JOLT_C_EXPORT void jolt_body_activate(JoltWorld* world, uint32_t body);
JOLT_C_EXPORT void jolt_body_deactivate(JoltWorld* world, uint32_t body);
JOLT_C_EXPORT bool jolt_body_is_active(JoltWorld* world, uint32_t body);

/// Body state, JOLT_BODY_STATE_STRIDE doubles: centre of mass xyz, rotation
/// xyzw, linear velocity xyz, angular velocity xyz, active (0/1), shape
/// origin xyz.
#define JOLT_BODY_STATE_STRIDE 17
JOLT_C_EXPORT void jolt_body_get_state(JoltWorld* world, uint32_t body, double* out);
/// The state of count bodies into out (count * JOLT_BODY_STATE_STRIDE doubles).
JOLT_C_EXPORT void jolt_world_get_body_states(JoltWorld* world, const uint32_t* bodies, uint32_t count, double* out);
/// The body's mass (kg; 0 for a static or kinematic body).
JOLT_C_EXPORT float jolt_body_get_mass(JoltWorld* world, uint32_t body);
JOLT_C_EXPORT uint64_t jolt_body_get_user_data(JoltWorld* world, uint32_t body);

// --- Contacts -----------------------------------------------------------------

/// A contact of the last jolt_world_step (added or persisted), between the
/// sub-shapes (by user data) of two bodies. normal points from body_a to
/// body_b; impulse is the estimated normal impulse (kg m/s) of this contact.
typedef struct JoltContact {
  uint32_t body_a;
  uint32_t body_b;
  uint32_t shape_a;  // sub-shape user data
  uint32_t shape_b;
  float point[3];
  float normal[3];
  float impulse;
  float penetration;
  int32_t point_count;
  bool persisted;
} JoltContact;

JOLT_C_EXPORT uint32_t jolt_world_contact_count(JoltWorld* world);
/// Copies up to max contacts; returns the number copied.
JOLT_C_EXPORT uint32_t jolt_world_get_contacts(JoltWorld* world, JoltContact* out, uint32_t max);

// --- Queries ------------------------------------------------------------------

typedef struct JoltRayHit {
  uint32_t body;
  uint32_t shape;    // sub-shape user data
  float fraction;    // of the ray's length
  float point[3];
  float normal[3];
} JoltRayHit;

/// Broad phase proxies: a static box body standing for the axis-aligned box
/// min3..max3 (a query world never stepped: what a scene query should test
/// in detail). Returns the body id; user_data comes back from the queries.
JOLT_C_EXPORT uint32_t jolt_world_add_box_proxy(JoltWorld* world, const float* min3, const float* max3,
                                                uint64_t user_data);
/// Moves and resizes a proxy to the box min3..max3.
JOLT_C_EXPORT void jolt_world_set_box_proxy(JoltWorld* world, uint32_t body, const float* min3, const float* max3);
/// The user data of every body whose bounds the segment origin3 ->
/// origin3 + delta3 crosses (broad phase only, any order); writes up to max,
/// returns how many there are.
JOLT_C_EXPORT uint32_t jolt_world_broad_phase_ray(JoltWorld* world, const float* origin3, const float* delta3,
                                                  uint64_t* out_user_data, uint32_t max);
/// The user data of every body whose bounds the box min3..max3 crosses when
/// moved by delta3 (a swept shape's bounds).
JOLT_C_EXPORT uint32_t jolt_world_broad_phase_box_cast(JoltWorld* world, const float* min3, const float* max3,
                                                       const float* delta3, uint64_t* out_user_data, uint32_t max);
/// The user data of every body whose bounds overlap the box min3..max3.
JOLT_C_EXPORT uint32_t jolt_world_broad_phase_box(JoltWorld* world, const float* min3, const float* max3,
                                                  uint64_t* out_user_data, uint32_t max);

/// Casts the ray origin3 -> origin3 + direction3 (its length is the range)
/// against every body; true and the closest hit when it hits.
JOLT_C_EXPORT bool jolt_world_cast_ray(JoltWorld* world, const float* origin3, const float* direction3,
                                       JoltRayHit* out);

// --- Soft bodies (cloth) ---------------------------------------------------------

/// How a cloth soft body is built and simulated. Compliances are inverse
/// stiffness (0 = rigid edges); a negative compliance disables that kind of
/// constraint.
typedef struct JoltClothSettings {
  float edge_compliance;
  float shear_compliance;
  float bend_compliance;
  int32_t bend_type;   // 0 none, 1 distance, 2 dihedral
  int32_t lra_type;    // long range attachments to pinned vertices: 0 none, 1 Euclidean, 2 geodesic
  float lra_max_distance_multiplier;
  uint32_t iterations;
  float linear_damping;
  float max_linear_velocity;
  float friction;
  float restitution;
  float pressure;
  /// Compliance of the tetrahedral volume constraints (0 keeps each
  /// tetrahedron's volume rigidly); used by jolt_soft_body_create_volume.
  float volume_compliance;
  float vertex_radius;
  float gravity_factor;
  bool update_position;
  bool allow_sleeping;
  bool double_sided;
  /// When set, each tetrahedron's volume compliance is volume_compliance
  /// times six times its rest volume (m³): the same material whatever the
  /// tetrahedra's size (one compliance for all made small ones far softer).
  bool volume_compliance_per_volume;
  /// When set, each edge's compliance (edge, shear and distance-bend
  /// constraints alike) is its compliance times its rest length in
  /// centimetres: the same material whatever the mesh's cut (one compliance
  /// for all makes finely cut skin far softer, and it buckles).
  bool edge_compliance_per_length;
  /// Optional, one per vertex: the edge, shear and bend compliances scaled
  /// by it for the constraints at that vertex (Jolt averages the two ends'
  /// attributes per constraint); null for the same everywhere.
  const float* compliance_scale;
} JoltClothSettings;

/// Fills settings with cloth defaults (stiff edges, soft dihedral bend,
/// Euclidean long range attachments, 8 iterations).
JOLT_C_EXPORT void jolt_cloth_settings_init(JoltClothSettings* settings);

/// A cloth from vertex_count vertices (xyz triples in the body frame,
/// metres), their inverse masses (0 = pinned) and index_count / 3 triangles,
/// placed at position3 / rotation4. Returns the body id, or
/// jolt_invalid_body_id().
JOLT_C_EXPORT uint32_t jolt_soft_body_create(JoltWorld* world, const float* positions, const float* inverse_masses,
                                             uint32_t vertex_count, const uint32_t* indices, uint32_t index_count,
                                             const float* position3, const float* rotation4,
                                             const JoltClothSettings* settings, uint64_t user_data);
JOLT_C_EXPORT uint32_t jolt_soft_body_vertex_count(JoltWorld* world, uint32_t body);
/// The vertices' world positions (3 floats each) into out; returns the count.
JOLT_C_EXPORT uint32_t jolt_soft_body_get_vertices(JoltWorld* world, uint32_t body, float* out, uint32_t max);
/// Moves vertex index to world position3 with inverse_mass (0 pins it there,
/// for a kinematic attachment; > 0 frees it), zeroing its velocity.
JOLT_C_EXPORT void jolt_soft_body_set_vertex(JoltWorld* world, uint32_t body, uint32_t index, const float* position3,
                                             float inverse_mass);
/// Wind (aerodynamic): every face is pushed along its normal by the part of
/// the wind velocity wind3 (m/s, relative to the face) that hits it, at
/// drag * dt (a fraction per second); a face edge-on to the wind feels
/// nothing. Wakes the body.
JOLT_C_EXPORT void jolt_soft_body_apply_wind(JoltWorld* world, uint32_t body, const float* wind3, float drag,
                                             float dt);

/// Moves count pinned (inverse mass 0) vertices toward world targets
/// (xyz triples, m) over dt: each gets the velocity that reaches its target
/// at the end of the next step, so attachments drag the cloth smoothly.
JOLT_C_EXPORT void jolt_soft_body_drive_vertices(JoltWorld* world, uint32_t body, const uint32_t* indices,
                                                 const float* targets, uint32_t count, float dt);
/// The vertices and their normals (area-weighted over the faces) in a frame
/// of the caller's: world_to_local16 is a column-major 4x4 matrix taking world
/// metres to that frame (it may scale; normals use its rotation and are
/// renormalised). Writes 3 floats per vertex to each of out_positions and
/// out_normals; returns the vertex count written.
JOLT_C_EXPORT uint32_t jolt_soft_body_get_local_vertices(JoltWorld* world, uint32_t body,
                                                         const float* world_to_local16, float* out_positions,
                                                         float* out_normals, uint32_t max);
/// Carries a cloth along a rigid motion: delta16 (column-major 4x4, world,
/// metres) moves every free vertex amount (0..1) of the way to where the
/// motion takes it and turns its velocity as much (a character that moved
/// or turned this step: 1 moves the cloth with it, 0 leaves it behind).
/// include_pinned also moves the pinned vertices, all the way (a teleport).
JOLT_C_EXPORT void jolt_soft_body_carry(JoltWorld* world, uint32_t body, const float* delta16, float amount,
                                        bool include_pinned);
/// Sets the inverse mass of vertex index (0 pins it where it is).
JOLT_C_EXPORT void jolt_soft_body_set_inverse_mass(JoltWorld* world, uint32_t body, uint32_t index,
                                                   float inverse_mass);

/// Skinning of a cloth to a skeleton (a garment on a character). Frames are
/// the soft body's creation frame (its position / rotation), in metres.
typedef struct JoltClothSkin {
  /// joint_count column-major 4x4 matrices: each joint's bind pose inverted.
  const float* inverse_binds;
  uint32_t joint_count;
  /// Four joints and weights per vertex (a weight of 0 ends a vertex's list).
  const uint32_t* joints;
  const float* weights;
  /// Per vertex: how far (m) it may move from its skinned position (0 hard
  /// skins it), and the backstop distance behind it (>= max distance: none).
  const float* max_distances;
  const float* backstop_distances;
  float backstop_radius;
} JoltClothSkin;

/// A cloth (as jolt_soft_body_create) whose vertices are skinned to joints:
/// each vertex stays within its max distance of where the skeleton puts it.
/// Call jolt_soft_body_skin with hard_skin_all once after creating it.
JOLT_C_EXPORT uint32_t jolt_skinned_cloth_create(JoltWorld* world, const float* positions, const float* inverse_masses,
                                                 uint32_t vertex_count, const uint32_t* indices, uint32_t index_count,
                                                 const float* position3, const float* rotation4,
                                                 const JoltClothSettings* settings, const JoltClothSkin* skin,
                                                 uint64_t user_data);
/// A soft body (as jolt_soft_body_create, or jolt_skinned_cloth_create when
/// skin is not null) whose volume is also held by tetrahedral volume
/// constraints: tetrahedron_count tetrahedra of four vertex indices each in
/// tetrahedra, kept at their rest volume with settings->volume_compliance.
/// The triangles are the surface (collision and rendering); the tetrahedra may
/// use inner vertices. A tetrahedron with an index past vertex_count, a
/// repeated vertex or no volume at rest is skipped.
JOLT_C_EXPORT uint32_t jolt_soft_body_create_volume(JoltWorld* world, const float* positions,
                                                    const float* inverse_masses, uint32_t vertex_count,
                                                    const uint32_t* indices, uint32_t index_count,
                                                    const uint32_t* tetrahedra, uint32_t tetrahedron_count,
                                                    const float* position3, const float* rotation4,
                                                    const JoltClothSettings* settings, const JoltClothSkin* skin,
                                                    uint64_t user_data);
/// Poses a skinned cloth's skeleton: count column-major 4x4 joint matrices in
/// the world (metres). hard_skin_all puts every vertex on its skinned
/// position (a reset or a teleport).
JOLT_C_EXPORT void jolt_soft_body_skin(JoltWorld* world, uint32_t body, const float* joint_world16, uint32_t count,
                                       bool hard_skin_all);
/// A body a cloth of the same owner collides with (a character's limb
/// capsules for its garment); other bodies of the cloth's owner are ignored.
JOLT_C_EXPORT void jolt_body_set_cloth_collider(JoltWorld* world, uint32_t body, bool cloth_collider);
/// Self-collision for a cloth: after every step, a vertex closer than
/// distance (m) to one of the cloth's triangles is pushed out (the triangle
/// back) and stops approaching it, except where it is that close at rest
/// (its neighbours). 0 switches it off.
JOLT_C_EXPORT void jolt_soft_body_set_self_collision(JoltWorld* world, uint32_t body, float distance);

// --- Constraints --------------------------------------------------------------

/// A ball-and-socket joint with a swing cone and a twist range. Frames are in
/// each body's local space relative to its centre of mass: the twist axis is
/// the joint frame's X axis, the plane axis its Y axis. plane_half_cone is the
/// swing about Y, normal_half_cone the swing about Z (radians).
typedef struct JoltSwingTwistSettings {
  float position_a[3];
  float twist_axis_a[3];
  float plane_axis_a[3];
  float position_b[3];
  float twist_axis_b[3];
  float plane_axis_b[3];
  float normal_half_cone;
  float plane_half_cone;
  float twist_min;
  float twist_max;
  float max_friction_torque;
} JoltSwingTwistSettings;

/// A hinge about the frame's X axis (hinge axis), the Y axis as the normal
/// that is 0 rad; limits in radians (min > max = no limits).
typedef struct JoltHingeSettings {
  float position_a[3];
  float hinge_axis_a[3];
  float normal_axis_a[3];
  float position_b[3];
  float hinge_axis_b[3];
  float normal_axis_b[3];
  float limit_min;
  float limit_max;
  float max_friction_torque;
} JoltHingeSettings;

JOLT_C_EXPORT JoltConstraint* jolt_constraint_swing_twist(JoltWorld* world, uint32_t body_a, uint32_t body_b,
                                                          const JoltSwingTwistSettings* settings);
JOLT_C_EXPORT JoltConstraint* jolt_constraint_hinge(JoltWorld* world, uint32_t body_a, uint32_t body_b,
                                                    const JoltHingeSettings* settings);
JOLT_C_EXPORT void jolt_constraint_destroy(JoltWorld* world, JoltConstraint* constraint);
JOLT_C_EXPORT void jolt_constraint_set_enabled(JoltConstraint* constraint, bool enabled);
JOLT_C_EXPORT void jolt_constraint_set_max_friction_torque(JoltConstraint* constraint, float torque);
/// Solver iterations for the island this constraint is in (0 = the world's
/// setting); the island uses the largest override of its constraints.
JOLT_C_EXPORT void jolt_constraint_set_solver_steps(JoltConstraint* constraint, uint32_t velocity_steps,
                                                    uint32_t position_steps);
/// Swing-twist: cone and twist limits. Hinge: limit_min / limit_max are
/// twist_min / twist_max, the cones are ignored.
JOLT_C_EXPORT void jolt_constraint_set_limits(JoltConstraint* constraint, float normal_half_cone,
                                              float plane_half_cone, float twist_min, float twist_max);
/// Angular velocity motor: drives body B's angular velocity relative to A
/// toward angular_velocity3 (rad/s, in B's constraint frame; a hinge reads
/// its x) with at most max_torque (N m). max_torque <= 0 switches it off.
JOLT_C_EXPORT void jolt_constraint_set_velocity_motor(JoltConstraint* constraint, const float* angular_velocity3,
                                                      float max_torque);
/// Position motor: a spring of frequency (Hz) and damping ratio pulls body
/// B's joint frame toward target4 (xyzw, B's frame in A's frame; a hinge
/// reads the angle about X, its hinge axis in that frame) with at most max_torque (N m).
/// max_torque <= 0 switches it off.
JOLT_C_EXPORT void jolt_constraint_set_position_motor(JoltConstraint* constraint, const float* target4,
                                                      float frequency, float damping, float max_torque);
/// The accumulated position and rotation impulse magnitudes of the last
/// step (for breakable joints and diagnostics).
JOLT_C_EXPORT void jolt_constraint_get_lambdas(JoltConstraint* constraint, float* out2);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_JOLT_C_H
