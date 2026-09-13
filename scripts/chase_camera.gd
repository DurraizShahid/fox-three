extends Camera3D
class_name ChaseCamera
## Arcadey chase cam: laggy follow, look-ahead, FOV kick, trauma shake.
## Drop it in Main, drag the Fighter into `target`.

@export var target: Node3D
@export_category("Frame")
@export var offset: Vector3 = Vector3(0, 1.7, 4.0) ## behind (+Z) and above, since forward is -Z
@export_range(1.0, 15.0, 0.1) var follow_response: float = 6.5
@export_range(0.0, 1.0, 0.01) var lookahead_lateral: float = 0.14
@export_range(0.0, 1.0, 0.01) var lookahead_forward: float = 0.08
@export_range(0.0, 1.0, 0.01) var roll_share_mult: float = 0.55 ## multiplies fighter.camera_roll_share
@export_range(1.0, 15.0, 0.1) var lateral_follow: float = 6.0
@export_range(0.0, 4.0, 0.1) var dolly_back: float = 0.7
@export_range(0.0, 3.0, 0.1) var dolly_up: float = 0.25

@export_category("Momentum / Velocity Align")
## Camera aligns to WHERE YOU'RE MOVING (velocity vector), not where you're pointing.
## The jet visibly crabs/yaws inside the frame when drifting — momentum becomes readable.
## Subtle default (0.78) — momentarily 15-30° crab in hard turns, not cartoon sideways.
@export_range(0.0, 1.0, 0.05) var momentum_alignment: float = 0.78 ## 0=world, 1=velocity
@export_range(0.5, 10.0, 0.1) var momentum_response: float = 3.0
@export_range(0.0, 1.0, 0.05) var momentum_position_share: float = 0.85
@export_range(0.0, 1.0, 0.05) var momentum_look_share: float = 0.75
@export_range(-45.0, 45.0, 1.0) var momentum_yaw_clamp_deg: float = 38.0
@export_range(-35.0, 35.0, 1.0) var momentum_pitch_clamp_deg: float = 26.0

@export_category("FOV")
@export_range(50.0, 110.0, 0.5) var cruise_fov: float = 75.0
@export_range(50.0, 120.0, 0.5) var boost_fov: float = 92.0
@export_range(40.0, 100.0, 0.5) var brake_fov: float = 68.0
@export_range(1.0, 10.0, 0.1) var fov_response: float = 4.0

@export_category("Shake")
@export_range(0.0, 1.0, 0.01) var shake_max_offset: float = 0.07
@export_range(0.0, 15.0, 0.1) var shake_frequency: float = 8.0

@export_category("Music Reactivity")
@export var music_reactivity_enabled: bool = true
@export_range(0.0, 2.0, 0.05) var music_intensity_fov: float = 2.5 ## hype adds FOV
@export_range(0.0, 4.0, 0.1) var music_beat_fov: float = 1.2 ## every beat
@export_range(0.0, 6.0, 0.1) var music_downbeat_fov: float = 2.6 ## downbeat stronger
@export_range(0.0, 2.0, 0.05) var music_beat_dolly: float = 0.35 ## micro dolly on beats
@export_range(0.0, 3.0, 0.05) var music_downbeat_dolly: float = 0.7
@export_range(0.0, 2.0, 0.05) var music_hype_shake: float = 0.6 ## hype adds shake
@export_range(0.0, 2.0, 0.05) var music_hype_follow_looseness: float = 0.35 ## hype loosens follow
@export_range(0.0, 15.0, 0.5) var music_drop_fov: float = 6.0 ## drop punch FOV
@export_range(0.0, 1.0, 0.05) var music_drop_shake: float = 0.4
@export_range(0.1, 3.0, 0.05) var music_drop_duration: float = 0.6
@export_range(0.0, 10.0, 0.1) var music_momentum_exaggeration: float = 1.2 ## hype exaggerates velocity alignment (solo)
@export_range(1.0, 12.0, 0.1) var music_impulse_decay: float = 14.0
@export_range(1.0, 8.0, 0.1) var music_hype_response: float = 3.0
@export_range(0.0, 1.0, 0.05) var music_accessibility_shake_mult: float = 1.0 ## reduce for motion-sensitive

## Public music-reactive state (written by MusicReactiveDirector, never private)
var music_intensity: float = 0.0 ## 0..1 section intensity
var music_hype: float = 0.0 ## 0..1 impact
var _music_hype_smooth: float = 0.0
var _beat_pulse: float = 0.0 ## 0..1 transient decays fast
var _downbeat_pulse: float = 0.0
var _drop_punch: float = 0.0 ## 0..1 decays over drop_duration
var _drop_t: float = 0.0

var _shake_t: float = 0.0
var _mom_yaw: float = 0.0
var _mom_pitch: float = 0.0

func _ready() -> void:
	if target != null:
		_snap_behind()


