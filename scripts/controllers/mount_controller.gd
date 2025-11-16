extends CharacterBody3D
class_name MountController

@export var max_speed: float = 14.0
@export var acceleration: float = 30.0
@export var turn_speed_deg: float = 90.0
@export var drift_factor: float = 0.1
@export var gravity_accel: float = 24.8
@export var is_player: bool = false
@onready var _logger = get_node("/root/LoggerInstance")
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring_arm: SpringArm3D = $CameraRig/SpringArm3D

func _ready() -> void:
	if is_player and is_instance_valid(_camera):
		_camera.current = true
	else:
		if is_instance_valid(_camera):
			_camera.current = false

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = _get_input_vector()
	if input_dir == Vector2.ZERO:
		_logger.debug("movement", name, "👣 idle input")
	_apply_movement(input_dir, delta)
	# camera reset
	if is_player and Input.is_action_just_pressed("camera_reset") and is_instance_valid(_spring_arm):
		_spring_arm.rotation = Vector3(-0.174533, 0.0, 0.0)
	# apply gravity
	if not is_on_floor():
		velocity.y -= gravity_accel * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
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
	var horiz_vel: Vector3 = velocity
	horiz_vel += forward * speed_delta
	# simple drift damping
	var lateral: Vector3 = horiz_vel - forward * horiz_vel.dot(forward)
	horiz_vel -= lateral * drift_factor
	# preserve vertical velocity component
	velocity.x = horiz_vel.x
	velocity.z = horiz_vel.z
	_logger.debug("movement", name, "📏 speed %.2f → %.2f, turn %.2f" % [current_speed, horiz_vel.dot(forward), input_dir.x])
