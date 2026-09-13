# Camera — `scripts/chase_camera.gd` (`ChaseCamera`)

Arcadey chase cam: laggy follow, velocity look-ahead, speed FOV, trauma shake. Reads the fighter every `_process`; never writes to it. Assign `target` in the editor (`Main/ChaseCamera.target = ../Fighter`) — `Main._ready` also wires it if null.

## Frame (`@export_category("Frame")`)

| Export | Default | Feel |
|---|---|---|
| `offset` | (0, 1.7, 4.0) | Behind (+Z, since forward is −Z) and above. `_snap_behind()` uses it on ready |
| `follow_response` | 6.5 | Expo rate for Y/Z — glued |
| `lateral_follow` | 4.2 | Expo rate for X — **deliberately looser**: jet swings off-center in turns (drama) |
| `lookahead_lateral` | 0.28 | Desired pos leads `velocity.x` (and 0.7× on y) so the jet drifts in-frame when turning |
| `lookahead_forward` | 0.12 | Look point leads velocity + `−forward·0.6` on Z — stare ahead, not at the jet |
| `roll_share_mult` | 1.0 | × fighter `camera_roll_share` (0.18) → camera borrows ~18% of `current_bank_deg` via tilted up-vector |
| `dolly_back` | 1.6 m | Extra +Z at full `speed_ratio` |
| `dolly_up` | 0.6 m | Extra +Y at full `speed_ratio` (floor 1.2 m) |

Position: `desired = target.pos + offset + lookahead + dolly`, then X eased at `lateral_follow`, Y/Z at `follow_response`. Look target = fighter pos + velocity lead; up-vector tilted by shared bank (`Vector3(sin, cos, 0)`). `look_at` guarded against zero distance.

## FOV (`@export_category("FOV")`)

| Export | Default |
|---|---|
| `cruise_fov` | 75° |
| `boost_fov` | 92° |
| `brake_fov` | 68° |
| `fov_response` | 4.0 (expo rate) |

Rolling adds +5° on top. FOV is the main speed sensation — boost kick 75→92 should feel like a punch; lower `fov_response` for a lazier swell.

## Shake (`@export_category("Shake")`)

| Export | Default |
|---|---|
| `shake_max_offset` | 0.45 (h/v_offset units) |
| `shake_frequency` | 28 Hz (1.1× on x, 1.3× on y for non-circular wobble) |

Trauma lives on the fighter (`shake_trauma` 0..1, decays 1.6/s) and is squared on read for nicer falloff. Sources: boost press 0.22, roll 0.35, hard-turn edge 0.08, wall grind (scaled), perfect thread 0.15 / thread 0.12 / graze 0.10, pillar skim 0.06. When trauma ≈ 0, offsets ease back to zero at rate 8.

## Tuning tips

- Too stiff? Lower `follow_response` / raise `lookahead_lateral` — the jet should breathe in-frame.
- Too seasick? Lower `roll_share_mult` or fighter `camera_roll_share` first, then shake.
- Speed feels flat? Raise `boost_fov` / `dolly_back` before touching actual speeds.
