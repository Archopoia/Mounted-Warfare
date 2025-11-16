extends Label3D
class_name HealthLabel3D

@export var target_health_path: NodePath = NodePath("../Health")
@onready var _health: Health = get_node_or_null(target_health_path) as Health

func _ready() -> void:
	visible = true
	# Improve readability in world
	pixel_size = 0.005
	modulate = Color(0.9, 0.2, 0.2, 1.0)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _health and _health.has_signal("health_changed"):
		_health.connect("health_changed", Callable(self, "_on_health_changed"))
		_on_health_changed(_health.mount_hp, _health.rider_hp)
	else:
		text = "HP:?/%?"

func _on_health_changed(mount_hp: float, _rider_hp: float) -> void:
	var max_hp: float = _health.mount_hp_max if _health != null else mount_hp
	text = "HP:%d/%d" % [int(mount_hp), int(max_hp)]
