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
# Track stacked weapons per slot: {slot: [WeaponAttachment, ...]}
var _stacked_weapons: Dictionary = {}  # {1: [weapon1, weapon2, ...], 2: [weapon1, weapon2, ...]}

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
	_logger.info("weapon", self, "📥 _on_weapon_picked_up CALLED: pickup=%s, mount=%s, weapon_type=%s" % [pickup.name, mount.name, weapon_type])
	
	# Only attach if this weapon was picked up by THIS mount
	if mount != self:
		_logger.debug("weapon", self, "⏭️ skipping: pickup not for this mount (mount=%s, self=%s)" % [mount.name, name])
		return
	
	_logger.info("weapon", self, "✅ pickup confirmed for this mount, processing...")
	
	# Get current weapons
	var left_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_left)
	var right_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_right)
	
	_logger.info("weapon", self, "🔍 pickup check: left=%s, right=%s, picking_up=%s" % [
		left_weapon.weapon_type if left_weapon != null else "null",
		right_weapon.weapon_type if right_weapon != null else "null",
		weapon_type
	])
	
	# Check if we already have this weapon type in either slot
	var left_matches: bool = left_weapon != null and left_weapon.weapon_type == weapon_type
	var right_matches: bool = right_weapon != null and right_weapon.weapon_type == weapon_type
	
	_logger.debug("weapon", self, "🔍 checking matches: left_matches=%s, right_matches=%s" % [str(left_matches), str(right_matches)])
	
	# If we have matching weapons, check which ones need refill
	if left_matches or right_matches:
		var weapons_to_refill: Array[Dictionary] = []  # Array of {weapon: WeaponAttachment, slot: int, ammo: int}
		
		if left_matches:
			_logger.info("weapon", self, "✅ found matching weapon in slot 1: type=%s, ammo=%d/%d" % [weapon_type, left_weapon.current_ammo, left_weapon.max_ammo])
			if left_weapon.current_ammo < left_weapon.max_ammo:
				weapons_to_refill.append({"weapon": left_weapon, "slot": 1, "ammo": left_weapon.current_ammo})
		
		if right_matches:
			_logger.info("weapon", self, "✅ found matching weapon in slot 2: type=%s, ammo=%d/%d" % [weapon_type, right_weapon.current_ammo, right_weapon.max_ammo])
			if right_weapon.current_ammo < right_weapon.max_ammo:
				weapons_to_refill.append({"weapon": right_weapon, "slot": 2, "ammo": right_weapon.current_ammo})
		
		# If any weapon needs refill, refill the one with the least ammo (or just the first one)
		if weapons_to_refill.size() > 0:
			# Sort by ammo (lowest first) to refill the one that needs it most
			weapons_to_refill.sort_custom(func(a, b): return a.ammo < b.ammo)
			var target: Dictionary = weapons_to_refill[0]
			var target_weapon: WeaponAttachment = target.weapon
			var target_slot: int = target.slot
			var old_ammo: int = target.ammo
			
			_logger.info("weapon", self, "🔋 REFILLING weapon in slot %d: %d/%d -> %d/%d" % [target_slot, old_ammo, target_weapon.max_ammo, target_weapon.max_ammo, target_weapon.max_ammo])
			target_weapon.current_ammo = target_weapon.max_ammo
			target_weapon.ammo_changed.emit(target_weapon.current_ammo, target_weapon.max_ammo)
			_logger.info("weapon", self, "✅ REFILL COMPLETE: ammo now %d/%d" % [target_weapon.current_ammo, target_weapon.max_ammo])
			return
		
		# Both matching weapons are at full ammo - offer upgrade or place in other slot
		# Check if we can upgrade (stack) or place in free slot
		var full_weapons: Array[Dictionary] = []  # Array of {weapon: WeaponAttachment, slot: int}
		
		if left_matches and left_weapon.current_ammo >= left_weapon.max_ammo:
			full_weapons.append({"weapon": left_weapon, "slot": 1})
		if right_matches and right_weapon.current_ammo >= right_weapon.max_ammo:
			full_weapons.append({"weapon": right_weapon, "slot": 2})
		
		# Check for free slots (not matching weapon type)
		var free_slot: int = 0
		var free_marker: Marker3D = null
		if not left_matches and left_weapon == null:
			free_slot = 1
			free_marker = _weapon_marker_left
		elif not right_matches and right_weapon == null:
			free_slot = 2
			free_marker = _weapon_marker_right
		
		# If we have full weapons and this is a player, show upgrade/replace prompt
		if full_weapons.size() > 0:
			if is_player and _weapon_hud != null:
				_pending_weapon_type = weapon_type
				_pending_weapon_color = pickup.pickup_color
				
				# Determine which slots can be upgraded
				var upgrade_slots: Array[int] = []
				for full_data in full_weapons:
					upgrade_slots.append(full_data.slot)
				
				_weapon_hud.show_upgrade_prompt(weapon_type, pickup.pickup_color, left_weapon.weapon_type if left_weapon != null else "", right_weapon.weapon_type if right_weapon != null else "", upgrade_slots, free_slot)
				_logger.info("weapon", self, "📋 showing upgrade prompt for: %s (upgrade_slots=%s, free_slot=%d)" % [weapon_type, str(upgrade_slots), free_slot])
				return
			else:
				# For non-player mounts, upgrade the first full weapon automatically
				var target_data: Dictionary = full_weapons[0]
				_logger.info("weapon", self, "🤖 auto-upgrading slot %d weapon with: %s" % [target_data.slot, weapon_type])
				_upgrade_weapon_in_slot(target_data.slot, weapon_type, pickup.pickup_color)
				return
		
		# If we have a free slot, attach there
		if free_marker != null:
			_logger.info("weapon", self, "➕ attaching to free slot %d (same weapon type, but existing is full)" % free_slot)
			# Use stored ammo if available (from dropped weapon)
			var free_slot_ammo_current: int = pickup.stored_current_ammo if pickup.stored_current_ammo >= 0 else -1
			var free_slot_ammo_max: int = pickup.stored_max_ammo if pickup.stored_max_ammo >= 0 else -1
			_attach_weapon(weapon_type, pickup.pickup_color, free_marker, free_slot_ammo_current, free_slot_ammo_max)
			return
	
	# We don't have this weapon type - check if slots are available
	if left_weapon != null and right_weapon != null:
		# Both slots are full with different weapons - show replacement prompt
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
	
	# Create and attach the weapon (use stored ammo if available)
	var stored_current: int = pickup.stored_current_ammo if pickup.stored_current_ammo >= 0 else -1
	var stored_max: int = pickup.stored_max_ammo if pickup.stored_max_ammo >= 0 else -1
	_attach_weapon(weapon_type, pickup.pickup_color, marker, stored_current, stored_max)

