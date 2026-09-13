# Flight Model — `scripts/fighter.gd` (`FighterJet`)

Arcade endless-runner controller. The body (`CharacterBody3D`) translates only — it always flies straight down `-Z` and ends every physics tick with `rotation = Vector3.ZERO`. X = strafe, Y = climb. All banking/pitching/yaw is visual-only on the `Model` child.

Tune from the Inspector via `@export` categories. Defaults below are the current shipped feel.

## Flight (`@export_category("Flight")`)

| Export | Default | What it does |
|---|---|---|
| `cruise_speed` | 45 m/s | Baseline forward speed |
| `boost_speed` | 85 m/s | Target while boosting |
| `brake_speed` | 24 m/s | Target while braking |
| `forward_accel` | 55 m/s² | `move_toward` rate for `forward_speed` → target; lower = weightier transitions |
| `lateral_max_x` | 32 m/s | Max strafe speed |
| `lateral_max_y` | 24 m/s | Max climb/dive speed |
| `lateral_response` | 7.0 | Expo convergence rate for `velocity.x/y`. Higher = snappier, lower = drifty |
| `input_curve` | 1.5 | Pow curve in `_shaped()`; >1 = precise center, aggressive edges |
| `keyboard_deadzone` | 0.08 | Applied to all steer after shaping |
| `gamepad_deadzone` | 0.15 | Left-stick ignore radius |
| `invert_y` | false | Flip climb axis |
| `boost_agility_mult` | 1.25 | Lateral target scale while boosting |
| `brake_agility_mult` | 0.85 | Lateral target scale while braking |
| `boost_grip_mult` | 0.8 | Lateral convergence scale while boosting (<1 = slidey fast) |
| `brake_grip_mult` | 1.35 | Same while braking (>1 = grippy slow) |
| `dive_gain` | 0.35 | Dives buy speed, climbs spend it: `target += clamp(-vy * gain, -12, +14)` |
| `turn_bleed` | 6.0 | Hard carves bleed speed: `target -= carve * bleed`, carve 0..1 from normalized lateral velocity |
| `reverse_snap` | 1.6 | Counter-steer multiplier when `target_v * velocity < 0` and fast — makes slaloms whip |

### Speed pipeline (per `_physics_process`)

```
want_boost = held AND NOT rolling → _set_boosting (emits + trauma 0.22 + kick 6.0)
want_brake = held AND NOT boost AND NOT rolling → _set_braking (emits)
target_forward = cruise / boost / brake (+ roll floor: max(target, cruise + barrel_speed_kick))
target_forward += dive/climb term − carve bleed
target_forward += bonus_speed (stunt kicks, capped +25, decays 18/s)
forward_speed = move_toward(forward_speed, target, forward_accel * dt)
velocity.z = −forward_speed
```

Boost and brake are mutually exclusive (brake requires `not want_boost`); both are suppressed while rolling.

`speed_ratio = inverse_lerp(brake_speed, boost_speed, forward_speed)` → 0 at brake, ~0.4 at cruise, 1 at boost. Drives camera dolly/FOV, turbulence, flame scale.

## Feel / Tilt (`@export_category("Feel / Tilt")`)

| Export | Default | What |
|---|---|---|
| `bank_max_deg` | 55° | Bank from `input_steer.x` + 12° extra from actual drift (`velocity.x`) |
| `pitch_vis_max_deg` | 24° | Pitch from `input_steer.y` (×0.9) + 8° from `velocity.y` |
| `yaw_vis_max_deg` | 26° | Visual yaw from `input_steer.x` |
| `tilt_response` | 9.0 | Expo rate for pitch/yaw; also spring constant for bank |
| `camera_roll_share` | 0.18 | Fraction of `current_bank_deg` the camera borrows (× camera `roll_share_mult`) |
| `model_yaw_correction_deg` | 0.0 | Fine trim only — the real -X→-Z fix is baked in `fighter.tscn` |
| `vortex_gain` | 1.0 | Scales wingtip-vortex particle density |

Bank is a slightly underdamped spring (`_bank` / `_bank_vel`: accelerate toward target with `tilt²·0.9`, damp with `exp(−tilt·1.1·dt)`) so turn entry whips past the target a touch. Pitch/yaw use plain exponential easing. `_bank` never includes the barrel-roll spin — `_roll_visual` (0..TAU) is added on top, so `current_bank_deg` stays clean for the camera.

