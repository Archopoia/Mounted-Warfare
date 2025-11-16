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
	_setup_visuals()
	_logger.info("weapon", self, "⚔️ weapon attachment ready: type=%s" % weapon_type)

func _setup_visuals() -> void:
	# Create a simple visual representation for the weapon
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
	
	# Create a cylinder mesh for weapon representation (looks like a cannon/launcher)
	var cylinder_mesh: CylinderMesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.15 * weapon_scale
	cylinder_mesh.bottom_radius = 0.15 * weapon_scale
	cylinder_mesh.height = 0.8 * weapon_scale
	mesh_instance.mesh = cylinder_mesh
	
	# Create material with weapon color
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = weapon_color
	material.emission_enabled = true
	material.emission = weapon_color * 0.3
	mesh_instance.set_surface_override_material(0, material)
	
	# Rotate weapon to point forward (cylinder is vertical by default)
	mesh_instance.rotation_degrees = Vector3(0, 0, 90)
	
	# Position slightly forward from marker center
	mesh_instance.position = Vector3(0, 0, 0.2)

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

