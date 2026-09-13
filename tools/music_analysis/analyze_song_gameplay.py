#!/usr/bin/env python3
"""Fox Three gameplay-oriented music analyzer.

This is the preferred analyzer for stage generation. It reuses the base feature
extractors in analyze_song.py but adds *impact-drop* detection: a drop means a
musically significant energy/onset re-entry, not merely a negative loudness
change. The resulting JSON can drive SongProfile automatically.

Usage:
    python tools/music_analysis/analyze_song_gameplay.py <song> --output <map.json>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import librosa
    import numpy as np
except ImportError:
    print("Missing dependencies. Install with: pip install -r tools/music_analysis/requirements.txt", file=sys.stderr)
    raise SystemExit(1)

try:
    import analyze_song as base
except ImportError:
    from tools.music_analysis import analyze_song as base


def _sample_curve(times, values, t, fallback=0.0):
    if not times or not values:
        return fallback
    idx = int(np.argmin(np.abs(np.asarray(times) - t)))
    return float(values[min(idx, len(values) - 1)])


def detect_impact_drops(rms_times, rms_values, onset_times, onset_values, novelty_times, novelty_values, beats):
    """Detect EDM/rock-style impact entries: quiet/build -> strong post-hit energy.

    Candidate points are analyzed beat timestamps. We compare a multi-second
    pre-window to a post-window, then reward onset/novelty at the transition.
    Non-max suppression prevents a run of adjacent kicks becoming many drops.
    """
    if not rms_times or not rms_values:
        return []
    rt = np.asarray(rms_times)
    rv = np.asarray(rms_values)
    candidates = beats if beats else rms_times
    scored = []
    for t in candidates:
        t = float(t)
        if t < 5.0:
            continue
        pre_mask = (rt >= t - 3.0) & (rt <= t - 0.45)
        post_mask = (rt >= t + 0.15) & (rt <= t + 3.0)
        if not np.any(pre_mask) or not np.any(post_mask):
            continue
        pre = float(np.mean(rv[pre_mask]))
        post = float(np.mean(rv[post_mask]))
        jump = post - pre
        onset = _sample_curve(onset_times, onset_values, t, 0.0)
        novelty = _sample_curve(novelty_times, novelty_values, t, 0.0)
        # Mastered tracks can have small RMS jumps but huge onset/novelty, so the
        # threshold deliberately combines all three instead of RMS alone.
        score = max(jump, 0.0) * 1.8 + post * 0.38 + onset * 0.34 + novelty * 0.18
        if post >= 0.52 and (jump >= 0.07 or (onset >= 0.62 and novelty >= 0.35)) and score >= 0.62:
            scored.append({
                "time": t,
                "score": score,
                "energy_jump": jump,
                "pre_energy": pre,
                "post_energy": post,
                "onset": onset,
                "novelty": novelty,
            })

    scored.sort(key=lambda x: x["score"], reverse=True)
    kept = []
    for cand in scored:
        if all(abs(cand["time"] - other["time"]) >= 12.0 for other in kept):
            kept.append(cand)
        if len(kept) >= 8:
            break
    kept.sort(key=lambda x: x["time"])
    for row in kept:
        for key in tuple(row.keys()):
            row[key] = round(float(row[key]), 4)
    return kept


def _dedupe_boundaries(boundaries, duration):
    out = []
    for t in sorted(float(x) for x in boundaries if 0.0 < float(x) < duration):
        if not out or t - out[-1] >= 2.0:
            out.append(t)
        elif t in boundaries:
            # Prefer the later/newer musically explicit boundary when very close.
            out[-1] = t
    return out


def mark_drop_sections(sections, impact_drops):
    impact_times = [float(d["time"]) for d in impact_drops]
    for sec in sections:
        start = float(sec["start"])
        hit = next((t for t in impact_times if abs(t - start) <= 0.8), None)
        if hit is None:
            continue
        sec["type"] = "DROP"
        sec["intensity"] = max(float(sec.get("intensity", 0.5)), 0.96)
        sec["importance"] = 1.0
        sec["density_mult"] = max(float(sec.get("density_mult", 1.0)), 1.65)
        sec["speed_mult"] = max(float(sec.get("speed_mult", 1.0)), 1.12)
    return sections


def thin_curve(times, values, duration, hz=5.0):
    pairs = [[round(float(t), 3), round(float(v), 3)] for t, v in zip(times, values)]
    target = max(1, int(duration * hz))
    if len(pairs) > target:
        step = max(1, len(pairs) // target)
        pairs = pairs[::step]
    return pairs


def main():
    parser = argparse.ArgumentParser(description="Fox Three gameplay music analyzer")
    parser.add_argument("song")
    parser.add_argument("--output", "-o", required=True)
    parser.add_argument("--bpm", type=float, default=None)
    parser.add_argument("--offset", type=float, default=0.0)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--beats-per-bar", type=int, default=4)
    args = parser.parse_args()

    song_path = Path(args.song)
    if not song_path.exists():
        print(f"Song not found: {song_path}", file=sys.stderr)
        return 1

    print(f"Analyzing gameplay map: {song_path}")
    y, sr = librosa.load(str(song_path), sr=22050, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))
    tempo, _ = base.estimate_bpm(y, sr, override_bpm=args.bpm)
    _, beat_times = librosa.beat.beat_track(y=y, sr=sr, units="time")
    beats = beat_times.tolist() if hasattr(beat_times, "tolist") else list(beat_times)
    beats = [float(x) for x in beats]

    rms_times, rms_values = base.compute_rms_curve(y, sr)
    onset_times, onset_values = base.compute_onset(y, sr)
    spec_times, low_values, mid_values, high_values = base.compute_spectral_bands(y, sr)
    novelty_times, novelty_values = base.compute_novelty(y, sr)

    impact_drops = detect_impact_drops(
        rms_times, rms_values,
        onset_times, onset_values,
        novelty_times, novelty_values,
        beats,
    )

    boundaries = base.find_section_boundaries(rms_times, rms_values, novelty_values, beats, top_n=12)
    # Impact hits are explicit section boundaries so their spectacle begins on
    # the exact hit rather than several seconds early.
    boundaries = _dedupe_boundaries(boundaries + [d["time"] for d in impact_drops], duration)
    sections = base.label_sections(boundaries, duration, rms_times, rms_values, beats)
    sections = mark_drop_sections(sections, impact_drops)

    peaks, energy_falls = base.find_peaks_and_drops(rms_times, rms_values, beats, novelty_values)
    importance_peaks = list(peaks) + [{"time": d["time"], "energy": 1.0} for d in impact_drops]
    imp_times, importance_values = base.build_importance_curve(
        rms_times, rms_values, importance_peaks, energy_falls, sections
    )

    downbeats = beats[:: max(1, args.beats_per_bar)]
    output = {
        "version": 2,
        "source": song_path.as_posix(),
        "duration": round(duration, 3),
        "bpm": round(float(tempo), 3),
        "beat_offset": float(args.offset),
        "beats_per_bar": int(args.beats_per_bar),
        "seed": args.seed,
        "beats": [round(t, 4) for t in beats],
        "downbeats": [round(float(t), 4) for t in downbeats],
        "energy_curve": thin_curve(rms_times, rms_values, duration, 5.0),
        "onset_curve": thin_curve(onset_times, onset_values, duration, 8.0),
        "low_curve": thin_curve(spec_times, low_values, duration, 5.0),
        "mid_curve": thin_curve(spec_times, mid_values, duration, 5.0),
        "high_curve": thin_curve(spec_times, high_values, duration, 5.0),
        "importance_curve": thin_curve(imp_times, importance_values, duration, 5.0),
        # Thin times and values together; the v1 script accidentally thinned only values.
        "novelty": thin_curve(novelty_times, novelty_values, duration, 4.0),
        "sections": sections,
        "boundaries": [round(float(t), 3) for t in boundaries],
        "peaks": peaks,
        "impact_drops": impact_drops,
        # `drops` is retained for compatibility but now means gameplay impact drops.
        "drops": [d["time"] for d in impact_drops],
        "energy_falls": energy_falls,
        "analysis_notes": [
            "v2 gameplay analysis: impact_drops are strong energy/onset re-entries, not volume decreases.",
            "Automatic section labels remain heuristic. Manual SongProfile sections/moments override overlaps.",
            "Detected beat timestamps are consumed directly by AccurateMusicDirector when this JSON is assigned.",
        ],
    }

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, indent=2), encoding="utf-8")

    print(f"Duration: {duration:.2f}s | BPM: {tempo:.3f} | beats: {len(beats)}")
    print(f"Sections: {len(sections)} | impact drops: {len(impact_drops)} | peaks: {len(peaks)}")
    for drop in impact_drops:
        print(f"  IMPACT DROP {drop['time']:7.3f}s  score={drop['score']:.3f} jump={drop['energy_jump']:.3f}")
    for sec in sections:
        print(f"  {sec['type']:12} {sec['start']:7.2f} -> {sec['end']:7.2f}  int={sec['intensity']:.2f} imp={sec['importance']:.2f}")
    print(f"Wrote: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
