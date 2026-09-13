extends Node3D
## Endless runner test track: recycles ground tiles, edge posts,
## fly-through rings and side pillars so forward flight never ends.
## Also drives the debug HUD and test keys (R = reset).

signal stunt_performed(kind: String, intensity: float, combo: int)

@export var tile_count: int = 6
@export var tile_length: float = 120.0
@export var tile_width: float = 320.0
@export var ring_count: int = 14
@export var ring_spacing: float = 55.0
@export var pillar_count: int = 60
@export var combo_window: float = 3.5

@export_category("Lane Elevation")
@export var lane_elevation_enabled: bool = true
@export_range(0.0, 20.0, 0.5) var lane_elevation_amplitude: float = 9.0
@export_range(0.0, 10.0, 0.5) var lane_elevation_second_amplitude: float = 3.5
@export_range(20.0, 400.0, 5.0) var lane_elevation_wavelength: float = 145.0
@export_range(20.0, 150.0, 5.0) var lane_elevation_short_wavelength: float = 46.0
@export_range(0.0, 10.0, 0.5) var lane_elevation_base_spread: float = 5.0
@export_range(1, 10, 1) var lane_segment_count: int = 6
@export_range(10.0, 40.0, 0.5) var lane_width: float = 28.0
@export_range(0.2, 4.0, 0.1) var lane_thickness: float = 1.4
@export var abyss_y: float = -9.0

@export_category("Music / Stage")
@export var song_profile: SongProfile = null ## assign a SongProfile to enable music-driven mode; null = fallback endless
@export var stage_theme: StageTheme = null ## optional override; if null uses SongProfile's theme or fallback sunset
@export var auto_play_music: bool = true
@export var debug_overlay_enabled: bool = false ## show F3 overlay at start

@onready var fighter: FighterJet = $Fighter
@onready var chase_cam: ChaseCamera = $ChaseCamera
@onready var speed_label: Label = $HUD/TopLeft/SpeedLabel
@onready var state_label: Label = $HUD/TopLeft/StateLabel
@onready var info_label: Label = $HUD/TopLeft/InfoLabel
@onready var help_label: Label = $HUD/Bottom
@onready var combo_label: Label = $HUD/TopLeft/ComboLabel
@onready var stunt_label: Label = $HUD/StuntLabel
@onready var lane_label: Label = $HUD/LaneLabel

## Music-driven systems (created in _ready if missing — keeps old scenes working).
var music_director: MusicDirector = null
var stage_director: StageDirector = null
var env_controller: EnvironmentController = null
var reactive_director: MusicReactiveDirector = null
var debug_overlay: MusicDebugOverlay = null

var _tiles: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_passed: Array[bool] = []
var _ring_flash: Array[float] = []
var _pillars: Array[MeshInstance3D] = []
var _pillar_passed: Array[bool] = []
var _rng := RandomNumberGenerator.new()
var _combo: int = 0
var _combo_t: float = 0.0
var _stunt_t: float = 0.0
var _was_rolling: bool = false
var _hitstop_busy: bool = false
var _lane_name: String = "CENTER"
var _lane_flash: float = 0.0

var _ground_mat: StandardMaterial3D
var _post_mat_a: StandardMaterial3D
var _post_mat_b: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _ring_hit_mat: StandardMaterial3D
var _ring_graze_mat: StandardMaterial3D
var _pillar_mats: Array[StandardMaterial3D] = []
var _roof_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _unit_box: BoxMesh
var _beacon_mesh: SphereMesh

# --- lane elevation ---
var _lane_params: Array[Dictionary] = []
var _lane_mats: Array[StandardMaterial3D] = []
var _abyss_mat: StandardMaterial3D
var _abyss_mesh: PlaneMesh


func _ready() -> void:
	_rng.seed = 1337
	_setup_lane_elevations()
	_make_materials()
	fighter.global_position = Vector3(0, 12, 0)
	_build_ground()
	_build_rings()
	_build_pillars()
	if chase_cam.target == null:
		chase_cam.target = fighter
	fighter.lane_switched.connect(_on_lane_switched)
	_ensure_music_systems()
	# Wire visualizer: give EnvironmentController live references to world materials + geometry
	if env_controller != null:
		env_controller.register_world_materials(
			_pillar_mats, _post_mat_a, _post_mat_b, _ring_mat, _beacon_mat, _roof_mat,
			_lane_mats, _ground_mat, _abyss_mat
		)
		env_controller.register_pillar_nodes(_pillars)
	_apply_song_profile()


