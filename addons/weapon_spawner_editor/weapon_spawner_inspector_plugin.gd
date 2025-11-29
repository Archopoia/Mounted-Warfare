@tool
extends EditorInspectorPlugin

const WeaponPoolPropertyEditor = preload("res://addons/weapon_spawner_editor/weapon_pool_property_editor.gd")

func _can_handle(object: Object) -> bool:
	# Only handle WeaponSpawner nodes
	# Check if the object has the WeaponSpawner script attached
	if object.get_script() == null:
		return false
	
	var script: Script = object.get_script()
	if script == null:
		return false
	
	# Check script path
	var script_path: String = script.resource_path
	if script_path.is_empty():
		return false
	
	# Check if it's the weapon_spawner script
	var is_weapon_spawner: bool = script_path.ends_with("weapon_spawner.gd")
	if is_weapon_spawner:
		print("Weapon Spawner Inspector Plugin: Handling object with script: %s" % script_path)
	return is_weapon_spawner

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: PropertyUsageFlags, wide: bool) -> bool:
	# Only handle the weapon_pool property
	if name == "weapon_pool":
		print("Weapon Spawner Inspector Plugin: Parsing property 'weapon_pool'")
		var editor = WeaponPoolPropertyEditor.new()
		add_property_editor(name, editor)
		return true
	return false

