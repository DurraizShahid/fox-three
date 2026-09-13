#!/usr/bin/env python3
"""
Fox Three — Offline Music Analyzer

Takes an audio file and generates a sidecar JSON "Music Map" for SongProfile.

Uses librosa for beat/BPM, onset, RMS, spectral energies, section novelty,
and an overall importance curve. Automatic labels are GENERIC (BUILD, PEAK,
BREAKDOWN, CHANGE, CLIMAX) — manual SongProfile markers override them.

Usage:
    python tools/music_analysis/analyze_song.py <song> --output <map.json>
    python tools/music_analysis/analyze_song.py sounds/music/track.ogg --output sounds/music/track.json --bpm 128 --offset 0.05 --seed 1337

No Python runtime dependency in exported Godot game; this is tooling only.

Output JSON is documented in tools/music_analysis/README.md.
"""

import argparse
import json
import math
import sys
from pathlib import Path

# ------------------------------------------------------------------
# Optional dependency check
# ------------------------------------------------------------------
try:
    import librosa
    import numpy as np
except ImportError:
    print("Missing dependencies. Install with:\n  pip install -r tools/music_analysis/requirements.txt", file=sys.stderr)
    sys.exit(1)


def estimate_bpm(y, sr, override_bpm=None):
    if override_bpm is not None:
        return float(override_bpm), None
    tempo, _beats = librosa.beat.beat_track(y=y, sr=sr)
    # tempo may be array or scalar depending librosa version.
    if isinstance(tempo, np.ndarray):
        tempo = float(tempo[0]) if tempo.size else 128.0
    else:
        tempo = float(tempo)
    # Clamp sane.
    tempo = float(np.clip(tempo, 40.0, 220.0))
    return tempo, _beats


def compute_rms_curve(y, sr, hop=2048, n_fft=4096):
    rms = librosa.feature.rms(y=y, frame_length=n_fft, hop_length=hop)[0]
    times = librosa.times_like(rms, sr=sr, hop_length=hop)
    # Normalize 0..1 via log scaling (RMS is 0..~0.5).
    # Use 20*log10(rms) mapped.
    # Simpler: normalize by percentile.
    if rms.size == 0:
        return [], []
    # Clip and normalize
    # Use 95th percentile as 1.0 so loud tracks don't compress.
    p95 = float(np.percentile(rms, 95)) or 1.0
    norm = np.clip(rms / max(p95, 1e-6), 0, 1)
    # Smooth with small window
    if norm.size > 5:
        norm = np.convolve(norm, np.ones(5)/5, mode="same")
    return times.tolist(), norm.tolist()


def compute_onset(y, sr):
    hop = 512
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    times = librosa.times_like(onset_env, sr=sr, hop_length=hop)
    if onset_env.size:
        # Normalize
        m = float(np.max(onset_env)) or 1.0
        onset_env = onset_env / m
    return times.tolist(), onset_env.tolist()


def compute_spectral_bands(y, sr):
    hop = 2048
    n_fft = 4096
    # Use librosa.feature.spectral_contrast or mfcc? We'll do RMS split via STFT magnitudes in bands.
    # Simpler: compute STFT then sum magnitudes in low/mid/high ranges.
    stft = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    times = librosa.times_like(stft, sr=sr, hop_length=hop)

    def band_energy(f_lo, f_hi):
        mask = (freqs >= f_lo) & (freqs < f_hi)
        if not np.any(mask):
            return np.zeros(stft.shape[1])
        e = np.mean(stft[mask, :], axis=0)
        # Normalize per band's own 95p
        p95 = float(np.percentile(e, 95)) or 1.0
        return np.clip(e / max(p95, 1e-6), 0, 1)

    low = band_energy(20, 250)
    mid = band_energy(250, 2000)
    high = band_energy(2000, 8000)
    # Smooth
    for arr in (low, mid, high):
        if arr.size > 5:
            arr[:] = np.convolve(arr, np.ones(5)/5, mode="same")
    return times.tolist(), low.tolist(), mid.tolist(), high.tolist()