func _ensure_music_systems() -> void:
	# Find or create MusicDirector
	music_director = get_node_or_null("MusicDirector") as MusicDirector
	if music_director == null:
		music_director = MusicDirector.new()
		music_director.name = "MusicDirector"
		music_director.music_bus = "Music"
		add_child(music_director)
	# Environment controller (drives WorldEnvironment / Sky / Sun / Fill)
	env_controller = get_node_or_null("EnvironmentController") as EnvironmentController
	if env_controller == null:
		env_controller = EnvironmentController.new()
		env_controller.name = "EnvironmentController"
		env_controller.world_env_path = NodePath("WorldEnvironment")
		env_controller.sun_path = NodePath("Sun")
		env_controller.fill_path = NodePath("Fill")
		add_child(env_controller)
	# StageDirector (music-chunk generation)
	stage_director = get_node_or_null("StageDirector") as StageDirector
	if stage_director == null:
		stage_director = StageDirector.new()
		stage_director.name = "StageDirector"
		stage_director.fighter_path = NodePath("Fighter")
		stage_director.music_director_path = NodePath("MusicDirector")
		add_child(stage_director)
	# Reactive director (fighter/camera/env mapping)
	reactive_director = get_node_or_null("MusicReactiveDirector") as MusicReactiveDirector
	if reactive_director == null:
		reactive_director = MusicReactiveDirector.new()
		reactive_director.name = "MusicReactiveDirector"
		reactive_director.fighter_path = NodePath("Fighter")
		reactive_director.camera_path = NodePath("ChaseCamera")
		reactive_director.music_director_path = NodePath("MusicDirector")
		reactive_director.environment_controller_path = NodePath("EnvironmentController")
		reactive_director.stage_director_path = NodePath("StageDirector")
		add_child(reactive_director)
	# Debug overlay (F3)
	debug_overlay = get_node_or_null("MusicDebugOverlay") as MusicDebugOverlay
	if debug_overlay == null:
		debug_overlay = MusicDebugOverlay.new()
		debug_overlay.name = "MusicDebugOverlay"
		debug_overlay.music_director_path = NodePath("../MusicDirector")
		debug_overlay.stage_director_path = NodePath("../StageDirector")
		debug_overlay.fighter_path = NodePath("../Fighter")
		debug_overlay.enabled = debug_overlay_enabled
		add_child(debug_overlay)
	# Theme wiring
	if stage_theme != null:
		stage_director.stage_theme = stage_theme
		env_controller.stage_theme = stage_theme
		env_controller.apply_theme(stage_theme)


func _apply_song_profile() -> void:
	var prof: SongProfile = song_profile
	# If inspector profile null, try to load demo if exists (so F5 shows hype even without manual assignment,
	# but fallback still works if demo missing).
	if prof == null and ResourceLoader.exists("res://resources/music/demo_song.tres"):
		var demo: Resource = load("res://resources/music/demo_song.tres")
		if demo is SongProfile:
			# Only auto-use demo if it has sections (so a truly empty project falls back cleanly,
			# but our demo provides clock without audio).
			# For fallback visibility we keep demo active — comment next line to disable auto.
			# To keep fallback as default, do NOT auto-assign: fallback mode is when no profile is set.
			# So we leave prof null intentionally. Uncomment to auto-enable demo:
			# prof = demo as SongProfile
			pass
	if music_director != null:
		if prof != null:
			music_director.set_song(prof, auto_play_music)
			if stage_director != null:
				stage_director.set_song(prof, stage_theme)
			if prof.stage_theme != null and stage_theme == null:
				var th: StageTheme = prof.stage_theme as StageTheme
				if th != null and env_controller != null:
					env_controller.apply_theme(th)
					if stage_director != null:
						stage_director.stage_theme = th
		else:
			music_director.set_song(null, false)
			if stage_director != null:
				stage_director.set_song(null)


func set_song_profile(profile: SongProfile, play_immediately: bool = true) -> void:
	song_profile = profile
	if music_director != null:
		music_director.set_song(profile, play_immediately)
	if stage_director != null:
		stage_director.set_song(profile, stage_theme)
	if profile != null and profile.stage_theme != null and env_controller != null and stage_theme == null:
		var th: StageTheme = profile.stage_theme as StageTheme
		env_controller.apply_theme(th)


func _process(delta: float) -> void:
	if fighter == null:
		return
	# Combo + stunt timers; heat feeds the music state on the fighter.
	_combo_t -= delta
	if _combo_t <= 0.0:
		_combo = 0
	_stunt_t = maxf(0.0, _stunt_t - delta)
	_lane_flash = maxf(0.0, _lane_flash - delta * 0.8)
	if _lane_flash <= 0.0 and lane_label.text.begins_with("LANE"):
		lane_label.text = "· %s ·" % _lane_name
	fighter.style_heat = clampf(float(_combo) * 0.12, 0.0, 1.0)
	# Rolls extend a live chain but never start one (threads build, rolls keep).
	if fighter.is_rolling and not _was_rolling and _combo > 0:
		_add_stunt("BARREL CHAIN", 0.4, 1, 0.0)
	_was_rolling = fighter.is_rolling
	_recycle_ground()
	_recycle_rings(delta)
	_recycle_pillars()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_flight"):
		_reset_flight()
		return
	# Debug: music transport (handled by debug overlay F3 + [ ] but also allow bare here)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				if debug_overlay != null:
					debug_overlay.toggle()
			KEY_R:
				pass # already handled via action; keep for keycode path
			KEY_BRACERIGHT, KEY_BRACKETRIGHT:
				if music_director != null and music_director.song_profile != null:
					var cur: int = music_director.current_section_index
					var nxt: int = cur + 1
					var sorted: Array[MusicSection] = music_director.song_profile.get_sorted_sections()
					if nxt < sorted.size():
						music_director.seek_to_section(nxt)
			KEY_BRACELEFT, KEY_BRACKETLEFT:
				if music_director != null and music_director.song_profile != null:
					var cur2: int = music_director.current_section_index
					var prv: int = cur2 - 1
					if prv >= 0:
						music_director.seek_to_section(prv)


