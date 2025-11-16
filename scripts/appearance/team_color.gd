extends Node
class_name TeamColor

@export var color: Color = Color(1, 1, 1, 1)
@onready var _logger = get_node("/root/LoggerInstance")

func _ready() -> void:
	var mount: Node = get_parent()
	if mount == null:
		_logger.error("scene", self, "TeamColor has no parent; cannot apply color")
		return
	var mesh: MeshInstance3D = mount.get_node_or_null("BodyMesh")
	if mesh == null:
		_logger.warn("scene", self, "BodyMesh node not found on '%s'; color not applied" % mount.name)
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	_logger.info("scene", self, "Applied team color %s to %s" % [str(color), mount.name])