func _attach_weapon(weapon_type: String, weapon_color: Color, marker: Marker3D, stored_current_ammo: int = -1, stored_max_ammo: int = -1) -> void:
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
	
	# Initialize ammo: use stored ammo if provided (from dropped weapon), otherwise use registry default
	if stored_current_ammo >= 0 and stored_max_ammo >= 0:
		weapon.max_ammo = stored_max_ammo
		weapon.current_ammo = stored_current_ammo
		_logger.info("weapon", self, "📥 restoring weapon ammo from pickup: %d/%d" % [stored_current_ammo, stored_max_ammo])
	else:
		# Initialize ammo to full capacity (new pickup)
		weapon.max_ammo = WeaponRegistry.get_max_ammo(weapon_type)
		weapon.current_ammo = weapon.max_ammo
	
	# Signals will be connected in _update_display_hud() after attachment
	
	# Add to scene tree first (required for reparenting)
	get_tree().root.add_child(weapon)
	
	# Attach to the marker
	weapon.attach_to_mount(self, marker)
	
	# Determine which slot this marker belongs to
	var slot: int = 1 if marker == _weapon_marker_left else 2
	
	# Initialize stack array for this slot if needed
	if not _stacked_weapons.has(slot):
		_stacked_weapons[slot] = []
	
	# Add as first weapon in stack
	_stacked_weapons[slot].append(weapon)
	
	# Track the weapon
	_attached_weapons.append(weapon)
	
	# Connect ammo_changed signal to check for upgrade drops (for when upgrades are added later)
	# Use a lambda to correctly capture the slot parameter
	var slot_capture: int = slot  # Capture slot in local variable
	var callable: Callable = func(new_ammo: int, max_ammo: int): _check_upgrade_drops(slot_capture, new_ammo, max_ammo)
	if not weapon.ammo_changed.is_connected(callable):
		weapon.ammo_changed.connect(callable)
		_logger.debug("weapon", self, "🔌 connected ammo_changed to _check_upgrade_drops for slot %d using lambda" % slot)
	
	# Update display HUD
	_update_display_hud()
	
	_logger.info("weapon", self, "⚔️ weapon attached: type=%s, color=%s, marker=%s, ammo=%d/%d, slot=%d" % [weapon_type, weapon.weapon_color, marker.name, weapon.current_ammo, weapon.max_ammo, slot])

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
	# Get the base weapon (first in stack) for this marker
	var slot: int = 0
	if marker == _weapon_marker_left:
		slot = 1
	elif marker == _weapon_marker_right:
		slot = 2
	
	if slot > 0 and _stacked_weapons.has(slot) and _stacked_weapons[slot].size() > 0:
		var base_weapon: WeaponAttachment = _stacked_weapons[slot][0]
		if is_instance_valid(base_weapon):
			return base_weapon
	
	# Fallback: search marker children (for backwards compatibility)
	if marker == null:
		_logger.debug("weapon", self, "🔍 _get_weapon_at_marker: marker is null")
		return null
	
	var child_count: int = marker.get_child_count()
	_logger.debug("weapon", self, "🔍 _get_weapon_at_marker: marker=%s, child_count=%d" % [marker.name, child_count])
	
	for child in marker.get_children():
		_logger.debug("weapon", self, "🔍   checking child: %s, type=%s, is_WeaponAttachment=%s" % [child.name, child.get_class(), str(child is WeaponAttachment)])
		if child is WeaponAttachment:
			var weapon: WeaponAttachment = child as WeaponAttachment
			_logger.debug("weapon", self, "🔍   found weapon: type=%s, id=%d" % [weapon.weapon_type, weapon.get_instance_id()])
			return weapon
	
	_logger.debug("weapon", self, "🔍 _get_weapon_at_marker: no weapon found")
	return null