func _reset_flight() -> void:
	fighter.global_position = Vector3(0, 12, 0)
	fighter.velocity = Vector3(0, 0, -fighter.cruise_speed)
	fighter.forward_speed = fighter.cruise_speed
	fighter.shake_trauma = 0.0
	# Resync music clock and stage so reset doesn't desync audio.
	if music_director != null:
		music_director.resync()
		# Also restart song if a profile is active and we want deterministic restart.
		if music_director.song_profile != null and auto_play_music:
			music_director.restart_song()
	if stage_director != null and music_director != null:
		stage_director._rebuild_rng()
	_combo = 0
	_combo_t = 0.0


func _add_stunt(kind: String, intensity: float, combo_add: int, kick: float) -> void:
	_combo = mini(_combo + combo_add, 99)
	_combo_t = combo_window
	if kick > 0.0 and fighter != null:
		fighter.add_speed_kick(kick)
	# Rumble scales with intensity: grazes buzz, perfect threads thump.
	if fighter != null:
		var w: float = clampf(intensity * 0.35, 0.15, 0.6)
		var s: float = clampf(intensity * 0.65, 0.25, 0.9)
		fighter._rumble(w, s, 0.16 if intensity >= 1.0 else 0.11)
	_show_stunt(kind)
	stunt_performed.emit(kind, intensity, _combo)


func _show_stunt(text: String) -> void:
	if stunt_label == null:
		return
	if _combo >= 2:
		stunt_label.text = "%s  x%d" % [text, _combo]
	else:
		stunt_label.text = text
	_stunt_t = 1.4


func _on_lane_switched(new_lane: int) -> void:
	_lane_name = "LEFT" if new_lane < 0 else ("RIGHT" if new_lane > 0 else "CENTER")
	lane_label.text = "LANE SWITCHED · %s" % _lane_name
	_lane_flash = 1.0


func _hitstop(scale: float, dur: float) -> void:
	if _hitstop_busy:
		return
	_hitstop_busy = true
	Engine.time_scale = scale
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_busy = false


# ------------------------------------------------------------------
# Lane elevation — 3 independent undulating profiles
# ------------------------------------------------------------------
func _setup_lane_elevations() -> void:
	# Use a separate RNG stream so the main track seed (1337) stays stable
	# for rings/pillars — lane elevations are deterministic but don't shift
	# the legacy RNG sequence.
	var erng := RandomNumberGenerator.new()
	erng.seed = 1337 ^ 0x9E3779B9
	_lane_params.clear()
	for i in 3:
		var lane_idx: int = i - 1
		var offset: float = erng.randf_range(-lane_elevation_base_spread, lane_elevation_base_spread)
		var amp1: float = erng.randf_range(lane_elevation_amplitude * 0.55, lane_elevation_amplitude)
		var amp2: float = erng.randf_range(lane_elevation_second_amplitude * 0.35, lane_elevation_second_amplitude)
		var w1: float = erng.randf_range(lane_elevation_wavelength * 0.75, lane_elevation_wavelength * 1.35)
		var w2: float = erng.randf_range(lane_elevation_short_wavelength * 0.75, lane_elevation_short_wavelength * 1.35)
		var freq1: float = TAU / maxf(w1, 1.0)
		var freq2: float = TAU / maxf(w2, 1.0)
		var phase1: float = erng.randf_range(0.0, TAU)
		var phase2: float = erng.randf_range(0.0, TAU)
		_lane_params.append({
			"offset": offset,
			"amp1": amp1,
			"freq1": freq1,
			"phase1": phase1,
			"amp2": amp2,
			"freq2": freq2,
			"phase2": phase2,
			"lane": lane_idx,
		})
	# Guarantee readable spread: one lane clearly dips, one clearly crests.
	var min_idx: int = 0
	var max_idx: int = 0
	for j in 3:
		if _lane_params[j].offset < _lane_params[min_idx].offset:
			min_idx = j
		if _lane_params[j].offset > _lane_params[max_idx].offset:
			max_idx = j
	var spread: float = _lane_params[max_idx].offset - _lane_params[min_idx].offset
	if spread < 3.0:
		_lane_params[min_idx].offset -= 2.2
		_lane_params[max_idx].offset += 1.8
	# Force extremes so the "dip below" is obvious within the first 500 m.
	if _lane_params[min_idx].offset > -2.8:
		_lane_params[min_idx].offset = -3.4 - erng.randf_range(0.0, 1.6)
	if _lane_params[max_idx].offset < 1.6:
		_lane_params[max_idx].offset = 1.9 + erng.randf_range(0.0, 1.4)


func _lane_height(lane: int, z: float) -> float:
	if not lane_elevation_enabled:
		return 0.0
	lane = clampi(lane, -1, 1)
	if _lane_params.size() != 3:
		return 0.0
	var p: Dictionary = _lane_params[lane + 1]
	var raw: float = p.offset + p.amp1 * sin(p.freq1 * z + p.phase1) + p.amp2 * sin(p.freq2 * z + p.phase2)
	# Keep lane floors above the canyon floor so the dip never hides under the abyss.
	# "Go below" means below the old flat ground (y=0), not below the abyss mesh.
	return maxf(raw, abyss_y + 2.2)