Life + turbulence are visual-only: idle bob (`sin` 0.05–0.06 m), speed shudder scaled by `speed_ratio`, exhaust flicker (`sin` layers + extra burner noise while boosting), flame core/halo scale + emission from `inverse_lerp(brake, boost, forward_speed)`, vortices from `lateral_g·1.35 − 0.3 + boost 0.35 + roll 0.5`.

## Barrel Roll (`@export_category("Barrel Roll")`)

| Export | Default | What |
|---|---|---|
| `barrel_duration` | 0.55 s | One full 360° (`_roll_visual = eased·TAU·dir`, smoothstep eased) |
| `barrel_cooldown` | 0.6 s | Lockout after start (`cooldown = duration + cooldown`) |
| `barrel_speed_kick` | 18 m/s | Roll floor: `target_forward ≥ cruise + kick` while rolling |
| `barrel_dash` | 10 m/s | Instant lateral shove `velocity.x += dir·dash` at roll start (dodge tool) |
| `double_tap_window` | 0.28 s | A/D double-tap window to trigger a roll |

Triggers: `roll_left`/`roll_right` actions (Q/E, LB/RB) in `_input`; double-tap `yaw_left/right`; **hold** Q/E loops rolls (checked each physics tick when idle + off cooldown). Emits `barrel_started(dir)` / `barrel_finished`, adds trauma 0.35. `try_barrel_roll(dir) -> bool` returns false while rolling or on cooldown.

## Bounds (`@export_category("Bounds (flight corridor)")`)

| Export | Default | What |
|---|---|---|
| `bound_half_width` | 32 m | Hard clamp on `x` |
| `bound_min_height` | 2 m | Hard clamp floor on `y` |
| `bound_max_height` | 34 m | Hard clamp ceiling on `y` |
| `bound_soft_margin` | 7 m | Zone before the wall where push-back ramps in |
| `bound_push_strength` | 3.5 | Push-back gain (× lateral max × t × dt × 4) + trauma when grinding |

Soft walls push velocity back before the hard `clampf` after `move_and_slide()`. Grinding the soft wall adds trauma (`grind·1.2·dt`).

### Bounds — keep these consistent

Corridor numbers must agree across files: fighter clamp (±32, 2–34) ↔ tile width 320 (`main.gd` `tile_width`) ↔ edge posts at x ±36 ↔ ring slots x ±24, y 6–30 ↔ pillar "skim" lane x 34–46. Widening the corridor means moving posts/rings/pillars too.

## Mouse / Touch (`@export_category("Mouse / Touch")`)

| Export | Default | What |
|---|---|---|
| `mouse_steer_enabled` | true | Toggled by `M` / `toggle_mouse_steer`; `CenterDot` visibility tracks it |
| `mouse_sensitivity` | 1.15 | Offset-from-center gain |
| `touch_steer_enabled` | true | Drag-to-steer on mobile |
| `touch_sensitivity` | 0.006 | ×0.25 applied per drag event (~250 px = full deflection), clamped to unit circle |
| `touch_decay` | 3.0 | Stick eases to zero on release (no snap) |

Input priority in `_gather_steer` (do not reorder): **1)** keyboard actions (+ key fallback) → **2)** gamepad left stick (stronger axis wins via `_pick_stronger`) → **3)** mouse offset-from-center — only after first `InputEventMouseMotion` (`_mouse_seen`), only while not rolling, only inside the viewport, only past `keyboard_deadzone`, only if stick/keys near idle (len < 0.05) → **4)** touch stick (stronger wins, then decays). `invert_y` applies last.

Hold fallbacks in `_is_boost_held` / `_is_brake_held` / `_is_roll_held` (Shift/Space/RMB/RT, Ctrl/C/Alt/LMB/LT, Q/E) keep the game flyable even if the input map is broken — keep them.

## Music state (`_update_music_state`)

```gdscript
speed_ratio      = inverse_lerp(brake, boost, forward_speed)
lateral_g        = |v.x|/maxX, |v.y|/maxY → length, clamped 0..1
maneuver_energy  = damped toward lateral_g·0.7 + speed_ratio·0.3 + roll 0.4 + style_heat·0.35
```

Hard-turn edge (`lateral_g > 0.7` or rolling) adds trauma 0.08. `get_music_state()` exposes `{speed_ratio, lateral_g, energy, boosting, braking, rolling, steer}` — the music phase reads this, not internals.
