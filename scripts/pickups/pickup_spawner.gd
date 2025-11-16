extends Node3D
class_name PickupSpawner

@export var respawn_time: float = 10.0
@export var pickup_scene: PackedScene

var _cooling_down := false

func spawn_now() -> void:
	if _cooling_down or pickup_scene == null:
		return
	var p := pickup_scene.instantiate()
	add_child(p)
	p.global_transform = global_transform
	p.connect("collected", Callable(self, "_on_pickup_collected"))

func _on_pickup_collected() -> void:
	_cooling_down = true
	await get_tree().create_timer(respawn_time).timeout
	_cooling_down = false
	spawn_now()

func _ready() -> void:
	spawn_now()