# ------------------------------------------------------------------
# Build
# ------------------------------------------------------------------
func _make_materials() -> void:
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_color = Color(0.05, 0.07, 0.11)
	_ground_mat.roughness = 0.95

	_post_mat_a = StandardMaterial3D.new()
	_post_mat_a.albedo_color = Color(0.1, 0.8, 1.0)
	_post_mat_a.emission_enabled = true
	_post_mat_a.emission = Color(0.1, 0.8, 1.0)
	_post_mat_a.emission_energy_multiplier = 2.5

	_post_mat_b = StandardMaterial3D.new()
	_post_mat_b.albedo_color = Color(1.0, 0.45, 0.1)
	_post_mat_b.emission_enabled = true
	_post_mat_b.emission = Color(1.0, 0.45, 0.1)
	_post_mat_b.emission_energy_multiplier = 2.5

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(1.0, 0.55, 0.15)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.5, 0.1)
	_ring_mat.emission_energy_multiplier = 2.0

	_ring_hit_mat = StandardMaterial3D.new()
	_ring_hit_mat.albedo_color = Color(0.3, 1.0, 0.6)
	_ring_hit_mat.emission_enabled = true
	_ring_hit_mat.emission = Color(0.3, 1.0, 0.6)
	_ring_hit_mat.emission_energy_multiplier = 3.5

	_ring_graze_mat = StandardMaterial3D.new()
	_ring_graze_mat.albedo_color = Color(1.0, 0.8, 0.4)
	_ring_graze_mat.emission_enabled = true
	_ring_graze_mat.emission = Color(1.0, 0.6, 0.2)
	_ring_graze_mat.emission_energy_multiplier = 3.0

	for i in 3:
		var m := StandardMaterial3D.new()
		var v: float = 0.10 + 0.06 * float(i)
		m.albedo_color = Color(v, v + 0.02, v + 0.06)
		m.roughness = 0.9
		_pillar_mats.append(m)

	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.2, 0.15, 0.12)
	_roof_mat.emission_enabled = true
	_roof_mat.emission = Color(1.0, 0.55, 0.25)
	_roof_mat.emission_energy_multiplier = 2.0

	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.4, 0.05, 0.05)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.15, 0.1)
	_beacon_mat.emission_energy_multiplier = 5.0

	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3(1, 1, 1)

	_beacon_mesh = SphereMesh.new()
	_beacon_mesh.radius = 0.4
	_beacon_mesh.height = 0.8

	# Abyss (canyon floor) and lane mats
	_abyss_mat = StandardMaterial3D.new()
	_abyss_mat.albedo_color = Color(0.025, 0.03, 0.055)
	_abyss_mat.roughness = 1.0

	_abyss_mesh = PlaneMesh.new()
	_abyss_mesh.size = Vector2(tile_width, tile_length)
	_abyss_mesh.subdivide_width = 2
	_abyss_mesh.subdivide_depth = 2

	_lane_mats.clear()
	var lane_colors: Array[Color] = [
		Color(0.085, 0.088, 0.115),
		Color(0.074, 0.096, 0.118),
		Color(0.090, 0.084, 0.105),
	]
	for i in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = lane_colors[i]
		m.roughness = 0.93
		_lane_mats.append(m)


