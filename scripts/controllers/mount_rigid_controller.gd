extends RigidBody3D
class_name MountRigidController

## Forward acceleration force applied when accelerating (units: Newtons)
@export var engine_force: float = 1800.0
## Backward deceleration force applied when braking (units: Newtons)
@export var brake_force: float = 2200.0
## Yaw rotation torque applied for turning, scales with forward speed (units: N⋅m)
@export var turn_torque: float = 450.0
## Damping factor to reduce sideways sliding (0.0 = no damping, 1.0 = full damping)
@export var lateral_damping: float = 0.15
## If true, this mount responds to player input actions (accelerate, brake, turn_left, turn_right)
@export var is_player: bool = false

@onready var _services: Node = get_node_or_null("/root/Services")
@onready var _logger = _services.logger() if _services != null else get_node_or_null("/root/LoggerInstance")
@onready var _bus: Node = _services.bus() if _services != null else get_node_or_null("/root/EventBus")
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring_arm: SpringArm3D = $CameraRig/SpringArm3D

func _ready() -> void:
	# Ensure RigidBody3D is in RIGID mode and awake for physics to work
	freeze = false
	sleeping = false
	_logger.info("movement", self, "🎮 rigid ready; is_player=%s, freeze=%s, sleeping=%s" % [str(is_player), str(freeze), str(sleeping)])
	var req := ["accelerate","brake","turn_left","turn_right","camera_reset"]
	for a in req:
		if not InputMap.has_action(a):
			_logger.error("movement", self, "❌ missing InputMap action '%s'" % a)
	if is_player and is_instance_valid(_camera):
		_camera.current = true
	else:
		if is_instance_valid(_camera):
			_camera.current = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Apply simple vehicle-like controls using real forces/torques
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	var throttle: float = 0.0
	if is_player:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		# Camera reset
		if Input.is_action_just_pressed("camera_reset") and is_instance_valid(_spring_arm):
			_spring_arm.rotation = Vector3(-0.174533, 0.0, 0.0)

	# Longitudinal force (forward/backward)
	var long_force: float = 0.0
	if throttle > 0.0:
		long_force = engine_force * throttle
	elif throttle < 0.0:
		long_force = -brake_force * -throttle
	apply_central_force(forward * long_force)

	# Yaw torque for turning (only when there is some forward motion for stability)
	var speed_forward: float = linear_velocity.dot(forward)
	var turn_input: float = 0.0
	if is_player:
		turn_input = Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")
	var yaw_torque: float = turn_torque * turn_input * clamp(speed_forward / 10.0, -1.0, 1.0)
	apply_torque_impulse(Vector3.UP * yaw_torque * state.step)

	# Simple lateral damping to reduce sideways sliding without killing physics feel
	var lateral_speed: float = linear_velocity.dot(right)
	var lateral_impulse: Vector3 = -right * lateral_speed * lateral_damping
	apply_central_impulse(lateral_impulse)

	# Movement breadcrumbs
	if _bus != null:
		_bus.emit_movement_intent(name, speed_forward)
	_logger.debug("movement", self, "📏 v=%.2f yaw=%.2f thr=%.2f" % [speed_forward, yaw_torque, throttle])


