extends Node
class_name TeamColor

@export var color: Color = Color(1, 1, 1, 1)

func _ready() -> void:
	var mount := get_parent()
	if mount == null:
		return
	var mesh: MeshInstance3D = mount.get_node_or_null("BodyMesh")
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
