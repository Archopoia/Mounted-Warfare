extends Node
class_name Weapon

signal fired
signal ammo_changed(current: int)

@export var ammo_max: int = 10
var ammo_current: int = 0
@onready var _services: Node = get_node_or_null("/root/Services")
@onready var _logger = _services.logger() if _services != null else get_node_or_null("/root/LoggerInstance")
@onready var _bus: Node = _services.bus() if _services != null else get_node_or_null("/root/EventBus")

func _ready() -> void:
	ammo_current = ammo_max
	if ammo_max < 0:
		_logger.warn("combat", self, "ammo_max was negative; clamping to 0")
		ammo_max = 0
	ammo_current = clamp(ammo_current, 0, ammo_max)
	_logger.info("combat", self, "🔫 weapon ready, ammo %d" % ammo_current)

func can_fire() -> bool:
	return ammo_current > 0

func fire(_origin: Node3D) -> void:
	if _origin == null:
		_logger.error("combat", self, "fire() called with null origin")
		return
	if not (_origin is Node3D):
		_logger.error("combat", self, "fire() origin is not Node3D")
		return
	if not can_fire():
		_logger.warn("combat", self, "🧯 cannot fire, no ammo")
		return
	ammo_current -= 1
	if ammo_current < 0:
		_logger.error("combat", self, "Ammo underflow detected; correcting to 0")
		ammo_current = 0
	emit_signal("ammo_changed", ammo_current)
	emit_signal("fired")
	# Global bus for decoupled subscribers (e.g., HUD)
	if _bus:
		_bus.emit_ammo_changed(self, ammo_current)
		_bus.emit_weapon_fired(self)
	_logger.info("combat", self, "🔫 fired, ammo %d" % ammo_current)
