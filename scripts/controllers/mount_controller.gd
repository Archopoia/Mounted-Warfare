extends RigidBody3D
class_name MountController

## Stride force applied when the mount moves forward (units: Newtons)
@export var stride_force: float = 1800.0
## Halt force applied when the mount stops or reverses (units: Newtons)
@export var halt_force: float = 2200.0
## Steer torque applied for turning, scales with forward speed (units: N⋅m)
@export var steer_torque: float = 450.0
## Balance factor to reduce sideways sliding (0.0 = no balance, 1.0 = full balance)
@export var balance_factor: float = 0.15
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
	_logger.info("movement", self, "🎮 mount ready; is_player=%s, freeze=%s, sleeping=%s" % [str(is_player), str(freeze), str(sleeping)])
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
	# Apply mount movement controls using real forces/torques
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	var reign_input: float = 0.0
	if is_player:
		reign_input = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		# Camera reset
		if Input.is_action_just_pressed("camera_reset") and is_instance_valid(_spring_arm):
			_spring_arm.rotation = Vector3(-0.174533, 0.0, 0.0)

	# Forward/backward stride force
	var stride_force_applied: float = 0.0
	if reign_input > 0.0:
		stride_force_applied = stride_force * reign_input
	elif reign_input < 0.0:
		stride_force_applied = -halt_force * -reign_input
	apply_central_force(forward * stride_force_applied)

	# Steer torque for turning (only when there is some forward motion for balance)
	var gallop_speed: float = linear_velocity.dot(forward)
	var steer_input: float = 0.0
	if is_player:
		steer_input = Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")
	var steer_torque_applied: float = steer_torque * steer_input * clamp(gallop_speed / 10.0, -1.0, 1.0)
	apply_torque_impulse(Vector3.UP * steer_torque_applied * state.step)

	# Balance damping to reduce sideways sliding without killing physics feel
	var drift_speed: float = linear_velocity.dot(right)
	var balance_impulse: Vector3 = -right * drift_speed * balance_factor
	apply_central_impulse(balance_impulse)

	# Movement breadcrumbs
	if _bus != null:
		_bus.emit_movement_intent(name, gallop_speed)
	_logger.debug("movement", self, "📏 v=%.2f steer=%.2f reign=%.2f" % [gallop_speed, steer_torque_applied, reign_input])