func replace_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	_logger.info("weapon", self, "🔄 REPLACE_WEAPON_START: slot=%d, type=%s" % [slot, weapon_type])
	
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
	
	_logger.debug("weapon", self, "🔍 BEFORE_REMOVAL: marker=%s, child_count=%d" % [marker.name, marker.get_child_count()])
	
	# Remove all stacked weapons at this marker (clear the stack)
	if _stacked_weapons.has(slot):
		var stack: Array = _stacked_weapons[slot]
		_logger.info("weapon", self, "🗑️ REMOVING_STACK: slot=%d, stack_size=%d" % [slot, stack.size()])
		
		for weapon in stack:
			if is_instance_valid(weapon):
				# Disconnect ammo signals
				if slot == 1:
					if weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed):
						weapon.ammo_changed.disconnect(_on_left_weapon_ammo_changed)
				elif slot == 2:
					if weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
						weapon.ammo_changed.disconnect(_on_right_weapon_ammo_changed)
				
				if weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
					weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
				
				# Remove from marker
				if marker.is_ancestor_of(weapon):
					marker.remove_child(weapon)
				
				weapon.detach_from_mount()
				_attached_weapons.erase(weapon)
		
		# Clear the stack
		_stacked_weapons[slot] = []
		_logger.debug("weapon", self, "✅ stack cleared for slot %d" % slot)
	else:
		# Fallback: remove single weapon (backwards compatibility)
		var existing_weapon: WeaponAttachment = _get_weapon_at_marker(marker)
		if existing_weapon != null:
			_logger.info("weapon", self, "🗑️ REMOVING_OLD_WEAPON: slot=%d, type=%s, id=%d" % [slot, existing_weapon.weapon_type, existing_weapon.get_instance_id()])
			
			# Disconnect ammo signals
			if slot == 1:
				if existing_weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed):
					existing_weapon.ammo_changed.disconnect(_on_left_weapon_ammo_changed)
			elif slot == 2:
				if existing_weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
					existing_weapon.ammo_changed.disconnect(_on_right_weapon_ammo_changed)
			
			if existing_weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
				existing_weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
			
			# Remove from marker
			if marker.is_ancestor_of(existing_weapon):
				marker.remove_child(existing_weapon)
			
			existing_weapon.detach_from_mount()
			_attached_weapons.erase(existing_weapon)
			_logger.debug("weapon", self, "✅ old weapon detached and removed from array")
	
	# Clear HUD cache for this slot to ensure fresh data is loaded for the new weapon
	if _weapon_display_hud != null:
		_weapon_display_hud.clear_slot_cache(slot)
		_logger.debug("weapon", self, "🗑️ HUD cache cleared for slot %d" % slot)
	
	_logger.debug("weapon", self, "🔍 AFTER_REMOVAL: marker=%s, child_count=%d" % [marker.name, marker.get_child_count()])
	
	# Attach new weapon
	_logger.info("weapon", self, "➕ ATTACHING_NEW_WEAPON: slot=%d, type=%s" % [slot, weapon_type])
	_attach_weapon(weapon_type, weapon_color, marker)
	
	_logger.debug("weapon", self, "🔍 AFTER_ATTACHMENT: marker=%s, child_count=%d" % [marker.name, marker.get_child_count()])
	var verify_weapon: WeaponAttachment = _get_weapon_at_marker(marker)
	if verify_weapon != null:
		_logger.info("weapon", self, "✅ VERIFIED_NEW_WEAPON: slot=%d, type=%s, id=%d, ammo=%d/%d" % [slot, verify_weapon.weapon_type, verify_weapon.get_instance_id(), verify_weapon.current_ammo, verify_weapon.max_ammo])
	else:
		_logger.error("weapon", self, "❌ VERIFICATION_FAILED: no weapon found at marker after attachment!")
	
	# Update display HUD (must happen after attachment)
	_logger.info("weapon", self, "📺 UPDATING_HUD: slot=%d" % slot)
	_update_display_hud()
	
	_pending_weapon_type = ""
	_pending_weapon_color = Color.WHITE
	
	_logger.info("weapon", self, "✅ REPLACE_WEAPON_COMPLETE: slot=%d" % slot)

func drop_pending_weapon() -> void:
	_logger.info("weapon", self, "🚫 dropped pending weapon: %s" % _pending_weapon_type)
	_pending_weapon_type = ""
	_pending_weapon_color = Color.WHITE

func refill_weapon_in_slot(slot: int) -> void:
	var weapon: WeaponAttachment = null
	if slot == 1:
		weapon = _get_weapon_at_marker(_weapon_marker_left)
	elif slot == 2:
		weapon = _get_weapon_at_marker(_weapon_marker_right)
	
	if weapon == null:
		_logger.error("weapon", self, "❌ Cannot refill: no weapon in slot %d" % slot)
		return
	
	if weapon.current_ammo >= weapon.max_ammo:
		_logger.debug("weapon", self, "ℹ️ weapon in slot %d is already at full ammo" % slot)
		return
	
	_logger.info("weapon", self, "🔋 refilling weapon in slot %d: %d/%d -> %d/%d" % [slot, weapon.current_ammo, weapon.max_ammo, weapon.max_ammo, weapon.max_ammo])
	weapon.current_ammo = weapon.max_ammo
	weapon.ammo_changed.emit(weapon.current_ammo, weapon.max_ammo)

func upgrade_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	_upgrade_weapon_in_slot(slot, weapon_type, weapon_color)

func attach_weapon_to_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	var marker: Marker3D = null
	if slot == 1:
		marker = _weapon_marker_left
	elif slot == 2:
		marker = _weapon_marker_right
	else:
		_logger.error("weapon", self, "❌ Invalid slot for attachment: %d" % slot)
		return
	
	if marker == null:
		_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	_logger.info("weapon", self, "➕ attaching weapon to free slot %d: %s" % [slot, weapon_type])
	_attach_weapon(weapon_type, weapon_color, marker)

