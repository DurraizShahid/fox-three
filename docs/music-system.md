# Music-Driven Stage System — Fox Three

This is the authoritative guide to the music infrastructure added in `feat/music-driven-stage-system`. It is the **implemented** reality, not a future roadmap.

## Mental model

Six cooperating modules replace the previous monolithic `main.gd` track. All musical timing derives from **one clock** (`MusicDirector`) so systems cannot drift independently. Steer input never waits for beats; the world choreographs *around* the player.

```
Audio file → [Offline Analyzer → JSON Map] → SongProfile (+ StageTheme) → MusicDirector (clock)
        → StageDirector (what to place, where, deterministically)
        → MusicReactiveDirector → Fighter (speed) + ChaseCamera (FOV/dolly/shake) + EnvironmentController (sky/fog/lights)
        → HUD (combat + debug)
        ↘ Main coordinates; fallback works with no SongProfile
```

## Files

| Path | What |
|---|---|
| `scripts/music/music_director.gd` (`MusicDirector`) | Authoritative clock, playback controller, spectrum |
| `scripts/music/song_profile.gd` (`SongProfile`) | Reusable Resource: BPM, sections, moments, theme, JSON |
| `scripts/music/music_section.gd` (`MusicSection`) | Section data (type/intensity/importance/density/speed) |
| `scripts/music/important_moment.gd` (`ImportantMoment`) | Short high-importance spike (exact drop hit) |
| `scripts/music/stage_theme.gd` (`StageTheme`) | Visual + gameplay environment definition |
| `scripts/music/stage_pattern.gd` (`StagePattern`) | Enum of ~17 reusable pattern families |
| `scripts/music/stage_director.gd` (`StageDirector`) | Music-chunk procedural generation, deterministic pooling |
| `scripts/music/music_reactive_director.gd` (`MusicReactiveDirector`) | Maps clock → fighter/camera/env/HUD, hype, drops |
| `scripts/music/environment_controller.gd` (`EnvironmentController`) | Caches WorldEnvironment/Sky/Sun/Fill, drives them musically |
| `scripts/music/music_debug_overlay.gd` (`MusicDebugOverlay`) | Toggleable F3 overlay + section seek debug keys |
| `scripts/fighter.gd` | Extended with public `music_speed_mult/hype/spectrum` API, additive VFX |
| `scripts/chase_camera.gd` | Extended with public `music_hype/trigger_beat/drop_punch` API |
| `scripts/main.gd` | Now a coordinator; owns combo but delegates stage/music to directors |
| `scripts/sfx_manager.gd` | Adds light Music-bus ducking during critical alarms |
| `audio/bus_layout.tres` | Bus layout with dedicated `Music` (spectrum analyzer) + `SFX` |
| `resources/themes/sunset_canyon.tres` | Working sunset StageTheme matching existing visuals |
| `resources/music/demo_song.tres` | Clock-only demo SongProfile (no audio) showcasing all section types |
| `tools/music_analysis/analyze_song.py` | Offline analyzer (Python + librosa) → sidecar JSON |
| `tools/music_analysis/requirements.txt`, `README.md` | Setup/docs |
| `sounds/music/` | Put tracks + JSONs here (gitkept, no copyrighted audio committed) |
| `project.godot` | Now references `audio/bus_layout.tres` |

## SongProfile

`SongProfile` is a `Resource`. Create via Godot: Right-click → Create Resource → SongProfile, or duplicate `demo_song.tres`.

Key exports:

| Field | Meaning |
|---|---|
| `song_id`, `song_name` | Identifiers |
| `stream` | `AudioStream` (mp3/ogg/wav). `null` = fallback clock (no audio) |
| `bpm` | Beats per minute (40–240). Drives all timing |
| `beat_offset` | Seconds to shift downbeat grid (transient alignment) |
| `beats_per_bar` | Time signature numerator (default 4) |
| `beats_per_phrase` | e.g. 16 = 4 bars (for phrase signals) |
| `seed` | Stage determinism: same profile + seed → same geometry |
| `difficulty` | 0..1 (future: pattern density/AI) |
| `global_speed_mult`, `global_intensity_mult` | Overall multipliers |
| `stage_theme` | Linked `StageTheme` |
| `sections: Array[MusicSection]` | Manual sections — override analyzer |
| `important_moments: Array[ImportantMoment]` | Exact drop/hit spikes |
| `analysis_json_path` | `res://sounds/music/track.json` sidecar |

