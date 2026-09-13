extends CharacterBody3D
class_name FighterJet
## Arcade endless-runner fighter controller.
##
## Design: the BODY never rotates — it always flies straight down -Z.
## All banking / pitching is visual-only on the `Model` child.
## This keeps controls fun, prevents getting lost, and makes an
## endless straight corridor trivial to recycle for the music phase.
##
## Forward is -Z (Godot convention). X = strafe, Y = climb.
## Tune everything from the Inspector under Flight / Feel / Bounds.

## ------------------------------------------------------------------
## Music hooks (next phase: every maneuver becomes part of the music)
## ------------------------------------------------------------------
signal boost_started
signal boost_ended
signal brake_started
signal brake_ended
signal barrel_started(direction: float) ## -1 = left, +1 = right
signal barrel_finished
signal lane_switched(new_lane: int) ## -1 = left, 0 = center, +1 = right

@export_category("Flight")
@export_range(10.0, 80.0, 0.5) var cruise_speed: float = 45.0
@export_range(40.0, 140.0, 0.5) var boost_speed: float = 85.0
@export_range(8.0, 40.0, 0.5) var brake_speed: float = 24.0
@export_range(10.0, 120.0, 1.0) var forward_accel: float = 55.0
@export_range(5.0, 60.0, 0.5) var lateral_max_x: float = 32.0 ## max strafe m/s
@export_range(5.0, 50.0, 0.5) var lateral_max_y: float = 24.0 ## max climb/dive m/s
@export_range(1.0, 20.0, 0.1) var lateral_response: float = 7.0 ## expo rate; higher = snappier
@export_range(1.0, 3.0, 0.05) var input_curve: float = 1.5 ## >1 = fine center, aggressive edges
@export_range(0.0, 0.4, 0.01) var keyboard_deadzone: float = 0.08
@export_range(0.0, 0.5, 0.01) var gamepad_deadzone: float = 0.15
@export var invert_y: bool = false
@export_range(0.5, 2.0, 0.05) var boost_agility_mult: float = 1.25
@export_range(0.5, 2.0, 0.05) var brake_agility_mult: float = 0.85
@export_range(0.5, 2.0, 0.05) var boost_grip_mult: float = 0.8 ## <1 = slidey fast
@export_range(0.5, 2.0, 0.05) var brake_grip_mult: float = 1.35 ## >1 = grippy slow
@export_range(0.0, 1.0, 0.05) var dive_gain: float = 0.18 ## dives buy speed, climbs spend it
@export_range(0.0, 15.0, 0.5) var turn_bleed: float = 2.5 ## hard carves bleed speed
@export_range(1.0, 2.5, 0.05) var reverse_snap: float = 1.25 ## counter-steer bite for slaloms

@export_category("Feel / Tilt")
@export_range(0.0, 80.0, 1.0) var bank_max_deg: float = 55.0
@export_range(0.0, 45.0, 1.0) var pitch_vis_max_deg: float = 24.0
@export_range(0.0, 45.0, 1.0) var yaw_vis_max_deg: float = 26.0
@export_range(1.0, 20.0, 0.1) var tilt_response: float = 9.0
@export_range(0.0, 1.0, 0.05) var camera_roll_share: float = 0.18 ## read by chase cam
@export var model_yaw_correction_deg: float = 0.0 ## scene already bakes -90 deg (nose was -X); use only for fine trim
@export_range(0.0, 2.0, 0.05) var vortex_gain: float = 1.0 ## scales wingtip-vortex density

@export_category("Momentum / Slip")
## Makes the jet's NOSE (pointing) visibly differ from its TRAIL (velocity) when you
## slide / yaw / pull high-G. Camera (chase_camera.gd) aligns to velocity, so
## this crab angle is what gives the dramatic "sideways while still moving forward" read.
@export_range(0.0, 45.0, 1.0) var slip_yaw_extra_deg: float = 14.0 ## max extra yaw added from slip (clamp)
@export_range(0.0, 30.0, 1.0) var slip_pitch_extra_deg: float = 8.0
@export_range(0.0, 1.5, 0.05) var slip_exaggeration: float = 0.42 ## scales slip (pointing - velocity) into visuals; 0 = legacy
@export_range(1.0, 12.0, 0.1) var slip_response: float = 5.0 ## smoothing for slip visuals

@export_category("Exhaust / Vortices")
@export_range(0.1, 1.0, 0.01) var exhaust_width_cruise: float = 0.28 ## flame diameter at cruise (narrow pilot flame)
@export_range(0.1, 1.0, 0.01) var exhaust_width_boost: float = 0.5 ## flame diameter at full burner (width barely grows)
@export_range(0.2, 3.0, 0.05) var exhaust_length_cruise: float = 0.4 ## flame length at cruise
@export_range(0.2, 4.0, 0.05) var exhaust_length_boost: float = 1.7 ## flame length at boost (length does the talking)
@export_range(0.0, 0.3, 0.01) var flicker_strength: float = 0.12 ## turbulent shimmer amount (multi-octave, not a slow pulse)
@export_range(0.0, 1.0, 0.05) var vortex_onset: float = 0.55 ## lateral_g where wisps start (straight cruise = clean air)

@export_category("Paint")
@export var body_color: Color = Color(0.02, 0.02, 0.02) ## stealth-black airframe (speed 0 uses this if no gradient)
@export_range(0.0, 1.0, 0.05) var body_metallic: float = 0.65 ## sun glints keep black readable
@export_range(0.0, 1.0, 0.05) var body_roughness: float = 0.38
@export var blacken_canopy: bool = true ## false keeps the pale-blue glTF canopy glass
@export var speed_tint_enabled: bool = true ## sample speed_gradient by speed_ratio (0=brake,1=boost)
@export var speed_gradient: Gradient ## null = auto grayscale ramp black→white; assign in Inspector to customize
@export_range(0.5, 3.0, 0.1) var speed_gradient_curve: float = 1.2 ## >1 lingers near black, <1 rushes to white
@export_range(0.0, 3.0, 0.1) var boost_emission: float = 0.9 ## glow energy at max speed (0=off)

