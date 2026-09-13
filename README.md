# Fox Three

Arcade endless-runner fighter prototype in **Godot 4.7 (Forward Plus)**. You fly a jet straight down `-Z` forever through a recycled corridor of ground tiles, light posts, rings, and pillars. Thread rings, skim pillars, chain barrel rolls, and build combos — every maneuver already emits signals for the upcoming music phase.

> Forward is `-Z` (Godot convention). The body never rotates; all banking/pitching is visual-only on the `Model` child.

## Quick Start

1. Install **Godot 4.7** (Forward Plus). Windows uses D3D12 (`rendering_device/driver.windows="d3d12"` in `project.godot`).
2. Open this folder as a Godot project (`project.godot` at root).
3. Press **F5** — main scene is `res://scenes/main.tscn`.
4. Steer with **WASD / arrows** or mouse. See [docs/controls.md](docs/controls.md).

Test keys: **R** = reset flight, **M** = toggle mouse steer.

## Controls (summary)

| Action | Input |
|---|---|
| Steer / climb | WASD / arrows, mouse (M toggles), gamepad left stick, touch drag |
| Boost | Shift / Space / RMB / RT |
| Brake | Ctrl / C / LMB / LT |
| Barrel roll | Q / E (or LB / RB), hold to loop; double-tap A/D |
| Reset | R |

Full map with deadzones and fallbacks: [docs/controls.md](docs/controls.md).

## Project Structure

```
project.godot          # app config, input map, physics (Jolt), display
scenes/
  main.tscn            # Main (main.gd) + WorldEnvironment + Sun/Fill + Fighter + ChaseCamera + HUD
  fighter.tscn         # CharacterBody3D Fighter (fighter.gd) + Model/Plane + VFX + collision
scripts/
  fighter.gd           # class_name FighterJet — flight model, input, barrel roll, visuals, music state
  chase_camera.gd      # class_name ChaseCamera — laggy follow, look-ahead, FOV kick, trauma shake
  main.gd              # endless track: tiles/rings/pillars, stunts, combo, HUD, hitstop
assets/
  plane.glb            # jet mesh (nose at -X in source; scene bakes -X → -Z correction)
docs/
  architecture.md      # scene tree, script responsibilities, data flow
  flight-model.md      # tuning guide for Flight / Feel / Barrel / Bounds exports
  controls.md          # full input map
  track-and-stunts.md  # endless recycling, rings/pillars, combo, hitstop, HUD
  camera.md            # chase-cam feel parameters
  development.md       # setup, conventions, gotchas, how to extend
  roadmap.md           # music phase + future work
```

Agent entry point: [AGENTS.md](AGENTS.md).

## Architecture (30-second version)

- **`FighterJet` (`scripts/fighter.gd`)** — `CharacterBody3D`, owns all flight physics in `_physics_process`. Exposes runtime state (`input_steer`, `forward_speed`, `speed_ratio`, `lateral_g`, `maneuver_energy`, `is_boosting/braking/rolling`, `current_bank_deg`, `shake_trauma`, `style_heat`) and music signals (`boost_started/ended`, `brake_started/ended`, `barrel_started/finished`). Never rotates `rotation` — stays `Vector3.ZERO`.
- **`ChaseCamera` (`scripts/chase_camera.gd`)** — `Camera3D`, reads the fighter each `_process` for position, `velocity`, `speed_ratio`, `current_bank_deg`, `shake_trauma`. Looser X follow than Y/Z so the jet swings off-center in turns.
- **`Main` (`scripts/main.gd`)** — `Node3D`, builds/recycles ground tiles, rings, pillars; detects stunts; owns combo timer and HUD; emits `stunt_performed(kind, intensity, combo)`. Writes `fighter.style_heat` from combo count.
- Data flow: `Input → FighterJet → (velocity/position/state) → ChaseCamera + Main → HUD / stunts`.

Details: [docs/architecture.md](docs/architecture.md).

## Flight Model (tuning)

All tunables are `@export` on the Fighter with categories **Flight / Feel / Tilt / Barrel Roll / Bounds / Mouse / Touch**. Defaults: cruise 45 m/s, boost 85, brake 24; bank 55°, corridor ±32 m wide, 2–34 m tall.

Start here: [docs/flight-model.md](docs/flight-model.md).

## Stunts & Combo

- `PERFECT THREAD` (< 2.2 m from ring center, +2 combo, +12 m/s kick, hitstop) · `THREADED` (< 5.5 m, +1) · `GRAZE` (< 7.5 m, +1) · `CLOSE!` (pillar skim, +1) · `BARREL CHAIN` (roll while combo alive, extends chain)
- Combo window 3.5 s, cap x99. Tiers at x4/x6/x8 (`STYLISH` → `DIZZYING` → `FOX THREE!!`).
- Details: [docs/track-and-stunts.md](docs/track-and-stunts.md).

## Music Phase (next)

`FighterJet.get_music_state()` returns `speed_ratio / lateral_g / energy / boosting / braking / rolling / steer`, plus the 6 maneuver signals and `Main.stunt_performed`. Build the reactive music system off those — do not poll internals. Roadmap: [docs/roadmap.md](docs/roadmap.md).

## Development

Godot 4.7 · Jolt Physics · 1280×720, stretch `canvas_items`/`expand`. Conventions, debugging, and extension recipes: [docs/development.md](docs/development.md).

## License

No license file yet. Add one before distributing builds or assets (note: `assets/plane.glb` is third-party — verify its license first).