### MusicSection

```
start_time, end_time   # seconds
type                   # INTRO/VERSE/BUILD/CHORUS/DROP/SOLO/GUITAR_SOLO/BRIDGE/BREAKDOWN/CRESCENDO/CLIMAX/OUTRO/PEAK/CUSTOM
intensity 0..1
importance 0..1  # 1 triggers hype spectacle
density_mult, speed_mult
pattern_override       # -1 = auto, else StagePattern.Type
stage_theme_override   # swap theme for this section only
auto_generated         # from analyzer vs manual
```

Manual `sections` and `important_moments` always beat analyzer guesses.

Useful alias: `SongProfile.get_section_at(t)`, `intensity_at(t)`, `is_in_important_moment(t)`.

### StageTheme

One song is not tied to one environment. Themes control:

- sky/horizon/ground palette, fog, exposure, glow
- sun/fill color + energy + music reactivity
- ground/lane/ring/pillar/beacon colors
- allowed `StagePattern`s + weights, density min/max, ring spacing, corridor width, verticality, altitude bias, reactivity multipliers
- optional `section_overrides: Dictionary<String, StageTheme>` (e.g. DROP uses a redder theme)

Existing visuals are baked into `sunset_canyon.tres` so fallback looks identical. Future themes: Night City, Storm, Ocean, Arctic, Desert, Neon Grid, Upper Atmosphere, Carrier Fleet — **without rewriting music logic**.

## MusicDirector — the clock

Single source of truth for musical time.

- **No delta drift**: `song_position = AudioStreamPlayer.get_playback_position() + AudioServer.get_time_since_last_mix() + AudioServer.get_output_latency() + beat_offset`
- **Derived**: `seconds_per_beat = 60/BPM`, `current_beat = floor(pos/spb)`, `beat_phase 0..1`, `current_bar`, `bar_phase`, `phrase_index`, `current_section`, `section_progress`, `current_intensity/importance`, `is_in_important_moment`, `hype` (smoothed `impact_intensity` 0..1)
- **Spectrum**: `AudioEffectSpectrumAnalyzer` on `Music` bus → `low/mid/high/overall` 0..1, smoothed, with intensity-based fallback when bus absent. `bass→exhaust/FOV`, `mid→lights`, `high→particles`, `overall→glow`
- **Signals**: `beat`, `downbeat`, `bar`, `phrase`, `section_started/ended`, `important_moment_started/ended`, `intensity_changed`, `hype_changed`, `song_finished/started`
- **Seeking**: `seek_to()`, `seek_to_section()`, `restart_song()`, `resync()` after hitstop all resynchronize every system

## Offline analysis tool

`tools/music_analysis/analyze_song.py` (Python, librosa) is **offline only**.

```bash
pip install -r tools/music_analysis/requirements.txt
python tools/music_analysis/analyze_song.py sounds/music/track.ogg --output sounds/music/track.json --bpm 128 --offset 0.05 --seed 1337
```

Generates:

- estimated BPM (or forced), `beats`, `downbeats`
- `energy_curve` (RMS), `onset_curve`, `low/mid/high_curve`
- `novelty` (chroma change), `boundaries`, generic `sections` (BUILD/PEAK/BREAKDOWN/CHANGE/CLIMAX/CHORUS), `peaks`, `drops`, `importance_curve`

Auto-labels are **generic** — it never invents `GUITAR_SOLO` with certainty. SongProfile manual sections relabel one of those to `GUITAR_SOLO`/`BRIDGE` etc.

## How to add a new song

1. Drop audio into `sounds/music/` (e.g. `sounds/music/neon_rush.ogg`). Do not commit copyrighted material.
2. Analyze once: `python tools/music_analysis/analyze_song.py sounds/music/neon_rush.ogg --output sounds/music/neon_rush.json`
3. In Godot, duplicate `resources/music/demo_song.tres` → `resources/music/neon_rush.tres`. Assign `stream` (imported OGG/MP3), set `bpm`/`beat_offset` from JSON (or force via `--bpm`), set `analysis_json_path` to the JSON, pick a `StageTheme` (e.g. `sunset_canyon.tres`).
4. Optionally open the profile, correct sections: relabel a `PEAK` to `GUITAR_SOLO`, raise `importance` to 1.0 for the drop, add an `ImportantMoment` at the exact hit (`triggers_drop_surge = true`).
5. In `Main` inspector, assign `song_profile = neon_rush.tres` (and optionally `stage_theme` override). Or call `Main.set_song_profile(profile)` in code. Press Play. The stage/camera/jet now choreograph.