## plane.glb surface table (single mesh, 4 surfaces, deterministic import order):
## 0 Metal (dark-gray airframe), 1 Metal.001 (red-orange accents),
## 2 Metal.002 (mid gray), 3 Material.002 (pale-blue canopy glass).
const GLASS_SURFACE: int = 3

@export_category("Barrel Roll")
@export_range(0.2, 1.2, 0.05) var barrel_duration: float = 0.55
@export_range(0.0, 2.0, 0.05) var barrel_cooldown: float = 0.6
@export_range(0.0, 40.0, 1.0) var barrel_speed_kick: float = 18.0
@export_range(0.0, 20.0, 0.5) var barrel_dash: float = 10.0 ## lateral shove at roll start (dodge tool)
@export_range(0.1, 0.5, 0.01) var double_tap_window: float = 0.28

@export_category("Bounds (flight corridor)")
@export_range(5.0, 90.0, 0.5) var bound_half_width: float = 62.0
@export_range(0.0, 10.0, 0.5) var bound_min_height: float = 2.0
@export_range(10.0, 80.0, 0.5) var bound_max_height: float = 34.0
@export_range(1.0, 15.0, 0.5) var bound_soft_margin: float = 7.0
@export_range(0.5, 10.0, 0.1) var bound_push_strength: float = 3.5

@export_category("Lanes")
@export var lanes_enabled: bool = true
@export_range(6.0, 60.0, 0.5) var lane_spacing: float = 40.0
@export_range(0.1, 0.8, 0.05) var lane_snap_time: float = 0.32
@export_range(4.0, 20.0, 0.5) var lane_snap_gain: float = 10.0
@export_range(10.0, 60.0, 1.0) var lane_snap_max: float = 40.0
@export_range(0.0, 12.0, 0.5) var lane_bank_kick: float = 6.0

@export_category("Audio — brown-noise engine")
@export_range(0.4, 1.2, 0.01) var audio_base_pitch: float = 0.82
@export_range(0.8, 2.0, 0.01) var audio_top_pitch: float = 1.42
@export_range(-24.0, -2.0, 0.1) var audio_base_vol_db: float = -12.0
@export_range(-12.0, 6.0, 0.1) var audio_top_vol_db: float = -0.8
@export_range(0.0, 0.4, 0.01) var audio_roll_pitch: float = 0.16
@export_range(0.0, 0.3, 0.01) var audio_g_pitch: float = 0.09
@export_range(1.0, 10.0, 0.1) var audio_response: float = 3.5

@export_category("Touch")
@export var touch_steer_enabled: bool = true
@export_range(0.001, 0.02, 0.0005) var touch_sensitivity: float = 0.006
@export_range(0.5, 8.0, 0.1) var touch_decay: float = 3.0

@export_category("Music Speed")
@export var music_speed_enabled: bool = true
@export_range(0.5, 2.0, 0.01) var music_speed_min_clamp: float = 0.85
@export_range(0.5, 2.5, 0.01) var music_speed_max_clamp: float = 1.55
@export_range(0.5, 10.0, 0.1) var music_speed_response: float = 2.2 ## smoothing for music multiplier
@export_range(0.0, 0.3, 0.01) var music_beat_impulse_gain: float = 0.04 ## small breathing pulse per beat
@export_range(0.0, 0.3, 0.01) var music_downbeat_gain: float = 0.07 ## stronger on downbeats
@export_range(1.0, 10.0, 0.1) var music_beat_decay: float = 6.0
@export_range(0.0, 20.0, 0.5) var music_surge_decay: float = 8.0 ## decay for drop surge (m/s per sec)

@export_category("Music Visuals")
@export_range(0.0, 2.0, 0.05) var music_exhaust_gain: float = 0.45 ## how much hype lifts flame
@export_range(0.0, 1.0, 0.05) var music_vortex_gain: float = 0.35 ## hype adds to vortices
@export_range(0.0, 1.0, 0.05) var music_particle_gain: float = 0.4 ## hype adds to speed particles
@export_range(0.0, 1.0, 0.05) var music_emission_gain: float = 0.5 ## hype adds to emission

## Runtime state (read these from camera / music / HUD — all 0..1 unless noted)
var input_steer: Vector2 = Vector2.ZERO ## x: -1 left / +1 right, y: +1 up / -1 down (after curve)
var raw_steer: Vector2 = Vector2.ZERO ## before curve, useful for HUD
var forward_speed: float = 45.0
var speed_ratio: float = 0.0 ## 0 = brake, ~0.4 = cruise, 1 = boost
var lateral_g: float = 0.0 ## 0..1 how hard we are turning
var maneuver_energy: float = 0.0 ## smoothed |turn| + boost, for music phase
var is_boosting: bool = false
var is_braking: bool = false
var is_rolling: bool = false
var current_bank_deg: float = 0.0 ## visual bank, camera reads a share of this
var shake_trauma: float = 0.0 ## 0..1, camera consumes this
var was_hard_turning: bool = false
var bonus_speed: float = 0.0 ## stunt speed kicks, decays back to plan (m/s)
var style_heat: float = 0.0 ## 0..1 written by the track: combo intensity for music
var lane_index: int = 0 ## -1 left, 0 center, +1 right
## Momentum — WHERE YOU'RE MOVING vs WHERE YOU'RE POINTING (read by camera).
## velocity_yaw/pitch = trail direction; heading_yaw = nose pointing; crab = slip visible in frame.
var velocity_yaw_deg: float = 0.0
var velocity_pitch_deg: float = 0.0
var heading_yaw_deg: float = 0.0
var crab_angle_deg: float = 0.0 ## heading - velocity yaw (the money value for momentum feel)

