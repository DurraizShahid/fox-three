extends Resource
class_name StageTheme
## Reusable visual + gameplay environment definition.
## One SongProfile picks one StageTheme; section overrides can swap it.

@export var theme_id: String = "sunset_canyon"
@export var display_name: String = "Sunset Canyon"

@export_category("Sky & Horizon")
@export var sky_top_color: Color = Color(0.08, 0.12, 0.28, 1.0)
@export var sky_horizon_color: Color = Color(0.95, 0.45, 0.25, 1.0)
@export_range(0.0, 0.5, 0.01) var sky_curve: float = 0.12
@export_range(0.2, 4.0, 0.05) var sky_energy: float = 1.0
@export var ground_bottom_color: Color = Color(0.02, 0.03, 0.06, 1.0)
@export var ground_horizon_color: Color = Color(0.35, 0.18, 0.15, 1.0)
@export_range(0.0, 24.0, 0.5) var sun_angle_max: float = 12.0
@export_range(0.0, 0.5, 0.01) var sun_curve: float = 0.08

@export_category("Fog & Exposure")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0.9, 0.5, 0.3, 1.0)
@export_range(0.0, 0.02, 0.0005) var fog_density: float = 0.004
@export_range(0.0, 1.0, 0.05) var fog_sky_affect: float = 0.35
@export_range(0.5, 2.0, 0.05) var exposure: float = 1.05
@export_range(0.0, 1.5, 0.05) var glow_intensity: float = 0.6
@export_range(0.0, 0.5, 0.01) var glow_bloom: float = 0.15
@export_range(0.0, 2.0, 0.05) var glow_intensity_music_mult: float = 0.6 ## how much music energy lifts glow

@export_category("Lighting")
@export var sun_color: Color = Color(1.0, 0.75, 0.55, 1.0)
@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.15
@export var fill_color: Color = Color(0.4, 0.6, 1.0, 1.0)
@export_range(0.0, 2.0, 0.05) var fill_energy: float = 0.35
@export_range(0.0, 2.0, 0.05) var sun_music_reactivity: float = 0.35 ## multiplier for downbeat flashes
@export_range(0.0, 2.0, 0.05) var fill_music_reactivity: float = 0.25

@export_category("Ground & Lanes")
@export var ground_color: Color = Color(0.05, 0.07, 0.11, 1.0)
@export_range(0.5, 1.5, 0.05) var ground_roughness: float = 0.95
@export var lane_colors: Array[Color] = [Color(0.085, 0.088, 0.115), Color(0.074, 0.096, 0.118), Color(0.09, 0.084, 0.105)]
@export var abyss_color: Color = Color(0.025, 0.03, 0.055, 1.0)

@export_category("Rings & Pillars")
@export var ring_color: Color = Color(1.0, 0.55, 0.15, 1.0)
@export var ring_emission: Color = Color(1.0, 0.5, 0.1, 1.0)
@export_range(0.0, 6.0, 0.1) var ring_emission_energy: float = 2.0
@export var ring_beat_pulse_color: Color = Color(1.0, 0.85, 0.5, 1.0)
@export_range(0.0, 1.0, 0.05) var ring_pulse_strength: float = 0.35
@export var pillar_colors: Array[Color] = [Color(0.10, 0.12, 0.16), Color(0.16, 0.18, 0.22), Color(0.22, 0.24, 0.28)]
@export var beacon_color: Color = Color(1.0, 0.15, 0.1, 1.0)
@export_range(0.0, 10.0, 0.1) var beacon_energy: float = 5.0
@export var roof_emission: Color = Color(1.0, 0.55, 0.25, 1.0)

@export_category("Patterns & Density")
## Which patterns this theme allows. Leave empty = allow all.
@export var allowed_patterns: Array[int] = [] ## StagePattern.Type values, empty = all
@export var pattern_weights: Dictionary = {} ## Type(int) -> weight(float)
@export_range(0.4, 2.0, 0.05) var density_min: float = 0.7
@export_range(0.4, 3.0, 0.05) var density_max: float = 1.6
@export_range(40.0, 120.0, 1.0) var ring_spacing_min: float = 42.0
@export_range(40.0, 120.0, 1.0) var ring_spacing_max: float = 68.0
@export_range(0.0, 40.0, 0.5) var corridor_width: float = 62.0 ## overrides fighter bound_half_width if >0
@export_range(0.0, 1.0, 0.05) var verticality: float = 0.45 ## how much lane elevation amplitude is kept
@export_range(0.0, 1.0, 0.05) var altitude_bias: float = 0.5 ## 0=low, 1=high

@export_category("Reactivity")
@export_range(0.0, 2.0, 0.05) var environment_reactivity: float = 1.0 ## master env pulse
@export_range(0.0, 2.0, 0.05) var vfx_intensity: float = 1.0 ## scales particles/exhaust music boost
@export_range(0.0, 2.0, 0.05) var camera_reactivity: float = 1.0 ## scales camera impulses

@export_category("Section Overrides")
## Optional per-section-type overrides: e.g. { "DROP": StageThemeOverride, ... }
## Kept as Dictionary String -> Resource for Inspector friendliness; created lazily.
@export var section_overrides: Dictionary = {} ## String (section type name) -> StageTheme (partial)

## ------------------------------------------------------------------
## Helpers
## ------------------------------------------------------------------

func allows_pattern(p: int) -> bool:
	if allowed_patterns.is_empty():
		return true
	return allowed_patterns.has(p)

func weight_for_pattern(p: int) -> float:
	if pattern_weights.has(p):
		return float(pattern_weights[p])
	# Defaults tuned per pattern family.
	match p:
		StagePattern.Type.OPEN_FLIGHT: return 1.0
		StagePattern.Type.RING_STREAM: return 1.2
		StagePattern.Type.RING_WAVE: return 1.0
		StagePattern.Type.RING_SLALOM: return 1.3
		StagePattern.Type.VERTICAL_WAVE: return 0.8
		StagePattern.Type.PILLAR_SLALOM: return 1.0
		StagePattern.Type.TIGHT_CORRIDOR: return 0.6
		StagePattern.Type.WIDE_CORRIDOR: return 0.7
		StagePattern.Type.DROP_RUSH: return 0.4 # rare, only hype picks it
		StagePattern.Type.SOLO_FLOW: return 0.7
		StagePattern.Type.CRESCENDO_CLIMB: return 0.8
		StagePattern.Type.BREAKDOWN_OPEN: return 0.8
		StagePattern.Type.CHAOS: return 0.5
		_: return 1.0

func get_effective_theme_for_section(sec: MusicSection) -> StageTheme:
	if sec == null:
		return self
	var key: String = sec.get_type_name()
	if section_overrides.has(key):
		var over: Resource = section_overrides[key] as Resource
		if over is StageTheme:
			return over as StageTheme
	return self

func density_for_intensity(intensity: float) -> float:
	return lerpf(density_min, density_max, clampf(intensity, 0.0, 1.0))

## Build a default sunset theme if no resource is assigned — keeps fallback identical to current visuals.
static func make_fallback() -> StageTheme:
	var t := StageTheme.new()
	t.theme_id = "fallback_sunset"
	t.display_name = "Fallback Sunset"
	# Keep defaults already set above — they mirror scenes/main.tscn sunset.
	return t