def compute_novelty(y, sr):
    # Chroma based novelty for section boundaries (Foote).
    hop = 2048
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop)
    # Recurrence / self-similar? Use librosa.segment?
    # Simpler: compute librosa.onset style / chroma diff novelty.
    if chroma.shape[1] < 10:
        return [], []
    # Checker kernel novelty
    # Use librosa.segment.agglomerative? For simplicity compute frame-to-frame cosine distance.
    # Novelty = 1 - cosine similarity of successive frames' chroma.
    times = librosa.times_like(chroma, sr=sr, hop_length=hop)
    novelty = np.zeros(chroma.shape[1])
    for i in range(1, chroma.shape[1]):
        a = chroma[:, i-1]
        b = chroma[:, i]
        # cosine
        denom = (np.linalg.norm(a) * np.linalg.norm(b))
        if denom < 1e-8:
            novelty[i] = 0
        else:
            novelty[i] = 1 - float(np.dot(a, b) / denom)
    # Smooth
    if novelty.size > 7:
        novelty = np.convolve(novelty, np.ones(7)/7, mode="same")
    # Normalize
    m = float(np.max(novelty)) or 1.0
    novelty = novelty / m
    return times.tolist(), novelty.tolist()


def find_section_boundaries(times, rms_norm, novelty, beat_times, top_n=8):
    """Combine RMS change + novelty spikes + beat alignment to propose boundaries."""
    if not times or not novelty:
        return []
    # Score = 0.6*novelty + 0.4 * rms_diff
    rms = np.array(rms_norm)
    nov = np.array(novelty)
    # Align lengths: rms and novelty may have different time grids. Resample novelty to rms grid via interp.
    if len(times) != len(nov):
        # Already aligned in our functions? times same hop, so lengths match expect.
        # If mismatch, interpolate.
        nov_interp = np.interp(times, times[:len(nov)], nov) if len(nov) else nov
        nov = nov_interp
    rms_diff = np.abs(np.diff(rms, prepend=rms[0]))
    if rms_diff.size:
        rms_diff = rms_diff / (float(np.max(rms_diff)) or 1.0)
    score = 0.55 * nov + 0.45 * rms_diff
    # Find peaks (simple local max + threshold)
    thresh = float(np.percentile(score, 75))
    peaks = []
    for i in range(1, len(score)-1):
        if score[i] > thresh and score[i] > score[i-1] and score[i] > score[i+1]:
            peaks.append((times[i], float(score[i])))
    # Sort by score desc, keep top_n, then sort by time
    peaks.sort(key=lambda x: -x[1])
    peaks = peaks[:top_n]
    peaks.sort(key=lambda x: x[0])
    # Snap each boundary to nearest beat (so sections start on beat, more musical)
    snapped = []
    for t, s in peaks:
        if beat_times:
            # nearest beat
            bt = min(beat_times, key=lambda b: abs(b - t))
            # Only snap if within 0.6 sec
            if abs(bt - t) < 0.6:
                snapped.append(bt)
            else:
                snapped.append(t)
        else:
            snapped.append(t)
    # Deduplicate close boundaries (< 4 sec apart)
    filtered = []
    for t in sorted(snapped):
        if not filtered or t - filtered[-1] > 4.0:
            filtered.append(float(t))
    # Ensure first boundary > 5 sec (avoid intro split too early)
    filtered = [t for t in filtered if t > 5.0]
    return filtered


