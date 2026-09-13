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
project.godot          # app config, input map, physics (Jolt), display, audio buses
audio/bus_layout.tres  # Master / Music (spectrum analyzer) / SFX
scenes/
  main.tscn            # Main (main.gd) + WorldEnvironment + Sun/Fill + Fighter + ChaseCamera + HUD
  fighter.tscn         # CharacterBody3D Fighter (fighter.gd) + Model/Plane + VFX + collision
scripts/
  fighter.gd           # FighterJet — flight + music-speed + visuals (Music Speed/Visuals categories)
  chase_camera.gd      # ChaseCamera — follow + music reactivity (FOV/dolly/shake/beat)
  main.gd              # Main — tiles/rings/pillars + stunts/combo + music coordination (fallback safe)
  sfx_manager.gd       # Radio + alarms + light Music ducking
  music/
    music_director.gd      # authoritative clock (latency-corrected, spectrum, hype)
    song_profile.gd        # Resource: BPM/sections/moments/theme/JSON
    music_section.gd       # section data
    important_moment.gd    # drop-hit spike
    stage_theme.gd         # environment palette + pattern weights
    stage_pattern.gd       # pattern enum (~17 families)
    stage_director.gd      # music-chunk procedural generation (deterministic pooling)
    music_reactive_director.gd # maps clock → fighter/camera/env
    environment_controller.gd  # cached WorldEnvironment/Sky/Sun/Fill reactivity
    music_debug_overlay.gd # F3 overlay + [ ] section seeks
resources/
  themes/sunset_canyon.tres # StageTheme matching existing sunset
  music/demo_song.tres       # demo SongProfile (clock-only, no audio) — all section types
sounds/music/              # put tracks + sidecar JSONs here (see tools/music_analysis)
tools/music_analysis/
  analyze_song.py        # offline analyzer (librosa) → JSON map
  requirements.txt
  README.md
assets/plane.glb           # jet mesh (nose at -X → -Z correction baked)
docs/
  architecture.md
  flight-model.md
  controls.md
  track-and-stunts.md
  camera.md
  development.md
  music-system.md      # music-driven stage system (implemented)
  roadmap.md           # future backlog (music phase is now done)
```

Agent entry point: [AGENTS.md](AGENTS.md).

## Architecture (30-second version)

- **`FighterJet` (`scripts/fighter.gd`)** — `CharacterBody3D`, owns all flight physics in `_physics_process`. Exposes runtime state (`input_steer`, `forward_speed`, `speed_ratio`, `lateral_g`, `maneuver_energy`, `is_boosting/braking/rolling`, `current_bank_deg`, `shake_trauma`, `style_heat`, `music_speed_*`, `music_hype`, `music_low/mid/high`) and music signals (`boost_started/ended`, `brake_started/ended`, `barrel_started/finished`). Never rotates `rotation` — stays `Vector3.ZERO`. Now accepts public `set_music_speed_multiplier()` / `trigger_music_beat/surge()` without exposing privates.
- **`ChaseCamera` (`scripts/chase_camera.gd`)** — `Camera3D`, reads fighter each `_process` for position/velocity/bank/trauma plus `music_hype`/`beat` via public `trigger_beat_pulse()/trigger_drop_punch()`. Looser X follow than Y/Z; adds beat micro-dolly, hype looseness, drop punch (all smoothed, accessible).
- **`Main` (`scripts/main.gd`)** — `Node3D`, builds/recycles ground tiles, rings, pillars; detects stunts; owns combo/HUD/hitstop; **coordinates** `MusicDirector`, `StageDirector`, `EnvironmentController`, `MusicReactiveDirector`, `MusicDebugOverlay`. Delegates stage placement and reactivity; preserves fallback when `song_profile == null`.
- **`MusicDirector`** — single authoritative clock (latency-corrected `AudioStreamPlayer` time → beats/bars/sections/hype + `AudioEffectSpectrumAnalyzer`). Signals: `beat/downbeat/bar/phrase/section_* /important_moment_*/hype_changed`.
- Data flow: `Input → FighterJet → (velocity/state) → ChaseCamera + Main → HUD/stunts`, while `MusicDirector → StageDirector/MusicReactiveDirector → Fighter/Camera/Environment` (all via public API). No duplicate clocks.

Details: [docs/architecture.md](docs/architecture.md) + [docs/music-system.md](docs/music-system.md).

## Flight Model (tuning)

All tunables are `@export` on the Fighter with categories **Flight / Feel / Tilt / Barrel Roll / Bounds / Mouse / Touch / Music Speed / Music Visuals**. Defaults: cruise 45 m/s, boost 85, brake 24; bank 55°, corridor ±32 m wide, 2–34 m tall. Music-driven speed adds a smoothed multiplier (INTRO 0.93 → DROP 1.32, clamped 0.85–1.55) plus tiny beat breaths and a drop surge — boost/brake remain meaningful.

Start here: [docs/flight-model.md](docs/flight-model.md) + [docs/music-system.md](docs/music-system.md).

## Stunts & Combo

- `PERFECT THREAD` (< 2.2 m from ring center, +2 combo, +12 m/s kick, hitstop) · `THREADED` (< 5.5 m, +1) · `GRAZE` (< 7.5 m, +1) · `CLOSE!` (pillar skim, +1) · `BARREL CHAIN` (roll while combo alive, extends chain)
- Combo window 3.5 s, cap x99. Tiers at x4/x6/x8 (`STYLISH` → `DIZZYING` → `FOX THREE!!`).
- Details: [docs/track-and-stunts.md](docs/track-and-stunts.md).

## Music-Driven Stage (implemented)

`FighterJet.get_music_state()` returns `speed_ratio / lateral_g / energy / boosting / braking / rolling / steer` **plus** `music_speed_mult/target, music_hype/intensity/beat_pulse/surge, music_low/mid/high`. `MusicDirector` is the single clock (BPM → beats/bars/sections/hype + spectrum). `SongProfile` (Resources in `resources/music/`) + `StageTheme` (`resources/themes/`) make adding a song workflow: put track in `sounds/music/`, run `python tools/music_analysis/analyze_song.py <track> -o <map.json>`, duplicate `demo_song.tres`, assign stream + JSON + theme, hit Play. No code for a new track. Full guide and pattern language: [docs/music-system.md](docs/music-system.md). Debug with **F3**, seek sections with **[ ]**.

## Development

Godot 4.7 · Jolt Physics · 1280×720, stretch `canvas_items`/`expand`. Conventions, debugging, and extension recipes: [docs/development.md](docs/development.md).

## License

No license file yet. Add one before distributing builds or assets (note: `assets/plane.glb` is third-party — verify its license first).
