extends RefCounted
class_name WeaponRegistry

## Registry of weapon definitions including visual scenes and colors
static var weapon_definitions: Dictionary = {
	"rocket_launcher": {
		"scene_path": "res://scenes/weapons/rocket_launcher.tscn",
		"color": Color(1.0, 0.5, 0.0, 1.0),  # Orange
		"name": "Rocket Launcher"
	},
	"mine_layer": {
		"scene_path": "res://scenes/weapons/mine_layer.tscn",
		"color": Color(0.0, 0.8, 1.0, 1.0),  # Cyan
		"name": "Mine Layer"
	},
	"autocannon": {
		"scene_path": "res://scenes/weapons/autocannon.tscn",
		"color": Color(1.0, 0.0, 0.5, 1.0),  # Magenta
		"name": "Autocannon"
	}
}

static func get_weapon_scene_path(weapon_type: String) -> String:
	if weapon_definitions.has(weapon_type):
		return weapon_definitions[weapon_type]["scene_path"]
	return "res://scenes/weapons/rocket_launcher.tscn"  # Default fallback

static func get_weapon_color(weapon_type: String) -> Color:
	if weapon_definitions.has(weapon_type):
		return weapon_definitions[weapon_type]["color"]
	return Color.WHITE  # Default fallback

static func get_weapon_name(weapon_type: String) -> String:
	if weapon_definitions.has(weapon_type):
		return weapon_definitions[weapon_type]["name"]
	return weapon_type.replace("_", " ").capitalize()