def label_sections(boundaries, duration, rms_times, rms_norm, beat_times):
    """Assign GENERIC labels based on energy relative to neighbors. No semantic solo detection."""
    if not boundaries:
        return []
    # Build segments: [0, b0), [b0, b1), ... [last, duration)
    cuts = [0.0] + boundaries + [duration]
    segments = []
    for i in range(len(cuts)-1):
        segments.append((cuts[i], cuts[i+1]))
    # Compute mean RMS per segment
    rms = np.array(rms_norm)
    rt = np.array(rms_times)
    seg_energy = []
    for (a, b) in segments:
        mask = (rt >= a) & (rt < b)
        if np.any(mask):
            seg_energy.append(float(np.mean(rms[mask])))
        else:
            seg_energy.append(0.5)
    # Normalize energies 0..1 across segments
    emin, emax = float(np.min(seg_energy)), float(np.max(seg_energy))
    span = max(emax - emin, 0.2)
    norm_e = [(e - emin)/span for e in seg_energy]

    labels = []
    for i, (a, b) in enumerate(segments):
        e = norm_e[i]
        prev = norm_e[i-1] if i > 0 else e
        nxt = norm_e[i+1] if i+1 < len(norm_e) else e
        dur = b - a
        # Heuristic labeling (generic, not semantic).
        label = "VERSE"
        intensity = 0.45 + e * 0.5
        importance = 0.2 + e * 0.3
        density = 0.85 + e * 0.4
        if e < 0.25 and dur > 6:
            label = "BREAKDOWN"
            importance = 0.1
            density = 0.6
        elif e > 0.78 and dur > 8:
            # Could be climax or peak
            if i >= len(segments)-2:
                label = "CLIMAX"
                importance = 0.9
                density = 1.6
            elif e > 0.88:
                label = "PEAK"
                importance = 0.95
                density = 1.7
            else:
                label = "CHORUS"
                importance = 0.65
                density = 1.25
        elif e > 0.62 and prev < 0.4 and nxt >= 0.5:
            label = "BUILD"
            importance = 0.35
            density = 1.05
        elif e > 0.7:
            label = "CHORUS"
            importance = 0.6
            density = 1.25
        elif dur < 8 and abs(e - prev) > 0.35:
            label = "CHANGE"
            importance = 0.3
            density = 0.9
        # Crescendo-like rise inside long segments: if RMS slopes up strongly, mark CRESCENDO
        if dur > 12:
            # check slope within segment
            mask = (rt >= a) & (rt < b)
            if np.any(mask):
                seg_rms = rms[mask]
                # linear fit slope
                x = np.linspace(0, 1, seg_rms.size)
                if seg_rms.size > 2:
                    slope = float(np.polyfit(x, seg_rms, 1)[0])
                    if slope > 0.3 and e > 0.55:
                        label = "CRESCENDO"
                        importance = 0.7
                        density = 1.35
                    elif slope < -0.3 and e < 0.45:
                        label = "BREAKDOWN"
        labels.append({
            "start": round(float(a), 3),
            "end": round(float(b), 3),
            "type": label,
            "intensity": round(float(np.clip(intensity, 0.0, 1.0)), 3),
            "importance": round(float(np.clip(importance, 0.0, 1.0)), 3),
            "density_mult": round(float(np.clip(density, 0.4, 2.0)), 3),
            "speed_mult": 1.0,  # user can override manually
        })
    # Merge tiny segments (<4s) into neighbor with closer energy
    merged = []
    for seg in labels:
        if merged and seg["end"] - seg["start"] < 4.0:
            # merge into previous (extend previous end)
            merged[-1]["end"] = seg["end"]
            # Recompute intensity as max
            merged[-1]["intensity"] = round(max(merged[-1]["intensity"], seg["intensity"]), 3)
            merged[-1]["importance"] = round(max(merged[-1]["importance"], seg["importance"]), 3)
        else:
            merged.append(seg)
    return merged


def find_peaks_and_drops(rms_times, rms_norm, beat_times, novelty):
    """Find energy peaks (potential drops/climaxes) and sudden drops."""
    if not rms_times:
        return [], []
    rms = np.array(rms_norm)
    times = np.array(rms_times)
    # Smooth rms already; look for peaks via local maxima above 75th percentile.
    thresh = float(np.percentile(rms, 75))
    peaks = []
    for i in range(1, len(rms)-1):
        if rms[i] > thresh and rms[i] > rms[i-1] and rms[i] > rms[i+1]:
            peaks.append((float(times[i]), float(rms[i])))
    # Keep top 6 peaks by rms value
    peaks.sort(key=lambda x: -x[1])
    peaks = peaks[:6]
    peaks.sort(key=lambda x: x[0])

    # Sudden drops: large negative diff
    diff = np.diff(rms, prepend=rms[0])
    drop_thresh = float(np.percentile(diff, 10))  # most negative
    drops = []
    for i in range(1, len(diff)):
        if diff[i] < drop_thresh - 0.05 and rms[i] < 0.45:
            drops.append(float(times[i]))
    # Deduplicate drops close together
    drops_f = []
    for t in sorted(drops):
        if not drops_f or t - drops_f[-1] > 5.0:
            drops_f.append(t)
    # Snap peaks/drops to nearest beat if close
    def snap(list_t):
        out = []
        for t in list_t:
            if isinstance(t, tuple):
                tt = t[0]
            else:
                tt = t
            if beat_times:
                bt = min(beat_times, key=lambda b: abs(b - tt))
                if abs(bt - tt) < 0.4:
                    tt = bt
            out.append(tt)
        return out

    peaks_t = snap(peaks)
    drops_t = snap(drops_f)
    # Convert peaks to dict with intensity
    peaks_out = [{"time": round(float(t),3), "energy": round(float(rms[np.argmin(np.abs(times - t))]),3)} for t in peaks_t]
    drops_out = [round(float(t),3) for t in drops_t]
    return peaks_out, drops_out


