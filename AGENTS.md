# AGENTS.md — Fox Three

Instructions for AI coding agents working in this repo. Human overview lives in `README.md`; deep dives in `docs/`.

## Stack

- Godot **4.7**, Forward Plus, Windows D3D12. Physics: **Jolt**. GDScript only (the `[dotnet] assembly_name` in `project.godot` is vestigial — do not add C# without asking).
- Main scene: `res://scenes/main.tscn`. Scripts: `scripts/fighter.gd` (`class_name FighterJet`), `scripts/chase_camera.gd` (`class_name ChaseCamera`), `scripts/main.gd`, plus `scripts/music/*` for the music-driven stage system.
- Buses: `audio/bus_layout.tres` defines `Master`, `Music` (with `AudioEffectSpectrumAnalyzer`), `SFX`. `MusicDirector.MusicPlayer` runs on `Music`.
- No tests, no linter config, no CI. Verify by running the project (F5) and flying: steer, boost, brake, roll, thread a ring. With a `SongProfile` assigned, also check F3 overlay.

## Invariants — do not break

1. **Forward is `-Z`.** The fighter always flies straight down `-Z`. Do not add free 3D turning.
2. **Body never rotates.** `FighterJet._physics_process` ends with `rotation = Vector3.ZERO`. All banking/pitching/yaw lives on the `Model` child (`_update_visuals`). Camera reads `current_bank_deg`, never body rotation.
3. **Plane mesh correction is baked.** In `scenes/fighter.tscn`, `Model/Plane` has transform `Transform3D(0,0,-0.15, 0,0.15,0, 0.15,0,0, 0,0.15,0.7)` because the source `plane.glb` nose is at `-X` (31 m long, 25.7 m span). Scale 0.15 fits the 5 m collision box; z +0.7 centers the pivot for barrel rolls. Do not "fix" this transform — use `model_yaw_correction_deg` (default 0.0) for fine trim only.
4. **Music integration goes through signals + `get_music_state()`.** Signals: `boost_started/ended`, `brake_started/ended`, `barrel_started(direction)/barrel_finished` on Fighter; `stunt_performed(kind, intensity, combo)` on Main; plus `MusicDirector` signals `beat/downbeat/bar/phrase/section_started/ended/important_moment_started/ended/hype_changed/song_finished`. State dict keys: `speed_ratio, lateral_g, energy, boosting, braking, rolling, steer` plus music keys `music_speed_mult/target, music_hype/intensity/beat_pulse/surge, music_low/mid/high`. Do not reach into privates (`_bank`, `_roll_t`, `__music_*`, `_beat_pulse`, …). Use `Fighter.set_music_*()` / `ChaseCamera.trigger_*()` public API.
5. **`Main` writes `fighter.style_heat`** (combo-derived, 0..1) every frame. Do not write it from anywhere else. `MusicReactiveDirector` writes `fighter.music_*` and `ChaseCamera.music_*` — no other writer.
6. **Deterministic track seed.** `main.gd` uses `_rng.seed = 1337`. `StageDirector` uses `song.seed ^ hash(theme_id)` and per-bar seeded RNG so same `SongProfile + seed + StageTheme` → same stage. Keep deterministic unless explicitly asked; recycle functions assume fixed counts.

## Where things live

| Task | File |
|---|---|
| Flight feel, input, barrel roll, tilt/VFX, trauma, music state | `scripts/fighter.gd` |
| Camera follow, look-ahead, FOV, shake + music reactivity | `scripts/chase_camera.gd` (`ChaseCamera` + `music_*` API) |
| Track building/recycling, stunts, combo, HUD, hitstop, music coordinator | `scripts/main.gd` (delegates to `scripts/music/*`) |
| Music clock, SongProfile, StageDirector, reactive directors | `scripts/music/music_director.gd`, `song_profile.gd`, `stage_director.gd`, `music_reactive_director.gd`, `environment_controller.gd` + `StageTheme`, `MusicSection`, `ImportantMoment`, `StagePattern` |
| Music debug overlay (F3, [ ] seek) | `scripts/music/music_debug_overlay.gd` |
| Offline analyzer (Python, librosa, no runtime deps) | `tools/music_analysis/analyze_song.py` |
| Scene tree, lighting, HUD layout | `scenes/main.tscn` |
| Jet assembly, collision, particles, exhaust | `scenes/fighter.tscn` |
| Audio buses (Master/Music/SFX, spectrum) | `audio/bus_layout.tres`, `project.godot` `[audio]` |
| Example sunset theme + demo song | `resources/themes/sunset_canyon.tres`, `resources/music/demo_song.tres` |
| Input actions, display, physics engine | `project.godot` (`[input]`) |

## Conventions

- Tune via `@export` in the Inspector, not magic numbers. Categories: Flight / Feel / Tilt / Barrel Roll / Bounds / Mouse / Touch (fighter), Frame / FOV / Shake (camera), plus **Music Speed / Music Visuals** (fighter) and **Music Reactivity** (camera/env).
- Null-safe node lookups: fighter VFX uses `get_node_or_null` (`flame_core`, `exhaust_halo`, `vortex_l/r`, `boost_particles`) — follow that pattern; missing VFX must not crash. `Main._ensure_music_systems()` also creates `MusicDirector/StageDirector/EnvironmentController/Reactive/Debug` if the scene lacks them so old scenes still launch.
- Input priority in `_gather_steer`: keyboard actions → gamepad left stick (stronger wins) → mouse offset-from-center (only if stick near idle, only after first mouse motion) → touch stick (decays). Keep this order.
- Shaping: `_shaped()` applies `keyboard_deadzone` + `input_curve` pow. Exponential damping via `_exp_damp(a, b, lambda, delta)` = `lerpf(a, b, 1-exp(-lambda*delta))`.
- Camera: X follow (`lateral_follow` 4.2) is looser than Y/Z (`follow_response` 6.5) on purpose — jet swings off-center in turns. With music active, `MusicReactiveDirector` adds beat micro-dolly/FOV and hype looseness via public `trigger_beat/drop_punch` (never private `_beat_pulse`).
- Stunt thresholds (ring-center distance): `< 2.2` PERFECT THREAD, `< 5.5` THREADED, `< 7.5` GRAZE. Do not retune without updating `docs/track-and-stunts.md`.
- Music: `Main` is coordinator; do not bloat it. Put clock timing in `MusicDirector`, placement in `StageDirector`, reactivity in `MusicReactiveDirector`/`EnvironmentController`. Use `SongProfile`/`StageTheme` Resources for data, not giant `match` on filenames.

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
- Music phase (implemented) → `docs/music-system.md` (was `roadmap.md` future plan)
- Full system map → `docs/architecture.md`

## Verification

- No automated tests. After a change: open in Godot 4.7, run F5, confirm no script errors, fly 30 s (steer/boost/brake/roll/ring thread), press R (reset works), check HUD updates.
- If you touch the input map, test keyboard + mouse; gamepad/touch paths have fallbacks (`_is_boost_held`, `_gather_steer`) — keep them working.
