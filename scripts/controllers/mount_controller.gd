extends RigidBody3D
class_name MountController

# Preload helper classes
const WeaponSlotConstantsClass = preload("res://scripts/controllers/weapon_slot_constants.gd")
const WeaponSlotManagerClass = preload("res://scripts/controllers/weapon_slot_manager.gd")
const WeaponPickupHandlerClass = preload("res://scripts/controllers/weapon_pickup_handler.gd")
# Preload component classes
const WeaponManagerClass = preload("res://scripts/controllers/components/weapon_manager.gd")
const WeaponInputHandlerClass = preload("res://scripts/controllers/components/weapon_input_handler.gd")
const WeaponHUDManagerClass = preload("res://scripts/controllers/components/weapon_hud_manager.gd")
const WeaponAttackCoordinatorClass = preload("res://scripts/controllers/components/weapon_attack_coordinator.gd")

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

# Component managers
var _slot_manager: WeaponSlotManagerClass = null
var _pickup_handler: WeaponPickupHandlerClass = null
var _weapon_manager: WeaponManagerClass = null
var _input_handler: WeaponInputHandlerClass = null
var _hud_manager: WeaponHUDManagerClass = null
var _attack_coordinator: WeaponAttackCoordinatorClass = null

# Pending weapon data for pickup prompts
var _pending_weapon_type: String = ""
var _pending_weapon_color: Color = Color.WHITE
var _pending_weapon_level: int = 1

func _ready() -> void:
	# Ensure RigidBody3D is in RIGID mode and awake for physics to work
	freeze = false
	sleeping = false
	_logger.info("movement", self, "🎮 mount ready; is_player=%s, freeze=%s, sleeping=%s" % [str(is_player), str(freeze), str(sleeping)])
	
	# Validate input actions
	var req := ["accelerate","brake","turn_left","turn_right","camera_reset"]
	for a in req:
		if not InputMap.has_action(a):
			_logger.error("movement", self, "❌ missing InputMap action '%s'" % a)
	
	var weapon_actions := ["fire_primary", "fire_alt"]
	for a in weapon_actions:
		if not InputMap.has_action(a):
			_logger.error("weapon", self, "❌ missing InputMap action '%s'" % a)
	
	# Setup camera
	if is_player and is_instance_valid(_camera):
		_camera.current = true
	else:
		if is_instance_valid(_camera):
			_camera.current = false
	
	# Initialize component managers
	_initialize_components()
	
	# Connect to weapon pickups in the scene (deferred to ensure scene tree is fully built)
	call_deferred("_connect_to_weapon_pickups")
	
	# Create HUD for player mount
	if is_player:
		call_deferred("_create_hud")

func _initialize_components() -> void:
	# Initialize slot manager
	_slot_manager = WeaponSlotManagerClass.new(self, _weapon_marker_left, _weapon_marker_right, _logger)
	
	# Initialize pickup handler
	_pickup_handler = WeaponPickupHandlerClass.new(self, _slot_manager, _logger)
	
	# Create and initialize component nodes
	_weapon_manager = WeaponManagerClass.new()
	add_child(_weapon_manager)
	_weapon_manager.initialize(self, _slot_manager, _logger)
	
	_input_handler = WeaponInputHandlerClass.new()
	add_child(_input_handler)
	_input_handler.initialize(self, _logger)
	
	_hud_manager = WeaponHUDManagerClass.new()
	add_child(_hud_manager)
	_hud_manager.initialize(self, _logger)
	
	_attack_coordinator = WeaponAttackCoordinatorClass.new()
	add_child(_attack_coordinator)
	_attack_coordinator.initialize(self, _weapon_manager, _logger)
	
	# Connect component signals
	_connect_component_signals()
	
	_logger.debug("weapon", self, "🔧 All components initialized")

func _connect_component_signals() -> void:
	# WeaponManager signals
	_weapon_manager.hud_update_needed.connect(_on_hud_update_needed)
	_weapon_manager.weapon_dropped.connect(_on_weapon_dropped)
	
	# InputHandler signals
	_input_handler.primary_attack_requested.connect(_on_primary_attack_requested)
	_input_handler.secondary_attack_started.connect(_on_secondary_attack_started)
	_input_handler.secondary_attack_updated.connect(_on_secondary_attack_updated)
	_input_handler.secondary_attack_released.connect(_on_secondary_attack_released)
	
	_logger.debug("weapon", self, "🔌 Component signals connected")

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