var _paint_mat: StandardMaterial3D = null ## shared airframe paint, tinted by speed
var _roll_t: float = 0.0
var _roll_dir: float = 1.0
var _roll_cooldown: float = 0.0
var _roll_visual: float = 0.0 ## extra 0..TAU added on top of bank during roll
var _vortex: float = 0.0 ## smoothed wingtip-vortex strength 0..1
var _bank: float = 0.0 ## clean bank state (never includes barrel-roll spins)
var _bank_vel: float = 0.0 ## bank spring velocity (the whip)
var _lane_snap_t: float = 0.0 ## lane-lock timer after a switch
var _rumble_cd: float = 0.0 ## throttle for repeated grind rumble
var _audio_pitch: float = 0.9
var _audio_vol: float = -10.0
var _last_tap_left: float = -10.0
var _last_tap_right: float = -10.0
var _touch_stick: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _slip_yaw_visual: float = 0.0 ## smoothed extra yaw (deg) from slip exaggeration
var _slip_pitch_visual: float = 0.0

## Music-driven state (public: written by MusicReactiveDirector, never by internals except smoothing)
var music_speed_mult: float = 1.0 ## target multiplier 0.85..1.55
var music_intensity: float = 0.0 ## 0..1 current section intensity
var music_hype: float = 0.0 ## 0..1 hype/impact
var music_low: float = 0.0
var music_mid: float = 0.0
var music_high: float = 0.0
var _music_speed_current: float = 1.0 ## smoothed
var _music_beat_kick: float = 0.0 ## transient 0..1 decays
var _music_surge: float = 0.0 ## m/s one-shot surge (drop) decays via surge_decay

@onready var model: Node3D = $Model
@onready var flame_core: MeshInstance3D = get_node_or_null("Model/FlameCore") as MeshInstance3D
@onready var exhaust_halo: MeshInstance3D = get_node_or_null("Model/ExhaustHalo") as MeshInstance3D
@onready var vortex_l: GPUParticles3D = get_node_or_null("Model/VortexL") as GPUParticles3D
@onready var vortex_r: GPUParticles3D = get_node_or_null("Model/VortexR") as GPUParticles3D
@onready var boost_particles: GPUParticles3D = get_node_or_null("BoostParticles") as GPUParticles3D
@onready var engine_audio: AudioStreamPlayer = get_node_or_null("EngineAudio") as AudioStreamPlayer


func _ready() -> void:
	forward_speed = cruise_speed
	# Body must stay axis-aligned: all tilt lives on Model.
	rotation = Vector3.ZERO
	_apply_paint()
	_start_engine_audio()


func _input(event: InputEvent) -> void:
	# --- Barrel roll: Q / E (or LB / RB) ---
	if event.is_action_pressed("roll_left") and not event.is_echo():
		try_barrel_roll(-1.0)
	elif event.is_action_pressed("roll_right") and not event.is_echo():
		try_barrel_roll(1.0)

	# --- Double-tap A/D / arrows to barrel roll (super fun, very Star Fox) ---
	if event.is_action_pressed("yaw_left") and not event.is_echo():
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_tap_left <= double_tap_window:
			try_barrel_roll(-1.0)
			_last_tap_left = -10.0
		else:
			_last_tap_left = now
	if event.is_action_pressed("yaw_right") and not event.is_echo():
		var now2: float = Time.get_ticks_msec() / 1000.0
		if now2 - _last_tap_right <= double_tap_window:
			try_barrel_roll(1.0)
			_last_tap_right = -10.0
		else:
			_last_tap_right = now2

	# --- Touch drag steers ---
	if touch_steer_enabled:
		if event is InputEventScreenDrag:
			var drag: InputEventScreenDrag = event as InputEventScreenDrag
			# ~250px drag = full deflection.
			_touch_stick.x = clampf(_touch_stick.x + drag.relative.x * touch_sensitivity * 0.25, -1.0, 1.0)
			_touch_stick.y = clampf(_touch_stick.y - drag.relative.y * touch_sensitivity * 0.25, -1.0, 1.0)
			_touch_stick = _touch_stick.limit_length(1.0)
		elif event is InputEventScreenTouch:
			var touch: InputEventScreenTouch = event as InputEventScreenTouch
			if not touch.pressed:
				pass # stick decays in _physics_process, no snap


