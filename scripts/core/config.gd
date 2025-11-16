extends Node
class_name GameConfig

@export var default_player_group: String = "players"
@export var default_weapon_group: String = "weapons"
@export var enable_throttled_debug: bool = true

var categories := {
	"movement": true,
	"combat": true,
	"projectile": true,
	"pickup": true,
	"progression": true,
	"health": true,
	"ai": true,
	"scene": true
}

func is_category_enabled(name: String) -> bool:
	return bool(categories.get(name, false))

func set_category(name: String, enabled: bool) -> void:
	categories[name] = enabled
