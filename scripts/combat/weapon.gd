extends Node
class_name Weapon

signal fired
signal ammo_changed(current: int)

@export var ammo_max: int = 10
var ammo_current: int = 0
@onready var _logger = get_node("/root/LoggerInstance")

func _ready() -> void:
	ammo_current = ammo_max
	_logger.info("combat", name, "🔫 weapon ready, ammo %d" % ammo_current)

func can_fire() -> bool:
	return ammo_current > 0

func fire(_origin: Node3D) -> void:
	if not can_fire():
		_logger.warn("combat", name, "🧯 cannot fire, no ammo")
		return
	ammo_current -= 1
	emit_signal("ammo_changed", ammo_current)
	emit_signal("fired")
	_logger.info("combat", name, "🔫 fired, ammo %d" % ammo_current)
