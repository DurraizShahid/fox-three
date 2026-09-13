extends Node
class_name MusicReactiveDirector
## Maps musical timing / intensity into Fighter, Camera, VFX, environment and HUD.
## Keeps responsibilities separated: Fighter/Camera/Environment each have their
## own public music API — this director only WRITES those public fields / calls
## public triggers, never private variables.

@export var fighter_path: NodePath = NodePath("../Fighter")
@export var camera_path: NodePath = NodePath("../ChaseCamera")
@export var music_director_path: NodePath = NodePath("../MusicDirector")
@export var environment_controller_path: NodePath = NodePath("../EnvironmentController")
@export var stage_director_path: NodePath = NodePath("../StageDirector")

## Tuning — expose everything.
@export_category("Speed Mapping")
@export_range(0.5, 1.5, 0.01) var speed_intro: float = 0.93
@export_range(0.5, 1.5, 0.01) var speed_verse: float = 1.0
@export_range(0.5, 1.5, 0.01) var speed_build: float = 1.07
@export_range(0.5, 1.5, 0.01) var speed_chorus: float = 1.12
@export_range(0.5, 1.6, 0.01) var speed_drop: float = 1.32
@export_range(0.5, 1.6, 0.01) var speed_climax: float = 1.35
@export_range(0.5, 1.6, 0.01) var speed_solo: float = 1.22
@export_range(0.5, 1.6, 0.01) var speed_bridge: float = 1.08
@export_range(0.5, 1.6, 0.01) var speed_breakdown: float = 0.96
@export_range(0.5, 1.6, 0.01) var speed_outro: float = 0.95
@export_range(0.5, 1.6, 0.01) var speed_peak: float = 1.38
@export_range(0.5, 1.6, 0.01) var speed_crescendo: float = 1.18
@export_range(0.0, 0.5, 0.01) var speed_build_ramp: float = 0.12 ## extra ramp across BUILD progress
@export_range(0.0, 0.3, 0.01) var speed_intensity_lerp: float = 0.08 ## how much intensity lifts speed
@export_range(0.5, 1.5, 0.02) var drop_surge_amount: float = 18.0 ## m/s one-shot surge at drop entry
@export_range(0.0, 1.0, 0.05) var style_heat_surge_mult: float = 0.4 ## high style_heat scales surge

@export_category("Visual Hype")
@export_range(0.0, 2.0, 0.05) var hype_visual_mult: float = 1.0 ## master for VFX hype (scales fighter gains)
@export_range(0.0, 1.0, 0.05) var downbeat_rumble_weak: float = 0.22
@export_range(0.0, 1.0, 0.05) var downbeat_rumble_strong: float = 0.45
@export_range(0.0, 1.0, 0.05) var drop_rumble_weak: float = 0.5
@export_range(0.0, 1.0, 0.05) var drop_rumble_strong: float = 0.9
@export var enable_rumble: bool = true

@export_category("Spectrum Mapping")
@export_range(0.0, 2.0, 0.05) var bass_to_exhaust: float = 0.22
@export_range(0.0, 2.0, 0.05) var mid_to_light: float = 0.35
@export_range(0.0, 2.0, 0.05) var high_to_particles: float = 0.4

var fighter: FighterJet = null
var chase_cam: ChaseCamera = null
var music_director: MusicDirector = null
var env_controller: EnvironmentController = null
var stage_director: StageDirector = null

var _last_section_type: int = -1
var _in_drop: bool = false
var _drop_anticipation_t: float = 0.0

func _ready() -> void:
	_resolve()
	if music_director != null:
		music_director.beat.connect(_on_beat)
		music_director.downbeat.connect(_on_downbeat)
		music_director.bar.connect(_on_bar)
		music_director.section_started.connect(_on_section_started)
		music_director.section_ended.connect(_on_section_ended)
		music_director.important_moment_started.connect(_on_important_started)
		music_director.important_moment_ended.connect(_on_important_ended)
		music_director.hype_changed.connect(_on_hype_changed)
	set_process(true)

func _resolve() -> void:
	if fighter_path != NodePath(""):
		fighter = get_node_or_null(fighter_path) as FighterJet
	if fighter == null:
		fighter = get_parent().get_node_or_null("Fighter") as FighterJet
	if camera_path != NodePath(""):
		chase_cam = get_node_or_null(camera_path) as ChaseCamera
	if chase_cam == null:
		chase_cam = get_parent().get_node_or_null("ChaseCamera") as ChaseCamera
	if music_director_path != NodePath(""):
		music_director = get_node_or_null(music_director_path) as MusicDirector
	if music_director == null:
		music_director = get_parent().get_node_or_null("MusicDirector") as MusicDirector
	if environment_controller_path != NodePath(""):
		env_controller = get_node_or_null(environment_controller_path) as EnvironmentController
	if env_controller == null:
		env_controller = get_parent().get_node_or_null("EnvironmentController") as EnvironmentController
	if stage_director_path != NodePath(""):
		stage_director = get_node_or_null(stage_director_path) as StageDirector
	if stage_director == null:
		stage_director = get_parent().get_node_or_null("StageDirector") as StageDirector

