// The flutter_jolt WebAssembly module (tool/web/build_jolt_wasm.sh) in Node:
// every jolt_* function of src/jolt_c.h is exported, and a sphere dropped on
// a static box comes to rest on it through the same C API the desktop
// library has.
//
//   node --test test/web/module_test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const require = createRequire(import.meta.url);
const FlutterJolt = require(join(root, 'web', 'flutter_jolt.js'));

const header = readFileSync(join(root, 'src', 'jolt_c.h'), 'utf8');
const declared = [...header.matchAll(/JOLT_C_EXPORT[^(]*[^a-z_0-9](jolt_[a-z0-9_]+)\(/g)].map((m) => m[1]);

test('every jolt_* function of the header is exported', async () => {
  const m = await FlutterJolt();
  assert.ok(declared.length > 80);
  for (const name of declared) assert.equal(typeof m[`_${name}`], 'function', name);
});

test('a sphere dropped on a static box rests on it', async () => {
  const m = await FlutterJolt();
  assert.equal(m._jolt_version(), 50600);
  const world = m._jolt_world_create(0);
  m._jolt_world_set_gravity(world, 0, -9.81, 0);
  const settings = m._malloc(256);
  const f32 = () => new Float32Array(m.HEAPU8.buffer);
  const i32 = () => new Int32Array(m.HEAPU8.buffer);

  const ground = m._jolt_shape_box(10, 0.5, 10, 0.05);
  m._jolt_body_settings_init(settings);
  i32()[settings >> 2] = 0; // static
  f32()[(settings + 8) >> 2] = -0.5; // position.y
  m._jolt_body_create(world, ground, settings);

  const ball = m._jolt_shape_sphere(0.5);
  m._jolt_body_settings_init(settings);
  i32()[settings >> 2] = 2; // dynamic
  f32()[(settings + 8) >> 2] = 5;
  const body = m._jolt_body_create(world, ball, settings);
  for (let i = 0; i < 240; i++) m._jolt_world_step(world, 1 / 60, 1);

  const state = m._malloc(17 * 8);
  m._jolt_body_get_state(world, body, state);
  const y = new Float64Array(m.HEAPU8.buffer, state, 17)[1];
  assert.ok(y > 0.45 && y < 0.6, `rests at y = ${y}`);
  m._free(state);
  m._free(settings);
  m._jolt_shape_release(ground);
  m._jolt_shape_release(ball);
  m._jolt_world_destroy(world);
});
