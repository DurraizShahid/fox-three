# Architecture — Fox Three

## Mental model

Endless straight-line runner. The fighter flies down `-Z` at all times; the world (ground tiles, rings, pillars) recycles from behind to ahead. Three scripts own three jobs:

| Script | Node | Job |
|---|---|---|
| `scripts/fighter.gd` (`FighterJet`) | `Main/Fighter` (`CharacterBody3D`) | All flight: input → velocity → visual tilt → VFX → music state |
| `scripts/chase_camera.gd` (`ChaseCamera`) | `Main/ChaseCamera` (`Camera3D`) | Follows the fighter with lag, look-ahead, FOV kick, trauma shake |
| `scripts/main.gd` | `Main` (`Node3D`) | Builds/recycles track, detects stunts, owns combo + HUD + hitstop |

Data flows one way: **Input → Fighter → Camera / Main → HUD**.

## Scene tree

### `scenes/main.tscn` (root `Main: Node3D`, script `main.gd`)

```
Main (Node3D, main.gd)
├─ WorldEnvironment (sunset ProceduralSkyMaterial, glow, fog)
├─ Sun (DirectionalLight3D, warm, shadows on)
├─ Fill (DirectionalLight3D, cool blue, no shadows)
├─ Fighter (instance of fighter.tscn) @ (0, 12, 0)
├─ ChaseCamera (Camera3D, chase_camera.gd, target=../Fighter)
└─ HUD (CanvasLayer)
   ├─ TopLeft (VBoxContainer)
   │  ├─ SpeedLabel · StateLabel · InfoLabel · ComboLabel
   ├─ Bottom (Label, help line)
   ├─ CenterDot (ColorRect, mouse-steer indicator)
   └─ StuntLabel (center popup)
```

Environment: `ProceduralSkyMaterial` sunset (orange horizon, blue top), `Environment` with ambient 0.7, tonemap ACES-ish (`tonemap_mode = 3`), glow on, fog density 0.004 tinted warm. Lighting is baked into the feel — changing sky/fog changes speed perception more than you'd expect.

HUD nodes are bound with `@onready` in `main.gd` (`$HUD/TopLeft/SpeedLabel`, …). **Rename in both `main.tscn` and `main.gd`.**

### `scenes/fighter.tscn` (root `Fighter: CharacterBody3D`, script `fighter.gd`)

```
Fighter (CharacterBody3D, motion_mode=1 floating)
├─ Model (Node3D — ALL visual rotation lives here)
│  ├─ Plane (plane.glb instance, baked -X→-Z correction transform)
│  ├─ FlameCore (billboard quad, boost glow)
│  ├─ ExhaustHalo (billboard quad, soft glow)
│  ├─ VortexL / VortexR (GPUParticles3D, wingtip trails)
├─ CollisionShape3D (Box 3.6 × 1.4 × 5.2)
└─ BoostParticles (GPUParticles3D, speed trail)
```

`motion_mode = 1` is **floating** — correct for a flyer, do not change to grounded. Collision box is ~5 m; the `plane.glb` source mesh is 31 m long with nose at `-X`, so `Model/Plane` carries the baked correction `Transform3D(0,0,-0.15, 0,0.15,0, 0.15,0,0, 0,0.15,0.7)`: rotates nose to `-Z`, scales 0.15, shifts z +0.7 to center the pivot for barrel rolls.

VFX nodes are looked up with `get_node_or_null` and guarded — deleting any VFX node must not crash.

## Runtime frame

### Physics (`FighterJet._physics_process`, 60 Hz)

1. `_gather_steer(delta)` → `raw_steer` → `_shaped()` curve → `input_steer`
2. Boost/brake latch via `_set_boosting/_set_braking` (emit signals on edges)
3. Compute `target_forward` (cruise/boost/brake + roll floor + dive gain − carve bleed + `bonus_speed`), ease `forward_speed` toward it at `forward_accel`; `velocity.z = -forward_speed`
4. Lateral arcade velocity: `velocity.x/y` exponentially damped toward `steer * max * agility`, with `reverse_snap` boost on counter-steer
5. `_apply_soft_bounds` pushes back inside the corridor; `move_and_slide()`; hard clamp x/y
6. `rotation = Vector3.ZERO` (the invariant)
7. `_update_barrel_roll` → `_update_visuals` (Model tilt, flame, vortices) → `_update_music_state` (`speed_ratio`, `lateral_g`, `maneuver_energy`, trauma on hard turns)

### Frame (`Main._process` + `ChaseCamera._process`)

- `Main` decrements combo/stunt timers, writes `fighter.style_heat = clamp(combo * 0.12)`, extends chains on roll start, recycles ground/rings/pillars, updates HUD, handles `toggle_mouse_steer`.
- `ChaseCamera` reads fighter position/velocity/state and eases its own transform + FOV + shake offsets. It never writes to the fighter.

## State & signals (the public API)

**Fighter runtime state** (read these; all 0..1 unless noted): `input_steer: Vector2`, `raw_steer: Vector2`, `forward_speed: float` (m/s), `speed_ratio: float` (0 = brake … 1 = boost), `lateral_g: float`, `maneuver_energy: float`, `is_boosting/is_braking/is_rolling: bool`, `current_bank_deg: float`, `shake_trauma: float`, `bonus_speed: float`, `style_heat: float` (written by Main).

**Fighter signals:** `boost_started`, `boost_ended`, `brake_started`, `brake_ended`, `barrel_started(direction: float)`, `barrel_finished`. Emitted exactly on transitions (`_set_boosting` is the template).

**Fighter method:** `get_music_state() -> {speed_ratio, lateral_g, energy, boosting, braking, rolling, steer}`.

**Main signal:** `stunt_performed(kind: String, intensity: float, combo: int)` — emitted from `_add_stunt` for every scored event.

**Rule:** music/HUD/camera code reads signals + `get_music_state()` + public vars. Never touch `_bank`, `_roll_t`, `_vortex`, etc.

## Key decisions (why it is this way)

- **Body-never-rotates:** prevents the player getting lost and makes endless recycling trivial (everything is axis-aligned; recycling is just `z -= span`). All thrill comes from the Model tilt + camera.
- **-Z forward:** Godot convention; camera offset `(0, 1.7, 4)` sits behind (+Z) and above.
- **Arcade velocity, not forces:** lateral axes use exponential damping toward a target, so the jet always feels responsive and the corridor bounds stay predictable.
- **Preallocate + recycle, never spawn per frame:** tiles/rings/pillars are built once in `_ready` and teleported ahead. No allocation churn, deterministic with seed 1337.
- **Jolt physics** (`3d/physics_engine="Jolt Physics"`) for the `CharacterBody3D` + `move_and_slide` path.
- **Vestigial `[dotnet] assembly_name`:** project is GDScript-only. Do not add C# without asking.

## File map

| Path | What |
|---|---|
| `project.godot` | Name, main scene, 1280×720 `canvas_items`/`expand`, `[input]` map, Jolt, D3D12 |
| `scenes/main.tscn` | World assembly: environment, lights, fighter instance, camera, HUD |
| `scenes/fighter.tscn` | Jet assembly: Model/Plane correction, exhaust, vortices, collision, boost trail |
| `scripts/fighter.gd` | Flight model + input + visuals + music state |
| `scripts/chase_camera.gd` | Camera feel |
| `scripts/main.gd` | Track + stunts + combo + HUD |
| `assets/plane.glb` | Jet mesh (+ `.import`) |
| `icon.svg` | Project icon |
