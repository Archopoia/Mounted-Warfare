extends RigidBody3D
class_name MountController

## Stride force applied when the mount moves forward (units: Newtons)
@export var stride_force: float = 1800.0
## Halt force applied when the mount stops or reverses (units: Newtons)
@export var halt_force: float = 2200.0
## Steer torque applied for turning, scales with forward speed (units: N⋅m)
@export var steer_torque: float = 450.0
## Balance factor to reduce sideways sliding (0.0 = no balance, 1.0 = full balance)
@export var balance_factor: float = 0.15
## If true, this mount responds to player input actions (accelerate, brake, turn_left, turn_right)
@export var is_player: bool = false

@onready var _services: Node = get_node_or_null("/root/Services")
@onready var _logger = _services.logger() if _services != null else get_node_or_null("/root/LoggerInstance")
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var _weapon_marker_left: Marker3D = $WeaponMarkerLeft
@onready var _weapon_marker_right: Marker3D = $WeaponMarkerRight

var _attached_weapons: Array[WeaponAttachment] = []
var _weapon_hud: WeaponReplacementHUD = null
var _weapon_display_hud: WeaponDisplayHUD = null
var _pending_weapon_type: String = ""
var _pending_weapon_color: Color = Color.WHITE

func _ready() -> void:
	# Ensure RigidBody3D is in RIGID mode and awake for physics to work
	freeze = false
	sleeping = false
	_logger.info("movement", self, "🎮 mount ready; is_player=%s, freeze=%s, sleeping=%s" % [str(is_player), str(freeze), str(sleeping)])
	var req := ["accelerate","brake","turn_left","turn_right","camera_reset"]
	for a in req:
		if not InputMap.has_action(a):
			_logger.error("movement", self, "❌ missing InputMap action '%s'" % a)
	
	# Check for weapon input actions
	var weapon_actions := ["fire_primary", "fire_alt"]
	for a in weapon_actions:
		if not InputMap.has_action(a):
			_logger.error("weapon", self, "❌ missing InputMap action '%s'" % a)
	if is_player and is_instance_valid(_camera):
		_camera.current = true
	else:
		if is_instance_valid(_camera):
			_camera.current = false
	
	# Connect to weapon pickups in the scene (deferred to ensure scene tree is fully built)
	call_deferred("_connect_to_weapon_pickups")
	
	# Create HUD for player mount
	if is_player:
		call_deferred("_create_hud")

func _connect_to_weapon_pickups() -> void:
	# Find all weapon pickups in the scene and connect to their signals
	var weapon_pickups: Array[Node] = get_tree().get_nodes_in_group("weapon_pickups")
	if weapon_pickups.is_empty():
		# If no group, search for WeaponPickup nodes manually
		weapon_pickups = _find_weapon_pickups_recursive(get_tree().root)
	
	for pickup in weapon_pickups:
		if pickup is WeaponPickup:
			var pickup_node: WeaponPickup = pickup as WeaponPickup
			if not pickup_node.weapon_picked_up.is_connected(_on_weapon_picked_up):
				pickup_node.weapon_picked_up.connect(_on_weapon_picked_up)
				_logger.debug("weapon", self, "🔌 connected to weapon pickup: %s" % pickup_node.name)

func _find_weapon_pickups_recursive(node: Node) -> Array[Node]:
	var pickups: Array[Node] = []
	if node is WeaponPickup:
		pickups.append(node)
	
	for child in node.get_children():
		pickups.append_array(_find_weapon_pickups_recursive(child))
	
	return pickups

