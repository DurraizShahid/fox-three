extends Node
class_name EnvironmentController
## Caches WorldEnvironment, Sky, Sun/Fill and drives them musically.
## No per-frame material creation — cache once, lerp.

@export var world_env_path: NodePath = NodePath("../WorldEnvironment")
@export var sun_path: NodePath = NodePath("../Sun")
@export var fill_path: NodePath = NodePath("../Fill")
@export var stage_theme: StageTheme = null

## Tunables (exposed, not buried).
@export_category("Reactivity")
@export_range(0.0, 2.0, 0.05) var glow_hype_gain: float = 0.4
@export_range(0.0, 2.0, 0.05) var exposure_hype_gain: float = 0.18
@export_range(0.0, 2.0, 0.05) var fog_hype_gain: float = 0.3
@export_range(0.0, 2.0, 0.05) var sky_energy_gain: float = 0.35
@export_range(0.0, 2.0, 0.05) var sun_beat_gain: float = 0.28
@export_range(0.0, 2.0, 0.05) var sun_hype_gain: float = 0.45
@export_range(0.0, 2.0, 0.05) var fill_beat_gain: float = 0.18
@export_range(0.0, 2.0, 0.05) var emission_beat_gain: float = 0.4
@export_range(1.0, 20.0, 0.5) var beat_decay: float = 12.0
@export_range(1.0, 12.0, 0.5) var hype_response: float = 3.5
@export_range(1.0, 12.0, 0.5) var drop_flash_decay: float = 8.0
@export_range(0.0, 1.0, 0.05) var accessibility_mult: float = 1.0

var world_env: WorldEnvironment = null
var env: Environment = null
var sky_mat: ProceduralSkyMaterial = null
var sun_light: DirectionalLight3D = null
var fill_light: DirectionalLight3D = null

# Cached base values so we lerp from known baseline (theme may change).
var _base_glow: float = 0.6
var _base_exposure: float = 1.05
var _base_fog_density: float = 0.004
var _base_sky_energy: float = 1.0
var _base_sun_energy: float = 1.15
var _base_fill_energy: float = 0.35
var _base_sky_top: Color = Color(0.08, 0.12, 0.28)
var _base_sky_horizon: Color = Color(0.95, 0.45, 0.25)
var _base_ground_bottom: Color = Color(0.02, 0.03, 0.06)
var _base_ground_horizon: Color = Color(0.35, 0.18, 0.15)
var _base_fog_color: Color = Color(0.9, 0.5, 0.3)

# Smoothed reactive state.
var _hype_smooth: float = 0.0
var _hype_target: float = 0.0
var _beat_pulse: float = 0.0
var _downbeat_pulse: float = 0.0
var _drop_flash: float = 0.0
var _mid_smoothed: float = 0.0
var _low_smoothed: float = 0.0

func _ready() -> void:
	_resolve()
	_cache_bases()

func _resolve() -> void:
	if world_env_path != NodePath(""):
		world_env = get_node_or_null(world_env_path) as WorldEnvironment
	if world_env == null:
		world_env = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		env = world_env.environment
		if env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	if sun_path != NodePath(""):
		sun_light = get_node_or_null(sun_path) as DirectionalLight3D
	if sun_light == null:
		sun_light = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if fill_path != NodePath(""):
		fill_light = get_node_or_null(fill_path) as DirectionalLight3D
	if fill_light == null:
		fill_light = get_parent().get_node_or_null("Fill") as DirectionalLight3D

func _cache_bases() -> void:
	if env != null:
		_base_glow = env.glow_intensity
		_base_exposure = env.tonemap_exposure
		_base_fog_density = env.fog_density
		_base_sky_energy = sky_mat.sky_energy_multiplier if sky_mat != null else 1.0
		if sky_mat != null:
			_base_sky_top = sky_mat.sky_top_color
			_base_sky_horizon = sky_mat.sky_horizon_color
			_base_ground_bottom = sky_mat.ground_bottom_color
			_base_ground_horizon = sky_mat.ground_horizon_color
		_base_fog_color = env.fog_light_color
	if sun_light != null:
		_base_sun_energy = sun_light.light_energy
	if fill_light != null:
		_base_fill_energy = fill_light.light_energy
	if stage_theme != null:
		_apply_theme(stage_theme, 1.0)

func apply_theme(theme: StageTheme) -> void:
	stage_theme = theme
	_apply_theme(theme, 1.0)
	# Re-cache after theme apply? Keep bases as theme baseline.
	_cache_bases()

