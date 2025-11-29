extends Resource
class_name WeaponPoolEntry

## Weapon type identifier (rocket_launcher, mine_layer, autocannon, etc.)
@export var weapon_type: String = "rocket_launcher"
## Level of the weapon to spawn (1 = single weapon, 2 = two stacked, 3 = three stacked, etc.)
## The visual will show this many weapons stacked on top of each other
@export var level: int = 1

func _init(p_weapon_type: String = "rocket_launcher", p_level: int = 1) -> void:
	weapon_type = p_weapon_type
	level = p_level

func _to_string() -> String:
	return "WeaponPoolEntry(type=%s, level=%d)" % [weapon_type, level]