func _on_weapon_picked_up(pickup: WeaponPickup, mount: Node, weapon_type: String) -> void:
	# Only attach if this weapon was picked up by THIS mount
	if mount != self:
		return
	
	# Check if both slots are full
	var left_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_left)
	var right_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_right)
	
	if left_weapon != null and right_weapon != null:
		# Both slots are full - show replacement prompt for player
		if is_player and _weapon_hud != null:
			_pending_weapon_type = weapon_type
			_pending_weapon_color = pickup.pickup_color
			_weapon_hud.show_replacement_prompt(weapon_type, pickup.pickup_color, left_weapon.weapon_type, right_weapon.weapon_type)
			_logger.info("weapon", self, "📋 showing replacement prompt for: %s" % weapon_type)
			return
		else:
			# For non-player mounts, replace the left weapon automatically
			_logger.info("weapon", self, "🤖 auto-replacing left weapon with: %s" % weapon_type)
			replace_weapon_in_slot(1, weapon_type, pickup.pickup_color)
			return
	
	# Find an available weapon marker
	var marker: Marker3D = null
	if _weapon_marker_left != null and _weapon_marker_left.get_child_count() == 0:
		marker = _weapon_marker_left
	elif _weapon_marker_right != null and _weapon_marker_right.get_child_count() == 0:
		marker = _weapon_marker_right
	
	if marker == null:
		_logger.error("weapon", self, "❌ No weapon markers available for weapon attachment")
		return
	
	# Create and attach the weapon
	_attach_weapon(weapon_type, pickup.pickup_color, marker)

func _attach_weapon(weapon_type: String, weapon_color: Color, marker: Marker3D) -> void:
	# Load the appropriate weapon scene for this weapon type
	var weapon_scene_path: String = WeaponRegistry.get_weapon_scene_path(weapon_type)
	var weapon_scene: PackedScene = load(weapon_scene_path)
	
	if weapon_scene == null:
		_logger.error("weapon", self, "❌ Failed to load weapon scene: %s" % weapon_scene_path)
		return
	
	# Instantiate the weapon
	var weapon_instance: Node = weapon_scene.instantiate()
	if weapon_instance == null or not weapon_instance is WeaponAttachment:
		_logger.error("weapon", self, "❌ Failed to instantiate weapon attachment")
		return
	
	var weapon: WeaponAttachment = weapon_instance as WeaponAttachment
	weapon.weapon_type = weapon_type
	# Use color from registry if not provided
	if weapon_color == Color.WHITE:
		weapon.weapon_color = WeaponRegistry.get_weapon_color(weapon_type)
	else:
		weapon.weapon_color = weapon_color
	
	# Initialize ammo to full capacity
	weapon.max_ammo = WeaponRegistry.get_max_ammo(weapon_type)
	weapon.current_ammo = weapon.max_ammo
	
	# Signals will be connected in _update_display_hud() after attachment
	
	# Add to scene tree first (required for reparenting)
	get_tree().root.add_child(weapon)
	
	# Attach to the marker
	weapon.attach_to_mount(self, marker)
	
	# Track the weapon
	_attached_weapons.append(weapon)
	
	# Update display HUD
	_update_display_hud()
	
	_logger.info("weapon", self, "⚔️ weapon attached: type=%s, color=%s, marker=%s, ammo=%d/%d" % [weapon_type, weapon.weapon_color, marker.name, weapon.current_ammo, weapon.max_ammo])