func _physics_process(delta: float) -> void:
	_time += delta
	_roll_cooldown = maxf(0.0, _roll_cooldown - delta)
	_rumble_cd = maxf(0.0, _rumble_cd - delta)
	shake_trauma = maxf(0.0, shake_trauma - delta * 1.6)

	# Held roll buttons chain barrel rolls: tap = one roll, hold = loop.
	if not is_rolling and _roll_cooldown <= 0.0:
		if _is_roll_held(-1.0):
			try_barrel_roll(-1.0)
		elif _is_roll_held(1.0):
			try_barrel_roll(1.0)

	var steer: Vector2 = _gather_steer(delta)
	raw_steer = steer
	# Input shaping: cubic-ish curve keeps center precise, edges aggressive.
	steer.x = _shaped(steer.x)
	steer.y = _shaped(steer.y)
	input_steer = steer

	# --- Lane system: lane lines at ±spacing/2. Gentle entries snap in, ---
	# --- hard full-stick traverses flow straight through to the far side. ---
	if lanes_enabled:
		var want_lane: int = clampi(int(round(global_position.x / lane_spacing)), -1, 1)
		if want_lane != lane_index:
			var cross_dir: float = _sgn(float(want_lane - lane_index))
			lane_index = want_lane
			lane_switched.emit(lane_index)
			if absf(input_steer.x) < 0.75:
				_start_lane_snap(cross_dir)
		if _lane_snap_t > 0.0:
			_lane_snap_t -= delta

	# --- Boost / brake ---
	var want_boost: bool = _is_boost_held()
	var want_brake: bool = _is_brake_held() and not want_boost
	_set_boosting(want_boost and not is_rolling)
	_set_braking(want_brake and not is_rolling)

	# --- Music speed (public target smoothed internally) ---
	if music_speed_enabled:
		_music_speed_current = _exp_damp(_music_speed_current, music_speed_mult, music_speed_response, delta)
		_music_beat_kick = maxf(0.0, _music_beat_kick - delta * music_beat_decay)
		_music_surge = maxf(0.0, _music_surge - delta * music_surge_decay)
	else:
		_music_speed_current = 1.0
		_music_beat_kick = 0.0
		_music_surge = 0.0

	var target_forward: float = cruise_speed
	var agility: float = 1.0
	var grip: float = 1.0
	if is_boosting:
		target_forward = boost_speed
		agility = boost_agility_mult
		grip = boost_grip_mult
	elif is_braking:
		target_forward = brake_speed
		agility = brake_agility_mult
		grip = brake_grip_mult
	if is_rolling:
		target_forward = maxf(target_forward, cruise_speed + barrel_speed_kick)

	# Apply music multiplier + beat breathing + drop surge additively (boost/brake remain meaningful).
	if music_speed_enabled:
		var music_factor: float = clampf(_music_speed_current + _music_beat_kick, music_speed_min_clamp, music_speed_max_clamp)
		target_forward *= music_factor
		target_forward += _music_surge

	# --- Lateral arcade velocity (with inertia/drift) ---
	var target_vx: float = steer.x * lateral_max_x * agility
	var target_vy: float = steer.y * lateral_max_y * agility
	var rate_x: float = lateral_response * grip
	var rate_y: float = lateral_response * grip
	# Lane lock: yank toward the lane center while the snap timer runs.
	if lanes_enabled and _lane_snap_t > 0.0:
		var lane_x: float = float(lane_index) * lane_spacing
		target_vx = clampf((lane_x - global_position.x) * lane_snap_gain, -lane_snap_max, lane_snap_max)
		rate_x = lateral_response * 2.0
	# Reversal snap: counter-steering bites harder, so slaloms whip.
	if target_vx * velocity.x < 0.0 and absf(velocity.x) > 6.0:
		rate_x *= reverse_snap
	if target_vy * velocity.y < 0.0 and absf(velocity.y) > 5.0:
		rate_y *= reverse_snap
	velocity.x = _exp_damp(velocity.x, target_vx, rate_x, delta)
	velocity.y = _exp_damp(velocity.y, target_vy, rate_y, delta)

	# Energy model: dives buy speed, climbs and hard carves spend it.
	var carve: float = clampf(Vector2(velocity.x / maxf(lateral_max_x * agility, 1.0), velocity.y / maxf(lateral_max_y * agility, 1.0)).length(), 0.0, 1.0)
	target_forward += clampf(-velocity.y * dive_gain, -12.0, 14.0) - carve * turn_bleed
	# Stunt kicks ride on top, then bleed off so cruise always returns.
	target_forward = clampf(target_forward + bonus_speed, 10.0, 120.0)
	bonus_speed = move_toward(bonus_speed, 0.0, 18.0 * delta)

	forward_speed = move_toward(forward_speed, target_forward, forward_accel * delta)
	velocity.z = -forward_speed

	# --- Soft corridor walls: push back before the hard clamp ---
	var grind: float = _apply_soft_bounds(delta)
	if grind > 0.05:
		add_trauma(minf(grind, 1.5) * 1.2 * delta)

	move_and_slide()

	# --- Hard clamp (keeps the runner inside the corridor) ---
	global_position.x = clampf(global_position.x, -bound_half_width, bound_half_width)
	global_position.y = clampf(global_position.y, bound_min_height, bound_max_height)
	# Never tilt the body; only the model.
	rotation = Vector3.ZERO

	_update_barrel_roll(delta)
	_update_visuals(delta)
	_update_music_state(delta)
	_update_paint(delta)
	_update_engine_audio(delta)


func try_barrel_roll(dir: float) -> bool:
	if is_rolling or _roll_cooldown > 0.0:
		return false
	is_rolling = true
	_roll_dir = _sgn(dir) if dir != 0.0 else 1.0
	_roll_t = 0.0
	_roll_cooldown = barrel_duration + barrel_cooldown
	# Dodge dash: lateral shove in the roll direction.
	velocity.x += _roll_dir * barrel_dash
	add_trauma(0.35)
	_rumble(0.35, 0.75, 0.22)
	barrel_started.emit(_roll_dir)
	return true


func _start_lane_snap(dir: float) -> void:
	_lane_snap_t = lane_snap_time
	# Flourish: bank whip into the switch, vortex burst, dash feel.
	_bank_vel += -dir * lane_bank_kick
	_vortex = maxf(_vortex, 0.8)
	add_trauma(0.22)
	add_speed_kick(3.0)
	_rumble(0.25, 0.45, 0.18)


func add_trauma(amount: float) -> void:
	shake_trauma = clampf(shake_trauma + amount, 0.0, 1.0)
	if amount >= 0.1:
		_rumble(minf(amount * 0.7, 0.6), minf(amount * 1.1, 0.9), 0.12)