func _upgrade_weapon_in_slot(slot: int, weapon_type: String, weapon_color: Color) -> void:
	_logger.info("weapon", self, "⬆️ UPGRADING weapon in slot %d with: %s" % [slot, weapon_type])
	
	var marker: Marker3D = null
	if slot == 1:
		marker = _weapon_marker_left
	elif slot == 2:
		marker = _weapon_marker_right
	else:
		_logger.error("weapon", self, "❌ Invalid slot for upgrade: %d" % slot)
		return
	
	if marker == null:
		_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	# Get current stack count for this slot
	var stack_count: int = 0
	if _stacked_weapons.has(slot):
		stack_count = _stacked_weapons[slot].size()
	
	# Load and instantiate the new weapon
	var weapon_scene_path: String = WeaponRegistry.get_weapon_scene_path(weapon_type)
	var weapon_scene: PackedScene = load(weapon_scene_path)
	if weapon_scene == null:
		_logger.error("weapon", self, "❌ Failed to load weapon scene: %s" % weapon_scene_path)
		return
	
	var weapon_instance: Node = weapon_scene.instantiate()
	if weapon_instance == null or not weapon_instance is WeaponAttachment:
		_logger.error("weapon", self, "❌ Failed to instantiate weapon attachment")
		return
	
	var new_weapon: WeaponAttachment = weapon_instance as WeaponAttachment
	new_weapon.weapon_type = weapon_type
	if weapon_color == Color.WHITE:
		new_weapon.weapon_color = WeaponRegistry.get_weapon_color(weapon_type)
	else:
		new_weapon.weapon_color = weapon_color
	
	var base_max_ammo: int = WeaponRegistry.get_max_ammo(weapon_type)
	new_weapon.max_ammo = base_max_ammo
	new_weapon.current_ammo = base_max_ammo
	
	# Add to scene tree
	get_tree().root.add_child(new_weapon)
	
	# Attach to marker with vertical offset for stacking
	new_weapon.attach_to_mount(self, marker)
	
	# Apply vertical offset based on stack count (stack weapons on top of each other)
	var stack_offset: float = 0.3 * stack_count  # 0.3 units per stack level
	new_weapon.position.y += stack_offset
	
	# Track in stacked weapons array
	if not _stacked_weapons.has(slot):
		_stacked_weapons[slot] = []
	_stacked_weapons[slot].append(new_weapon)
	_attached_weapons.append(new_weapon)
	
	# Merge ammo: add the new weapon's ammo to the base weapon
	var base_weapon: WeaponAttachment = _stacked_weapons[slot][0]
	if not is_instance_valid(base_weapon):
		_logger.error("weapon", self, "❌ base_weapon is not valid during upgrade")
		return
	
	var old_max_ammo: int = base_weapon.max_ammo
	var old_current_ammo: int = base_weapon.current_ammo
	
	base_weapon.max_ammo += base_max_ammo
	base_weapon.current_ammo += base_max_ammo
	
	_logger.info("weapon", self, "⬆️ MERGING AMMO: base_weapon.max_ammo %d -> %d (+%d)" % [old_max_ammo, base_weapon.max_ammo, base_max_ammo])
	_logger.info("weapon", self, "⬆️ MERGING AMMO: base_weapon.current_ammo %d -> %d (+%d)" % [old_current_ammo, base_weapon.current_ammo, base_max_ammo])
	
	_logger.info("weapon", self, "⬆️ UPGRADE COMPLETE: slot %d now has %d stacked weapons, total ammo=%d/%d" % [slot, _stacked_weapons[slot].size(), base_weapon.current_ammo, base_weapon.max_ammo])
	
	# Connect ammo_changed signal to check for upgrade drops
	# Use a lambda to correctly capture the slot parameter
	var slot_capture: int = slot  # Capture slot in local variable
	var callable: Callable = func(new_ammo: int, max_ammo: int): _check_upgrade_drops(slot_capture, new_ammo, max_ammo)
	var signal_connected: bool = base_weapon.ammo_changed.is_connected(callable)
	_logger.debug("weapon", self, "🔌 ammo_changed signal connected to _check_upgrade_drops: %s" % str(signal_connected))
	if not signal_connected:
		base_weapon.ammo_changed.connect(callable)
		_logger.info("weapon", self, "🔌 connected ammo_changed signal to _check_upgrade_drops for slot %d using lambda" % slot)
	
	# Emit ammo changed signal to update HUD and trigger drop check
	_logger.debug("weapon", self, "📡 emitting ammo_changed after upgrade: current_ammo=%d, max_ammo=%d" % [base_weapon.current_ammo, base_weapon.max_ammo])
	base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
	
	# Update display HUD
	_update_display_hud()

