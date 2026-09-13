# Track & Stunts — `scripts/main.gd`

Endless runner track: preallocate everything in `_ready`, detect crossings as the fighter passes, recycle ahead. Deterministic seed `1337`. Emits `stunt_performed(kind, intensity, combo)` for the music phase.

## Layout (exports on `Main`)

| Export | Default | What |
|---|---|---|
| `tile_count` / `tile_length` / `tile_width` | 6 / 120 m / 320 m | Ground ribbon: 720 m paved, from +60 behind start far ahead (−Z) |
| `ring_count` / `ring_spacing` | 14 / 55 m | ~770 m of rings, slots x ±24, y 6–30 |
| `pillar_count` | 60 | Boxes scattered z +100 … −900, x by lane (below) |
| `combo_window` | 3.5 s | Time to extend a chain |

## Build (`_ready`)

Seed `_rng` (1337) → `_make_materials()` (ground, 2 post colors, ring/hit/graze, 3 pillar grays) → spawn fighter at (0, 12, 0) → `_build_ground()` / `_build_rings()` / `_build_pillars()` → wire `chase_cam.target` if unset.

- **Ground:** shared `PlaneMesh` (320×120) per tile + children: 6 edge posts (x ±36, alternating cyan/orange emissive, 3 per side) and 6 center dashes. Posts/dashes ride the tile so recycling moves them for free.
- **Rings:** shared `TorusMesh` (inner 4.5, outer 5.2 ≈ 10 m across), 24×12 segments. `_ring_slot(i)` = (±24, 6–30, −60 − i·55).
- **Pillars:** unique `BoxMesh` each (4–14 m wide/deep, 8–46 m tall), gray mats, base at y −1. Lane: 30% "skim" at x 34–46 (just outside the ±32 corridor), 70% scenic at x 48–140.

## Recycle (the endless loop)

Pattern for all three: **detect at crossing `fz < z`, teleport ahead `z -= span`**. Never `queue_free` + respawn per frame.

- **Ground** (`_recycle_ground`): tile fully behind (`tile.z − len/2 > fz + 70`) → `z −= len·count`.
- **Rings** (`_recycle_rings`): on crossing, score by 2D distance from ring center (see stunts); when 20 m behind → respawn at `fz − spacing·count ± 8` with a fresh slot, reset material/scale/passed flag. Hit rings pop (scale + flash 2.5/s decay) and slowly `rotate_z(0.25·dt)`.
- **Pillars** (`_recycle_pillars`): on crossing, check skim (see below); when `z − depth > fz + 60` → `z −= 1000`, new lane, re-seat y, reset flag.

## Stunts & combo (`_add_stunt`)

`_add_stunt(kind, intensity, combo_add, kick)` → bump combo (cap 99), reset `combo_window`, `add_speed_kick`, show popup, emit `stunt_performed`. Combo decays in `_process`; `_combo_t ≤ 0` resets to 0. `style_heat = combo·0.12` (0..1) is written to the fighter every frame for the music phase.

| Stunt | Trigger | Combo | Kick | Extra |
|---|---|---|---|---|
| `PERFECT THREAD` | Ring crossing, dist < **2.2 m** | +2 | +12 m/s | Green flash 1.5, trauma 0.15, **hitstop** 0.25× for 0.12 s |
| `THREADED` | Ring crossing, dist < **5.5 m** | +1 | +7 m/s | Green flash 1.0, trauma 0.12 |
| `GRAZE` | Ring crossing, dist < **7.5 m** | +1 | +3 m/s | Gold flash 1.0, trauma 0.10 |
| `CLOSE!` | Pillar pass: |x| < 48, gap 0–6 m from face, below top + 2 | +1 | +2 m/s | Trauma 0.06 |
| `BARREL CHAIN` | Roll starts while combo > 0 | +1 (extends) | 0 | Rolls never *start* a chain — threads build, rolls keep |

Ring outer radius is ~5.2 m, so THREADED ≈ through the hole, GRAZE ≈ rim. Hitstop uses `Engine.time_scale` with a `_hitstop_busy` guard (no stacking) and `create_timer(dur, true, false, true)` so the timer ignores the time scale.

Combo tiers in `_update_hud`: x2+ shows `COMBO`, x4+ `STYLISH COMBO`, x6+ `DIZZYING COMBO`, x8+ `FOX THREE!!`.

## HUD (`_update_hud`)

- `SpeedLabel`: `km/h + ALT` from `forward_speed·3.6` and `y`.
- `StateLabel`: `BARREL ROLL! > BOOST >> > << BRAKE > HARD TURN (g>0.7) > CRUISE`.
- `InfoLabel`: `energy / g / z / mouse ON|OFF`.
- `Bottom`: static help line (see `docs/controls.md`).
- `CenterDot`: visible iff mouse steer on.
- `ComboLabel`: visible at x2+, tier text; `StuntLabel`: popup, alpha fades with `_stunt_t` (1.4 s).

## Reset / toggles

- `R` → `_reset_flight()`: back to (0, 12, 0), cruise forward, trauma 0. (Track is *not* rebuilt — rings stay where they are.)
- `M` or `toggle_mouse_steer` action → flip `fighter.mouse_steer_enabled`.