Optional editor helper: the `SongProfile` workflow is already a clean Resource workflow; no heavy editor plugin is installed — duplicating and assigning via inspector is the intended flow (see also the importer note below).

## How to create a new StageTheme

1. Right-click `resources/themes/` → Create Resource → `StageTheme`. Or duplicate `sunset_canyon.tres`.
2. Tune palettes (sky, horizon, ground, fog, sun/fill, ring/beam colors), densities (`density_min/max`, `ring_spacing_min/max`), `corridor_width`, `verticality`, `altitude_bias`, allowed patterns (`allowed_patterns` empty = all, plus per-pattern `pattern_weights`), and reactivity `environment_reactivity/vfx_intensity/camera_reactivity`.
3. For section-specific looks, add to `section_overrides` e.g. key `"DROP"` → a theme with redder horizon/higher glow. `StageDirector` auto-swaps on section entry.
4. Assign to `SongProfile.stage_theme` or `Main.stage_theme` (Main override wins). The existing game still uses the fallback sunset when none is assigned.

## Stage generation

- **Musical chunks, not arbitrary distances**: blocks are `beats`, `bars`, `4-bar`/`8-bar` phrases, and `sections`. `StageDirector` decides pattern every `bars_per_pattern` (default 4) or on section change.
- **Deterministic**: `rng.seed = song_seed ^ hash(theme_id)`. Per-bar placement uses a per-bar seeded RNG (`seed ^ bar * prime …`) so same `SongProfile + seed → same stage` even after seeking.
- **Pattern families**: `OPEN_FLIGHT, RING_STREAM, RING_WAVE, RING_SLALOM, VERTICAL_WAVE, PILLAR_SLALOM, LOW/HIGH_ALTITUDE_RUN, LANE_WEAVE, TIGHT/WIDE_CORRIDOR, DROP_RUSH, SOLO_FLOW, CRESCENDO_CLIMB, BREAKDOWN_OPEN, CHAOS, CUSTOM`. Adding a new pattern = new enum entry + handler in `StageDirector._position_for_pattern()` + optional weight.
- **Musical distance**: `meters_per_beat = expected_forward_speed * 60/BPM`. Ring spacing = `meters_per_beat * beats_per_ring * density⁻¹`, clamped to `StageTheme` bounds. Spacing feels related to the song, but obstacles never require frame-perfect timing — arcade flight, not Guitar Hero.
- **Pooling**: tiles/rings/pillars are preallocated in `Main._ready()` and teleported ahead (`z -= span`). StageDirector only decides *where*; no per-frame `queue_free()`/instantiate spikes.

### Music-to-stage language

- `INTRO`: sparse, long sightlines, low density
- `VERSE`: readable rhythmic layouts (moderate rings/pillars)
- `BUILD`: tighten patterns, increase verticality, ramp speed/anticipation
- `CHORUS`: larger gestures, denser
- `BREAKDOWN`: open stage, reduce clutter
- `BRIDGE`: noticeably change language (altitude/lanes/camera/palette)
- `SOLO/GUITAR_SOLO`: fast flowing lines encouraging banking/near-misses
- `CRESCENDO`: continuously escalate density/speed/lights/camera
- `DROP/CLIMAX/PEAK`: `impact_intensity` → 1 → **GO ABSOLUTELY INSANE** (see below)

## Jet speed — music-driven

`FighterJet` now has a public, smoothed music-speed layer:

- **Target**: `MusicReactiveDirector` computes per-section base: `INTRO 0.93, VERSE 1.0, BUILD 1.07 (+ ramp), CHORUS 1.12, BREAKDOWN 0.96, BRIDGE 1.08, SOLO 1.22, CRESCENDO 1.18 (ramped), DROP 1.32, CLIMAX 1.35, PEAK 1.38` — multiplied by `Section.speed_mult` and `SongProfile.global_speed_mult`, plus small `intensity`/`hype` nudges.
- **Smoothing**: `Fighter._music_speed_current = exp_damp(current, target, music_speed_response)`, clamp `music_speed_min_clamp..max_clamp` (0.85–1.55). Boost/brake remain meaningful (they set base `target_forward` *before* the music factor multiplies it).
- **Beat breathe**: tiny forward pulse on beats (`music_beat_impulse_gain` 0.04, downbeat 0.07) scaled by hype, feels like acceleration with rhythm not a speed bump.
- **Drop surge**: on entering a high-importance `DROP/CLIMAX/PEAK`, `fighter.trigger_music_surge(≈18 m/s)` is added and decays at `music_surge_decay` — a large but smoothly handled surge, with FOV/camera synced. Star `style_heat` scales the surge.
- **Safety**: hard clamps + `forward_accel` keep it non-jerky; meters-per-beat generation uses expected speed so geometry stays playable.
- **Public API**: `set_music_speed_multiplier()`, `trigger_music_beat()`, `trigger_music_surge()`, `set_music_hype/intensity/spectrum()`. `get_music_state()` now also returns `music_speed_mult/target, music_hype/intensity/beat_pulse/surge, music_low/mid/high`.