func _build_ground() -> void:
	# Disabled → legacy flat strip (keeps the straight-line look for comparison)
	if not lane_elevation_enabled:
		var ground_mesh := PlaneMesh.new()
		ground_mesh.size = Vector2(tile_width, tile_length)
		var post_mesh_legacy := BoxMesh.new()
		post_mesh_legacy.size = Vector3(0.5, 7.0, 0.5)
		var strip_mesh_legacy := BoxMesh.new()
		strip_mesh_legacy.size = Vector3(0.35, 0.12, 8.0)
		var strip_mat_legacy := StandardMaterial3D.new()
		strip_mat_legacy.albedo_color = Color(0.2, 0.9, 1.0)
		strip_mat_legacy.emission_enabled = true
		strip_mat_legacy.emission = Color(0.2, 0.9, 1.0)
		strip_mat_legacy.emission_energy_multiplier = 1.2
		for i in tile_count:
			var world_z: float = 60.0 - tile_length * 0.5 - float(i) * tile_length
			var tile := Node3D.new()
			tile.name = "GroundTile%d" % i
			tile.position = Vector3(0, 0, world_z)
			add_child(tile)
			_tiles.append(tile)
			var ground := MeshInstance3D.new()
			ground.name = "Ground"
			ground.mesh = ground_mesh
			ground.material_override = _ground_mat
			ground.position = Vector3(0, 0, 0)
			ground.set_meta("kind", "ground")
			tile.add_child(ground)
			for s in 3:
				var local_z_post: float = tile_length * 0.5 - 12.0 - float(s) * (tile_length / 3.0)
				for lx in [-58.0, -20.0, 20.0, 58.0]:
					var post := MeshInstance3D.new()
					post.mesh = post_mesh_legacy
					post.material_override = _post_mat_b if absf(lx) > 40.0 else _post_mat_a
					post.position = Vector3(lx, 3.5, local_z_post)
					tile.add_child(post)
			for d in 6:
				var strip := MeshInstance3D.new()
				strip.mesh = strip_mesh_legacy
				strip.material_override = strip_mat_legacy
				strip.position = Vector3(0, 0.08, tile_length * 0.5 - 10.0 - float(d) * 20.0)
				tile.add_child(strip)
		return

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.5, 7.0, 0.5)
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(0.35, 0.12, 8.0)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(0.2, 0.9, 1.0)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.2, 0.9, 1.0)
	strip_mat.emission_energy_multiplier = 1.2

	var seg_len: float = tile_length / float(maxi(lane_segment_count, 1))
	var lane_box := BoxMesh.new()
	lane_box.size = Vector3(lane_width, lane_thickness, seg_len - 0.12)

	for i in tile_count:
		var world_z: float = 60.0 - tile_length * 0.5 - float(i) * tile_length
		var tile := Node3D.new()
		tile.name = "GroundTile%d" % i
		tile.position = Vector3(0, 0, world_z)
		add_child(tile)
		_tiles.append(tile)

		# Canyon abyss floor — static dark plane the elevated lanes float above.
		var abyss := MeshInstance3D.new()
		abyss.name = "Abyss"
		abyss.mesh = _abyss_mesh
		abyss.material_override = _abyss_mat
		abyss.position = Vector3(0, abyss_y, 0)
		abyss.set_meta("kind", "abyss")
		tile.add_child(abyss)

		# Three elevated lane platforms, subdivided along Z so hills read smooth.
		# Each segment samples _lane_height at its world Z; gaps between lanes
		# reveal the abyss, making the dip/bump obvious.
		for lane_i in 3:
			var lane_idx: int = lane_i - 1
			var lane_x: float = float(lane_idx) * fighter.lane_spacing
			for seg in lane_segment_count:
				var local_z: float = tile_length * 0.5 - seg_len * 0.5 - float(seg) * seg_len
				var world_seg_z: float = world_z + local_z
				var h: float = _lane_height(lane_idx, world_seg_z)
				var seg_node := MeshInstance3D.new()
				seg_node.name = "Lane%d_Seg%d" % [lane_idx, seg]
				seg_node.mesh = lane_box
				seg_node.material_override = _lane_mats[lane_i]
				seg_node.position = Vector3(lane_x, h + lane_thickness * 0.5, local_z)
				seg_node.set_meta("kind", "lane")
				seg_node.set_meta("lane", lane_idx)
				tile.add_child(seg_node)

		# Light posts mark the lane dividers (±20) and the world edge (±58),
		# so every boundary you can hit is one you can see. Posts ride the
		# lane height (dividers average the two neighboring lanes).
		for s in 3:
			var local_z_post: float = tile_length * 0.5 - 12.0 - float(s) * (tile_length / 3.0)
			var world_z_post: float = world_z + local_z_post
			for lx in [-58.0, -20.0, 20.0, 58.0]:
				var post_h: float
				if is_equal_approx(lx, 20.0):
					post_h = (_lane_height(0, world_z_post) + _lane_height(1, world_z_post)) * 0.5
				elif is_equal_approx(lx, -20.0):
					post_h = (_lane_height(-1, world_z_post) + _lane_height(0, world_z_post)) * 0.5
				elif lx > 0.0:
					post_h = _lane_height(1, world_z_post)
				else:
					post_h = _lane_height(-1, world_z_post)
				var post := MeshInstance3D.new()
				post.name = "Post%.0f_%d" % [lx, s]
				post.mesh = post_mesh
				post.material_override = _post_mat_b if absf(lx) > 40.0 else _post_mat_a
				post.position = Vector3(lx, post_h + 3.5, local_z_post)
				post.set_meta("kind", "post")
				post.set_meta("lx", lx)
				tile.add_child(post)

		# Center dashes ride the center lane.
		for d in 6:
			var local_z_dash: float = tile_length * 0.5 - 10.0 - float(d) * 20.0
			var world_z_dash: float = world_z + local_z_dash
			var center_h: float = _lane_height(0, world_z_dash)
			var strip := MeshInstance3D.new()
			strip.name = "Dash%d" % d
			strip.mesh = strip_mesh
			strip.material_override = strip_mat
			strip.position = Vector3(0, center_h + lane_thickness * 0.5 + 0.08, local_z_dash)
			strip.set_meta("kind", "dash")
			tile.add_child(strip)


func _build_rings() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 4.5
	mesh.outer_radius = 5.2
	mesh.rings = 24
	mesh.ring_segments = 12
	for i in ring_count:
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % i
		ring.mesh = mesh
		ring.material_override = _ring_mat
		ring.position = _ring_slot(i)
		add_child(ring)
		_rings.append(ring)
		_ring_passed.append(false)
		_ring_flash.append(0.0)


