@tool
extends EditorPlugin

const WeaponSpawnerInspectorPlugin = preload("res://addons/weapon_spawner_editor/weapon_spawner_inspector_plugin.gd")

var inspector_plugin: EditorInspectorPlugin

func _enter_tree() -> void:
	inspector_plugin = WeaponSpawnerInspectorPlugin.new()
	add_inspector_plugin(inspector_plugin)

func _exit_tree() -> void:
	if inspector_plugin:
		remove_inspector_plugin(inspector_plugin)
		inspector_plugin = null

