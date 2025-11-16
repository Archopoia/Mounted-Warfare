extends RefCounted
class_name WeaponRegistry

## Registry of weapon definitions including visual scenes, colors, and ammo
static var weapon_definitions: Dictionary = {
	"rocket_launcher": {
		"scene_path": "res://scenes/weapons/rocket_launcher.tscn",
		"color": Color(1.0, 0.5, 0.0, 1.0),  # Orange
		"name": "Rocket Launcher",
		"max_ammo": 30,  # 30 rockets
		"projectile_count": 1  # 1 projectile per shot
	},
	"mine_layer": {
		"scene_path": "res://scenes/weapons/mine_layer.tscn",
		"color": Color(0.0, 0.8, 1.0, 1.0),  # Cyan
		"name": "Mine Layer",
		"max_ammo": 20,  # 20 mines
		"projectile_count": 1  # 1 projectile per shot
	},
	"autocannon": {
		"scene_path": "res://scenes/weapons/autocannon.tscn",
		"color": Color(1.0, 0.0, 0.5, 1.0),  # Magenta
		"name": "Autocannon",
		"max_ammo": 150,  # 150 rounds (50 shots × 3 projectiles)
		"projectile_count": 3  # 3 projectiles per shot (burst)
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

static func get_projectile_scene_path(weapon_type: String) -> String:
	# Map weapon types to their projectile scenes
	var projectile_map := {
		"rocket_launcher": "res://scenes/projectiles/rocket_projectile.tscn",
		"mine_layer": "res://scenes/projectiles/mine_projectile.tscn",
		"autocannon": "res://scenes/projectiles/autocannon_projectile.tscn"
	}
	
	if projectile_map.has(weapon_type):
		return projectile_map[weapon_type]
	return "res://scenes/projectiles/rocket_projectile.tscn"  # Default fallback

## Get maximum ammo for a weapon type
static func get_max_ammo(weapon_type: String) -> int:
	if weapon_definitions.has(weapon_type):
		return weapon_definitions[weapon_type]["max_ammo"]
	return 30  # Default fallback

## Get projectile count per shot for a weapon type
static func get_projectile_count(weapon_type: String) -> int:
	if weapon_definitions.has(weapon_type):
		return weapon_definitions[weapon_type]["projectile_count"]
	return 1  # Default fallback