func _rumble(weak: float, strong: float, duration: float) -> void:
	if _rumble_cd > 0.0 and weak < 0.5 and strong < 0.5:
		return
	_rumble_cd = 0.06
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, duration)
	if Input.get_connected_joypads().is_empty():
		Input.start_joy_vibration(0, weak, strong, duration)


func _joy_axis_max(axis: int) -> float:
	var best: float = 0.0
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		return Input.get_joy_axis(0, axis)
	for id in pads:
		var v: float = Input.get_joy_axis(id, axis)
		if absf(v) > absf(best):
			best = v
	return best


func add_speed_kick(amount: float) -> void:
	## Reward burst from stunts. Capped + decays in _physics_process.
	bonus_speed = minf(bonus_speed + amount, 25.0)


## ------------------------------------------------------------------
## Music public API (called by MusicReactiveDirector — no private access)
## ------------------------------------------------------------------

func set_music_speed_multiplier(mult: float) -> void:
	music_speed_mult = clampf(mult, music_speed_min_clamp, music_speed_max_clamp)

func trigger_music_beat(is_downbeat: bool) -> void:
	var gain: float = music_downbeat_gain if is_downbeat else music_beat_impulse_gain
	# Scale by hype so drops breathe harder, but quiet still subtle.
	gain *= 0.6 + music_hype * 0.9
	_music_beat_kick = maxf(_music_beat_kick, gain)

func trigger_music_surge(amount: float) -> void:
	# One-shot forward surge at drop entry — much larger but decays quickly.
	_music_surge = maxf(_music_surge, amount)

func set_music_hype(h: float) -> void:
	music_hype = clampf(h, 0.0, 1.0)

func set_music_intensity(v: float) -> void:
	music_intensity = clampf(v, 0.0, 1.0)

func set_music_spectrum(low: float, mid: float, high: float) -> void:
	music_low = clampf(low, 0.0, 1.0)
	music_mid = clampf(mid, 0.0, 1.0)
	music_high = clampf(high, 0.0, 1.0)


func get_music_state() -> Dictionary:
	return {
		"speed_ratio": speed_ratio,
		"lateral_g": lateral_g,
		"energy": maneuver_energy,
		"boosting": is_boosting,
		"braking": is_braking,
		"rolling": is_rolling,
		"steer": input_steer,
		"lane": lane_index,
		# Momentum: where you're moving vs where you're pointing — for music / camera.
		"velocity_yaw_deg": velocity_yaw_deg,
		"velocity_pitch_deg": velocity_pitch_deg,
		"heading_yaw_deg": heading_yaw_deg,
		"crab_angle_deg": crab_angle_deg,
		"slip_yaw_deg": crab_angle_deg, # alias
		# Music-driven extensions (for reactive directors + HUD).
		"music_speed_mult": _music_speed_current,
		"music_speed_target": music_speed_mult,
		"music_hype": music_hype,
		"music_intensity": music_intensity,
		"music_beat_pulse": _music_beat_kick,
		"music_surge": _music_surge,
		"music_low": music_low,
		"music_mid": music_mid,
		"music_high": music_high,
	}


# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------
func _gather_steer(delta: float) -> Vector2:
	var x: float = 0.0
	var y: float = 0.0

	# 1) Keyboard / mapped actions
	if InputMap.has_action("yaw_right") and InputMap.has_action("yaw_left"):
		x += Input.get_axis("yaw_left", "yaw_right")
	if InputMap.has_action("pitch_up") and InputMap.has_action("pitch_down"):
		y += Input.get_axis("pitch_down", "pitch_up")

	# Fallback if actions are missing (keeps prototype flyable).
	if x == 0.0 and y == 0.0:
		x += float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
		x -= float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
		y += float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
		y -= float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))

	# 2) Gamepad left stick + right stick (both steer, either hand). Any pad wins.
	var pad_x: float = _joy_axis_max(JOY_AXIS_LEFT_X)
	var pad_y: float = -_joy_axis_max(JOY_AXIS_LEFT_Y)
	var rpad_x: float = _joy_axis_max(JOY_AXIS_RIGHT_X)
	var rpad_y: float = -_joy_axis_max(JOY_AXIS_RIGHT_Y)
	if absf(rpad_x) > gamepad_deadzone:
		pad_x = _pick_stronger(pad_x, rpad_x)
	if absf(rpad_y) > gamepad_deadzone:
		pad_y = _pick_stronger(pad_y, rpad_y)
	if absf(pad_x) > gamepad_deadzone:
		x = _pick_stronger(x, pad_x)
	if absf(pad_y) > gamepad_deadzone:
		y = _pick_stronger(y, pad_y)

	# 3) Touch drag stick (decays so release = level out)
	if touch_steer_enabled and _touch_stick.length() > 0.01:
		x = _pick_stronger(x, clampf(_touch_stick.x, -1.0, 1.0))
		y = _pick_stronger(y, clampf(_touch_stick.y, -1.0, 1.0))
		_touch_stick = _touch_stick.move_toward(Vector2.ZERO, touch_decay * delta)

	if invert_y:
		y = -y
	return Vector2(clampf(x, -1.0, 1.0), clampf(y, -1.0, 1.0))


func _pick_stronger(a: float, b: float) -> float:
	return b if absf(b) > absf(a) else a


func _is_boost_held() -> bool:
	if InputMap.has_action("boost") and Input.is_action_pressed("boost"):
		return true
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE):
		return true
	if _joy_axis_max(JOY_AXIS_TRIGGER_RIGHT) > 0.3:
		return true
	return false


func _is_brake_held() -> bool:
	if InputMap.has_action("brake") and Input.is_action_pressed("brake"):
		return true
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_ALT):
		return true
	if _joy_axis_max(JOY_AXIS_TRIGGER_LEFT) > 0.3:
		return true
	return false


