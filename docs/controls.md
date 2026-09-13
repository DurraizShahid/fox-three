# Controls — Fox Three

Source of truth: `project.godot` `[input]` plus fallbacks in `scripts/fighter.gd` (`_gather_steer`, `_is_boost_held`, `_is_brake_held`, `_is_roll_held`) and test keys in `scripts/main.gd` (`_unhandled_input`). HUD help line (`Bottom` label) mirrors this — update it if the map changes.

## Steer

| Action | Keyboard | Gamepad | Mouse / touch |
|---|---|---|---|
| `pitch_up` (climb) | W, Up | Left stick up (axis −Y flipped to +climb) | Mouse up from center; touch drag up |
| `pitch_down` (dive) | S, Down | Left stick down | Mouse down; touch drag down |
| `yaw_left` | A, Left | Left stick left | Mouse left; touch drag left |
| `yaw_right` | D, Right | Left stick right | Mouse right; touch drag right |

Deadzones: keyboard shaping `keyboard_deadzone` 0.08 + `input_curve` 1.5 pow; stick `gamepad_deadzone` 0.15. If stick and keys disagree, the stronger magnitude wins (`_pick_stronger`). Missing actions fall back to direct `Input.is_key_pressed` checks (WASD/arrows), so the game stays flyable.

Mouse steer: position offset from screen center × `mouse_sensitivity` 1.15, clamped ±1. Engages only **after the first mouse motion** (no spawn drift), yields to any active keys/stick (len ≥ 0.05 wins over mouse), disabled while rolling. Toggle with **M** (`toggle_mouse_steer`); the `CenterDot` HUD rect shows the state.

Touch: screen-drag accumulates into `_touch_stick` (`touch_sensitivity` 0.006 × 0.25 per event, ~250 px = full deflection), limited to the unit circle, decays at `touch_decay` 3.0/s. Enable with `touch_steer_enabled`.

## Maneuvers

| Action | Input | Notes |
|---|---|---|
| `boost` | Shift, Space, **RMB**, RT (axis > 0.3) | Target 85 m/s, agility ×1.25, grip ×0.8. Emits `boost_started/ended`, trauma 0.22 + 6 m/s launch kick |
| `brake` | Ctrl, C, Alt?, **LMB**, LT (axis > 0.3) | Target 24 m/s, agility ×0.85, grip ×1.35. Emits `brake_started/ended`. Suppressed if boost held |
| `roll_left` | Q, LB (button 9) | `try_barrel_roll(−1)`; hold to loop |
| `roll_right` | E, RB (button 10) | `try_barrel_roll(+1)`; hold to loop |
| Double-tap roll | Tap A/D or ←/→ twice within 0.28 s | Star-Fox style; same cooldown rules |

Boost and brake are mutually exclusive and both suppressed while rolling; rolling forces forward target ≥ cruise + 18 m/s kick and adds a 10 m/s lateral dash in the roll direction.

## Test keys (`main.gd`)

| Key | What |
|---|---|
| **R** | `_reset_flight()`: position (0, 12, 0), velocity −cruise on Z, trauma 0 |
| **M** | Toggle `fighter.mouse_steer_enabled` (same as `toggle_mouse_steer` action) |

Handled by raw keycode in `_unhandled_input` — they work even without the input action. New debug keys go here; new flight inputs go in `fighter.gd` `_input`.

## HUD help line

`Bottom` label text (in `_update_hud`): `WASD/Arrows steer · mouse steers (M toggles) · SHIFT/Space/RMB boost · CTRL/C/LMB brake · Q/E barrel roll (hold to loop), double-tap A/D · R reset`. Keep it accurate.
