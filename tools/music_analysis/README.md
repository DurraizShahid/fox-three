# Music Analysis Tool — `tools/music_analysis/`

Offline Python utility that analyzes a music file and generates a sidecar **Music Map JSON** for `SongProfile`.

This is **tooling only**. There is no Python runtime in the exported Godot game. You analyze once on your dev machine, commit the JSON, and the game reads it at runtime via `SongProfile.analysis_json_path`.

## What it detects

- **BPM** and **beat timestamps** (librosa.beat)
- **Downbeats** (every `beats_per_bar`; assumes 4/4 but configurable)
- **RMS / loudness curve** (energy)
- **Onset strength**
- **Spectral band summaries** low (20–250 Hz), mid (250–2k), high (2k–8k)
- **Novelty / change score** (chroma cosine distance) → likely section boundaries
- **Generic sections**: `INTRO`, `VERSE`, `BUILD`, `CHORUS`, `PEAK`, `BREAKDOWN`, `CHANGE`, `CRESCENDO`, `CLIMAX` with `intensity`/`importance`/`density_mult`
- **Peaks, drops**, and an **overall importance curve**

> **Automatic labels are generic.** The analyzer does **not** pretend to know a guitar solo from a chorus. It will create labels like `BUILD`, `PEAK`, `BREAKDOWN`, `CHANGE`, `CLIMAX`. You then open the `SongProfile` in Godot and relabel a section to `GUITAR_SOLO`, `BRIDGE`, etc. Manual markers always override automatic guesses.

## Setup

Requires Python 3.10+ and ffmpeg for MP3/OGG decoding.

```powershell
# Windows PowerShell
py -m pip install -r tools/music_analysis/requirements.txt
ffmpeg -version  # ensure ffmpeg is on PATH (https://ffmpeg.org)
```

On macOS/Linux:

```bash
pip install -r tools/music_analysis/requirements.txt
# brew install ffmpeg  (or apt install ffmpeg)
```

## Usage

```bash
# Basic
python tools/music_analysis/analyze_song.py sounds/music/my_track.ogg --output sounds/music/my_track.json

# With BPM / offset / seed overrides
python tools/music_analysis/analyze_song.py sounds/music/my_track.mp3 --output sounds/music/my_track.json --bpm 128 --offset 0.12 --seed 1337 --beats-per-bar 4
```

Arguments:

| Flag | What |
|---|---|
| `song` (positional) | Input audio (wav/mp3/ogg/flac) |
| `--output, -o` | Output JSON path (required). Put it next to the audio, e.g. `sounds/music/track.json` |
| `--bpm` | Skip detection, force this BPM |
| `--offset` | Beat offset seconds (shifts grid to align transients). Same as `SongProfile.beat_offset` |
| `--seed` | Embed a stage seed in JSON (optional; otherwise SongProfile.seed is used) |
| `--beats-per-bar` | Time signature numerator (default 4) |

## Output JSON

```json
{
  "version": 1,
  "duration": 184.3,
  "bpm": 128.0,
  "beat_offset": 0.12,
  "beats": [0.42, 0.89, 1.36, ...],
  "downbeats": [0.42, 2.31, 4.19, ...],
  "energy_curve": [[0.0, 0.12], [0.1, 0.15], ...],
  "onset_curve": [[0.0, 0.05], ...],
  "low_curve":  [[0.0, 0.3], ...],
  "mid_curve":  [[0.0, 0.2], ...],
  "high_curve": [[0.0, 0.15], ...],
  "importance_curve": [[0.0, 0.2], ...],
  "novelty": [[0.0, 0.05], ...],
  "sections": [
    {"start": 0.0, "end": 8.0, "type": "INTRO", "intensity": 0.22, "importance": 0.05, "density_mult": 0.7, "speed_mult": 1.0},
    {"start": 8.0, "end": 24.0, "type": "VERSE", ...}
  ],
  "boundaries": [8.0, 24.0, 32.0, ...],
  "peaks": [{"time": 88.0, "energy": 0.93}, ...],
  "drops": [48.0, 88.0]
}
```

In Godot, set `SongProfile.analysis_json_path` to this file. The game can then query `get_analysis_beats()`, `get_analysis_energy_at(t)`, etc. Manual `sections` / `important_moments` on the `SongProfile` override any analyzer guesses at the same time range.

## Workflow to add a song

1. Drop the audio into `sounds/music/` (e.g. `sounds/music/neon_rush.ogg`). **Do not commit copyrighted music** without rights; use your own or royalty-free tracks.
2. Analyze once: `python tools/music_analysis/analyze_song.py sounds/music/neon_rush.ogg --output sounds/music/neon_rush.json`
3. In Godot, duplicate `resources/music/demo_song.tres` → `resources/music/neon_rush.tres`, assign the `AudioStream` (import the ogg/mp3), set `bpm` / `beat_offset` from JSON, set `analysis_json_path` to the JSON, pick a `StageTheme`.
4. Optionally correct sections: relabel a `PEAK` to `GUITAR_SOLO`, tweak `importance`, add `ImportantMoment` at the drop time.
5. Assign the new `SongProfile` to `Main` (or `MusicDirector.song_profile`) and press Play — the stage, camera, and jet now choreograph to the track. See `docs/music-system.md` for details.

## Tuning tips

- If beats feel late/early, nudge `--offset` by ±0.02–0.10 s. Check the debug overlay (F3) — beat phase should hit 0 on audible kicks.
- If sections are too fragmented, increase the merge threshold in `analyze_song.py` (`top_n` / distance filter). If you want more sections, decrease it.
- `importance_curve` is exposed to `MusicDirector.hype`. To force a drop to go crazy, ensure its section has `importance >= 0.9` or add an `ImportantMoment` with `triggers_drop_surge = true`.

## Troubleshooting

- `librosa` import error → run `pip install -r requirements.txt` in the same interpreter you're invoking (`py -m pip` vs `pip`).
- `SoundFile` decode error on MP3 → install ffmpeg and reopen the terminal, or convert to WAV/OGG.
- Analysis is slow on long tracks (librosa loads fully into RAM) — for a 5-minute track expect ~15–45 s on a modern machine. For batch work, run one file at a time.

## No runtime dependency

The exported Godot game never imports `librosa` or runs Python. At runtime the game only reads the JSON sidecar if present; otherwise it synthesizes timing from `SongProfile.bpm` and manual sections.