func _process(_delta: float) -> void:
	if fighter == null or music_director == null:
		return
	# Continuous hype/intensity drift — set public fields each frame (smoothly inside targets).
	var hype: float = music_director.hype
	var intensity: float = music_director.current_intensity
	var low: float = music_director.low_energy
	var mid: float = music_director.mid_energy
	var high: float = music_director.high_energy

	# style_heat enhances hype visually (skill adds spectacle, but poor play doesn't ruin song).
	var heat: float = fighter.style_heat if fighter != null else 0.0
	var visual_hype: float = clampf(hype * (1.0 + heat * 0.25 * hype_visual_mult), 0.0, 1.0)

	# Push to Fighter public API.
	fighter.set_music_hype(visual_hype)
	fighter.set_music_intensity(intensity)
	fighter.set_music_spectrum(low, mid, high)

	# Push to Camera.
	if chase_cam != null:
		chase_cam.set_music_hype(visual_hype)
		chase_cam.set_music_intensity(intensity)

	# Push to Environment.
	if env_controller != null:
		env_controller.set_hype(visual_hype)
		env_controller.set_spectrum(low, mid, high)

	# Update speed target continuously (section-driven + builds + intensity).
	var target_speed: float = _compute_speed_target(intensity, hype, low)
	if fighter != null:
		fighter.set_music_speed_multiplier(target_speed)

	# Anticipation just before a known DROP: subtle pre-drop visual tension.
	if _drop_anticipation_t > 0.0:
		_drop_anticipation_t -= _delta
		# Nudge FOV/exhaust slightly before the exact drop for "brace" feel.

func _compute_speed_target(intensity: float, hype: float, _low: float) -> float:
	if music_director == null or music_director.is_fallback():
		return 1.0
	var sec: MusicSection = music_director.current_section
	var base: float = speed_verse
	if sec != null:
		match sec.section_type:
			MusicSection.Type.INTRO: base = speed_intro
			MusicSection.Type.VERSE: base = speed_verse
			MusicSection.Type.BUILD: base = speed_build + music_director.section_progress * speed_build_ramp
			MusicSection.Type.CHORUS: base = speed_chorus
			MusicSection.Type.DROP: base = speed_drop
			MusicSection.Type.SOLO, MusicSection.Type.GUITAR_SOLO: base = speed_solo
			MusicSection.Type.BRIDGE: base = speed_bridge
			MusicSection.Type.BREAKDOWN: base = speed_breakdown
			MusicSection.Type.CRESCENDO:
				# Continuously escalate across crescendo.
				base = lerpf(speed_build, speed_crescendo, music_director.section_progress)
				base = maxf(base, speed_crescendo * 0.92 + music_director.section_progress * 0.12)
			MusicSection.Type.CLIMAX: base = speed_climax
			MusicSection.Type.OUTRO: base = speed_outro
			MusicSection.Type.PEAK: base = speed_peak
			_: base = speed_verse
		# Section speed_mult multiplies author intent (e.g. a hyper bridge).
		base *= sec.speed_mult
	# Intensity/hype nudge (tasteful, not jerky).
	base += (intensity - 0.5) * speed_intensity_lerp
	base += hype * 0.04
	# Important moment lift (brief, already smoothed via hype but add a touch).
	if music_director.is_in_important_moment:
		base += 0.06
	# Clamp to safe playable bounds (matches fighter clamps).
	var prof: SongProfile = music_director.song_profile
	if prof != null:
		base *= prof.global_speed_mult
	# Accessibility clamp inside Fighter will also enforce 0.85..1.55, but keep target sane here too.
	return clampf(base, 0.88, 1.55)

## ------------------------------------------------------------------
## Signal handlers — WHEN (beat) + HOW MUCH (energy)
## ------------------------------------------------------------------

func _on_beat(beat_idx: int, _pos: float) -> void:
	if fighter == null:
		return
	# Beat-level subtle impulses (not every system flashes equally).
	var is_down: bool = false
	if music_director != null:
		var bpb: int = music_director.song_profile.beats_per_bar if music_director.song_profile != null else 4
		is_down = (beat_idx % bpb == 0)
	fighter.trigger_music_beat(is_down)
	if chase_cam != null:
		chase_cam.trigger_beat_pulse(is_down)
	if env_controller != null:
		env_controller.trigger_beat(is_down)
	# Rumble on downbeats only (not every beat — avoid fatigue).
	if is_down and enable_rumble:
		var hype: float = music_director.hype if music_director != null else 0.0
		if hype > 0.5 or (music_director != null and music_director.current_importance > 0.6):
			_rumble(downbeat_rumble_weak * (0.7 + hype * 0.6), downbeat_rumble_strong * (0.7 + hype * 0.6), 0.14)