func _check_upgrade_drops(slot: int, new_ammo: int, max_ammo: int) -> void:
	_logger.info("weapon", self, "🔍 _check_upgrade_drops CALLED: slot=%d, new_ammo=%d, max_ammo=%d" % [slot, new_ammo, max_ammo])
	
	# Validate slot parameter (should be 1 or 2, not an ammo value)
	# If slot is wrong (it's receiving ammo value instead), detect the correct slot
	if slot != 1 and slot != 2:
		_logger.error("weapon", self, "❌ INVALID SLOT PARAMETER: slot=%d (expected 1 or 2). Signal binding issue detected!" % slot)
		_logger.info("weapon", self, "🔍 Attempting to detect correct slot from ammo values...")
		
		# Try to determine the correct slot by checking which weapon has matching ammo
		var detected_slot: int = 0
		if _stacked_weapons.has(1):
			var left_stack: Array = _stacked_weapons[1]
			if left_stack.size() > 0:
				var left_base: WeaponAttachment = left_stack[0]
				if is_instance_valid(left_base):
					_logger.debug("weapon", self, "🔍   slot 1: base_weapon.current_ammo=%d, new_ammo=%d" % [left_base.current_ammo, new_ammo])
					if left_base.current_ammo == new_ammo or abs(left_base.current_ammo - new_ammo) <= 1:
						detected_slot = 1
						_logger.info("weapon", self, "✅ DETECTED: slot 1 matches (ammo=%d)" % new_ammo)
		
		if detected_slot == 0 and _stacked_weapons.has(2):
			var right_stack: Array = _stacked_weapons[2]
			if right_stack.size() > 0:
				var right_base: WeaponAttachment = right_stack[0]
				if is_instance_valid(right_base):
					_logger.debug("weapon", self, "🔍   slot 2: base_weapon.current_ammo=%d, new_ammo=%d" % [right_base.current_ammo, new_ammo])
					if right_base.current_ammo == new_ammo or abs(right_base.current_ammo - new_ammo) <= 1:
						detected_slot = 2
						_logger.info("weapon", self, "✅ DETECTED: slot 2 matches (ammo=%d)" % new_ammo)
		
		if detected_slot > 0:
			var old_slot: int = slot
			slot = detected_slot
			_logger.warn("weapon", self, "⚠️ Using detected slot=%d (was incorrectly %d)" % [slot, old_slot])
		else:
			_logger.error("weapon", self, "❌ Could not determine correct slot, aborting drop check")
			return
	
	# Check if ammo has dropped below thresholds that would cause upgrade drops
	# Thresholds: 20, 40, 60, 80... (20 * stack_level)
	if not _stacked_weapons.has(slot):
		_logger.debug("weapon", self, "🔍 no stack array for slot %d" % slot)
		return
	
	var stack: Array = _stacked_weapons[slot]
	_logger.info("weapon", self, "🔍 stack size for slot %d: %d" % [slot, stack.size()])
	
	if stack.size() <= 1:
		_logger.debug("weapon", self, "🔍 no upgrades to drop (stack_size=%d)" % stack.size())
		return  # No upgrades to drop
	
	var base_weapon: WeaponAttachment = stack[0]
	if not is_instance_valid(base_weapon):
		_logger.error("weapon", self, "❌ base weapon is not valid")
		return
	
	var base_max_ammo: int = WeaponRegistry.get_max_ammo(base_weapon.weapon_type)
	_logger.info("weapon", self, "🔍 base_max_ammo=%d, base_weapon.current_ammo=%d, base_weapon.max_ammo=%d" % [base_max_ammo, base_weapon.current_ammo, base_weapon.max_ammo])
	
	# Calculate how many upgrades should remain based on current ammo
	# Each upgrade adds base_max_ammo to the total
	var expected_stack_size: int = 1  # Base weapon always remains
	var threshold: int = base_max_ammo
	
	_logger.info("weapon", self, "🔍 calculating expected_stack_size: starting threshold=%d, new_ammo=%d" % [threshold, new_ammo])
	
	# Calculate expected stack size based on ammo thresholds
	# With 3 weapons (60 ammo total), thresholds are:
	# - 1 weapon: 0-19 ammo
	# - 2 weapons: 20-39 ammo  
	# - 3 weapons: 40-59 ammo
	# - 4 weapons: 60-79 ammo
	# So if new_ammo is 39, we should have 2 weapons (base + 1 upgrade)
	# If new_ammo is 40, we should have 3 weapons (base + 2 upgrades)
	
	while new_ammo >= threshold and expected_stack_size < stack.size():
		expected_stack_size += 1
		threshold += base_max_ammo
		_logger.debug("weapon", self, "🔍   new_ammo (%d) >= threshold (%d), expected_stack_size=%d" % [new_ammo, threshold, expected_stack_size])
	
	_logger.info("weapon", self, "🔍 FINAL: expected_stack_size=%d, current_stack_size=%d, final_threshold=%d, new_ammo=%d" % [expected_stack_size, stack.size(), threshold, new_ammo])
	
	# If we have more upgrades than we should, drop the excess
	if stack.size() > expected_stack_size:
		_logger.info("weapon", self, "⬇️ NEED TO DROP UPGRADES: stack_size=%d > expected=%d (ammo=%d, threshold=%d)" % [stack.size(), expected_stack_size, new_ammo, threshold])
	else:
		_logger.debug("weapon", self, "✅ no drops needed: stack_size=%d <= expected=%d (ammo=%d, threshold=%d)" % [stack.size(), expected_stack_size, new_ammo, threshold])
	
	while stack.size() > expected_stack_size:
		var top_weapon: WeaponAttachment = stack[stack.size() - 1]
		_logger.info("weapon", self, "⬇️ DROPPING UPGRADE: slot %d, ammo=%d/%d, stack_size=%d -> %d, top_weapon_type=%s" % [slot, new_ammo, max_ammo, stack.size(), expected_stack_size, top_weapon.weapon_type])
		
		if not is_instance_valid(top_weapon):
			_logger.error("weapon", self, "❌ top_weapon is not valid, removing from stack")
			stack.erase(top_weapon)
			continue
		
		# Remove from stack
		stack.erase(top_weapon)
		_attached_weapons.erase(top_weapon)
		_logger.info("weapon", self, "✅ removed from stack and _attached_weapons")
		
		# Update base weapon ammo (subtract the dropped weapon's ammo)
		var old_max_ammo: int = base_weapon.max_ammo
		base_weapon.max_ammo -= base_max_ammo
		_logger.info("weapon", self, "🔧 updated base_weapon.max_ammo: %d -> %d (subtracted %d)" % [old_max_ammo, base_weapon.max_ammo, base_max_ammo])
		
		# Don't reduce current_ammo below 0, but adjust if needed
		var old_current_ammo: int = base_weapon.current_ammo
		if base_weapon.current_ammo > base_weapon.max_ammo:
			base_weapon.current_ammo = base_weapon.max_ammo
			_logger.info("weapon", self, "🔧 adjusted base_weapon.current_ammo: %d -> %d (capped at max)" % [old_current_ammo, base_weapon.current_ammo])
		
		# Drop the weapon as a pickup
		_logger.info("weapon", self, "💧 calling _drop_weapon_upgrade...")
		_drop_weapon_upgrade(top_weapon, slot)
		
		# Remove from scene
		var marker: Marker3D = _weapon_marker_left if slot == 1 else _weapon_marker_right
		if marker != null:
			if marker.is_ancestor_of(top_weapon):
				_logger.info("weapon", self, "🗑️ removing top_weapon from marker children")
				marker.remove_child(top_weapon)
			else:
				_logger.warn("weapon", self, "⚠️ top_weapon is not a child of marker")
		else:
			_logger.error("weapon", self, "❌ marker is null for slot %d" % slot)
		
		if is_instance_valid(top_weapon):
			top_weapon.queue_free()
			_logger.info("weapon", self, "🗑️ queued top_weapon for deletion")
		
		# Update HUD
		_logger.info("weapon", self, "📺 emitting ammo_changed and updating HUD")
		base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
		_update_display_hud()
		
		_logger.info("weapon", self, "✅ UPGRADE DROP COMPLETE: new stack_size=%d" % stack.size())

