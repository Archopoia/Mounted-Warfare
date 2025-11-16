extends Node
class_name BehaviorExecutor

## Executes primitive movement/attack behaviors for non-player mounts.

const MAX_SPEED: float = 20.0

func execute(behavior: String, context: Dictionary, delta: float) -> void:
	var mount: CharacterBody3D = context.get("mount", null)
	var target: Node3D = context.get("target", null)
	if mount == null:
		return
	match behavior:
		"attack":
			_face_target(mount, target, delta)
			_throttle_forward(mount, 6.0, delta)
			_try_fire(mount)
		"chase":
			_face_target(mount, target, delta)
			_throttle_forward(mount, 8.0, delta)
		"strafe":
			_orbit_target(mount, target, 1.0, delta)
			_try_fire(mount)
		"evade":
			_face_away(mount, target, delta)
			_throttle_forward(mount, 9.0, delta)
		"patrol":
			_wander(mount, delta)
		_:
			_idle(mount, delta)
	_limit_speed(mount)

func _face_target(mount: CharacterBody3D, target: Node3D, delta: float) -> void:
	if target == null:
		return
	var mp: Vector3 = mount.global_transform.origin
	var tp: Vector3 = target.global_transform.origin
	var dir: Vector3 = (tp - mp)
	dir.y = 0.0
	var dist: float = dir.length()
	if dist <= 0.0001:
		return
	dir = dir.normalized()
	var desired_yaw: float = atan2(dir.x, dir.z)
	var yaw_delta: float = wrapf(desired_yaw - mount.rotation.y, -PI, PI)
	var yaw_step: float = clamp(yaw_delta, -1.5, 1.5) * delta
	mount.rotation.y += yaw_step

func _face_away(mount: CharacterBody3D, target: Node3D, delta: float) -> void:
	if target == null:
		return
	var mp: Vector3 = mount.global_transform.origin
	var tp: Vector3 = target.global_transform.origin
	var dir: Vector3 = (mp - tp) # reversed
	dir.y = 0.0
	var dist: float = dir.length()
	if dist <= 0.0001:
		return
	dir = dir.normalized()
	var desired_yaw: float = atan2(dir.x, dir.z)
	var yaw_delta: float = wrapf(desired_yaw - mount.rotation.y, -PI, PI)
	var yaw_step: float = clamp(yaw_delta, -1.5, 1.5) * delta
	mount.rotation.y += yaw_step

func _orbit_target(mount: CharacterBody3D, target: Node3D, turn_bias: float, delta: float) -> void:
	_face_target(mount, target, delta)
	# apply lateral rotation bias for orbiting
	mount.rotation.y += turn_bias * 0.75 * delta
	_throttle_forward(mount, 5.0, delta)

func _throttle_forward(mount: CharacterBody3D, accel: float, delta: float) -> void:
	var forward: Vector3 = -mount.transform.basis.z
	mount.velocity += forward * accel * delta

func _try_fire(mount: CharacterBody3D) -> void:
	# Fire the first child weapon that can fire
	for c in mount.get_children():
		if c is Node and c.has_method("can_fire") and c.has_method("fire"):
			if c.call("can_fire"):
				c.call("fire", mount)
				return

func _wander(mount: CharacterBody3D, delta: float) -> void:
	# simple gentle drift with slow turning
	mount.rotation.y += 0.25 * delta
	_throttle_forward(mount, 2.5, delta)

func _idle(_mount: CharacterBody3D, _delta: float) -> void:
	# no-op for now (gravity and slide handled by controller)
	pass

func _limit_speed(mount: CharacterBody3D) -> void:
	if mount.velocity.length() > MAX_SPEED:
		mount.velocity = mount.velocity.normalized() * MAX_SPEED