func _on_downbeat(_bar_idx: int, _pos: float) -> void:
	# Downbeat already handled in _on_beat with is_down, but stronger hooks can go here.
	# Environment light pulse stronger on downbeat (already in env_controller via downbeat flag).
	pass

func _on_bar(bar_idx: int, _pos: float) -> void:
	# Bar-level: larger light pulse, occasional environment event — handled via env's downbeat+hype.
	# Stage pattern decision lives in StageDirector (listens to bar directly).
	pass

func _on_section_started(sec: MusicSection, _idx: int) -> void:
	if sec == null:
		return
	_last_section_type = sec.section_type
	# Drop-entry spectacle: the "holy shit" moment.
	var is_drop: bool = sec.section_type == MusicSection.Type.DROP and sec.importance > 0.6
	var is_climax: bool = sec.section_type == MusicSection.Type.CLIMAX and sec.importance > 0.65
	var is_peak: bool = sec.section_type == MusicSection.Type.PEAK and sec.importance > 0.7
	if is_drop or is_climax or is_peak:
		_trigger_drop_spectacle(sec)
	# Solo / crescendo also get a milder surge.
	if sec.section_type == MusicSection.Type.GUITAR_SOLO or sec.section_type == MusicSection.Type.SOLO:
		if sec.importance > 0.55:
			# Flowing solo — smaller surge but longer hype.
			if fighter != null:
				var amt: float = 8.0 + fighter.style_heat * 6.0
				fighter.trigger_music_surge(amt)
	if sec.section_type == MusicSection.Type.CRESCENDO and sec.importance > 0.5:
		# Anticipation visual before climax — no surge yet, just hype building (handled continuously).
		pass
	# Apply StageTheme override if section specifies one.
	if sec.stage_theme_override != null and env_controller != null and stage_director != null:
		var over: StageTheme = sec.stage_theme_override as StageTheme
		if over != null:
			env_controller.apply_theme(over)
			stage_director.stage_theme = over

func _on_section_ended(sec: MusicSection, _idx: int) -> void:
	if sec == null:
		return
	# Restore theme if we had overridden.
	if sec.stage_theme_override != null and env_controller != null and stage_director != null:
		var prof: SongProfile = music_director.song_profile if music_director != null else null
		var base_theme: StageTheme = null
		if prof != null and prof.stage_theme != null:
			base_theme = prof.stage_theme as StageTheme
		if base_theme != null:
			env_controller.apply_theme(base_theme)
			stage_director.stage_theme = base_theme

func _on_important_started(mom: ImportantMoment) -> void:
	if mom == null:
		return
	if mom.triggers_drop_surge:
		_trigger_drop_spectacle(null, mom)

func _on_important_ended(_mom: ImportantMoment) -> void:
	pass

func _on_hype_changed(hype: float) -> void:
	# Hype already pushed continuously; this hook is for one-shot thresholds if needed.
	if hype > 0.92 and not _in_drop:
		# Near max hype — add subtle extra punch if not already in drop.
		pass

func _trigger_drop_spectacle(sec: MusicSection, mom: ImportantMoment = null) -> void:
	_in_drop = true
	# 1) Jet surge.
	if fighter != null:
		var surge: float = drop_surge_amount
		# Scale by importance + style_heat.
		var imp: float = sec.importance if sec != null else 1.0
		if mom != null:
			imp = maxf(imp, mom.intensity)
		surge *= clampf(0.7 + imp * 0.5, 0.8, 1.4)
		surge *= 1.0 + fighter.style_heat * style_heat_surge_mult
		fighter.trigger_music_surge(surge)
		fighter.add_trauma(0.18)
		fighter.trigger_music_beat(true) # extra beat punch
	# 2) Camera punch.
	if chase_cam != null:
		chase_cam.trigger_drop_punch()
	# 3) Environment flash.
	if env_controller != null:
		env_controller.trigger_drop_flash()
	# 4) Rumble.
	if enable_rumble:
		_rumble(drop_rumble_weak, drop_rumble_strong, 0.35)
	# 5) Brief screen flash / exposure handled via env_controller's flash.
	# Do NOT touch Engine.time_scale — would desync audio.

func _rumble(weak: float, strong: float, duration: float) -> void:
	if not enable_rumble:
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, duration)
	if Input.get_connected_joypads().is_empty():
		Input.start_joy_vibration(0, weak, strong, duration)

func trigger_build_anticipation(duration: float = 1.0) -> void:
	_drop_anticipation_t = duration