func _detach_weapon_slot(slot: int) -> void:
	_logger.info("weapon", self, "🔓 DETACHING weapon slot %d (0 ammo click)" % slot)
	
	var marker: Marker3D = null
	if slot == 1:
		marker = _weapon_marker_left
	elif slot == 2:
		marker = _weapon_marker_right
	else:
		_logger.error("weapon", self, "❌ Invalid slot for detachment: %d" % slot)
		return
	
	if marker == null:
		_logger.error("weapon", self, "❌ Marker for slot %d is null" % slot)
		return
	
	# Drop all weapons in the stack as pickups
	if _stacked_weapons.has(slot):
		var stack: Array = _stacked_weapons[slot]
		_logger.info("weapon", self, "🔓 dropping %d weapons from slot %d as pickups" % [stack.size(), slot])
		
		# Drop weapons starting from the top (reverse order)
		for i in range(stack.size() - 1, -1, -1):
			var weapon: WeaponAttachment = stack[i]
			if is_instance_valid(weapon):
				# Drop as pickup
				_drop_weapon_upgrade(weapon, slot)
				
				# Disconnect ammo signals
				if slot == 1:
					if weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed):
						weapon.ammo_changed.disconnect(_on_left_weapon_ammo_changed)
				elif slot == 2:
					if weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
						weapon.ammo_changed.disconnect(_on_right_weapon_ammo_changed)
				
				if weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
					weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
				
				# Remove from marker
				if marker.is_ancestor_of(weapon):
					marker.remove_child(weapon)
				
				# Remove from tracking arrays
				_attached_weapons.erase(weapon)
				
				# Queue for deletion
				weapon.queue_free()
				_logger.debug("weapon", self, "🗑️ queued weapon %d for deletion" % i)
		
		# Clear the stack
		_stacked_weapons[slot] = []
		_logger.info("weapon", self, "✅ all weapons detached from slot %d" % slot)
		
		# Update HUD
		_update_display_hud()
	else:
		_logger.debug("weapon", self, "🔍 no weapons in slot %d to detach" % slot)

func _drop_weapon_upgrade(weapon: WeaponAttachment, slot: int) -> void:
	# Create a weapon pickup at the mount's position
	var pickup_scene: PackedScene = load("res://scenes/pickups/weapon_pickup.tscn")
	if pickup_scene == null:
		_logger.error("weapon", self, "❌ Failed to load weapon pickup scene")
		return
	
	var pickup: WeaponPickup = pickup_scene.instantiate() as WeaponPickup
	if pickup == null:
		_logger.error("weapon", self, "❌ Failed to instantiate weapon pickup")
		return
	
	# Set pickup properties BEFORE adding to scene tree (so they're available in _ready())
	pickup.weapon_type = weapon.weapon_type
	pickup.pickup_color = weapon.weapon_color
	# Set pickup delay to prevent immediate re-collection (dropped weapons need time to move away)
	pickup.pickup_delay = 0.8
	# Store weapon's ammo state so it's preserved when picked up again
	pickup.stored_current_ammo = weapon.current_ammo
	pickup.stored_max_ammo = weapon.max_ammo
	_logger.info("weapon", self, "💾 stored weapon ammo state: %d/%d" % [weapon.current_ammo, weapon.max_ammo])
	
	# Add to scene tree FIRST (required before setting global_position)
	get_tree().current_scene.add_child(pickup)
	
	# Calculate ejection direction and velocity
	# Get mount's forward direction
	var mount_forward: Vector3 = -global_transform.basis.z  # Mount's forward
	var mount_up: Vector3 = global_transform.basis.y  # Mount's up
	var mount_right: Vector3 = global_transform.basis.x  # Mount's right
	
	# Calculate ejection direction (backward and to the side, with upward arc)
	var ejection_direction: Vector3 = Vector3.ZERO
	ejection_direction -= mount_forward * 0.7  # Backward component
	ejection_direction += mount_up * 0.4  # Upward component
	if slot == 1:
		ejection_direction -= mount_right * 0.6  # Left side
	else:
		ejection_direction += mount_right * 0.6  # Right side
	
	ejection_direction = ejection_direction.normalized()
	
	# Set ejection velocity in the pickup
	pickup._ejection_velocity = ejection_direction * pickup.ejection_speed
	
	# Set initial position at the weapon marker (or slightly offset)
	var marker: Marker3D = _weapon_marker_left if slot == 1 else _weapon_marker_right
	var spawn_position: Vector3 = marker.global_position if marker != null else global_position
	spawn_position += mount_up * 0.5  # Slightly above
	
	# Set position after node is in tree
	if pickup.is_inside_tree():
		pickup.global_position = spawn_position
	else:
		# If pickup is not in tree yet, use a deferred call
		call_deferred("_set_pickup_position", pickup, spawn_position)
	
	# Connect pickup to mounts (same as spawner does)
	_connect_pickup_to_mounts(pickup)
	
	_logger.info("weapon", self, "💧 DROPPED UPGRADE: type=%s at pos=%s" % [weapon.weapon_type, pickup.global_position])

