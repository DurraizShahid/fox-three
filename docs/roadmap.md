# Roadmap — Fox Three

## Now (prototype, done)

Endless straight-line flight with arcade feel: steer/boost/brake/barrel roll, recycled tiles + rings + pillars, stunts + combo + hitstop, chase cam with FOV kick + trauma shake, debug HUD. Deterministic (seed 1337).

## Next: music phase

The scaffolding is already in: every maneuver is a signal, every frame is a state dict.

**Consume (do not reinvent):**

- Fighter signals: `boost_started/ended`, `brake_started/ended`, `barrel_started(direction)/barrel_finished`
- `FighterJet.get_music_state()` → `{speed_ratio, lateral_g, energy, boosting, braking, rolling, steer}`
- `Main.stunt_performed(kind, intensity, combo)` + `fighter.style_heat` (combo 0..1)

**Suggested mapping (starting point, tune by ear):**

| Game event | Musical role |
|---|---|
| `speed_ratio` | Tempo / filter cutoff / master intensity |
| `lateral_g` | Harmonic tension / riser amount |
| `energy` (`maneuver_energy`) | Single "how hard are we going" macro |
| `boost_started` → beat drop; `brake_started` → breakdown | Section changes |
| `barrel_started` | Fill / crash; `direction` picks stereo side |
| `stunt_performed` intensity + combo tier | Stinger pitch/layer (PERFECT = resolve, GRAZE = tease) |
| `style_heat` | Extra layer fader (0 = drums+bass, 1 = full stack) |

**Rules:** new maneuvers must emit signals + extend `get_music_state()` (see `development.md#recipes`). Keep the audio bus off the physics thread — sample state in `_process`, never in `_physics_process`.

## Later (backlog, not scheduled)

- Collision consequences (rings are free today — pillars don't kill; decide: bounce, slow, or death + respawn?).
- Score persistence / best-combo display.
- Track variety: moving rings, gates, tunnels, altitude layers; biome swaps on the tile material.
- Enemies / projectiles (needs a real forward-aim model — currently there is none).
- Menus, pause, settings (sensitivity, invert Y already exported), game-over flow.
- Mobile: touch boost/brake buttons (steer exists; triggers don't).
- Performance pass if pillars/tiles grow: `MultiMeshInstance3D` for posts/pillars.
- License file + `plane.glb` provenance check before any release.
