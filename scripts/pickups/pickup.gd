extends Area3D
class_name Pickup

@export var pickup_type: String = "ammo"
@export var value: int = 10
signal collected

@onready var _logger = get_node("/root/LoggerInstance")

func _ready() -> void:
	connect("body_entered", Callable(self, "_on_body_entered"))
	_logger.info("pickup", name, "🎁 spawned type=%s value=%d" % [pickup_type, value])

func _on_body_entered(_body: Node) -> void:
	_logger.info("pickup", name, "🎁 collected type=%s value=%d" % [pickup_type, value])
	emit_signal("collected")
	queue_free()