func _ring_slot(i: int) -> Vector3:
	# If music-driven stage is active, let StageDirector place rings musically.
	if stage_director != null and stage_director.is_active() and fighter != null:
		# Build initial line ahead: use stage director with synthetic fighter_z offset.
		var fz: float = -60.0 - float(i) * 10.0 # approximate ahead pos for initial build
		var pos: Vector3 = stage_director.get_next_ring_position(fz, i, ring_spacing)
		# Ensure initial rings are spread forward from start, not all at same Z.
		# Re-map Z to linear ahead for initial frame: -60 - i*spacing but y/x from musical.
		var base_z: float = -60.0 - float(i) * ring_spacing
		# Keep musical X/Y, replace Z with deterministic spread.
		var lane_h: float = _lane_height(int(round(pos.x / maxf(fighter.lane_spacing, 1.0))), base_z) if lane_elevation_enabled else 0.0
		return Vector3(pos.x, clampf(lane_h + 8.0 + (pos.y - 10.0) * 0.3, 4.5, 28.0) if lane_elevation_enabled else pos.y, base_z)
	# Rings sit on lanes; when elevations are on, height rides the lane
	# (clearance 7–14 keeps threading reachable 4.5–28 m). When off, keep
	# the legacy 6–30 spread.
	if not lane_elevation_enabled:
		var lane_pick: float = float(_rng.randi_range(0, 2) - 1)
		return Vector3(
			lane_pick * fighter.lane_spacing + _rng.randf_range(-3.0, 3.0),
			_rng.randf_range(6.0, 30.0),
			-60.0 - float(i) * ring_spacing
		)
	var lane_pick2: float = float(_rng.randi_range(0, 2) - 1)
	var lane_idx: int = int(lane_pick2)
	var jitter_x: float = _rng.randf_range(-3.0, 3.0)
	var z: float = -60.0 - float(i) * ring_spacing
	var clearance: float = _rng.randf_range(7.0, 14.0)
	var base_h: float = _lane_height(lane_idx, z)
	var y: float = clampf(base_h + clearance, 4.5, 28.0)
	return Vector3(
		lane_pick2 * fighter.lane_spacing + jitter_x,
		y,
		z
	)


func _build_pillars() -> void:
	for i in pillar_count:
		var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
		var dist: float = _pillar_lane()
		var near: bool = dist < 72.0
		var mesh := BoxMesh.new()
		if near:
			# City towers hugging the side lanes: tall with lit roofs.
			mesh.size = Vector3(
				_rng.randf_range(6.0, 12.0),
				_rng.randf_range(25.0, 60.0),
				_rng.randf_range(6.0, 12.0)
			)
		else:
			mesh.size = Vector3(
				_rng.randf_range(4.0, 14.0),
				_rng.randf_range(8.0, 46.0),
				_rng.randf_range(4.0, 14.0)
			)
		var p := MeshInstance3D.new()
		p.mesh = mesh
		p.material_override = _pillar_mats[_rng.randi_range(0, _pillar_mats.size() - 1)]
		var base_y: float = (abyss_y + mesh.size.y * 0.5) if lane_elevation_enabled else (mesh.size.y * 0.5 - 1.0)
		p.position = Vector3(
			side * dist,
			base_y,
			_rng.randf_range(100.0, -900.0)
		)
		if near:
			var roof := MeshInstance3D.new()
			roof.mesh = _unit_box
			roof.material_override = _roof_mat
			roof.scale = Vector3(mesh.size.x + 1.2, 0.8, mesh.size.z + 1.2)
			roof.position = Vector3(0, mesh.size.y * 0.5 + 0.4, 0)
			p.add_child(roof)
			var beacon := MeshInstance3D.new()
			beacon.mesh = _beacon_mesh
			beacon.material_override = _beacon_mat
			beacon.position = Vector3(0, mesh.size.y * 0.5 + 1.8, 0)
			p.add_child(beacon)
		add_child(p)
		_pillars.append(p)
		_pillar_passed.append(false)


func _pillar_lane() -> float:
	# City towers line the outside of the outer lanes; rest stay scenic.
	if _rng.randf() < 0.35:
		return _rng.randf_range(48.0, 70.0)
	return _rng.randf_range(70.0, 140.0)


# ------------------------------------------------------------------
# Recycle (endless)
# ------------------------------------------------------------------
func _recycle_ground() -> void:
	var fz: float = fighter.global_position.z
	if not lane_elevation_enabled:
		for tile in _tiles:
			if tile.global_position.z - tile_length * 0.5 > fz + 70.0:
				tile.global_position.z -= tile_length * float(tile_count)
		return
	for tile in _tiles:
		# Tile behind us? Jump it far ahead and re-sample lane heights at the new Z.
		if tile.global_position.z - tile_length * 0.5 > fz + 70.0:
			tile.global_position.z -= tile_length * float(tile_count)
			var new_tile_z: float = tile.global_position.z
			for child in tile.get_children():
				if not (child is MeshInstance3D):
					continue
				if not child.has_meta("kind"):
					continue
				var kind: String = child.get_meta("kind")
				if kind == "lane":
					var lane_idx: int = child.get_meta("lane")
					var local_z: float = child.position.z
					var world_z: float = new_tile_z + local_z
					var h: float = _lane_height(lane_idx, world_z)
					var p: Vector3 = child.position
					p.y = h + lane_thickness * 0.5
					child.position = p
				elif kind == "post":
					var lx: float = child.get_meta("lx")
					var local_z_post: float = child.position.z
					var world_z_post: float = new_tile_z + local_z_post
					var post_h: float
					if is_equal_approx(lx, 20.0):
						post_h = (_lane_height(0, world_z_post) + _lane_height(1, world_z_post)) * 0.5
					elif is_equal_approx(lx, -20.0):
						post_h = (_lane_height(-1, world_z_post) + _lane_height(0, world_z_post)) * 0.5
					elif lx > 0.0:
						post_h = _lane_height(1, world_z_post)
					else:
						post_h = _lane_height(-1, world_z_post)
					var pp: Vector3 = child.position
					pp.y = post_h + 3.5
					child.position = pp
				elif kind == "dash":
					var local_z_dash: float = child.position.z
					var world_z_dash: float = new_tile_z + local_z_dash
					var center_h: float = _lane_height(0, world_z_dash)
					var pd: Vector3 = child.position
					pd.y = center_h + lane_thickness * 0.5 + 0.08
					child.position = pd