func _is_roll_held(dir: float) -> bool:
	var action: String = "roll_left" if dir < 0.0 else "roll_right"
	if InputMap.has_action(action) and Input.is_action_pressed(action):
		return true
	if dir < 0.0:
		return Input.is_key_pressed(KEY_Q)
	return Input.is_key_pressed(KEY_E)


# ------------------------------------------------------------------
# Bounds / rolls / visuals / music state
# ------------------------------------------------------------------
func _apply_soft_bounds(delta: float) -> float:
	var p: Vector3 = global_position
	var push: float = 0.0
	# X walls
	var edge_x: float = bound_half_width - bound_soft_margin
	if p.x > edge_x:
		var t: float = (p.x - edge_x) / bound_soft_margin
		push = maxf(push, t)
		velocity.x -= bound_push_strength * lateral_max_x * t * delta * 4.0
	elif p.x < -edge_x:
		var t2: float = (-p.x - edge_x) / bound_soft_margin
		push = maxf(push, t2)
		velocity.x += bound_push_strength * lateral_max_x * t2 * delta * 4.0
	# Ceiling / floor
	var edge_top: float = bound_max_height - bound_soft_margin
	var edge_bot: float = bound_min_height + bound_soft_margin
	if p.y > edge_top:
		var t3: float = (p.y - edge_top) / bound_soft_margin
		push = maxf(push, t3)
		velocity.y -= bound_push_strength * lateral_max_y * t3 * delta * 4.0
	elif p.y < edge_bot:
		var t4: float = (edge_bot - p.y) / bound_soft_margin
		push = maxf(push, t4)
		velocity.y += bound_push_strength * lateral_max_y * t4 * delta * 4.0
	return push


func _update_barrel_roll(delta: float) -> void:
	if not is_rolling:
		_roll_visual = lerp(_roll_visual, 0.0, 1.0 - exp(-10.0 * delta))
		return
	_roll_t += delta
	var prog: float = clampf(_roll_t / barrel_duration, 0.0, 1.0)
	# Ease in-out so the snap feels punchy at start, soft at catch.
	var eased: float = prog * prog * (3.0 - 2.0 * prog)
	_roll_visual = eased * TAU * _roll_dir
	if prog >= 1.0:
		is_rolling = false
		_roll_visual = 0.0
		barrel_finished.emit()