func _apply_theme(theme: StageTheme, lerp_t: float) -> void:
	if theme == null or env == null:
		return
	# Called once on theme switch — we tween via lerp_t (0..1) but for now snap.
	if sky_mat != null:
		sky_mat.sky_top_color = theme.sky_top_color
		sky_mat.sky_horizon_color = theme.sky_horizon_color
		sky_mat.sky_curve = theme.sky_curve
		sky_mat.ground_bottom_color = theme.ground_bottom_color
		sky_mat.ground_horizon_color = theme.ground_horizon_color
		sky_mat.sun_angle_max = theme.sun_angle_max
		sky_mat.sun_curve = theme.sun_curve
		sky_mat.sky_energy_multiplier = theme.sky_energy
	env.background_mode = 2
	env.fog_enabled = theme.fog_enabled
	env.fog_light_color = theme.fog_color
	env.fog_density = theme.fog_density
	env.fog_sky_affect = theme.fog_sky_affect
	env.glow_intensity = theme.glow_intensity
	env.glow_bloom = theme.glow_bloom
	env.tonemap_exposure = theme.exposure
	if sun_light != null:
		sun_light.light_color = theme.sun_color
		sun_light.light_energy = theme.sun_energy
	if fill_light != null:
		fill_light.light_color = theme.fill_color
		fill_light.light_energy = theme.fill_energy

## Public API — called by MusicReactiveDirector (no private access).

func set_hype(h: float) -> void:
	_hype_target = clampf(h, 0.0, 1.0)

func set_spectrum(low: float, mid: float, _high: float) -> void:
	_low_smoothed = lerpf(_low_smoothed, low, 0.18)
	_mid_smoothed = lerpf(_mid_smoothed, mid, 0.18)

func trigger_beat(is_downbeat: bool) -> void:
	if is_downbeat:
		_downbeat_pulse = 1.0
		_beat_pulse = maxf(_beat_pulse, 0.7)
	else:
		_beat_pulse = 1.0

func trigger_drop_flash() -> void:
	_drop_flash = 1.0

func get_hype_smooth() -> float:
	return _hype_smooth

func _process(delta: float) -> void:
	# Always process even if not active — decay pulses.
	_beat_pulse = maxf(0.0, _beat_pulse - delta * beat_decay)
	_downbeat_pulse = maxf(0.0, _downbeat_pulse - delta * beat_decay * 0.85)
	_drop_flash = maxf(0.0, _drop_flash - delta * drop_flash_decay)
	_hype_smooth = lerpf(_hype_smooth, _hype_target, 1.0 - exp(-hype_response * delta))

	if env == null:
		return
	var theme: StageTheme = stage_theme
	var env_react: float = 1.0
	if theme != null:
		env_react = theme.environment_reactivity
	env_react *= accessibility_mult

	# Glow: hype lifts, beat pulses add sparkle (mid drives emission).
	var hype: float = _hype_smooth
	var target_glow: float = _base_glow + hype * glow_hype_gain * env_react + _mid_smoothed * 0.15 + _drop_flash * 0.35 + _downbeat_pulse * 0.12
	env.glow_intensity = lerpf(env.glow_intensity, target_glow, 1.0 - exp(-6.0 * delta))

	# Exposure breathing.
	var target_exposure: float = _base_exposure + hype * exposure_hype_gain * env_react + _drop_flash * 0.18
	env.tonemap_exposure = lerpf(env.tonemap_exposure, target_exposure, 1.0 - exp(-4.5 * delta))

	# Fog density/hype: lift slightly at hype.
	if env.fog_enabled:
		var target_fog: float = _base_fog_density + hype * fog_hype_gain * 0.003 * env_react + _drop_flash * 0.002
		env.fog_density = lerpf(env.fog_density, target_fog, 1.0 - exp(-3.0 * delta))

	# Sky energy.
	if sky_mat != null:
		var target_sky_e: float = _base_sky_energy + hype * sky_energy_gain * 0.4 * env_react + _low_smoothed * 0.08 + _drop_flash * 0.5
		sky_mat.sky_energy_multiplier = lerpf(sky_mat.sky_energy_multiplier, target_sky_e, 1.0 - exp(-4.0 * delta))
		# Subtle horizon color lerp toward hype warmer (very subtle).
		if hype > 0.6:
			var warm: Color = Color(1.0, 0.55, 0.3)
			sky_mat.sky_horizon_color = _base_sky_horizon.lerp(warm, hype * 0.12 * env_react + _drop_flash * 0.18)

	# Sun / Fill energy.
	if sun_light != null:
		var sun_add: float = _beat_pulse * sun_beat_gain * 0.25 + _downbeat_pulse * sun_hype_gain * 0.35 + hype * 0.35 * env_react + _drop_flash * 0.9
		sun_add += _low_smoothed * 0.12
		var target_sun: float = _base_sun_energy + sun_add
		sun_light.light_energy = lerpf(sun_light.light_energy, target_sun, 1.0 - exp(-8.0 * delta))
	if fill_light != null:
		var fill_add: float = _beat_pulse * fill_beat_gain * 0.2 + hype * 0.22 * env_react + _drop_flash * 0.45
		fill_add += _mid_smoothed * 0.08
		var target_fill: float = _base_fill_energy + fill_add
		fill_light.light_energy = lerpf(fill_light.light_energy, target_fill, 1.0 - exp(-7.0 * delta))

	# Beacon/ring emission pulsing is handled by StageDirector/HUD via material lerp;
	# we expose beat pulse for them to query via get_beat_pulse()
	# No extra work here to avoid per-frame material allocation.

func get_beat_pulse() -> float:
	return _beat_pulse

func get_downbeat_pulse() -> float:
	return _downbeat_pulse

func get_drop_flash() -> float:
	return _drop_flash