func _on_weapon_picked_up(pickup: WeaponPickup, mount: Node, weapon_type: String, weapon_level: int = 1) -> void:
	var start_time: int = Time.get_ticks_msec()
	_logger.info("weapon", self, "⏱️ [TIMING START] _on_weapon_picked_up: pickup=%s, mount=%s, weapon_type=%s, level=%d" % [pickup.name, mount.name, weapon_type, weapon_level])
	
	# Only process if this weapon was picked up by THIS mount
	if mount != self:
		_logger.debug("weapon", self, "⏭️ skipping: pickup not for this mount (mount=%s, self=%s)" % [mount.name, name])
		return
	
	_logger.info("weapon", self, "✅ pickup confirmed for this mount, processing...")
	
	# Use pickup handler to process the pickup and make a decision
	var handler_start: int = Time.get_ticks_msec()
	var stored_current: int = pickup.stored_current_ammo if pickup.stored_current_ammo >= 0 else -1
	var stored_max: int = pickup.stored_max_ammo if pickup.stored_max_ammo >= 0 else -1
	var decision: WeaponPickupHandlerClass.PickupDecision = _pickup_handler.process_pickup(weapon_type, weapon_level, pickup.pickup_color, stored_current, stored_max)
	var handler_time: int = Time.get_ticks_msec() - handler_start
	_logger.info("weapon", self, "⏱️ [TIMING] process_pickup took %d ms" % handler_time)
	_logger.info("weapon", self, "🔍 Decision result: %d (can_attach=%s, free_slot=%d, upgrade_slots=%s)" % [decision.result, decision.can_attach_to_free, decision.free_slot, decision.upgrade_slots])
	
	# Handle the decision based on result
	match decision.result:
		WeaponPickupHandlerClass.PickupResult.ATTACHED_TO_EMPTY_SLOT:
			_pickup_handler.apply_decision(decision, weapon_type, weapon_level, pickup.pickup_color, stored_current, stored_max)
		
		WeaponPickupHandlerClass.PickupResult.REFILLED_EXISTING:
			_pickup_handler.apply_decision(decision, weapon_type, weapon_level, pickup.pickup_color, stored_current, stored_max)
		
		WeaponPickupHandlerClass.PickupResult.UPGRADED_EXISTING:
			_pickup_handler.apply_decision(decision, weapon_type, weapon_level, pickup.pickup_color, stored_current, stored_max)
		
		WeaponPickupHandlerClass.PickupResult.AUTO_REPLACED:
			_pickup_handler.apply_decision(decision, weapon_type, weapon_level, pickup.pickup_color, stored_current, stored_max)
		
		WeaponPickupHandlerClass.PickupResult.AUTO_UPGRADED:
			_pickup_handler.apply_decision(decision, weapon_type, weapon_level, pickup.pickup_color, stored_current, stored_max)
		
		WeaponPickupHandlerClass.PickupResult.NEEDS_PLAYER_CHOICE:
			# Show UI prompt for player to choose
			_show_pickup_choice_prompt(weapon_type, weapon_level, pickup.pickup_color, decision)
		
		_:
			_logger.error("weapon", self, "❌ Unknown pickup result: %d" % decision.result)
	
	var total_time: int = Time.get_ticks_msec() - start_time
	_logger.info("weapon", self, "⏱️ [TIMING END] _on_weapon_picked_up took %d ms total" % total_time)

func _show_pickup_choice_prompt(weapon_type: String, weapon_level: int, weapon_color: Color, decision: WeaponPickupHandlerClass.PickupDecision) -> void:
	if not is_player:
		if _logger:
			_logger.error("weapon", self, "❌ Cannot show prompt: not player")
		return
	
	# Store pending weapon data (use level from decision to ensure consistency)
	_pending_weapon_type = weapon_type
	_pending_weapon_color = weapon_color
	_pending_weapon_level = decision.weapon_level
	
	# Get current weapon types for display
	var left_weapon: WeaponAttachment = _slot_manager.get_weapon_at_slot(WeaponSlotConstantsClass.Slot.LEFT)
	var right_weapon: WeaponAttachment = _slot_manager.get_weapon_at_slot(WeaponSlotConstantsClass.Slot.RIGHT)
	var left_type: String = left_weapon.weapon_type if left_weapon != null else ""
	var right_type: String = right_weapon.weapon_type if right_weapon != null else ""
	
	# Use HUD manager to show prompt
	_hud_manager.show_pickup_choice_prompt(weapon_type, weapon_level, weapon_color, decision, left_type, right_type)

