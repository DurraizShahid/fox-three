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

var _shake_t: float = 0.0
var _mom_yaw: float = 0.0
var _mom_pitch: float = 0.0

func _ready() -> void:
	if target != null:
		_snap_behind()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_shake_t += delta

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

		if momentum_alignment > 0.01:
			var yaw: float = _mom_yaw * momentum_position_share * momentum_alignment
			var pitch: float = _mom_pitch * momentum_position_share * momentum_alignment
			var b: Basis = Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch)
			var rotated: Vector3 = b * base
			var d: Vector3 = target.global_position + rotated
			var resid: float = 1.0 - momentum_alignment * 0.75
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
		if momentum_alignment > 0.01:
			var legacy: Vector3 = Vector3(fighter.velocity.x * lookahead_forward, fighter.velocity.y * lookahead_forward, -fighter.forward_speed * lookahead_forward * 0.6)
			var mom: Vector3 = fighter.velocity * lookahead_forward
			look_point += legacy.lerp(mom, clampf(momentum_look_share * momentum_alignment, 0.0, 1.0))
		else:
			look_point += Vector3(fighter.velocity.x * lookahead_forward, fighter.velocity.y * lookahead_forward, -fighter.forward_speed * lookahead_forward * 0.6)
	var up: Vector3 = Vector3.UP
	if fighter != null:
		var bank_rad: float = deg_to_rad(fighter.current_bank_deg) * fighter.camera_roll_share * roll_share_mult
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
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_response * delta))
	fov = lerpf(fov, target_fov, 1.0 - exp(-3.0 * delta))

	if fighter != null and fighter.shake_trauma > 0.001:
		var s: float = pow(fighter.shake_trauma, 1.8)
		var ox: float = sin(_shake_t * shake_frequency) * shake_max_offset * s
		var oy: float = cos(_shake_t * shake_frequency * 1.2) * shake_max_offset * s
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
