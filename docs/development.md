# Development — Fox Three

## Setup

- Engine: **Godot 4.7**, renderer Forward Plus. Windows D3D12 is forced (`rendering_device/driver.windows="d3d12"`).
- Physics: **Jolt** (`3d/physics_engine="Jolt Physics"`).
- Display: 1280×720, stretch `canvas_items` / `expand`.
- Open the repo root in Godot (it contains `project.godot`), F5 runs `res://scenes/main.tscn`.
- No packages, no build step, no tests. `.godot/` is build cache (gitignored) — never edit it. Commit `assets/*.import`.

## GDScript conventions in this repo

- `class_name FighterJet` / `ChaseCamera` for cross-script typing (`target as FighterJet`).
- `@export_category` + `@export_range` for every tunable — add Inspector ranges, never magic numbers in logic.
- `@onready` for scene nodes; fighter VFX uses `get_node_or_null(...) as Type` + null guards so missing VFX never crashes. Follow that pattern.
- Helpers: `_exp_damp(a, b, lambda, delta) = lerpf(a, b, 1−exp(−λ·dt))`, `_shaped()` deadzone+curve, `_sgn()`, `_pick_stronger()`.
- Signals on transitions (`_set_boosting` template: guard `if v == state: return`, mutate, emit). Music code subscribes; gameplay never polls subscribers.

## Debugging

- Run F5, watch the debugger for script errors. Fly 30 s: steer both axes, boost, brake, Q/E rolls, thread a ring, press R.
- HUD `InfoLabel` shows `energy / g / z / mouse` live — your first stop when feel is off.
- Common causes: body has rotation (must be ZERO — tilt belongs on `Model`), camera `target` null (Main wires it, but check the editor path), stale `.godot` cache after moving files (delete `.godot/`, reimport).

## Recipes

### Add a maneuver (e.g. loop, stall turn)

1. `fighter.gd`: add `signal my_move_started/finished`, state var, `_try_my_move()` + `_set_my_move()` following `_set_boosting`, emit on edges, add trauma/kick as needed.
2. Expose in `get_music_state()` (new key) and document the key in `AGENTS.md` invariant 4.
3. `main.gd`: handle in `_process` like `BARREL CHAIN` (`_add_stunt` + `stunt_performed`), add HUD state in `_update_hud`.
4. `controls.md` + help line: add the binding; add the action to `project.godot` `[input]` if needed (keep the `_is_*_held` fallback too).

### Add an obstacle / pickup

1. `main.gd`: `_build_my_things()` (preallocate `Array`, shared mesh + material, deterministic `_rng`), `_recycle_my_things()` (detect `fz < z`, score, teleport `z -= span`, reset flags/materials). Copy `_build_rings` / `_recycle_rings`.
2. Score via `_add_stunt(kind, intensity, combo_add, kick)` — it handles combo, popup, signal, speed kick.
3. Keep corridor numbers consistent (see `flight-model.md#bounds`).

### Add a HUD element

1. `scenes/main.tscn`: add under `HUD/` with a `LabelSettings` sub-resource.
2. `main.gd`: `@onready var`, update in `_update_hud()`, null-guard like `stunt_label`.

### Hook up music (next phase)

Subscribe to the 7 signals (`boost_started/ended`, `brake_started/ended`, `barrel_started/finished`, `stunt_performed`) and poll `get_music_state()` per frame. Read `docs/roadmap.md`. Do not read fighter privates or write `style_heat` from anywhere but `Main._process`.
