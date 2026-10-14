import 'support/test_api.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:flutter_jolt/flutter_jolt.dart';

/// Broad phase proxies for scene queries: boxes in a world never stepped,
/// found by the segments and boxes that cross their bounds, moved and
/// resized in place, gone once destroyed.
void main() {
  setUpAll(() => expect(JoltPhysics.isAvailable, isTrue, reason: '${JoltPhysics.loadError}'));

  test('a ray and a box find the proxies whose bounds they cross', () {
    final world = JoltWorld(workerThreads: 0);
    addTearDown(world.dispose);
    // A row of unit boxes along x, user data = their x.
    final ids = <int, int>{};
    for (var x = 0; x < 10; x++) {
      ids[x] = world.addBoxProxy(
        Vector3(x * 3.0, 0, 0),
        Vector3(x * 3.0 + 1, 1, 1),
        x,
      );
    }
    final along = world.broadPhaseRay(Vector3(-1, 0.5, 0.5), Vector3(40, 0, 0))
      ..sort();
    expect(along, List.generate(10, (i) => i));
    expect(
      world.broadPhaseRay(Vector3(-1, 5, 0.5), Vector3(40, 0, 0)),
      isEmpty,
    );
    expect(
      world.broadPhaseRay(Vector3(-1, 0.5, 0.5), Vector3(5, 0, 0))..sort(),
      [0, 1],
    );
    expect(
      world.broadPhaseBox(Vector3(2.5, 0, 0), Vector3(6.5, 1, 1))..sort(),
      [1, 2],
    );
    // A unit box swept 7 m along x from x = 2.2 crosses boxes 1, 2 and 3.
    expect(
      world.broadPhaseBoxCast(
        Vector3(2.2, 0.2, 0.2),
        Vector3(2.4, 0.4, 0.4),
        Vector3(7, 0, 0),
      )..sort(),
      [1, 2, 3],
    );
    expect(
      world.broadPhaseBoxCast(
        Vector3(2.2, 3, 0.2),
        Vector3(2.4, 3.2, 0.4),
        Vector3(7, 0, 0),
      ),
      isEmpty,
    );

    // Moved and grown: box 0 now spans x 100..110.
    world.setBoxProxy(ids[0]!, Vector3(100, 0, 0), Vector3(110, 1, 1));
    expect(world.broadPhaseBox(Vector3(105, 0, 0), Vector3(106, 1, 1)), [0]);
    // The tree only grows until it is rebuilt: a moved proxy may still be
    // found where it was (a broad phase finds a superset), never missed.
    world.optimizeBroadPhase();
    expect(world.broadPhaseBox(Vector3(0, 0, 0), Vector3(0.5, 1, 1)), isEmpty);
    expect(world.broadPhaseBox(Vector3(105, 0, 0), Vector3(106, 1, 1)), [0]);
    world.destroyBody(ids[1]!);
    expect(
      world.broadPhaseRay(Vector3(-1, 0.5, 0.5), Vector3(5, 0, 0)),
      isEmpty,
    );
  });

  test('more hits than the buffer holds are all returned', () {
    final world = JoltWorld(workerThreads: 0);
    addTearDown(world.dispose);
    for (var i = 0; i < 1000; i++) {
      world.addBoxProxy(
        Vector3(i * 0.01, 0, 0),
        Vector3(i * 0.01 + 0.5, 1, 1),
        i,
      );
    }
    expect(
      world.broadPhaseBox(Vector3(-1, -1, -1), Vector3(20, 2, 2)).toSet(),
      Set.of(List.generate(1000, (i) => i)),
    );
  });
}