## BPM-reactive systems (WHEN vs HOW MUCH)

Timing (`WHEN`) from the clock; energy/spectrum (`HOW MUCH`) from analysis/live analyzer:

- **EVERY BEAT**: subtle camera micro-dolly/FOV tick, small exhaust/afterburner pulse, minor HUD tick
- **DOWNBEAT**: stronger camera/FOV pulse, env light pulse, controller rumble, stronger exhaust (scaled by hype so drops hit harder)
- **BAR**: stage pattern decisions, larger light pulse, occasional env event
- **4/8-BAR PHRASE**: camera choreography shift, larger layout transition, env transition
- **SECTION CHANGE**: pattern family, intensity, speed target, env behavior all switch
- **IMPORTANT MOMENT**: `impact_intensity` → full spectacle (see below)

Nothing simply blinks every subdivision at equal strength.

## Important moments — hype / impact

Central 0..1 `hype` (= `impact_intensity` / `music_hype`):

- Built from `max(importance, remapped intensity)`, boosted to `0.92` inside an `ImportantMoment`, and to `0.95/0.88` for `DROP/CLIMAX/PEAK` or `SOLO/CRESCENDO` with high importance. Smoothed with fast attack (`hype_response`) and slower decay (`hype_decay`) so hype lingers after a peak.
- At `hype → 1` the game combines (while keeping readability):
  - large smooth jet-speed lift + one-time surge at entry
  - stronger afterburner (length * (1+ hype)), halo, particles, vortices
  - FOV expansion + beat/downbeat pulses + drop punch (6°), dolly punch, controlled shake (capped, accessibility-mult)
  - momentum framing exaggerated (camera aligns more to velocity)
  - env glow/exposure/fog/sky/sun/fill pulses, beacon/ring beat scale, stage verticality/density escalation, tighter near-miss lanes
  - strong downbeat rumble, HUD section label pulse, optional screen flash via `EnvironmentController` exposure spike
  - NOT `Engine.time_scale` pause — audio must stay synced; NOT violent enough to prevent flying

Concrete drop **“holy shit”**: build-up tension (BUILD/CRESCENDO hype ramping), brief anticipation, drop hits → jet surges (`trigger_music_surge`), FOV punches outward, afterburner erupts, env lights hit, particles surge, pattern switches aggressively (to `DROP_RUSH/CHAOS`), major downbeat rumble. All routed through `MusicReactiveDirector._trigger_drop_spectacle()` (tunable, accessible).

## Camera

`ChaseCamera` keeps its momentum/velocity-alignment, FOV, dolly, trauma. New public reactive layer (never private manipulation):

- `set_music_hype/intensity()`, `trigger_beat_pulse(is_downbeat)`, `trigger_drop_punch()` → micro dolly/FOV on beats, larger downbeat pull, section-dependent follow looseness, momentum alignment exaggeration during solos, drop punch, capped hype-shift + beat shake, phrase-level behavior. All smoothed; no teleporting.

## Exhaust / visuals

`final_exhaust = flight_contribution + music_contribution`. Fast + hype is spectacular; slow + hype still pops. Gains exposed: `music_exhaust_gain`, `music_vortex_gain`, `music_particle_gain`, `music_emission_gain`.

## Environment reactivity

`EnvironmentController` caches `WorldEnvironment.environment`, `ProceduralSkyMaterial`, `Sun`, `Fill` (no per-frame material creation). Drives `glow`, `exposure`, `fog density`, `sky_energy`, `sun/fill energy`, horizon/top colors via `hype_response`, `beat_decay`, `drop_flash_decay`, all scaled by `environment_reactivity` and `accessibility_mult`. Small changes are smoothed; section transitions tween; drops hit hard.

