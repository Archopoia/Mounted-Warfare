extends Weapon
class_name RocketLauncher

@export var projectile_scene: PackedScene
@export var lock_on: bool = true

func fire(origin: Node3D) -> void:
	if not can_fire():
		return
	ammo_current -= 1
	emit_signal("ammo_changed", ammo_current)
	var proj := projectile_scene.instantiate() as Node3D
	origin.add_child(proj)
	proj.global_transform = origin.global_transform
	emit_signal("fired")
