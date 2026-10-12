# Changelog

## 0.0.1

- Initial release: Dart FFI bindings to Jolt Physics 5.6.0 (`JoltWorld`,
  `JoltShape`, `JoltConstraint`): rigid bodies, box / sphere / capsule /
  cylinder / convex hull / height field / compound shapes, swing-twist and
  hinge constraints with motors, contacts with estimated impulses, ray casts,
  per-sub-shape collision profiles, owner groups and ignored pairs.
- `tool/build_jolt.bat` / `tool/build_jolt.sh` fetch the pinned Jolt release
  and build a static library; the native-assets hook links it with the same
  `JPH_*` defines, or builds nothing when no Jolt build exists
  (`JoltPhysics.isAvailable` is then false).
