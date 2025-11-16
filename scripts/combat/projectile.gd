extends Area3D
class_name Projectile

@export var speed: float = 40.0
@export var gravity_accel: float = 0.0
@export var life_time: float = 4.0
@export var damage: float = 30.0
@export var splash_radius: float = 0.0

var _vel: Vector3
@onready var _logger = get_node("/root/LoggerInstance")

func _ready() -> void:
	_vel = -transform.basis.z * speed
	connect("body_entered", Callable(self, "_on_body_entered"))
	set_physics_process(true)
	await get_tree().create_timer(life_time).timeout
	_queue_explode()

func _physics_process(delta: float) -> void:
	_vel.y -= gravity_accel * delta
	global_transform.origin += _vel * delta

func _on_body_entered(_body: Node) -> void:
	_logger.info("projectile", name, "💥 hit body, exploding")
	_queue_explode()

func _queue_explode() -> void:
	# TODO: apply damage in radius
	_logger.info("projectile", name, "💥 explode | splash_radius=%.2f damage=%.2f" % [splash_radius, damage])
	queue_free()
