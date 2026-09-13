extends Node
class_name EnvironmentController
## Caches WorldEnvironment, Sky, Sun/Fill and drives them musically.
## Now a full visualizer: sky, fog, lights AND buildings/objects in the world
## pulse with the beat/hype/spectrum. No per-frame material creation — cache once, lerp.
## Main registers world materials via register_world_materials() after _make_materials.

@export var world_env_path: NodePath = NodePath("../WorldEnvironment")
@export var sun_path: NodePath = NodePath("../Sun")
@export var fill_path: NodePath = NodePath("../Fill")
@export var stage_theme: StageTheme = null

## Tunables (exposed, not buried). Rebalanced to avoid whiteout — subtle at low hype, readable.
@export_category("Reactivity — Sky & Fog")
@export_range(0.0, 3.0, 0.05) var glow_hype_gain: float = 0.32
@export_range(0.0, 3.0, 0.05) var exposure_hype_gain: float = 0.14
@export_range(0.0, 3.0, 0.05) var fog_hype_gain: float = 0.22
@export_range(0.0, 3.0, 0.05) var sky_energy_gain: float = 0.38
@export_range(0.0, 3.0, 0.05) var sun_beat_gain: float = 0.32
@export_range(0.0, 3.0, 0.05) var sun_hype_gain: float = 0.38
@export_range(0.0, 3.0, 0.05) var fill_beat_gain: float = 0.28
@export_range(1.0, 20.0, 0.5) var beat_decay: float = 10.0
@export_range(1.0, 12.0, 0.5) var hype_response: float = 3.2
@export_range(1.0, 12.0, 0.5) var drop_flash_decay: float = 6.5
@export_range(0.0, 1.0, 0.05) var accessibility_mult: float = 1.0

@export_category("Visualizer — World Objects")
@export var visualizer_enabled: bool = true
@export_range(0.0, 3.0, 0.05) var building_hype_gain: float = 0.42
@export_range(0.0, 3.0, 0.05) var building_beat_gain: float = 0.34
@export_range(0.0, 3.0, 0.05) var building_low_gain: float = 0.28 ## bass → pillars/ground
@export_range(0.0, 3.0, 0.05) var ring_hype_gain: float = 0.52
@export_range(0.0, 3.0, 0.05) var ring_beat_gain: float = 0.48
@export_range(0.0, 3.0, 0.05) var beacon_hype_gain: float = 0.62
@export_range(0.0, 3.0, 0.05) var beacon_beat_gain: float = 0.58
@export_range(0.0, 3.0, 0.05) var lane_hype_gain: float = 0.26
@export_range(0.0, 2.0, 0.05) var ground_hype_gain: float = 0.28
@export_range(0.0, 2.0, 0.05) var sky_hue_shift_gain: float = 0.32 ## 0=none, 1=full palette pulse
@export_range(0.0, 0.4, 0.01) var building_scale_gain: float = 0.05 ## visualizer: buildings stretch on bass/beat
@export_range(0.0, 1.0, 0.01) var building_scale_low_gain: float = 0.025

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
var _high_smoothed: float = 0.0

# World material caches — injected by Main.
var _pillar_mats: Array[StandardMaterial3D] = []
var _pillar_base_colors: Array[Color] = []
var _pillar_base_emission: Array[Color] = []
var _post_mat_a: StandardMaterial3D = null
var _post_mat_b: StandardMaterial3D = null
var _post_a_base_energy: float = 2.5
var _post_b_base_energy: float = 2.5
var _post_a_base_color: Color = Color(0.1, 0.8, 1.0)
var _post_b_base_color: Color = Color(1.0, 0.45, 0.1)
var _ring_mat: StandardMaterial3D = null
var _ring_base_energy: float = 2.0
var _ring_base_color: Color = Color(1.0, 0.55, 0.15)
var _beacon_mat: StandardMaterial3D = null
var _beacon_base_energy: float = 5.0
var _beacon_base_color: Color = Color(1.0, 0.15, 0.1)
var _roof_mat: StandardMaterial3D = null
var _roof_base_energy: float = 2.0
var _lane_mats: Array[StandardMaterial3D] = []
var _lane_base_colors: Array[Color] = []
var _ground_mat: StandardMaterial3D = null
var _ground_base_color: Color = Color(0.05, 0.07, 0.11)
var _abyss_mat: StandardMaterial3D = null
var _abyss_base_color: Color = Color(0.025, 0.03, 0.055)
var _strip_mat: StandardMaterial3D = null
var _strip_base_energy: float = 1.2
var _strip_base_color: Color = Color(0.2, 0.9, 1.0)
var _pillar_nodes: Array[MeshInstance3D] = []
var _pillar_base_scales: Array[Vector3] = []

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
	_cache_bases()
	# Also recache world material bases from theme if already registered
	if not _pillar_mats.is_empty() or _post_mat_a != null:
		_recache_world_bases_from_theme()