func _create_hud() -> void:
	if not is_player:
		return
	
	# Create CanvasLayer for HUD
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	canvas_layer.name = "HUD"
	get_tree().root.add_child(canvas_layer)
	
	# Create permanent weapon display HUD
	var display_hud_scene: PackedScene = load("res://scenes/ui/weapon_display_hud.tscn")
	if display_hud_scene == null:
		_logger.error("ui", self, "❌ Failed to load weapon display HUD scene")
		return
	
	var display_hud_instance: Node = display_hud_scene.instantiate()
	if display_hud_instance == null or not display_hud_instance is WeaponDisplayHUD:
		_logger.error("ui", self, "❌ Failed to instantiate weapon display HUD")
		return
	
	_weapon_display_hud = display_hud_instance as WeaponDisplayHUD
	_weapon_display_hud.mount_controller = self
	canvas_layer.add_child(_weapon_display_hud)
	
	# Create replacement prompt HUD
	var replacement_hud_scene: PackedScene = load("res://scenes/ui/weapon_replacement_hud.tscn")
	if replacement_hud_scene == null:
		_logger.error("ui", self, "❌ Failed to load weapon replacement HUD scene")
		return
	
	var replacement_hud_instance: Node = replacement_hud_scene.instantiate()
	if replacement_hud_instance == null or not replacement_hud_instance is WeaponReplacementHUD:
		_logger.error("ui", self, "❌ Failed to instantiate weapon replacement HUD")
		return
	
	_weapon_hud = replacement_hud_instance as WeaponReplacementHUD
	_weapon_hud.mount_controller = self
	canvas_layer.add_child(_weapon_hud)
	
	# Initialize display HUD with current weapon state
	call_deferred("_update_display_hud")
	
	_logger.info("ui", self, "📺 HUD created for player mount")

func _get_weapon_at_marker(marker: Marker3D) -> WeaponAttachment:
	if marker == null:
		return null
	
	for child in marker.get_children():
		if child is WeaponAttachment:
			return child as WeaponAttachment
	
	return null

func replace_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	var marker: Marker3D = null
	if slot == 1:
		marker = _weapon_marker_left
	elif slot == 2:
		marker = _weapon_marker_right
	else:
		_logger.error("weapon", self, "❌ Invalid weapon slot: %d" % slot)
		return
	
	if marker == null:
		_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	# Remove existing weapon at this marker
	var existing_weapon: WeaponAttachment = _get_weapon_at_marker(marker)
	if existing_weapon != null:
		existing_weapon.detach_from_mount()
		_attached_weapons.erase(existing_weapon)
	
	# Attach new weapon
	_attach_weapon(weapon_type, weapon_color, marker)
	
	# Update display HUD
	_update_display_hud()
	
	_pending_weapon_type = ""
	_pending_weapon_color = Color.WHITE

func drop_pending_weapon() -> void:
	_logger.info("weapon", self, "🚫 dropped pending weapon: %s" % _pending_weapon_type)
	_pending_weapon_type = ""
	_pending_weapon_color = Color.WHITE

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Apply mount movement controls using real forces/torques
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	var reign_input: float = 0.0
	if is_player:
		reign_input = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		# Camera reset
		if Input.is_action_just_pressed("camera_reset") and is_instance_valid(_spring_arm):
			_spring_arm.rotation = Vector3(-0.174533, 0.0, 0.0)

	# Forward/backward stride force
	var stride_force_applied: float = 0.0
	if reign_input > 0.0:
		stride_force_applied = stride_force * reign_input
	elif reign_input < 0.0:
		stride_force_applied = -halt_force * -reign_input
	apply_central_force(forward * stride_force_applied)

	# Steer torque for turning (only when there is some forward motion for balance)
	var gallop_speed: float = linear_velocity.dot(forward)
	var steer_input: float = 0.0
	if is_player:
		steer_input = Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")
	var steer_torque_applied: float = steer_torque * steer_input * clamp(gallop_speed / 10.0, -1.0, 1.0)
	apply_torque_impulse(Vector3.UP * steer_torque_applied * state.step)

	# Balance damping to reduce sideways sliding without killing physics feel
	var drift_speed: float = linear_velocity.dot(right)
	var balance_impulse: Vector3 = -right * drift_speed * balance_factor
	apply_central_impulse(balance_impulse)

	# Movement breadcrumbs
	#if _bus != null:
		#_bus.emit_movement_intent(name, gallop_speed)
	#_logger.debug("movement", self, "📏 v=%.2f steer=%.2f reign=%.2f" % [gallop_speed, steer_torque_applied, reign_input])