func _recycle_rings(delta: float) -> void:
	var fz: float = fighter.global_position.z
	var fp: Vector3 = fighter.global_position
	for i in _rings.size():
		var ring: MeshInstance3D = _rings[i]
		# Fly-through detection at crossing moment.
		if not _ring_passed[i] and fz < ring.global_position.z:
			_ring_passed[i] = true
			var d: Vector2 = Vector2(fp.x - ring.global_position.x, fp.y - ring.global_position.y)
			var dist: float = d.length()
			if dist < 2.2:
				# Dead-center thread: the money move.
				_ring_flash[i] = 1.5
				ring.material_override = _ring_hit_mat
				fighter.add_trauma(0.15)
				_add_stunt("PERFECT THREAD", 1.0, 2, 12.0)
				_hitstop(0.25, 0.12)
			elif dist < 5.5:
				_ring_flash[i] = 1.0
				ring.material_override = _ring_hit_mat
				fighter.add_trauma(0.12)
				_add_stunt("THREADED", 0.7, 1, 7.0)
			elif dist < 7.5:
				# Rim graze: style points for living dangerously.
				_ring_flash[i] = 1.0
				ring.material_override = _ring_graze_mat
				fighter.add_trauma(0.1)
				_add_stunt("GRAZE", 0.5, 1, 3.0)
		# Recycle passed rings far ahead with a fresh slot.
		if ring.global_position.z > fz + 20.0:
			if stage_director != null and stage_director.is_active():
				var new_pos: Vector3 = stage_director.get_next_ring_position(fz, i, ring_spacing)
				# Respect lane elevation if enabled: lift Y above lane.
				if lane_elevation_enabled:
					var lane_idx_music: int = clampi(int(round(new_pos.x / maxf(fighter.lane_spacing, 1.0))), -1, 1)
					var base_h2: float = _lane_height(lane_idx_music, new_pos.z)
					# Keep musical Y delta but anchored to lane.
					new_pos.y = clampf(base_h2 + maxf(new_pos.y - _lane_height(lane_idx_music, -60.0), 5.0), 4.5, 28.0)
				ring.global_position = new_pos
			elif not lane_elevation_enabled:
				var lane_pick_legacy: float = float(_rng.randi_range(0, 2) - 1)
				ring.global_position = Vector3(
					lane_pick_legacy * fighter.lane_spacing + _rng.randf_range(-3.0, 3.0),
					_rng.randf_range(6.0, 30.0),
					fz - ring_spacing * float(ring_count) + _rng.randf_range(-8.0, 8.0)
				)
			else:
				var lane_pick2: float = float(_rng.randi_range(0, 2) - 1)
				var lane_idx2: int = int(lane_pick2)
				# Keep RNG order identical to the original (jitter, Y, Z) so the
				# legacy seed still drives X/Z distribution — Y is now an offset
				# above the lane's elevation at the recycled Z.
				var jitter_x: float = _rng.randf_range(-3.0, 3.0)
				var raw_y: float = _rng.randf_range(7.0, 14.0)
				var z_jitter: float = _rng.randf_range(-8.0, 8.0)
				var new_z: float = fz - ring_spacing * float(ring_count) + z_jitter
				var base_h: float = _lane_height(lane_idx2, new_z)
				var new_y: float = clampf(base_h + raw_y, 4.5, 28.0)
				ring.global_position = Vector3(
					lane_pick2 * fighter.lane_spacing + jitter_x,
					new_y,
					new_z
				)
			_ring_passed[i] = false
			ring.material_override = _ring_mat
			ring.scale = Vector3.ONE
			# Music: beat-pulsed rings (scale/emission) handled in _process tick below (no allocation).
		# Hit flash pop.
		if _ring_flash[i] > 0.0:
			_ring_flash[i] = maxf(0.0, _ring_flash[i] - delta * 2.5)
			var s: float = 1.0 + (1.0 - _ring_flash[i]) * 0.15 + _ring_flash[i] * 0.25
			ring.scale = Vector3(s, s, s)
			if _ring_flash[i] <= 0.0:
				ring.material_override = _ring_mat
				ring.scale = Vector3.ONE
		# Gentle spin for life.
		ring.rotate_z(delta * 0.25)
		# Music: beat-synced ring pulse (small scale/emission breathing on beats, stronger on downbeats)
		# Keep cheap: only when music active and not already flashing.
		if _ring_flash[i] <= 0.001 and music_director != null and not music_director.is_fallback():
			var hype: float = music_director.hype
			var beat_p: float = 1.0 - music_director.beat_phase # 1 at beat, 0 before next
			# Exponential shape so pulse is sharp at beat — visualizer strong.
			beat_p = pow(clampf(beat_p, 0.0, 1.0), 2.2)
			var pulse: float = beat_p * 0.14 * (0.55 + hype * 1.1)
			if music_director.current_beat % 4 == 0:
				pulse *= 1.55
			if pulse > 0.001:
				var s2: float = 1.0 + pulse
				ring.scale = Vector3(s2, s2, s2)
			# Emission pulse: lerp toward beat color when hype high (no material alloc — just vary override energy if we keep same mat).
			# We avoid creating new materials per frame; instead we rely on ring's material_override energy tweak via env?
			# For now keep scale pulse only; emission is driven globally via EnvironmentController + StageTheme.