func _apply_theme(theme: StageTheme, lerp_t: float) -> void:
	if theme == null or env == null:
		return
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

## Inject world materials once after Main builds them. No per-frame allocation.
func register_world_materials(
	pillar_mats: Array[StandardMaterial3D],
	post_a: StandardMaterial3D,
	post_b: StandardMaterial3D,
	ring: StandardMaterial3D,
	beacon: StandardMaterial3D,
	roof: StandardMaterial3D,
	lane_mats: Array[StandardMaterial3D],
	ground: StandardMaterial3D,
	abyss: StandardMaterial3D,
	strip: StandardMaterial3D = null
) -> void:
	_pillar_mats = pillar_mats.duplicate()
	_pillar_base_colors.resize(_pillar_mats.size())
	_pillar_base_emission.resize(_pillar_mats.size())
	for i in _pillar_mats.size():
		var m: StandardMaterial3D = _pillar_mats[i]
		if m != null:
			_pillar_base_colors[i] = m.albedo_color
			# Ensure emission is usable as visualizer
			if not m.emission_enabled:
				m.emission_enabled = true
				m.emission = m.albedo_color * 0.35
				m.emission_energy_multiplier = 0.0
			_pillar_base_emission[i] = m.emission
	_post_mat_a = post_a
	_post_mat_b = post_b
	if _post_mat_a != null:
		_post_a_base_energy = _post_mat_a.emission_energy_multiplier
		_post_a_base_color = _post_mat_a.emission
	if _post_mat_b != null:
		_post_b_base_energy = _post_mat_b.emission_energy_multiplier
		_post_b_base_color = _post_mat_b.emission
	_ring_mat = ring
	if _ring_mat != null:
		_ring_base_energy = _ring_mat.emission_energy_multiplier
		_ring_base_color = _ring_mat.emission
	_beacon_mat = beacon
	if _beacon_mat != null:
		_beacon_base_energy = _beacon_mat.emission_energy_multiplier
		_beacon_base_color = _beacon_mat.emission
	_roof_mat = roof
	if _roof_mat != null:
		_roof_base_energy = _roof_mat.emission_energy_multiplier
	_lane_mats = lane_mats.duplicate()
	_lane_base_colors.resize(_lane_mats.size())
	for i in _lane_mats.size():
		if _lane_mats[i] != null:
			_lane_base_colors[i] = _lane_mats[i].albedo_color
	_ground_mat = ground
	if _ground_mat != null:
		_ground_base_color = _ground_mat.albedo_color
	_abyss_mat = abyss
	if _abyss_mat != null:
		_abyss_base_color = _abyss_mat.albedo_color
	_strip_mat = strip
	if _strip_mat != null:
		_strip_base_energy = _strip_mat.emission_energy_multiplier
		_strip_base_color = _strip_mat.emission if _strip_mat.emission != Color(0,0,0,0) else _strip_mat.albedo_color
	_recache_world_bases_from_theme()
	# Cache pillar node base scales if already registered
	if not _pillar_nodes.is_empty() and _pillar_base_scales.size() != _pillar_nodes.size():
		_pillar_base_scales.resize(_pillar_nodes.size())
		for i in _pillar_nodes.size():
			if _pillar_nodes[i] != null:
				_pillar_base_scales[i] = _pillar_nodes[i].scale

