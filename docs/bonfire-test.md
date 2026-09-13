# Bonfire local music-system smoke test

`resources/music/bonfire_local_test.tres` is intentionally committed **without** the copyrighted song file.

The profile resolves this local path at runtime:

`res://audio/Knife Party - Bonfire.mp3`

If the MP3 is absent, Fox Three falls back safely. Do not commit the MP3 unless you have distribution rights.

## 1. Generate the gameplay music map

From the repository root:

```powershell
py -m pip install -r tools/music_analysis/requirements.txt
py tools/music_analysis/analyze_song_gameplay.py "audio/Knife Party - Bonfire.mp3" --output "audio/Knife Party - Bonfire.analysis.json" --bpm 174 --seed 174052 --beats-per-bar 4
```

The gameplay analyzer detects beat timestamps, energy, frequency summaries, generic sections and **impact drops**. The committed profile also includes a manual smoke-test marker around the first major drop so the spectacle can be tested before/independently of automatic analysis.

The generated JSON contains no audio and can be committed if desired. The MP3 can remain untracked.

## 2. Run

Open the project in Godot 4.7 and press F5. `scenes/main.tscn` is already wired to `bonfire_local_test.tres` on this feature branch.

The music debug overlay starts enabled. F3 toggles it. Use `[` and `]` to seek between detected/authored sections.

Verify:

- `beat_source` shows `ANALYSIS` after the JSON exists; before that it uses the 174 BPM fallback grid.
- Beat/downbeat visual impulses line up with what you hear.
- The build approaching the first drop accelerates and tightens the stage.
- The drop causes a large but playable speed surge, FOV/camera punch, exhaust/VFX escalation, environment flash, rumble and aggressive stage pattern.
- Boost/brake still remain under player control on top of music speed.
- Radio chatter and cockpit alarms remain audible.

## 3. Fine alignment

If the audible kicks are consistently early/late, adjust `beat_offset` in `resources/music/bonfire_local_test.tres` by a few hundredths of a second.

`beat_offset` now affects only the beat/bar/phrase grid. It does **not** move section timestamps or important-moment timestamps.

If this MP3 is a different edit/master and the manual first-drop marker is off, change the `52.0` section/moment time in the Bonfire profile. The analyzer-generated map remains the long-term source of automatic choreography.

## What was fixed during this test pass

- Correct heard-audio clock: playback position + time since last mix - cached output latency.
- Output latency is cached rather than queried every frame.
- Beat-grid offset no longer shifts absolute song sections.
- Analyzer beat timestamps are consumed at runtime when available.
- Analyzer sections/energy/importance now actually feed SongProfile runtime queries.
- Manual SongProfile sections and moments override overlapping automatic guesses.
- Gameplay analyzer detects impact drops (energy/onset re-entry) instead of treating a fall in loudness as an EDM drop.
- Novelty time/value thinning is kept aligned in the gameplay analyzer.