def build_importance_curve(rms_times, rms_norm, peaks, drops, segments):
    """Build per-frame importance 0..1 as combination of segment importance + peak proximity."""
    if not rms_times:
        return [], []
    times = np.array(rms_times)
    rms = np.array(rms_norm)
    # Base importance from segments
    # Map each time to segment importance
    seg_importance = np.zeros_like(rms, dtype=float)
    for seg in segments:
        a, b = seg["start"], seg["end"]
        imp = seg["importance"]
        mask = (times >= a) & (times < b)
        seg_importance[mask] = imp
    # Peak boost: Gaussian around each peak (1 sec sigma)
    peak_boost = np.zeros_like(rms, dtype=float)
    for p in peaks:
        t = p["time"] if isinstance(p, dict) else float(p)
        sigma = 2.0
        peak_boost += np.exp(-0.5 * ((times - t)/sigma)**2) * 0.5
    # Novelty/section change boost small
    # Combine: importance = max(seg_importance, peak_boost) blended? Use seg + boost but clip.
    importance = np.clip(seg_importance + peak_boost * 0.7, 0, 1)
    # Also add RMS itself a bit (high energy = more important)
    importance = np.clip(importance * 0.7 + rms * 0.3, 0, 1)
    # Smooth
    if importance.size > 9:
        importance = np.convolve(importance, np.ones(7)/7, mode="same")
    return times.tolist(), importance.tolist()