func register_pillar_nodes(nodes: Array[MeshInstance3D]) -> void:
	_pillar_nodes = nodes.duplicate()
	_pillar_base_scales.resize(_pillar_nodes.size())
	for i in _pillar_nodes.size():
		var n: MeshInstance3D = _pillar_nodes[i]
		if n != null:
			_pillar_base_scales[i] = n.scale

func _recache_world_bases_from_theme() -> void:
	if stage_theme == null:
		return
	# Align bases with theme palette where applicable
	if stage_theme.pillar_colors.size() == _pillar_mats.size():
		for i in _pillar_mats.size():
			_pillar_base_colors[i] = stage_theme.pillar_colors[i]
			if _pillar_mats[i] != null:
				_pillar_mats[i].albedo_color = _pillar_base_colors[i]
				_pillar_mats[i].emission = _pillar_base_colors[i] * 0.35
	if _post_mat_a != null:
		# post colors are theme proxies; keep emission hue but match lerp
		pass
	if _ring_mat != null and stage_theme.ring_emission != Color(0,0,0,0):
		_ring_base_color = stage_theme.ring_emission
		_ring_mat.emission = _ring_base_color
		_ring_base_energy = stage_theme.ring_emission_energy
		_ring_mat.emission_energy_multiplier = _ring_base_energy
	if _beacon_mat != null:
		_beacon_base_color = stage_theme.beacon_color
		_beacon_base_color.a = 1.0
		_beacon_mat.emission = _beacon_base_color
		_beacon_base_energy = stage_theme.beacon_energy
		_beacon_mat.emission_energy_multiplier = _beacon_base_energy
	if _ground_mat != null:
		_ground_base_color = stage_theme.ground_color
		_ground_mat.albedo_color = _ground_base_color
	if _abyss_mat != null:
		_abyss_base_color = stage_theme.abyss_color
		_abyss_mat.albedo_color = _abyss_base_color
	for i in _lane_mats.size():
		if i < stage_theme.lane_colors.size() and _lane_mats[i] != null:
			_lane_base_colors[i] = stage_theme.lane_colors[i]
			_lane_mats[i].albedo_color = _lane_base_colors[i]

## Public API — called by MusicReactiveDirector (no private access).

func set_hype(h: float) -> void:
	_hype_target = clampf(h, 0.0, 1.0)

func set_spectrum(low: float, mid: float, high: float) -> void:
	_low_smoothed = lerpf(_low_smoothed, low, 0.20)
	_mid_smoothed = lerpf(_mid_smoothed, mid, 0.20)
	_high_smoothed = lerpf(_high_smoothed, high, 0.22)

func trigger_beat(is_downbeat: bool) -> void:
	if is_downbeat:
		_downbeat_pulse = 1.0
		_beat_pulse = maxf(_beat_pulse, 0.75)
	else:
		_beat_pulse = 1.0

func trigger_drop_flash() -> void:
	_drop_flash = 1.0

func get_hype_smooth() -> float:
	return _hype_smooth