func _update_visuals(delta: float) -> void:
	if model == null:
		return
	var bank_target: float = deg_to_rad(-input_steer.x * bank_max_deg)
	# Add extra lean from actual lateral velocity (drift feels weighty).
	bank_target += deg_to_rad(clampf(-velocity.x / maxf(lateral_max_x, 1.0), -1.0, 1.0) * 12.0)
	var pitch_target: float = deg_to_rad(input_steer.y * pitch_vis_max_deg * 0.9)
	pitch_target += deg_to_rad(clampf(velocity.y / maxf(lateral_max_y, 1.0), -1.0, 1.0) * 8.0)
	var yaw_target: float = deg_to_rad(-input_steer.x * yaw_vis_max_deg)

	# --- Momentum: nose (pointing) vs trail (velocity) ---
	# Camera aligns to velocity, so this slip is what makes the jet crab
	# visibly inside the frame — "almost sideways while still moving forward".
	var fwd_for_ang: float = maxf(forward_speed, 1.0)
	var vel_yaw_rad: float = atan2(velocity.x, fwd_for_ang)
	var horiz: float = sqrt(fwd_for_ang * fwd_for_ang + velocity.x * velocity.x)
	var vel_pitch_rad: float = atan2(velocity.y, horiz)
	velocity_yaw_deg = rad_to_deg(vel_yaw_rad)
	velocity_pitch_deg = rad_to_deg(vel_pitch_rad)
	heading_yaw_deg = -input_steer.x * yaw_vis_max_deg
	crab_angle_deg = heading_yaw_deg - velocity_yaw_deg
	var heading_pitch_deg_local: float = input_steer.y * pitch_vis_max_deg * 0.9
	var slip_pitch_deg: float = heading_pitch_deg_local - velocity_pitch_deg
	var target_extra_yaw: float = clampf(crab_angle_deg * slip_exaggeration, -slip_yaw_extra_deg, slip_yaw_extra_deg)
	var target_extra_pitch: float = clampf(slip_pitch_deg * slip_exaggeration, -slip_pitch_extra_deg, slip_pitch_extra_deg)
	_slip_yaw_visual = _exp_damp(_slip_yaw_visual, target_extra_yaw, slip_response, delta)
	_slip_pitch_visual = _exp_damp(_slip_pitch_visual, target_extra_pitch, slip_response, delta)
	yaw_target += deg_to_rad(_slip_yaw_visual)
	pitch_target += deg_to_rad(_slip_pitch_visual)

	var k: float = 1.0 - exp(-tilt_response * delta)
	var e: Vector3 = model.rotation
	# Model base orientation: yaw correction first, then fun tilt.
	# We store tilt as local euler; correction applied on Y only when idle.
	var base_yaw: float = deg_to_rad(model_yaw_correction_deg) + yaw_target
	e.y = lerp_angle(e.y, base_yaw, k)
	e.x = lerp_angle(e.x, pitch_target, k)
	# Bank is a slightly underdamped spring: it whips past the target a
	# touch on turn entry (alive!) instead of easing like everything else.
	# (_bank never sees the barrel-roll spin; that's added on top below.)
	_bank_vel += (bank_target - _bank) * tilt_response * tilt_response * 0.9 * delta
	_bank_vel *= exp(-tilt_response * 1.1 * delta)
	_bank += _bank_vel * delta
	var bank: float = _bank
	e.z = bank + _roll_visual
	model.rotation = e
	current_bank_deg = rad_to_deg(wrapf(bank, -PI, PI))

	# Idle life: single low-frequency float so the jet feels alive without
	# the high-frequency position jitter that reads as motion blur up close.
	model.position.y = sin(_time * 0.9) * 0.04
	model.position.x = cos(_time * 0.7) * 0.03

	model.rotation = e

	# Exhaust flame: narrow white-hot core that stretches with throttle.
	# Real burners grow in LENGTH, not diameter, with fast turbulent shimmer
	# instead of a slow cartoon pulse. Emission stays restrained so glow
	# bloom reads as heat, not a neon balloon. Null-safe.
	# Music contribution is ADDITIVE so fast + hype is spectacular, slow + hype still pops.
	var t: float = inverse_lerp(brake_speed, boost_speed, forward_speed)
	var turb_n: float = sin(_time * 11.0) * 0.5 + sin(_time * 17.0 + 1.7) * 0.3 + sin(_time * 23.0 + 0.6) * 0.2
	var flick: float = 1.0 + turb_n * flicker_strength * 0.35
	if is_boosting:
		flick += sin(_time * 29.0 + 0.9) * flicker_strength * 0.2
	# Music additive: hype lifts flame; beat kick adds momentary punch.
	var music_flame_add: float = music_hype * music_exhaust_gain * 0.35 + _music_beat_kick * 0.4 + music_low * 0.08
	var music_halo_add: float = music_hype * music_exhaust_gain * 0.25 + _music_beat_kick * 0.22
	if flame_core != null:
		var flame_w: float = lerpf(exhaust_width_cruise, exhaust_width_boost, t) * (1.0 + (flick - 1.0) * 0.6)
		var flame_l: float = lerpf(exhaust_length_cruise, exhaust_length_boost, t) * flick
		# Music: exaggerate length strongly at hype, width barely.
		flame_l *= 1.0 + music_hype * music_exhaust_gain * 0.7 + _music_beat_kick * 0.5
		flame_w *= 1.0 + music_hype * 0.12
		flame_core.scale = Vector3(flame_w, flame_l, 1.0)
		var cm: StandardMaterial3D = flame_core.get_surface_override_material(0) as StandardMaterial3D
		if cm != null:
			cm.emission_energy_multiplier = 0.8 + 1.8 * t + (0.6 if is_boosting else 0.0) + music_flame_add * 1.9
	if exhaust_halo != null:
		var halo_s: float = (0.45 + 0.65 * t + (0.15 if is_rolling else 0.0)) * (1.0 + (flick - 1.0) * 0.3)
		halo_s *= 1.0 + music_halo_add * 1.2 + music_hype * 0.15
		exhaust_halo.scale = Vector3(halo_s, halo_s, 1.0)
		var hm: StandardMaterial3D = exhaust_halo.get_surface_override_material(0) as StandardMaterial3D
		if hm != null:
			hm.emission_energy_multiplier = 0.25 + 0.6 * t + music_halo_add * 0.8
	# Wingtip vortices: faint wisps that onset only past vortex_onset G.
	# Straight cruise stays clean; hard carves / rolls draw thin trails.
	# Music hype adds vortices so important sections look dense even when flying straight.
	var vortex_base: float = clampf((lateral_g - vortex_onset) / maxf(1.0 - vortex_onset, 0.01), 0.0, 1.0)
	var target_v: float = clampf(vortex_base + (0.15 if is_boosting else 0.0) + (0.4 if is_rolling else 0.0) + music_hype * music_vortex_gain * 0.9 + _music_beat_kick * 0.3, 0.0, 1.0)
	_vortex = _exp_damp(_vortex, target_v * vortex_gain, 4.0, delta)
	if vortex_l != null:
		vortex_l.amount_ratio = clampf(_vortex, 0.0, 1.0)
	if vortex_r != null:
		vortex_r.amount_ratio = clampf(_vortex, 0.0, 1.0)
	if boost_particles != null:
		# Speed dust only when actually fast: cruise is clean, boost/roll streaks.
		# Music hype densifies it without replacing throttle response.
		var trail_t: float = clampf((t - 0.35) * 1.6, 0.0, 1.0) + (0.4 if is_rolling else 0.0) + music_hype * music_particle_gain * 0.85 + _music_beat_kick * 0.25 + music_high * 0.15
		boost_particles.amount_ratio = clampf(trail_t, 0.0, 1.0)


func _update_music_state(delta: float) -> void:
	speed_ratio = inverse_lerp(float(brake_speed), float(boost_speed), float(forward_speed))
	var gx: float = absf(velocity.x) / maxf(lateral_max_x * boost_agility_mult, 1.0)
	var gy: float = absf(velocity.y) / maxf(lateral_max_y * boost_agility_mult, 1.0)
	lateral_g = clampf(Vector2(gx, gy).length(), 0.0, 1.0)
	var target_energy: float = clampf(lateral_g * 0.7 + speed_ratio * 0.3 + (0.4 if is_rolling else 0.0) + style_heat * 0.35, 0.0, 1.0)
	maneuver_energy = _exp_damp(maneuver_energy, target_energy, 5.0, delta)

	var hard: bool = lateral_g > 0.7 or is_rolling
	if hard and not was_hard_turning:
		add_trauma(0.08)
	was_hard_turning = hard


func _start_engine_audio() -> void:
	if engine_audio == null:
		return
	# Brown-noise file is 10 min; ensure it loops (import flag also set).
	var s: AudioStream = engine_audio.stream
	if s != null and s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	if not engine_audio.playing:
		engine_audio.play()