def main():
    parser = argparse.ArgumentParser(description="Fox Three music analyzer — generate sidecar Music Map JSON.")
    parser.add_argument("song", help="Path to audio file (wav/mp3/ogg/flac)")
    parser.add_argument("--output", "-o", required=True, help="Output JSON path (e.g. sounds/music/track.json)")
    parser.add_argument("--bpm", type=float, default=None, help="Override detected BPM (manually specified)")
    parser.add_argument("--offset", type=float, default=0.0, help="Beat offset seconds (shifts grid)")
    parser.add_argument("--seed", type=int, default=None, help="Stage seed to embed in JSON (optional)")
    parser.add_argument("--beats-per-bar", type=int, default=4, help="Beats per bar (time signature)")
    args = parser.parse_args()

    song_path = Path(args.song)
    if not song_path.exists():
        print(f"Song not found: {song_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Analyzing: {song_path} ...")
    # Load mono, sr 22050 for faster analysis (librosa default). Keep original duration.
    y, sr = librosa.load(str(song_path), sr=22050, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))
    print(f"  Duration {duration:.1f}s  SR {sr}  Samples {y.size}")

    # BPM + beats
    tempo, beat_frames = None, None
    tempo, _unused = estimate_bpm(y, sr, override_bpm=args.bpm)
    # Get beat timestamps
    _, beats = librosa.beat.beat_track(y=y, sr=sr, units="time")
    beats = beats.tolist() if hasattr(beats, "tolist") else list(beats)
    # Apply offset (like SongProfile.beat_offset) to beats for map alignment? Store offset separately.
    print(f"  BPM {tempo:.2f}  Beats {len(beats)}  Offset {args.offset}")

    # Downbeats (try): use beat_track with tighter? librosa's downbeat not trivial.
    # Estimate downbeat as every beats_per_bar.
    downbeats = beats[::args.beats_per_bar] if beats else []

    # Curves
    rms_times, rms_norm = compute_rms_curve(y, sr)
    onset_times, onset_strength = compute_onset(y, sr)
    spec_times, low_e, mid_e, high_e = compute_spectral_bands(y, sr)
    nov_times, novelty = compute_novelty(y, sr)

    # Boundaries & sections
    boundaries = find_section_boundaries(rms_times, rms_norm, novelty, beats, top_n=10)
    segments = label_sections(boundaries, duration, rms_times, rms_norm, beats)
    peaks, drops = find_peaks_and_drops(rms_times, rms_norm, beats, novelty)
    imp_times, importance = build_importance_curve(rms_times, rms_norm, peaks, drops, segments)

    # Build energy curve sampled at rms_times (already)
    energy_curve = [[round(float(t), 3), round(float(v), 3)] for t, v in zip(rms_times, rms_norm)]  # type: ignore[arg-type]
    # Thin to ~ 4Hz to keep JSON small (take every N).
    # rms_times is ~hop 2048 => ~10 Hz at 22050. Thin to 5 Hz.
    if len(energy_curve) > duration * 6:
        step = max(1, len(energy_curve) // int(duration * 5))
        energy_curve = energy_curve[::step]

    # Onset curve similarly thin
    onset_curve = [[round(float(t), 3), round(float(v), 3)] for t, v in zip(onset_times, onset_strength)]
    if len(onset_curve) > duration * 8:
        step = max(1, len(onset_curve) // int(duration * 8))
        onset_curve = onset_curve[::step]

    # Spectral summaries: keep full-ish but thin
    def thin_curve(times, vals):
        curve = [[round(float(t),3), round(float(v),3)] for t, v in zip(times, vals)]
        if len(curve) > duration * 5:
            step = max(1, len(curve) // int(duration * 5))
            curve = curve[::step]
        return curve

    low_curve = thin_curve(spec_times, low_e)
    mid_curve = thin_curve(spec_times, mid_e)
    high_curve = thin_curve(spec_times, high_e)

    # Importance curve thin
    imp_curve = [[round(float(t),3), round(float(v),3)] for t, v in zip(imp_times, importance)]
    if len(imp_curve) > duration * 5:
        step = max(1, len(imp_curve) // int(duration * 5))
        imp_curve = imp_curve[::step]

    # Assemble JSON
    out = {
        "version": 1,
        "source": str(song_path.as_posix()),
        "duration": round(duration, 3),
        "bpm": round(float(tempo), 2),
        "beat_offset": float(args.offset),
        "beats_per_bar": int(args.beats_per_bar),
        "seed": args.seed,
        "beats": [round(float(t), 4) for t in beats],
        "downbeats": [round(float(t), 4) for t in downbeats],
        "energy_curve": energy_curve,
        "onset_curve": onset_curve,
        "low_curve": low_curve,
        "mid_curve": mid_curve,
        "high_curve": high_curve,
        "importance_curve": imp_curve,
        "novelty": [[round(float(t),3), round(float(v),3)] for t, v in zip(nov_times, novelty[:: max(1, len(novelty)//int(duration*4))])][: int(duration*4)],
        "sections": segments,
        "boundaries": [round(float(b), 3) for b in boundaries],
        "peaks": peaks,
        "drops": drops,
        "analysis_notes": [
            "Automatic labels are GENERIC (BUILD, PEAK, BREAKDOWN, CHANGE, CLIMAX, CHORUS). Manual SongProfile markers override them.",
            "Energy is RMS normalized 0..1 (95th percentile = 1). Importance is segment + peak composite.",
            "Beats/downbeats are via librosa.beat.beat_track; downbeats are every N beats (assumed 4/4).",
        ]
    }

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {out_path}  ({out_path.stat().st_size/1024:.1f} KB)")
    print(f"  Sections: {len(segments)}  Peaks: {len(peaks)}  Drops: {len(drops)}")
    for s in segments:
        print(f"    {s['type']:12} {s['start']:6.1f}->{s['end']:6.1f}  int {s['intensity']:.2f} imp {s['importance']:.2f} dens {s['density_mult']:.2f}")
    print("Done. Create a SongProfile, set analysis_json_path to this file, then override any section's type to GUITAR_SOLO/BRIDGE etc manually.")


if __name__ == "__main__":
    main()
