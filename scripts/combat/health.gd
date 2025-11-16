extends Node
class_name Health

signal health_changed(mount_hp: float, rider_hp: float)

@export var mount_hp_max: float = 200.0
@export var rider_hp_max: float = 100.0
@export var armor: float = 0.1

var mount_hp: float
var rider_hp: float

func _ready() -> void:
	mount_hp = mount_hp_max
	rider_hp = rider_hp_max
	emit_signal("health_changed", mount_hp, rider_hp)
	LoggerInstance.info("health", name, "❤️ initialized mount=%d rider=%d" % [int(mount_hp), int(rider_hp)])

func apply_damage(value: float, hit_rider: bool = false) -> void:
	var effective: float = float(max(0.0, value * (1.0 - armor)))
	if hit_rider:
		var before := rider_hp
		rider_hp = max(0.0, rider_hp - effective)
		LoggerInstance.stat_delta("health", name, "rider_hp", before, rider_hp, "❤️")
	else:
		var beforem := mount_hp
		mount_hp = max(0.0, mount_hp - effective)
		LoggerInstance.stat_delta("health", name, "mount_hp", beforem, mount_hp, "❤️")
	emit_signal("health_changed", mount_hp, rider_hp)
