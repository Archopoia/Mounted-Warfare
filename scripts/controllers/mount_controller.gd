extends CharacterBody3D
class_name MountController

@export var max_speed: float = 14.0
@export var acceleration: float = 30.0
@export var turn_speed_deg: float = 90.0
@export var drift_factor: float = 0.1
@onready var camera_spring: SpringArm3D = $SpringArm3D
@onready var _logger = get_node("/root/LoggerInstance")

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = _get_input_vector()
	if input_dir == Vector2.ZERO:
		_logger.debug("movement", name, "👣 idle input")
	_apply_movement(input_dir, delta)
	move_and_slide()

func _get_input_vector() -> Vector2:
	var f: float = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	var t: float = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	return Vector2(t, f)

func _apply_movement(input_dir: Vector2, delta: float) -> void:
	rotation.y += deg_to_rad(input_dir.x * turn_speed_deg) * delta
	var forward: Vector3 = -transform.basis.z
	var target_speed: float = input_dir.y * max_speed
	var current_speed: float = velocity.dot(forward)
	var max_delta: float = acceleration * delta
	var speed_delta: float = clamp(target_speed - current_speed, -max_delta, max_delta)
	velocity += forward * speed_delta
	# simple drift damping
	var lateral: Vector3 = velocity - forward * velocity.dot(forward)
	velocity -= lateral * drift_factor
	_logger.debug("movement", name, "📏 speed %.2f → %.2f, turn %.2f" % [current_speed, velocity.dot(forward), input_dir.x])