func _process(delta: float) -> void:
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
	var vis: float = 1.0
	if visualizer_enabled:
		vis = accessibility_mult

	var hype: float = _hype_smooth
	var beat: float = _beat_pulse
	var down: float = _downbeat_pulse
	var drop: float = _drop_flash
	var low: float = _low_smoothed
	var mid: float = _mid_smoothed
	var high: float = _high_smoothed

	# ------------------------------------------------------------------
	# Environment — rebalanced: readable at low hype, strong but not white at drops
	# ------------------------------------------------------------------
	var target_glow: float = _base_glow + hype * glow_hype_gain * env_react + mid * 0.18 * vis + drop * 0.35 + down * 0.14
	target_glow = clampf(target_glow, 0.55, 1.15)
	env.glow_intensity = lerpf(env.glow_intensity, target_glow, 1.0 - exp(-6.0 * delta))
	env.glow_bloom = lerpf(env.glow_bloom, clampf(_base_glow * 0.25 + hype * 0.055 * vis + drop * 0.035, 0.05, 0.22), 1.0 - exp(-5.0 * delta))

	var target_exposure: float = _base_exposure + hype * exposure_hype_gain * env_react + drop * 0.18 + beat * 0.03
	target_exposure = clampf(target_exposure, 0.98, 1.28)
	env.tonemap_exposure = lerpf(env.tonemap_exposure, target_exposure, 1.0 - exp(-4.5 * delta))

	if env.fog_enabled:
		var target_fog: float = _base_fog_density + hype * fog_hype_gain * 0.0022 * env_react + low * 0.0012 * vis + drop * 0.0018 + beat * 0.0004
		target_fog = clampf(target_fog, 0.001, 0.012)
		env.fog_density = lerpf(env.fog_density, target_fog, 1.0 - exp(-3.0 * delta))
		var fog_target: Color = _base_fog_color.lerp(Color(1.0, 0.5, 0.30), hype * 0.22 * vis + drop * 0.22)
		fog_target = fog_target.lerp(Color(0.45, 0.60, 1.0), high * 0.07 * vis)
		env.fog_light_color = env.fog_light_color.lerp(fog_target, 1.0 - exp(-3.5 * delta))

	if sky_mat != null:
		var target_sky_e: float = _base_sky_energy + hype * sky_energy_gain * 0.45 * env_react + low * 0.14 * vis + high * 0.07 * vis + drop * 0.42 + beat * 0.07 + down * 0.13
		target_sky_e = clampf(target_sky_e, 0.88, 1.55)
		sky_mat.sky_energy_multiplier = lerpf(sky_mat.sky_energy_multiplier, target_sky_e, 1.0 - exp(-4.0 * delta))
		var horizon_shift: float = hype * sky_hue_shift_gain * vis * 0.55 + drop * 0.32
		var top_shift: float = beat * 0.06 * vis + high * 0.08 * vis + drop * 0.14
		var warm: Color = Color(1.0, 0.42, 0.18).lerp(Color(1.0, 0.22, 0.55), hype * 0.32)
		var cool: Color = Color(0.28, 0.45, 1.0)
		sky_mat.sky_horizon_color = _base_sky_horizon.lerp(warm, clampf(horizon_shift, 0.0, 0.55))
		sky_mat.sky_top_color = _base_sky_top.lerp(cool, clampf(top_shift * 0.35, 0.0, 0.32))
		sky_mat.ground_bottom_color = _base_ground_bottom.lerp(Color(0.18, 0.12, 0.22), hype * 0.18 * vis + low * 0.07)
		sky_mat.ground_horizon_color = _base_ground_horizon.lerp(Color(0.65, 0.25, 0.18), hype * 0.24 * vis + mid * 0.08)

	if sun_light != null:
		var sun_add: float = beat * sun_beat_gain * 0.42 + down * sun_hype_gain * 0.62 + hype * 0.42 * env_react + drop * 0.75 + low * 0.22
		var target_sun: float = clampf(_base_sun_energy + sun_add, 0.55, 2.2)
		sun_light.light_energy = lerpf(sun_light.light_energy, target_sun, 1.0 - exp(-7.5 * delta))
		var sun_warm: Color = Color(1.0, 0.72, 0.45).lerp(Color(1.0, 0.58, 0.28), hype * 0.38 + low * 0.14)
		sun_warm = sun_warm.lerp(Color(0.80, 0.86, 1.0), high * 0.09)
		sun_light.light_color = sun_light.light_color.lerp(sun_warm, 1.0 - exp(-4.5 * delta))

	if fill_light != null:
		var fill_add: float = beat * fill_beat_gain * 0.38 + hype * 0.34 * env_react + drop * 0.52 + mid * 0.20 + high * 0.09
		var target_fill: float = clampf(_base_fill_energy + fill_add, 0.18, 1.35)
		fill_light.light_energy = lerpf(fill_light.light_energy, target_fill, 1.0 - exp(-6.5 * delta))
		var fill_cool: Color = Color(0.45, 0.65, 1.0).lerp(Color(0.88, 0.48, 0.92), hype * 0.18 + mid * 0.12)
		fill_light.light_color = fill_light.light_color.lerp(fill_cool, 1.0 - exp(-5.0 * delta))

	# ------------------------------------------------------------------
	# World objects — rebalanced so quiet sections still read dark
	# ------------------------------------------------------------------
	if not visualizer_enabled:
		return

	if _post_mat_a != null:
		var a_e: float = _post_a_base_energy + hype * building_hype_gain * 0.62 + beat * building_beat_gain * 0.9 + down * 0.45 + low * building_low_gain * 0.52 + drop * 1.15
		a_e = clampf(a_e, 1.8, 5.2)
		_post_mat_a.emission_energy_multiplier = lerpf(_post_mat_a.emission_energy_multiplier, a_e, 1.0 - exp(-14.0 * delta))
	if _post_mat_b != null:
		var b_e: float = _post_b_base_energy + hype * building_hype_gain * 0.62 + beat * building_beat_gain * 0.9 + down * 0.45 + low * building_low_gain * 0.52 + drop * 1.15
		b_e = clampf(b_e, 1.8, 5.2)
		_post_mat_b.emission_energy_multiplier = lerpf(_post_mat_b.emission_energy_multiplier, b_e, 1.0 - exp(-14.0 * delta))

	if _ring_mat != null:
		var r_e: float = _ring_base_energy + hype * ring_hype_gain * 0.78 + beat * ring_beat_gain * 1.0 + down * 0.62 + high * 0.52 + drop * 1.45
		r_e = clampf(r_e, 1.6, 4.6)
		_ring_mat.emission_energy_multiplier = lerpf(_ring_mat.emission_energy_multiplier, r_e, 1.0 - exp(-12.0 * delta))
		var r_col: Color = _ring_base_color.lerp(Color(1.0, 0.92, 0.55), (beat * 0.22 + high * 0.18 + drop * 0.28) * vis)
		_ring_mat.emission = _ring_mat.emission.lerp(r_col, 1.0 - exp(-10.0 * delta))

	if _beacon_mat != null:
		var bec_e: float = _beacon_base_energy + hype * beacon_hype_gain * 0.72 + beat * beacon_beat_gain * 1.05 + down * 0.85 + low * 0.32 + drop * 2.0
		bec_e = clampf(bec_e, 3.5, 9.5)
		_beacon_mat.emission_energy_multiplier = lerpf(_beacon_mat.emission_energy_multiplier, bec_e, 1.0 - exp(-13.0 * delta))
		var bec_col: Color = _beacon_base_color.lerp(Color(1.0, 0.85, 0.3), beat * 0.18 + drop * 0.26)
		_beacon_mat.emission = _beacon_mat.emission.lerp(bec_col, 1.0 - exp(-10.0 * delta))

	if _roof_mat != null:
		var roof_e: float = _roof_base_energy + hype * 0.35 * vis + mid * 0.42 * vis + beat * 0.26 + drop * 0.72
		roof_e = clampf(roof_e, 1.4, 3.6)
		_roof_mat.emission_energy_multiplier = lerpf(_roof_mat.emission_energy_multiplier, roof_e, 1.0 - exp(-9.0 * delta))

	# Center dash strips - road path flashes hard with beat/downbeat
	if _strip_mat != null:
		var s_e: float = _strip_base_energy + hype * 0.42 * vis + beat * 1.05 + down * 0.78 + mid * 0.32 + drop * 1.2
		s_e = clampf(s_e, 0.9, 3.8)
		_strip_mat.emission_energy_multiplier = lerpf(_strip_mat.emission_energy_multiplier, s_e, 1.0 - exp(-13.5 * delta))
		var s_col: Color = _strip_base_color.lerp(Color(0.55, 1.0, 1.0), beat * 0.28 + drop * 0.32)
		s_col = s_col.lerp(Color(1.0, 0.95, 0.45), hype * 0.18 + down * 0.22)
		_strip_mat.emission = _strip_mat.emission.lerp(s_col, 1.0 - exp(-11.0 * delta))
		_strip_mat.albedo_color = _strip_mat.albedo_color.lerp(s_col, 1.0 - exp(-10.0 * delta))

	for i in _pillar_mats.size():
		var m: StandardMaterial3D = _pillar_mats[i]
		if m == null:
			continue
		var base: Color = _pillar_base_colors[i]
		var phase_off: float = float(i) * 0.33
		var beat_phased: float = beat * (0.55 + sin(phase_off * TAU) * 0.18)
		var target_e: float = hype * building_hype_gain * 0.32 + beat_phased * building_beat_gain * 0.42 + down * 0.22 + low * building_low_gain * 0.30 + drop * 0.62
		target_e = clampf(target_e, 0.0, 1.35)
		m.emission_energy_multiplier = lerpf(m.emission_energy_multiplier, target_e, 1.0 - exp(-8.0 * delta))
		var bright: Color = base.lerp(Color(0.48, 0.50, 0.58), hype * 0.18 * vis + beat * 0.07 * vis)
		bright = bright.lerp(Color(0.78, 0.55, 0.42), low * 0.06 * vis + drop * 0.10)
		m.albedo_color = m.albedo_color.lerp(bright, 1.0 - exp(-7.0 * delta))

	# Buildings scale visualizer — bass makes city breathe, beat gives snap
	if not _pillar_nodes.is_empty():
		var scale_beat: float = beat * building_scale_gain + down * building_scale_gain * 1.35 + drop * 0.12
		var scale_low: float = low * building_scale_low_gain + hype * 0.02
		for i in _pillar_nodes.size():
			var node: MeshInstance3D = _pillar_nodes[i]
			if node == null:
				continue
			var base_scale: Vector3 = _pillar_base_scales[i] if i < _pillar_base_scales.size() else Vector3.ONE
			# Per-pillar phase so stretch ripples across skyline rather than uniform pop
			var ph: float = float(i % 7) * 0.18
			var beat_local: float = scale_beat * (0.85 + sin(ph * TAU + hype * 3.0) * 0.22)
			var target_y: float = 1.0 + beat_local + scale_low * 0.9 + hype * 0.04
			target_y = clampf(target_y, 0.92, 1.22)
			var cur: Vector3 = node.scale
			var nxt: Vector3 = Vector3(
				lerpf(cur.x, base_scale.x * (0.98 + (target_y - 1.0) * 0.25), 1.0 - exp(-9.0 * delta)),
				lerpf(cur.y, base_scale.y * target_y, 1.0 - exp(-11.0 * delta)),
				lerpf(cur.z, base_scale.z * (0.98 + (target_y - 1.0) * 0.25), 1.0 - exp(-9.0 * delta))
			)
			node.scale = nxt

	# Lanes — hype + beat shimmer
	for i in _lane_mats.size():
		var lm: StandardMaterial3D = _lane_mats[i]
		if lm == null:
			continue
		var lb: Color = _lane_base_colors[i]
		var lane_bright: Color = lb.lerp(Color(0.22, 0.35, 0.55), hype * lane_hype_gain * 0.22 + beat * 0.15 + mid * 0.14 + drop * 0.35)
		lm.albedo_color = lm.albedo_color.lerp(lane_bright, 1.0 - exp(-6.5 * delta))
		lm.roughness = lerpf(lm.roughness, 0.92 - hype * 0.12 - beat * 0.06, 1.0 - exp(-6.0 * delta))

	if _ground_mat != null:
		var gb: Color = _ground_base_color
		var g_tgt: Color = gb.lerp(Color(0.16, 0.18, 0.28), hype * ground_hype_gain * 0.45 + low * 0.22 + drop * 0.35 + mid * 0.12)
		_ground_mat.albedo_color = _ground_mat.albedo_color.lerp(g_tgt, 1.0 - exp(-5.5 * delta))

	if _abyss_mat != null:
		var ab: Color = _abyss_base_color
		var ab_tgt: Color = ab.lerp(Color(0.10, 0.14, 0.28), hype * 0.5 * vis + low * 0.18 + drop * 0.4)
		_abyss_mat.albedo_color = _abyss_mat.albedo_color.lerp(ab_tgt, 1.0 - exp(-5.0 * delta))

func get_beat_pulse() -> float:
	return _beat_pulse

func get_downbeat_pulse() -> float:
	return _downbeat_pulse

func get_drop_flash() -> float:
	return _drop_flash