func _create_hud() -> void:
	if not is_player:
		return
	_hud_manager.create_hud()

func _on_hud_update_needed(_slot: int) -> void:
	# Get weapons for both slots and update HUD
	var left_weapon: WeaponAttachment = _weapon_manager.get_weapon_at_marker(_weapon_marker_left)
	var right_weapon: WeaponAttachment = _weapon_manager.get_weapon_at_marker(_weapon_marker_right)
	_hud_manager.update_display_hud(left_weapon, right_weapon)

func _on_weapon_dropped(weapon: WeaponAttachment, slot: int) -> void:
	# Create a pickup from the dropped weapon
	_drop_weapon_as_pickup(weapon, slot)

func _drop_weapon_as_pickup(weapon: WeaponAttachment, slot: int) -> void:
	# Create a weapon pickup at the mount's position
	var pickup_scene: PackedScene = load("res://scenes/pickups/weapon_pickup.tscn")
	if pickup_scene == null:
		if _logger:
			_logger.error("weapon", self, "❌ Failed to load weapon pickup scene")
		return
	
	var pickup: WeaponPickup = pickup_scene.instantiate() as WeaponPickup
	if pickup == null:
		if _logger:
			_logger.error("weapon", self, "❌ Failed to instantiate weapon pickup")
		return
	
	# Set pickup properties BEFORE adding to scene tree
	pickup.weapon_type = weapon.weapon_type
	pickup.pickup_color = weapon.weapon_color
	pickup.pickup_delay = 0.8  # Prevent immediate re-collection
	pickup.stored_current_ammo = weapon.current_ammo
	pickup.stored_max_ammo = weapon.max_ammo
	
	if _logger:
		_logger.info("weapon", self, "💾 stored weapon ammo state: %d/%d" % [weapon.current_ammo, weapon.max_ammo])
	
	# Add to scene tree FIRST
	get_tree().current_scene.add_child(pickup)
	
	# Calculate ejection direction and velocity
	var mount_forward: Vector3 = -global_transform.basis.z
	var mount_up: Vector3 = global_transform.basis.y
	var mount_right: Vector3 = global_transform.basis.x
	
	var ejection_direction: Vector3 = Vector3.ZERO
	ejection_direction -= mount_forward * 0.7  # Backward
	ejection_direction += mount_up * 0.4  # Upward
	if slot == 1:
		ejection_direction -= mount_right * 0.6  # Left side
	else:
		ejection_direction += mount_right * 0.6  # Right side
	
	ejection_direction = ejection_direction.normalized()
	pickup._ejection_velocity = ejection_direction * pickup.ejection_speed
	
	# Set initial position
	var marker: Marker3D = _weapon_marker_left if slot == 1 else _weapon_marker_right
	var spawn_position: Vector3 = marker.global_position if marker != null else global_position
	spawn_position += mount_up * 0.5  # Slightly above
	
	if pickup.is_inside_tree():
		pickup.global_position = spawn_position
	else:
		call_deferred("_set_pickup_position", pickup, spawn_position)
	
	# Connect pickup to mounts
	_connect_pickup_to_mounts(pickup)
	
	if _logger:
		_logger.info("weapon", self, "💧 DROPPED UPGRADE: type=%s at pos=%s" % [weapon.weapon_type, pickup.global_position])

func _connect_pickup_to_mounts(pickup: WeaponPickup) -> void:
	# Find all MountController nodes in the scene and connect the pickup signal
	var mounts: Array[MountController] = []
	_find_mount_controllers_recursive(get_tree().current_scene, mounts)
	
	for mount in mounts:
		if not pickup.weapon_picked_up.is_connected(mount._on_weapon_picked_up):
			pickup.weapon_picked_up.connect(mount._on_weapon_picked_up)
			if _logger:
				_logger.debug("weapon", self, "🔌 connected pickup to mount: %s" % mount.name)

