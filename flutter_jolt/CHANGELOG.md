# Changelog

## 0.0.1

- Initial release: Dart FFI bindings to Jolt Physics 5.6.0 (`JoltWorld`,
  `JoltShape`, `JoltConstraint`): rigid bodies, box / sphere / capsule /
  cylinder / convex hull / height field / compound shapes, swing-twist and
  hinge constraints with velocity and position motors and per-island solver
  iterations, contacts with estimated impulses, ray casts,
  per-sub-shape collision profiles, owner groups and ignored pairs.
- Steps run on a stepping thread of their own with a 16 MB stack (a deep
  narrow phase on a Dart mutator thread's small stack corrupted the VM).
- `tool/build_jolt.bat` / `tool/build_jolt.sh` fetch the pinned Jolt release
  and build a static library; the native-assets hook links it with the same
  `JPH_*` defines, or builds nothing when no Jolt build exists
  (`JoltPhysics.isAvailable` is then false).