func _input(event: InputEvent) -> void:
	# Only handle weapon input for player mounts
	if not is_player:
		return
	
	# Check for weapon attacks via mouse clicks
	# Left mouse button (MOUSE_BUTTON_LEFT = 1) fires left weapon
	# Right mouse button (MOUSE_BUTTON_RIGHT = 2) fires right weapon
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_logger.debug("weapon", self, "🖱️ left mouse button pressed")
			_attack_with_left_weapon()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_logger.debug("weapon", self, "🖱️ right mouse button pressed")
			_attack_with_right_weapon()

func _attack_with_left_weapon() -> void:
	if _weapon_marker_left == null:
		_logger.debug("weapon", self, "⚠️ cannot attack: left weapon marker is null")
		return
	
	var left_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_left)
	if left_weapon == null:
		_logger.debug("weapon", self, "⚠️ cannot attack: no weapon attached to left marker")
		return
	
	if not is_instance_valid(left_weapon):
		_logger.error("weapon", self, "❌ cannot attack: left weapon is not valid")
		return
	
	_logger.info("weapon", self, "🎯 left mouse click detected - attacking with left weapon")
	left_weapon.attack()

func _attack_with_right_weapon() -> void:
	if _weapon_marker_right == null:
		_logger.debug("weapon", self, "⚠️ cannot attack: right weapon marker is null")
		return
	
	var right_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_right)
	if right_weapon == null:
		_logger.debug("weapon", self, "⚠️ cannot attack: no weapon attached to right marker")
		return
	
	if not is_instance_valid(right_weapon):
		_logger.error("weapon", self, "❌ cannot attack: right weapon is not valid")
		return
	
	_logger.info("weapon", self, "🎯 right mouse click detected - attacking with right weapon")
	right_weapon.attack()

func _update_display_hud() -> void:
	if not is_player or _weapon_display_hud == null:
		return
	
	# Update slot 1 (left weapon)
	var left_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_left)
	_weapon_display_hud.update_weapon_slot(1, left_weapon)
	
	# Connect ammo signal if weapon exists
	if left_weapon != null:
		# Disconnect previous connections if any
		if left_weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed):
			left_weapon.ammo_changed.disconnect(_on_left_weapon_ammo_changed)
		if left_weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
			left_weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
		
		# Connect new signals
		left_weapon.ammo_changed.connect(_on_left_weapon_ammo_changed)
		left_weapon.ammo_depleted.connect(_on_weapon_ammo_depleted)
	
	# Update slot 2 (right weapon)
	var right_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_right)
	_weapon_display_hud.update_weapon_slot(2, right_weapon)
	
	# Connect ammo signal if weapon exists
	if right_weapon != null:
		# Disconnect previous connections if any
		if right_weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
			right_weapon.ammo_changed.disconnect(_on_right_weapon_ammo_changed)
		if right_weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
			right_weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
		
		# Connect new signals
		right_weapon.ammo_changed.connect(_on_right_weapon_ammo_changed)
		right_weapon.ammo_depleted.connect(_on_weapon_ammo_depleted)

func _on_left_weapon_ammo_changed(new_ammo: int, max_ammo: int) -> void:
	if not is_player or _weapon_display_hud == null:
		return
	_weapon_display_hud.update_weapon_ammo(1, new_ammo, max_ammo)
	_logger.debug("weapon", self, "📊 ammo updated: slot=1, ammo=%d/%d" % [new_ammo, max_ammo])

func _on_right_weapon_ammo_changed(new_ammo: int, max_ammo: int) -> void:
	if not is_player or _weapon_display_hud == null:
		return
	_weapon_display_hud.update_weapon_ammo(2, new_ammo, max_ammo)
	_logger.debug("weapon", self, "📊 ammo updated: slot=2, ammo=%d/%d" % [new_ammo, max_ammo])

func _on_weapon_ammo_depleted(weapon_type: String) -> void:
	_logger.info("weapon", self, "⚠️ weapon ammo depleted: %s" % weapon_type)