func _connect_pickup_to_mounts(pickup: WeaponPickup) -> void:
	# Find all MountController nodes in the scene and connect the pickup signal
	var mounts: Array[MountController] = []
	_find_mount_controllers_recursive(get_tree().current_scene, mounts)
	
	for mount in mounts:
		if not pickup.weapon_picked_up.is_connected(mount._on_weapon_picked_up):
			pickup.weapon_picked_up.connect(mount._on_weapon_picked_up)
			_logger.debug("weapon", self, "🔌 connected pickup to mount: %s" % mount.name)

func _set_pickup_position(pickup: WeaponPickup, pos: Vector3) -> void:
	if is_instance_valid(pickup) and pickup.is_inside_tree():
		pickup.global_position = pos

func _find_mount_controllers_recursive(node: Node, mounts: Array) -> void:
	if node is MountController:
		mounts.append(node)
	
	for child in node.get_children():
		_find_mount_controllers_recursive(child, mounts)

func _attack_with_upgraded_weapon(weapon: WeaponAttachment, _base_weapon: WeaponAttachment) -> void:
	# Fire the upgraded weapon without consuming its own ammo
	# The base weapon's attack() already consumed ammo, so we just fire projectiles
	# Check if weapon is still valid and in scene tree (may have been dropped during attack)
	if not is_instance_valid(weapon):
		_logger.debug("weapon", self, "⚠️ upgraded weapon is not valid, skipping fire")
		return
	
	if not weapon.is_inside_tree():
		_logger.debug("weapon", self, "⚠️ upgraded weapon not in scene tree (may have been dropped), skipping fire")
		return
	
	weapon.fire_without_consuming_ammo()

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
	
	# Fire all stacked weapons in slot 1
	if _stacked_weapons.has(1) and _stacked_weapons[1].size() > 0:
		var stack: Array = _stacked_weapons[1]
		# Create a copy of weapons to fire BEFORE iterating (stack may be modified during attack)
		var weapons_to_fire: Array[WeaponAttachment] = []
		for weapon in stack:
			if is_instance_valid(weapon):
				weapons_to_fire.append(weapon)
		
		if weapons_to_fire.size() == 0:
			_logger.debug("weapon", self, "⚠️ no valid weapons to fire in slot 1")
			return
		
		var base_weapon: WeaponAttachment = weapons_to_fire[0]
		var stack_count: int = weapons_to_fire.size()
		
		# Calculate total ammo consumption (projectile_count per weapon in stack)
		var projectile_count_per_weapon: int = WeaponRegistry.get_projectile_count(base_weapon.weapon_type)
		var total_projectiles_needed: int = projectile_count_per_weapon * stack_count
		_logger.info("weapon", self, "🎯 left mouse click detected - attacking with %d stacked weapons (will consume %d ammo: %d per weapon × %d weapons)" % [stack_count, total_projectiles_needed, projectile_count_per_weapon, stack_count])
		
		# Check if we have 0 ammo - detach weapon completely
		if base_weapon.current_ammo <= 0:
			_logger.info("weapon", self, "🔓 weapon has 0 ammo - detaching all weapons from slot 1")
			_detach_weapon_slot(1)
			return
		
		# Check if we have enough ammo for all weapons
		if base_weapon.current_ammo < total_projectiles_needed:
			_logger.info("weapon", self, "⚠️ insufficient ammo: have %d, need %d (for %d weapons)" % [base_weapon.current_ammo, total_projectiles_needed, stack_count])
			# Don't fire if we don't have enough ammo
			return
		
		# Consume ammo based on stack count (1 per weapon)
		var old_ammo: int = base_weapon.current_ammo
		base_weapon.current_ammo -= total_projectiles_needed
		_logger.info("weapon", self, "🔋 consumed %d ammo (%d per weapon × %d weapons): %d -> %d" % [total_projectiles_needed, projectile_count_per_weapon, stack_count, old_ammo, base_weapon.current_ammo])
		
		# Fire all weapons
		for i in range(weapons_to_fire.size()):
			var weapon: WeaponAttachment = weapons_to_fire[i]
			if not is_instance_valid(weapon):
				_logger.warn("weapon", self, "⚠️ weapon at index %d became invalid during attack" % i)
				continue
			
			if not weapon.is_inside_tree():
				_logger.debug("weapon", self, "⚠️ weapon at index %d not in scene tree, skipping" % i)
				continue
			
			# All weapons fire their projectiles (ammo already consumed above)
			_attack_with_upgraded_weapon(weapon, base_weapon)
		
		# Emit ammo changed signal after all weapons have fired
		base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
		
		# Check if ammo is depleted
		if base_weapon.current_ammo <= 0:
			base_weapon.ammo_depleted.emit(base_weapon.weapon_type)
	else:
		_logger.debug("weapon", self, "⚠️ cannot attack: no weapons in slot 1")

