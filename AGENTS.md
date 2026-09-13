# AGENTS.md — Fox Three

Instructions for AI coding agents working in this repo. Human overview lives in `README.md`; deep dives in `docs/`.

## Stack

- Godot **4.7**, Forward Plus, Windows D3D12. Physics: **Jolt**. GDScript only (the `[dotnet] assembly_name` in `project.godot` is vestigial — do not add C# without asking).
- Main scene: `res://scenes/main.tscn`. Scripts: `scripts/fighter.gd` (`class_name FighterJet`), `scripts/chase_camera.gd` (`class_name ChaseCamera`), `scripts/main.gd`.
- No tests, no linter config, no CI. Verify by running the project (F5) and flying: steer, boost, brake, roll, thread a ring.

## Invariants — do not break

1. **Forward is `-Z`.** The fighter always flies straight down `-Z`. Do not add free 3D turning.
2. **Body never rotates.** `FighterJet._physics_process` ends with `rotation = Vector3.ZERO`. All banking/pitching/yaw lives on the `Model` child (`_update_visuals`). Camera reads `current_bank_deg`, never body rotation.
3. **Plane mesh correction is baked.** In `scenes/fighter.tscn`, `Model/Plane` has transform `Transform3D(0,0,-0.15, 0,0.15,0, 0.15,0,0, 0,0.15,0.7)` because the source `plane.glb` nose is at `-X` (31 m long, 25.7 m span). Scale 0.15 fits the 5 m collision box; z +0.7 centers the pivot for barrel rolls. Do not "fix" this transform — use `model_yaw_correction_deg` (default 0.0) for fine trim only.
4. **Music integration goes through signals + `get_music_state()`.** Signals: `boost_started/ended`, `brake_started/ended`, `barrel_started(direction)/barrel_finished` on Fighter; `stunt_performed(kind, intensity, combo)` on Main. State dict keys: `speed_ratio, lateral_g, energy, boosting, braking, rolling, steer`. Do not reach into privates (`_bank`, `_roll_t`, …).
5. **`Main` writes `fighter.style_heat`** (combo-derived, 0..1) every frame. Do not write it from anywhere else.
6. **Deterministic track seed.** `main.gd` uses `_rng.seed = 1337`. Keep deterministic unless the task explicitly asks for randomization; recycle functions assume fixed counts (`tile_count`, `ring_count`, `pillar_count`).

## Where things live

| Task | File |
|---|---|
| Flight feel, input, barrel roll, tilt/VFX, trauma, music state | `scripts/fighter.gd` |
| Camera follow, look-ahead, FOV, shake | `scripts/chase_camera.gd` |
| Track building/recycling, stunts, combo, HUD, hitstop, R/M keys | `scripts/main.gd` |
| Scene tree, lighting, HUD layout | `scenes/main.tscn` |
| Jet assembly, collision, particles, exhaust | `scenes/fighter.tscn` |
| Input actions, display, physics engine | `project.godot` (`[input]`) |

## Conventions

- Tune via `@export` in the Inspector, not magic numbers. Categories: Flight / Feel / Tilt / Barrel Roll / Bounds / Mouse / Touch (fighter), Frame / FOV / Shake (camera).
- Null-safe node lookups: fighter VFX uses `get_node_or_null` (`flame_core`, `exhaust_halo`, `vortex_l/r`, `boost_particles`) — follow that pattern; missing VFX must not crash.
- Input priority in `_gather_steer`: keyboard actions → gamepad left stick (stronger wins) → mouse offset-from-center (only if stick near idle, only after first mouse motion) → touch stick (decays). Keep this order.
- Shaping: `_shaped()` applies `keyboard_deadzone` + `input_curve` pow. Exponential damping via `_exp_damp(a, b, lambda, delta)` = `lerpf(a, b, 1-exp(-lambda*delta))`.
- Camera: X follow (`lateral_follow` 4.2) is looser than Y/Z (`follow_response` 6.5) on purpose — jet swings off-center in turns.
- Stunt thresholds (ring-center distance): `< 2.2` PERFECT THREAD, `< 5.5` THREADED, `< 7.5` GRAZE. Do not retune without updating `docs/track-and-stunts.md`.

## Common tasks

- **Add a maneuver:** add signal + state on `FighterJet`, emit at the transition (`_set_boosting` is the template), expose in `get_music_state()`, handle in `Main` (combo/HUD) — see `docs/development.md#recipes`.
- **Add an obstacle/pickup:** follow `_build_rings` / `_recycle_rings` pattern in `main.gd` (preallocate array, detect at crossing `fz < z`, recycle ahead `z -= span`). Never `queue_free` + respawn per frame.
- **Change corridor:** `bound_*` exports on fighter (hard clamp) must stay consistent with tile width (320), post x (±36), ring slots (x ±24, y 6–30). See `docs/flight-model.md#bounds`.
- **HUD:** nodes under `HUD/` in `main.tscn` are `@onready` in `main.gd` — rename in both places.

## Gotchas

- `fighter.tscn` root `motion_mode = 1` (floating) — correct for a flyer; don't switch to grounded.
- Mouse steer only engages after first `InputEventMouseMotion` (`_mouse_seen`) and yields to any active stick/keys. `M` / `toggle_mouse_steer` flips `mouse_steer_enabled`; `CenterDot` visibility tracks it.
- `_unhandled_input` in `main.gd` handles bare `KEY_M`/`KEY_R` by keycode; `fighter.gd` `_input` handles roll/double-tap/touch. Put new test keys in `main.gd`, new flight inputs in `fighter.gd`.
- Boost and brake are mutually exclusive (`want_brake ... and not want_boost`); both are suppressed while rolling, but rolling forces `target_forward >= cruise + barrel_speed_kick`.
- `Engine.time_scale` hitstop (`_hitstop`) uses `create_timer(..., true, false, true)` (ignore time scale) with `_hitstop_busy` guard — don't stack it.
- `.godot/` is gitignored build cache — never edit or commit it. `assets/*.import` files are committed; keep them.

## Docs to read before changing an area

- Flight feel → `docs/flight-model.md`
- Input map → `docs/controls.md`
- Track/stunts/combo/HUD → `docs/track-and-stunts.md`
- Camera → `docs/camera.md`
- Setup/debugging/recipes → `docs/development.md`
- Music phase → `docs/roadmap.md`
- Full system map → `docs/architecture.md`

## Verification

- No automated tests. After a change: open in Godot 4.7, run F5, confirm no script errors, fly 30 s (steer/boost/brake/roll/ring thread), press R (reset works), check HUD updates.
- If you touch the input map, test keyboard + mouse; gamepad/touch paths have fallbacks (`_is_boost_held`, `_gather_steer`) — keep them working.