func _update_engine_audio(delta: float) -> void:
	if engine_audio == null:
		return
	if not engine_audio.playing:
		engine_audio.play()
	# Throttle rumble: brown noise pitch carries speed. Base curve is
	# non-linear so cruise sits low (rumble), boost screams without
	# chipmunking. Rolls and hard carves add whine on top.
	var cruise: float = inverse_lerp(brake_speed, boost_speed, forward_speed)
	var t: float = pow(clampf(cruise, 0.0, 1.0), 0.85)
	var target_pitch: float = lerpf(audio_base_pitch, audio_top_pitch, t)
	target_pitch += lateral_g * audio_g_pitch
	if is_boosting:
		target_pitch += 0.08
	elif is_braking:
		target_pitch -= 0.09
	if is_rolling:
		# Doppler-esque whoosh through the roll.
		var roll_phase: float = clampf(_roll_t / maxf(barrel_duration, 0.01), 0.0, 1.0)
		target_pitch += sin(roll_phase * PI) * audio_roll_pitch
	# Tiny turbine shimmer so it never sits static.
	target_pitch += sin(_time * 6.7) * 0.015 + sin(_time * 13.3 + 0.8) * 0.008
	target_pitch = clampf(target_pitch, 0.5, 2.4)

	var target_vol: float = lerpf(audio_base_vol_db, audio_top_vol_db, t)
	if is_boosting:
		target_vol += 2.0
	elif is_braking:
		target_vol -= 1.5
	if is_rolling:
		target_vol += 1.2
	target_vol = clampf(target_vol, -28.0, 4.0)

	_audio_pitch = _exp_damp(_audio_pitch, target_pitch, audio_response, delta)
	_audio_vol = _exp_damp(_audio_vol, target_vol, audio_response * 1.6, delta)
	engine_audio.pitch_scale = _audio_pitch
	engine_audio.volume_db = _audio_vol


func _set_boosting(v: bool) -> void:
	if v == is_boosting:
		return
	is_boosting = v
	if v:
		add_trauma(0.22)
		add_speed_kick(6.0) ## launch shove on press
		boost_started.emit()
	else:
		boost_ended.emit()


func _set_braking(v: bool) -> void:
	if v == is_braking:
		return
	is_braking = v
	if v:
		brake_started.emit()
	else:
		brake_ended.emit()


func _shaped(x: float) -> float:
	var ax: float = absf(x)
	if ax <= keyboard_deadzone:
		return 0.0
	var norm: float = (ax - keyboard_deadzone) / (1.0 - keyboard_deadzone)
	return _sgn(x) * pow(clampf(norm, 0.0, 1.0), input_curve)


func _exp_damp(a: float, b: float, lambda: float, delta: float) -> float:
	return lerpf(a, b, 1.0 - exp(-lambda * delta))


func _sgn(x: float) -> float:
	return 1.0 if x >= 0.0 else -1.0


func _apply_paint() -> void:
	## Recolors the imported plane.glb (whose materials are embedded in the
	## import, so they can't be overridden from fighter.tscn). Null-safe:
	## a missing/repathed Plane must never crash _ready.
	var plane: Node = get_node_or_null("Model/Plane")
	if plane == null:
		return
	_paint_mat = StandardMaterial3D.new()
	_paint_mat.albedo_color = body_color
	_paint_mat.metallic = body_metallic
	_paint_mat.roughness = body_roughness
	for mi: MeshInstance3D in _find_meshes(plane):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			if s == GLASS_SURFACE and not blacken_canopy:
				continue
			mi.set_surface_override_material(s, _paint_mat)


func _ensure_speed_gradient() -> Gradient:
	if speed_gradient != null:
		return speed_gradient
	# Grayscale only: black → white through neutral shades.
	# No hues — speed reads as value only, per request.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.50, 0.75, 1.0])
	g.colors = PackedColorArray([
		body_color,                # 0.00 stealth black (follows Inspector body_color)
		Color(0.18, 0.18, 0.18),   # 0.25 charcoal
		Color(0.42, 0.42, 0.42),   # 0.50 mid gray
		Color(0.72, 0.72, 0.72),   # 0.75 light gray
		Color(1.0, 1.0, 1.0),      # 1.00 white at max speed
	])
	speed_gradient = g
	return g


func _update_paint(_delta: float) -> void:
	## Speed-reactive grayscale ramp: samples speed_gradient by
	## speed_ratio (0=brake, 1=boost) through a shaped curve. Black
	## at rest, white at max speed, shades of gray in between — no hues.
	## Null-safe; metallic/roughness follow Inspector live.
	if _paint_mat == null:
		return
	if not speed_tint_enabled:
		_paint_mat.albedo_color = body_color
		_paint_mat.emission_enabled = false
		return
	var g: Gradient = _ensure_speed_gradient()
	var t: float = clampf(pow(clampf(speed_ratio, 0.0, 1.0), speed_gradient_curve), 0.0, 1.0)
	var tinted: Color = g.sample(t)
	# Preserve alpha at 1; gradient alpha is not authored.
	tinted.a = 1.0
	_paint_mat.albedo_color = tinted
	_paint_mat.metallic = body_metallic
	_paint_mat.roughness = body_roughness
	var hype_emission: float = music_hype * music_emission_gain * 0.6 + _music_beat_kick * 0.25 + music_high * 0.12
	if boost_emission > 0.01 or hype_emission > 0.01:
		if t > 0.01 or hype_emission > 0.01:
			_paint_mat.emission_enabled = true
			_paint_mat.emission = tinted
			_paint_mat.emission_energy_multiplier = t * boost_emission + hype_emission
		else:
			_paint_mat.emission_enabled = false
	else:
		_paint_mat.emission_enabled = false


func _find_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out
