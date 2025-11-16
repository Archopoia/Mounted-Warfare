extends CharacterBody3D
class_name MountController

@export var max_speed: float = 14.0
@export var acceleration: float = 30.0
@export var turn_speed_deg: float = 90.0
@export var drift_factor: float = 0.1
@export var gravity_accel: float = 24.8
@export var is_player: bool = false
@onready var _services: Node = get_node_or_null("/root/Services")
@onready var _logger = _services.logger() if _services != null else get_node_or_null("/root/LoggerInstance")
@onready var _bus: Node = _services.bus() if _services != null else get_node_or_null("/root/EventBus")
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring_arm: SpringArm3D = $CameraRig/SpringArm3D

func _ready() -> void:
	_logger.info("movement", self, "🎮 ready; is_player=%s" % [str(is_player)])
	# Verify input actions exist (once)
	var req := ["accelerate","brake","turn_left","turn_right","camera_reset"]
	for a in req:
		if not InputMap.has_action(a):
			_logger.error("movement", self, "❌ missing InputMap action '%s'" % a)
	if is_player and is_instance_valid(_camera):
		_camera.current = true
	else:
		if is_instance_valid(_camera):
			_camera.current = false

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = _get_input_vector()
	if input_dir == Vector2.ZERO:
		_logger.debug("movement", name, "👣 idle input")
	# apply player-controlled movement only for player
	if is_player:
		_apply_movement(input_dir, delta)
		if _bus:
			var forward: Vector3 = -transform.basis.z
			var speed: float = velocity.dot(forward)
			_bus.emit_movement_intent(name, speed)
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
	if not is_player:
		return Vector2.ZERO
	if not (InputMap.has_action("accelerate") and InputMap.has_action("brake") and InputMap.has_action("turn_left") and InputMap.has_action("turn_right")):
		_logger.error("movement", self, "❌ input actions not configured; cannot move")
		return Vector2.ZERO
	var f: float = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	var t: float = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	if f == 0.0 and t == 0.0:
		# Log when player is pressing nothing or mapping broken
		if is_player:
			_logger.debug("movement", self, "👣 no input (WASD idle or unmapped)")
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
	_logger.debug("movement", self, "📏 speed %.2f → %.2f, turn %.2f" % [current_speed, horiz_vel.dot(forward), input_dir.x])
