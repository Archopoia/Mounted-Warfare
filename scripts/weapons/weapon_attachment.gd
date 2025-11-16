extends Node3D
class_name WeaponAttachment

## Weapon type identifier (rocket_launcher, mine_layer, autocannon, etc.)
@export var weapon_type: String = "rocket_launcher"
## Weapon display name
@export var weapon_name: String = "Rocket Launcher"
## Color for the weapon visual representation
@export var weapon_color: Color = Color(1.0, 0.5, 0.0, 1.0)
## Weapon size scale (for visual representation)
@export var weapon_scale: float = 0.5

var _logger: Node
var _attached_to_mount: Node = null

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	_update_visuals()
	_logger.info("weapon", self, "⚔️ weapon attachment ready: type=%s" % weapon_type)

func _update_visuals() -> void:
	# Update material colors for all mesh instances to match weapon color
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = weapon_color
	material.emission_enabled = true
	material.emission = weapon_color * 0.3
	
	# Update all MeshInstance3D children to use the weapon color
	for child in get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.set_surface_override_material(0, material)

func attach_to_mount(mount: Node, marker: Marker3D) -> void:
	if _attached_to_mount != null:
		_logger.warn("weapon", self, "⚠️ weapon already attached to mount")
		return
	
	if marker == null:
		_logger.error("weapon", self, "❌ Failed to attach weapon: marker is null")
		return
	
	_attached_to_mount = mount
	
	# Reparent to the marker node
	if is_inside_tree():
		var old_parent: Node = get_parent()
		if old_parent != null:
			old_parent.remove_child(self)
	
	marker.add_child(self)
	
	# Reset transform to be relative to marker (weapon should be at marker origin)
	transform = Transform3D.IDENTITY
	
	_logger.info("weapon", self, "🔗 weapon attached to mount: type=%s, marker=%s" % [weapon_type, marker.name])

func detach_from_mount() -> void:
	if _attached_to_mount == null:
		return
	
	_logger.info("weapon", self, "🔓 weapon detached from mount: type=%s" % weapon_type)
	_attached_to_mount = null
	
	# Remove weapon from scene
	queue_free()