func _attack_with_right_weapon() -> void:
	if _weapon_marker_right == null:
		_logger.debug("weapon", self, "⚠️ cannot attack: right weapon marker is null")
		return
	
	# Fire all stacked weapons in slot 2
	if _stacked_weapons.has(2) and _stacked_weapons[2].size() > 0:
		var stack: Array = _stacked_weapons[2]
		# Create a copy of weapons to fire BEFORE iterating (stack may be modified during attack)
		var weapons_to_fire: Array[WeaponAttachment] = []
		for weapon in stack:
			if is_instance_valid(weapon):
				weapons_to_fire.append(weapon)
		
		if weapons_to_fire.size() == 0:
			_logger.debug("weapon", self, "⚠️ no valid weapons to fire in slot 2")
			return
		
		var base_weapon: WeaponAttachment = weapons_to_fire[0]
		var stack_count: int = weapons_to_fire.size()
		
		# Calculate total ammo consumption (projectile_count per weapon in stack)
		var projectile_count_per_weapon: int = WeaponRegistry.get_projectile_count(base_weapon.weapon_type)
		var total_projectiles_needed: int = projectile_count_per_weapon * stack_count
		_logger.info("weapon", self, "🎯 right mouse click detected - attacking with %d stacked weapons (will consume %d ammo: %d per weapon × %d weapons)" % [stack_count, total_projectiles_needed, projectile_count_per_weapon, stack_count])
		
		# Check if we have 0 ammo - detach weapon completely
		if base_weapon.current_ammo <= 0:
			_logger.info("weapon", self, "🔓 weapon has 0 ammo - detaching all weapons from slot 2")
			_detach_weapon_slot(2)
			return
		
		# Check if we have enough ammo for all weapons
		if base_weapon.current_ammo < total_projectiles_needed:
			_logger.info("weapon", self, "⚠️ insufficient ammo: have %d, need %d (for %d weapons)" % [base_weapon.current_ammo, total_projectiles_needed, stack_count])
			# Don't fire if we don't have enough ammo
			return
		
		# Consume ammo based on stack count (1 per weapon)
		var old_ammo: int = base_weapon.current_ammo
		base_weapon.current_ammo -= total_projectiles_needed
		_logger.info("weapon", self, "🔋 consumed %d ammo (%d per weapon × %d weapons): %d -> %d" % [total_projectiles_needed, projectile_count_per_weapon, stack_count, old_ammo, base_weapon.current_ammo])
		
		# Fire all weapons
		for i in range(weapons_to_fire.size()):
			var weapon: WeaponAttachment = weapons_to_fire[i]
			if not is_instance_valid(weapon):
				_logger.warn("weapon", self, "⚠️ weapon at index %d became invalid during attack" % i)
				continue
			
			if not weapon.is_inside_tree():
				_logger.debug("weapon", self, "⚠️ weapon at index %d not in scene tree, skipping" % i)
				continue
			
			# All weapons fire their projectiles (ammo already consumed above)
			_attack_with_upgraded_weapon(weapon, base_weapon)
		
		# Emit ammo changed signal after all weapons have fired
		base_weapon.ammo_changed.emit(base_weapon.current_ammo, base_weapon.max_ammo)
		
		# Check if ammo is depleted
		if base_weapon.current_ammo <= 0:
			base_weapon.ammo_depleted.emit(base_weapon.weapon_type)
	else:
		_logger.debug("weapon", self, "⚠️ cannot attack: no weapons in slot 2")

func _update_display_hud() -> void:
	if not is_player or _weapon_display_hud == null:
		return
	
	_logger.debug("weapon", self, "📺 _update_display_hud() called")
	
	# Update slot 1 (left weapon)
	var left_marker_name: String = "null"
	var left_marker_children: int = 0
	if _weapon_marker_left != null:
		left_marker_name = _weapon_marker_left.name
		left_marker_children = _weapon_marker_left.get_child_count()
	_logger.debug("weapon", self, "🔍 Checking left marker: %s, child_count=%d" % [left_marker_name, left_marker_children])
	var left_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_left)
	if left_weapon != null:
		_logger.debug("weapon", self, "🔍 Left weapon found: type=%s, id=%d, ammo=%d/%d" % [left_weapon.weapon_type, left_weapon.get_instance_id(), left_weapon.current_ammo, left_weapon.max_ammo])
	else:
		_logger.debug("weapon", self, "🔍 Left weapon: null")
	_weapon_display_hud.update_weapon_slot(1, left_weapon)
	
	# Connect ammo signal if weapon exists
	if left_weapon != null:
		# Disconnect previous connections if any
		if left_weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed):
			left_weapon.ammo_changed.disconnect(_on_left_weapon_ammo_changed)
			_logger.debug("weapon", self, "🔌 disconnected existing left ammo signal")
		if left_weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
			left_weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
			_logger.debug("weapon", self, "🔌 disconnected existing left ammo_depleted signal")
		
		# Connect new signals
		left_weapon.ammo_changed.connect(_on_left_weapon_ammo_changed)
		left_weapon.ammo_depleted.connect(_on_weapon_ammo_depleted)
		_logger.debug("weapon", self, "🔌 connected left weapon signals")
	
	# Update slot 2 (right weapon)
	var right_marker_name: String = "null"
	var right_marker_children: int = 0
	if _weapon_marker_right != null:
		right_marker_name = _weapon_marker_right.name
		right_marker_children = _weapon_marker_right.get_child_count()
	_logger.debug("weapon", self, "🔍 Checking right marker: %s, child_count=%d" % [right_marker_name, right_marker_children])
	var right_weapon: WeaponAttachment = _get_weapon_at_marker(_weapon_marker_right)
	if right_weapon != null:
		_logger.debug("weapon", self, "🔍 Right weapon found: type=%s, id=%d, ammo=%d/%d" % [right_weapon.weapon_type, right_weapon.get_instance_id(), right_weapon.current_ammo, right_weapon.max_ammo])
	else:
		_logger.debug("weapon", self, "🔍 Right weapon: null")
	_weapon_display_hud.update_weapon_slot(2, right_weapon)
	
	# Connect ammo signal if weapon exists
	if right_weapon != null:
		# Disconnect previous connections if any
		if right_weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
			right_weapon.ammo_changed.disconnect(_on_right_weapon_ammo_changed)
			_logger.debug("weapon", self, "🔌 disconnected existing right ammo signal")
		if right_weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
			right_weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
			_logger.debug("weapon", self, "🔌 disconnected existing right ammo_depleted signal")
		
		# Connect new signals
		right_weapon.ammo_changed.connect(_on_right_weapon_ammo_changed)
		right_weapon.ammo_depleted.connect(_on_weapon_ammo_depleted)
		_logger.debug("weapon", self, "🔌 connected right weapon signals")

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