## Audio mixing

New bus layout `audio/bus_layout.tres`: `Master`, `Music` (with `AudioEffectSpectrumAnalyzer`), `SFX`. `MusicDirector.MusicPlayer` is on `Music`; `SFXManager` stays on `Master`/`SFX` so engines/alarms remain intelligible. Light ducking (`music_ducking_enabled`, `music_duck_db`) lowers `Music` bus ≈ −3.5 dB during `pull_up`/`altitude`/`warning` so cockpit warnings cut through; no wholesale SFX overhaul.

## Debugging / HUD

- **Toggle**: `F3` (or `Main.debug_overlay_enabled`). Shows song/BPM/beat/bar/phase, section/progress, energy/importance/hype, speed mult, spectrum L/M/H, pattern/seed, analysis presence.
- **Seek**: `]` / `[` next/prev section, `,` / `.` one bar back/forward, `+`/`-` one second — all go through `MusicDirector.seek_to_section()`/`seek_to()` so the entire game resyncs (StageDirector regenerates deterministically from the new bar).
- HUD `StateLabel` appends `· SECTION` when music active; `InfoLabel` shows `beat/bar/hype/pattern`. `help` line mentions `F3`/`[ ]`.

## Fallback

If `SongProfile` is `null` or `stream` is `null`, `MusicDirector.is_fallback()` is true:

- A slow synthetic clock still ticks (so pattern demo works with `demo_song`'s clock-only BPM), but with no audio requirement.
- `StageDirector.is_active()` is false → `Main` uses original `ring_spacing`/`_rng` endless behavior.
- Game launches and plays exactly as before. Do not commit a required MP3.

## Performance

- Preallocate + pool + recycle preserved (rings/pillars/tiles). `StageDirector` only picks coordinates, no instantiation.
- Materials/environment cached; no per-frame `new StandardMaterial3D` or `Resource` allocation. Ring pulse reuses scale, not a new mesh.
- Analyzer reads one `SpectrumAnalyzerInstance` per frame; budget linear in bars, not in particles.

## Deterministic generation

Same `SongProfile + seed + stage_theme` → same stage, because:

- `StageDirector._base_seed = song.seed ^ hash(theme_id)`
- Per-bar placement `rng.seed = base ^ bar*prime ^ index`
- Weighted pattern picks use per-bar RNG (not sequential frame-order RNG)
- Seek/restart calls `resync()`/`_rebuild_rng()` so bar-aligned recomputation is identical.

## `get_music_state()` & signals — do not touch privates

Fighter public state remains the contract:

```gdscript
fighter.get_music_state() -> {
  speed_ratio, lateral_g, energy, boosting, braking, rolling, steer, lane,
  velocity_yaw_deg, velocity_pitch_deg, heading_yaw_deg, crab_angle_deg, slip_yaw_deg,
  music_speed_mult, music_speed_target, music_hype, music_intensity, music_beat_pulse, music_surge, music_low/mid/high
}
```

Fighter signals: `boost_started/ended, brake_started/ended, barrel_started(dir)/barrel_finished, lane_switched`.  
Main signal: `stunt_performed(kind, intensity, combo)` (+ `fighter.style_heat` written only by `Main`).

New music signals on `MusicDirector`: `beat, downbeat, bar, phrase, section_started/ended, important_moment_started/ended, intensity_changed, hype_changed, song_started/finished`.

**Do not reach into `Fighter._bank/_roll_t/_vortex/__music_*` or `ChaseCamera._mom_yaw/_beat_pulse`** — use the public API and `get_music_state()`.

## Limitations / next steps

- Analyzer downbeats are every N beats (assumes 4/4); manual `beats_per_bar` correction handles other meters. True meter detection would require more heavyweight analysis.
- Spectrum analyzer calibration (`log(mag) → 0..1`) is ear-tuned defaults; tweak `EnvironmentController`/`MusicDirector.spectrum_smoothing` if a track's mix is atypical.
- No hard `analysis → GUITAR_SOLO` semantic detection by design — that relabeling stays manual. Future work could add a lightweight classifier, but it must remain overrideable.
- Multi-theme visual content (City/Storm/etc.) ships only as the *system* + one sunset profile; building actual mesh palettes for every future biome is out of scope and kept data-driven.
- Ducking is light (−3.5 dB) and only for critical alarms; more elaborate side-chaining is not scheduled.