## ------------------------------------------------------------------
## Music public API (no private access)
## ------------------------------------------------------------------

func set_music_hype(h: float) -> void:
	music_hype = clampf(h, 0.0, 1.0)

func set_music_intensity(v: float) -> void:
	music_intensity = clampf(v, 0.0, 1.0)

func trigger_beat_pulse(is_downbeat: bool) -> void:
	if not music_reactivity_enabled:
		return
	var base: float = 1.0 if not is_downbeat else 1.0
	if is_downbeat:
		_downbeat_pulse = maxf(_downbeat_pulse, 1.0)
		_beat_pulse = maxf(_beat_pulse, 0.6)
	else:
		_beat_pulse = maxf(_beat_pulse, 1.0)

func trigger_drop_punch() -> void:
	if not music_reactivity_enabled:
		return
	_drop_punch = 1.0
	_drop_t = music_drop_duration

func _physics_process(delta: float) -> void:
	if target == null:
		return
	_shake_t += delta
	# Decay music impulses
	if music_reactivity_enabled:
		_beat_pulse = maxf(0.0, _beat_pulse - delta * music_impulse_decay)
		_downbeat_pulse = maxf(0.0, _downbeat_pulse - delta * (music_impulse_decay * 0.85))
		if _drop_t > 0.0:
			_drop_t -= delta
			_drop_punch = clampf(_drop_t / maxf(music_drop_duration, 0.01), 0.0, 1.0)
		else:
			_drop_punch = maxf(0.0, _drop_punch - delta * 6.0)
		_music_hype_smooth = lerpf(_music_hype_smooth, music_hype, 1.0 - exp(-music_hype_response * delta))
	else:
		_music_hype_smooth = 0.0
		_beat_pulse = 0.0
		_downbeat_pulse = 0.0
		_drop_punch = 0.0

	var fighter: FighterJet = target as FighterJet

	# --- Momentum: track smoothed velocity direction ---
	if fighter != null:
		var fwd: float = maxf(fighter.forward_speed, 1.0)
		var raw_yaw: float = atan2(fighter.velocity.x, fwd)
		var horiz: float = sqrt(fwd * fwd + fighter.velocity.x * fighter.velocity.x)
		var raw_pitch: float = atan2(fighter.velocity.y, horiz)
		raw_yaw = clampf(raw_yaw, -deg_to_rad(momentum_yaw_clamp_deg), deg_to_rad(momentum_yaw_clamp_deg))
		raw_pitch = clampf(raw_pitch, -deg_to_rad(momentum_pitch_clamp_deg), deg_to_rad(momentum_pitch_clamp_deg))
		var l: float = 1.0 - exp(-momentum_response * delta)
		_mom_yaw = lerp_angle(_mom_yaw, raw_yaw, l)
		_mom_pitch = lerpf(_mom_pitch, raw_pitch, l)
	else:
		_mom_yaw = lerpf(_mom_yaw, 0.0, 1.0 - exp(-momentum_response * delta))
		_mom_pitch = lerpf(_mom_pitch, 0.0, 1.0 - exp(-momentum_response * delta))

	# Desired position: chase point behind the VELOCITY tail when momentum is on,
	# otherwise legacy world + lateral lookahead.
	var desired: Vector3
	if fighter != null:
		var base: Vector3 = offset
		base.y += fighter.speed_ratio * dolly_up
		base.z += fighter.speed_ratio * dolly_back
		# Music: micro dolly on beats/downbeats + hype expands view.
		if music_reactivity_enabled:
			var beat_d: float = _beat_pulse * music_beat_dolly
			var down_d: float = _downbeat_pulse * music_downbeat_dolly
			base.z += (beat_d + down_d) * (0.6 + _music_hype_smooth * 0.8)
			base.y += (beat_d + down_d) * 0.18
			base.z += _music_hype_smooth * music_hype_follow_looseness * 0.6
			base.z += _drop_punch * 0.9
			base.y += _drop_punch * 0.35

		var effective_align: float = momentum_alignment
		if music_reactivity_enabled:
			effective_align = clampf(momentum_alignment + _music_hype_smooth * music_momentum_exaggeration * 0.08, 0.0, 1.0)
		if effective_align > 0.01:
			var yaw: float = _mom_yaw * momentum_position_share * effective_align
			var pitch: float = _mom_pitch * momentum_position_share * effective_align
			var b: Basis = Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch)
			var rotated: Vector3 = b * base
			var d: Vector3 = target.global_position + rotated
			var resid: float = 1.0 - effective_align * 0.75
			if resid > 0.001:
				d.x += fighter.velocity.x * lookahead_lateral * resid
				d.y += fighter.velocity.y * lookahead_lateral * 0.7 * resid
			d.y = maxf(d.y, 1.2)
			desired = d
		else:
			var d2: Vector3 = target.global_position + base
			d2.x += fighter.velocity.x * lookahead_lateral
			d2.y += fighter.velocity.y * lookahead_lateral * 0.7
			d2.y = maxf(d2.y, 1.2)
			desired = d2
	else:
		desired = target.global_position + offset

	var kx: float = 1.0 - exp(-lateral_follow * delta)
	var ky: float = 1.0 - exp(-follow_response * delta)
	global_position.x = lerpf(global_position.x, desired.x, kx)
	global_position.y = lerpf(global_position.y, desired.y, ky)
	global_position.z = lerpf(global_position.z, desired.z, ky)

	var look_point: Vector3 = target.global_position
	if fighter != null:
		var eff_look: float = momentum_alignment
		if music_reactivity_enabled:
			eff_look = clampf(momentum_alignment + _music_hype_smooth * music_momentum_exaggeration * 0.06, 0.0, 1.0)
		if eff_look > 0.01:
			var legacy: Vector3 = Vector3(fighter.velocity.x * lookahead_forward, fighter.velocity.y * lookahead_forward, -fighter.forward_speed * lookahead_forward * 0.6)
			var mom: Vector3 = fighter.velocity * lookahead_forward
			look_point += legacy.lerp(mom, clampf(momentum_look_share * eff_look, 0.0, 1.0))
		else:
			look_point += Vector3(fighter.velocity.x * lookahead_forward, fighter.velocity.y * lookahead_forward, -fighter.forward_speed * lookahead_forward * 0.6)
		# Section/phrase camera choreography: hype loosens lateral follow slightly.
		if music_reactivity_enabled and _music_hype_smooth > 0.5:
			look_point.x += fighter.velocity.x * 0.02 * _music_hype_smooth
	var up: Vector3 = Vector3.UP
	if fighter != null:
		var bank_rad: float = deg_to_rad(fighter.current_bank_deg) * fighter.camera_roll_share * roll_share_mult
		# Music hype slightly exaggerates bank lean in camera.
		if music_reactivity_enabled:
			bank_rad *= 1.0 + _music_hype_smooth * 0.18
		up = Vector3(sin(bank_rad), cos(bank_rad), 0.0).normalized()
	_apply_look(look_point, up)

	var target_fov: float = cruise_fov
	if fighter != null:
		if fighter.is_boosting:
			target_fov = boost_fov
		elif fighter.is_braking:
			target_fov = brake_fov
		if fighter.is_rolling:
			target_fov += 4.0
	# Music FOV: hype lifts baseline, beats punch.
	if music_reactivity_enabled:
		target_fov += _music_hype_smooth * music_intensity_fov
		target_fov += _beat_pulse * music_beat_fov
		target_fov += _downbeat_pulse * music_downbeat_fov
		target_fov += _drop_punch * music_drop_fov
		# Clamp so not unreadable.
		target_fov = clampf(target_fov, 55.0, 110.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_response * delta))
	fov = lerpf(fov, target_fov, 1.0 - exp(-3.0 * delta))

	# Shake: trauma + music hype + drop punch (capped & accessibility-scaled)
	var total_shake: float = 0.0
	var shake_src: float = 0.0
	if fighter != null:
		shake_src = pow(fighter.shake_trauma, 1.8)
	if music_reactivity_enabled:
		var hype_shake_src: float = _music_hype_smooth * music_hype_shake * 0.4
		hype_shake_src += _beat_pulse * 0.06
		hype_shake_src += _downbeat_pulse * 0.09
		hype_shake_src += _drop_punch * music_drop_shake
		hype_shake_src *= music_accessibility_shake_mult
		# Combine: trauma dominates but hype adds when not shaking via flight.
		shake_src = maxf(shake_src, hype_shake_src)
		# Also allow hype to raise ceiling slightly but cap.
		total_shake = clampf(shake_src, 0.0, 1.0)
	else:
		total_shake = shake_src
	if total_shake > 0.001:
		var ox: float = sin(_shake_t * shake_frequency) * shake_max_offset * total_shake
		var oy: float = cos(_shake_t * shake_frequency * 1.2) * shake_max_offset * total_shake
		# Drop punch adds a single larger kick on top.
		if _drop_punch > 0.01:
			ox += sin(_shake_t * 23.0) * 0.015 * _drop_punch
			oy += cos(_shake_t * 19.0) * 0.015 * _drop_punch
		h_offset = lerpf(h_offset, ox, 1.0 - exp(-18.0 * delta))
		v_offset = lerpf(v_offset, oy, 1.0 - exp(-18.0 * delta))
	else:
		h_offset = lerpf(h_offset, 0.0, 1.0 - exp(-8.0 * delta))
		v_offset = lerpf(v_offset, 0.0, 1.0 - exp(-8.0 * delta))


func _snap_behind() -> void:
	global_position = target.global_position + offset
	look_at(target.global_position, Vector3.UP)


func _apply_look(point: Vector3, up: Vector3) -> void:
	if global_position.distance_squared_to(point) > 0.001:
		look_at(point, up)