func _recycle_pillars() -> void:
	var fz: float = fighter.global_position.z
	var fp: Vector3 = fighter.global_position
	for idx in _pillars.size():
		var p: MeshInstance3D = _pillars[idx]
		var mesh: BoxMesh = p.mesh as BoxMesh
		var depth: float = mesh.size.z if mesh != null else 10.0
		# Near-miss skim as we pass abreast of close pillars.
		if not _pillar_passed[idx] and fz < p.global_position.z:
			_pillar_passed[idx] = true
			if mesh != null and absf(p.global_position.x) < 72.0:
				var gap: float = absf(fp.x - p.global_position.x) - mesh.size.x * 0.5
				var top: float = (abyss_y + mesh.size.y) if lane_elevation_enabled else (mesh.size.y - 1.0)
				if gap > 0.0 and gap < 6.0 and fp.y < top + 2.0:
					fighter.add_trauma(0.06)
					_add_stunt("CLOSE!", 0.5, 1, 2.0)
		if p.global_position.z - depth > fz + 60.0:
			if stage_director != null and stage_director.is_active():
				var pillar_pos: Vector3 = stage_director.get_next_pillar_position(fz, idx, mesh != null and absf(p.global_position.x) < 72.0)
				p.global_position.x = pillar_pos.x
				p.global_position.z = pillar_pos.z
				if mesh != null:
					var new_base_y2: float = (abyss_y + mesh.size.y * 0.5) if lane_elevation_enabled else (mesh.size.y * 0.5 - 1.0)
					p.global_position.y = new_base_y2
			else:
				var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
				p.global_position.z -= 1000.0
				p.global_position.x = side * _pillar_lane()
				if mesh != null:
					var new_base_y: float = (abyss_y + mesh.size.y * 0.5) if lane_elevation_enabled else (mesh.size.y * 0.5 - 1.0)
					p.global_position.y = new_base_y
			_pillar_passed[idx] = false


# ------------------------------------------------------------------
# HUD
# ------------------------------------------------------------------
func _update_hud() -> void:
	var kmh: float = fighter.forward_speed * 3.6
	speed_label.text = "%d km/h  ALT %.0fm" % [int(kmh), fighter.global_position.y]
	var state: String = "CRUISE"
	if fighter.is_rolling:
		state = "BARREL ROLL!"
	elif fighter.is_boosting:
		state = "BOOST >>"
	elif fighter.is_braking:
		state = "<< BRAKE"
	elif fighter.lateral_g > 0.7:
		state = "HARD TURN"
	# Append music section when active (readable without opening overlay).
	if music_director != null and not music_director.is_fallback() and music_director.current_section != null:
		var sec_name: String = music_director.current_section.get_type_name()
		var hype_str: String = "!" if music_director.hype > 0.85 else ""
		state += " · %s%s" % [sec_name, hype_str]
	state_label.text = state
	var base_info: String = "energy %.2f   g %.2f   z %.0f" % [
		fighter.maneuver_energy, fighter.lateral_g, fighter.global_position.z
	]
	if music_director != null and not music_director.is_fallback():
		base_info += " | beat %d  bar %d  hype %.2f" % [music_director.current_beat, music_director.current_bar, music_director.hype]
		if stage_director != null:
			base_info += "  %s" % stage_director.get_current_pattern_name()
	info_label.text = base_info
	help_label.text = "WASD/Arrows steer · SHIFT/Space boost · CTRL/C brake · Q/E roll (hold) · R reset · F3 music debug · [ ] section · N radio | V next | B/J alarms"
	# Combo meter + stunt popup.
	if _combo >= 2:
		combo_label.visible = true
		var tier: String = "COMBO"
		if _combo >= 8:
			tier = "FOX THREE!!"
		elif _combo >= 6:
			tier = "DIZZYING COMBO"
		elif _combo >= 4:
			tier = "STYLISH COMBO"
		combo_label.text = "x%d %s" % [_combo, tier]
	else:
		combo_label.visible = false
	stunt_label.modulate.a = clampf(_stunt_t, 0.0, 1.0)
	lane_label.modulate.a = 0.55 + 0.45 * _lane_flash
