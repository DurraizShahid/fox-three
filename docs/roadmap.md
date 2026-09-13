# Roadmap — Fox Three

## Now (prototype, done)

Endless straight-line flight with arcade feel: steer/boost/brake/barrel roll, recycled tiles + rings + pillars, stunts + combo + hitstop, chase cam with FOV kick + trauma shake, debug HUD. Deterministic (seed 1337).

## Music phase — implemented (feat/music-driven-stage-system)

Endless runner now has a reusable music-driven stage architecture. See `docs/music-system.md` for truth. Quick map:

- **Clock**: `MusicDirector` (latency-corrected `AudioStreamPlayer` time, not delta drift; signals `beat/downbeat/bar/phrase/section_*/important_moment_*/hype_changed`)
- **Config**: `SongProfile` (BPM, beat_offset, sections, moments, theme, JSON) + `StageTheme` (palette/lights/density/pattern weights)
- **Stage**: `StageDirector` (musical-chunk generation by beats/bars/phrases/sections, deterministic `seed ^ hash(theme)`, pooling)
- **Mapping**: `MusicReactiveDirector` → `Fighter` (`set_music_speed_multiplier` / beats) + `ChaseCamera` (`trigger_beat_pulse/drop_punch`) + `EnvironmentController` (sky/fog/lights) — no private access, no hard-coded song
- **Analyzer**: `tools/music_analysis/analyze_song.py` (librosa, offline, JSON sidecar; generic labels — manual relabel to `GUITAR_SOLO` etc.)
- **Debug**: F3 overlay + `[ ]` section seek, all seekers go through `MusicDirector` so the entire game resyncs

Legacy mapping suggestion still useful for new maneuvers, but now those signals *feed* the music system via `get_music_state()` extended keys (`music_speed_mult/target, music_hype/intensity/beat_pulse/surge, music_low/mid/high`). Rule: new maneuvers must emit signals + extend that dict via public API (see `development.md#recipes`); never poll Fighter privates.

Details + workflow to add a song: `docs/music-system.md`.

## Later (backlog, not scheduled)

- Collision consequences (rings are free today — pillars don't kill; decide: bounce, slow, or death + respawn?).
- Score persistence / best-combo display.
- Track variety: moving rings, gates, tunnels, altitude layers; biome swaps on the tile material.
- Enemies / projectiles (needs a real forward-aim model — currently there is none).
- Menus, pause, settings (sensitivity, invert Y already exported), game-over flow.
- Mobile: touch boost/brake buttons (steer exists; triggers don't).
- Performance pass if pillars/tiles grow: `MultiMeshInstance3D` for posts/pillars.
- License file + `plane.glb` provenance check before any release.
