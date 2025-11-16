extends Weapon
class_name Mines

@export var mine_scene: PackedScene

func fire(origin: Node3D) -> void:
	if not can_fire():
		return
	ammo_current -= 1
	emit_signal("ammo_changed", ammo_current)
	var mine := mine_scene.instantiate() as Node3D
	origin.get_tree().current_scene.add_child(mine)
	mine.global_transform.origin = origin.global_transform.origin - origin.transform.basis.z * 1.5
	emit_signal("fired")