func _set_pickup_position(pickup: WeaponPickup, pos: Vector3) -> void:
	if is_instance_valid(pickup) and pickup.is_inside_tree():
		pickup.global_position = pos

func _find_mount_controllers_recursive(node: Node, mounts: Array) -> void:
	if node is MountController:
		mounts.append(node)
	
	for child in node.get_children():
		_find_mount_controllers_recursive(child, mounts)

func _on_primary_attack_requested(slot: int) -> void:
	_attack_coordinator.attack_with_slot(slot)

func _on_secondary_attack_started(slot: int) -> void:
	_attack_coordinator.start_secondary_attack(slot)

func _on_secondary_attack_updated(slot: int, delta: float) -> void:
	_attack_coordinator.update_secondary_charge(slot, delta)

func _on_secondary_attack_released(slot: int) -> void:
	_attack_coordinator.release_secondary_attack(slot)

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

# ============================================================================
# Public API Methods (called by UI, pickup handler, etc.)
# These delegate to the appropriate components for backwards compatibility
# ============================================================================

## Attach a weapon at a specific level (called by pickup handler)
func _attach_weapon_at_level(weapon_type: String, weapon_color: Color, marker: Marker3D, level: int = 1, stored_current_ammo: int = -1, stored_max_ammo: int = -1) -> void:
	_weapon_manager.attach_weapon_at_level(weapon_type, weapon_color, marker, level, stored_current_ammo, stored_max_ammo)

## Upgrade weapon in a slot (called by pickup handler)
func _upgrade_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	_weapon_manager.upgrade_weapon_in_slot(slot, weapon_type, weapon_color)

## Replace weapon in a slot (called by UI)
func replace_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color, weapon_level: int = -1) -> void:
	# If weapon_level not provided, use pending weapon level (defaults to 1)
	if weapon_level < 1:
		weapon_level = _pending_weapon_level if _pending_weapon_level > 0 else 1
	
	if _logger:
		_logger.info("weapon", self, "🔄 REPLACE_WEAPON: slot=%d, type=%s, level=%d" % [slot, weapon_type, weapon_level])
	
	_weapon_manager.replace_weapon_in_slot(slot, weapon_type, weapon_color, weapon_level)
	
	# Clear pending weapon data
	_pending_weapon_type = ""
	_pending_weapon_color = Color.WHITE
	_pending_weapon_level = 1
	
	# Update HUD
	call_deferred("_on_hud_update_needed", slot)

## Attach weapon to a free slot (called by UI)
func attach_weapon_to_slot(slot: int, weapon_type: String, weapon_color: Color, weapon_level: int = 1) -> void:
	var marker: Marker3D = null
	if slot == 1:
		marker = _weapon_marker_left
	elif slot == 2:
		marker = _weapon_marker_right
	else:
		if _logger:
			_logger.error("weapon", self, "❌ Invalid slot for attachment: %d" % slot)
		return
	
	if marker == null:
		if _logger:
			_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
			return
		
	if _logger:
		_logger.info("weapon", self, "➕ attaching weapon to free slot %d: %s (level %d)" % [slot, weapon_type, weapon_level])
	_weapon_manager.attach_weapon_at_level(weapon_type, weapon_color, marker, weapon_level)

## Upgrade weapon in a slot (called by UI)
func upgrade_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	_weapon_manager.upgrade_weapon_in_slot(slot, weapon_type, weapon_color)

## Refill weapon in a slot (called by UI)
func refill_weapon_in_slot(slot: int) -> void:
	_weapon_manager.refill_weapon_in_slot(slot)

## Drop pending weapon (called by UI)
func drop_pending_weapon() -> void:
	if _logger:
		_logger.info("weapon", self, "🚫 dropped pending weapon: %s" % _pending_weapon_type)
	
	if _hud_manager != null:
		_hud_manager.hide_pickup_choice_prompt()
	
	_pending_weapon_type = ""
	_pending_weapon_color = Color.WHITE
	_pending_weapon_level = 1

## Get weapon at a marker (for backwards compatibility)
func _get_weapon_at_marker(marker: Marker3D) -> WeaponAttachment:
	return _weapon_manager.get_weapon_at_marker(marker)
