extends Node
class_name WeaponHUDManager

## Manages weapon HUD creation, updates, and cleanup
## Handles both the permanent display HUD and the replacement prompt HUD

var _mount_controller: MountController = null
var _logger: Node = null
var _weapon_hud: WeaponReplacementHUD = null
var _weapon_display_hud: WeaponDisplayHUD = null
# Track last weapon IDs per slot to avoid unnecessary signal reconnections
var _last_hud_weapons: Dictionary = {}  # {slot: weapon_instance_id}

func initialize(mount_controller: MountController, logger: Node) -> void:
	_mount_controller = mount_controller
	_logger = logger
	
	if _logger:
		_logger.debug("weapon", self, "🔧 WeaponHUDManager initialized")

## Create HUD elements for player mount
func create_hud() -> void:
	if not _mount_controller.is_player:
		return
	
	# Create CanvasLayer for HUD
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	canvas_layer.name = "HUD"
	get_tree().root.add_child(canvas_layer)
	
	# Create permanent weapon display HUD
	var display_hud_scene: PackedScene = load("res://scenes/ui/weapon_display_hud.tscn")
	if display_hud_scene == null:
		if _logger:
			_logger.error("ui", self, "❌ Failed to load weapon display HUD scene")
		return
	
	var display_hud_instance: Node = display_hud_scene.instantiate()
	if display_hud_instance == null or not display_hud_instance is WeaponDisplayHUD:
		if _logger:
			_logger.error("ui", self, "❌ Failed to instantiate weapon display HUD")
		return
	
	_weapon_display_hud = display_hud_instance as WeaponDisplayHUD
	_weapon_display_hud.mount_controller = _mount_controller
	canvas_layer.add_child(_weapon_display_hud)
	
	# Create replacement prompt HUD
	var replacement_hud_scene: PackedScene = load("res://scenes/ui/weapon_replacement_hud.tscn")
	if replacement_hud_scene == null:
		if _logger:
			_logger.error("ui", self, "❌ Failed to load weapon replacement HUD scene")
		return
	
	var replacement_hud_instance: Node = replacement_hud_scene.instantiate()
	if replacement_hud_instance == null or not replacement_hud_instance is WeaponReplacementHUD:
		if _logger:
			_logger.error("ui", self, "❌ Failed to instantiate weapon replacement HUD")
		return
	
	_weapon_hud = replacement_hud_instance as WeaponReplacementHUD
	_weapon_hud.mount_controller = _mount_controller
	canvas_layer.add_child(_weapon_hud)
	
	if _logger:
		_logger.info("ui", self, "📺 HUD created for player mount")

## Update display HUD with current weapon state
func update_display_hud(left_weapon: WeaponAttachment, right_weapon: WeaponAttachment) -> void:
	if not _mount_controller.is_player or _weapon_display_hud == null:
		return
	
	var hud_start: int = Time.get_ticks_msec()
	if _logger:
		_logger.info("weapon", self, "⏱️ [TIMING START] update_display_hud() called")
	
	# Update slot 1 (left weapon)
	var slot1_start: int = Time.get_ticks_msec()
	_weapon_display_hud.update_weapon_slot(1, left_weapon)
	var slot1_time: int = Time.get_ticks_msec() - slot1_start
	if _logger:
		_logger.info("weapon", self, "⏱️ [TIMING] Slot 1 update took %d ms" % slot1_time)
	
	# Connect ammo signal if weapon exists and changed
	if left_weapon != null:
		_connect_weapon_signals(left_weapon, 1)
	
	# Update slot 2 (right weapon)
	var slot2_start: int = Time.get_ticks_msec()
	_weapon_display_hud.update_weapon_slot(2, right_weapon)
	var slot2_time: int = Time.get_ticks_msec() - slot2_start
	if _logger:
		_logger.info("weapon", self, "⏱️ [TIMING] Slot 2 update took %d ms" % slot2_time)
	
	# Connect ammo signal if weapon exists and changed
	if right_weapon != null:
		_connect_weapon_signals(right_weapon, 2)
	
	var hud_total: int = Time.get_ticks_msec() - hud_start
	if _logger:
		_logger.info("weapon", self, "⏱️ [TIMING END] update_display_hud() took %d ms total" % hud_total)

## Connect weapon signals for HUD updates
func _connect_weapon_signals(weapon: WeaponAttachment, slot: int) -> void:
	if weapon == null:
		return
	
	var weapon_id: int = weapon.get_instance_id()
	var last_weapon_id: int = _last_hud_weapons.get(slot, -1)
	
	# Only reconnect signals if weapon actually changed
	if weapon_id != last_weapon_id:
		# Disconnect previous connections if any
		if weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed) or weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
			# Try to disconnect from both (only one will be connected)
			if weapon.ammo_changed.is_connected(_on_left_weapon_ammo_changed):
				weapon.ammo_changed.disconnect(_on_left_weapon_ammo_changed)
			if weapon.ammo_changed.is_connected(_on_right_weapon_ammo_changed):
				weapon.ammo_changed.disconnect(_on_right_weapon_ammo_changed)
		
		if weapon.ammo_depleted.is_connected(_on_weapon_ammo_depleted):
			weapon.ammo_depleted.disconnect(_on_weapon_ammo_depleted)
		
		# Connect new signals based on slot
		if slot == 1:
			weapon.ammo_changed.connect(_on_left_weapon_ammo_changed)
		elif slot == 2:
			weapon.ammo_changed.connect(_on_right_weapon_ammo_changed)
		
		weapon.ammo_depleted.connect(_on_weapon_ammo_depleted)
		_last_hud_weapons[slot] = weapon_id
		
		if _logger:
			_logger.debug("weapon", self, "🔌 connected weapon signals for slot %d (weapon changed)" % slot)
	else:
		if _logger:
			_logger.debug("weapon", self, "⏭️ skipped signal reconnect (same weapon)")

## Clear HUD cache for a slot
func clear_slot_cache(slot: int) -> void:
	if _weapon_display_hud != null:
		_weapon_display_hud.clear_slot_cache(slot)
		if _logger:
			_logger.debug("weapon", self, "🗑️ HUD cache cleared for slot %d" % slot)
	
	# Clear weapon tracking to force signal reconnection for new weapon
	_last_hud_weapons.erase(slot)

## Show pickup choice prompt
func show_pickup_choice_prompt(weapon_type: String, weapon_level: int, weapon_color: Color, decision, left_type: String, right_type: String) -> void:
	if not _mount_controller.is_player or _weapon_hud == null:
		if _logger:
			_logger.error("weapon", self, "❌ Cannot show prompt: not player or HUD missing")
		return
	
	# Access properties directly from PickupDecision class (not a Dictionary)
	var upgrade_slots: Array[int] = decision.upgrade_slots
	var free_slot: int = decision.free_slot
	var can_upgrade: bool = decision.can_upgrade
	var can_replace: bool = decision.can_replace
	var can_attach_to_free: bool = decision.can_attach_to_free
	
	# Show appropriate prompt based on decision context
	if can_upgrade or can_replace or can_attach_to_free:
		if can_upgrade and upgrade_slots.size() > 0:
			_weapon_hud.show_upgrade_prompt(weapon_type, weapon_color, left_type, right_type, upgrade_slots, free_slot, weapon_level)
		elif can_attach_to_free and free_slot > 0:
			# Show upgrade prompt with free slot option
			if upgrade_slots.size() > 0:
				# Has both upgrade slots and free slot
				_weapon_hud.show_upgrade_prompt(weapon_type, weapon_color, left_type, right_type, upgrade_slots, free_slot, weapon_level)
			else:
				# Only free slot available, but show replacement prompt for occupied slots
				_weapon_hud.show_replacement_prompt(weapon_type, weapon_color, left_type, right_type, weapon_level)
		else:
			_weapon_hud.show_replacement_prompt(weapon_type, weapon_color, left_type, right_type, weapon_level)
		if _logger:
			_logger.info("weapon", self, "📋 showing pickup choice prompt for: %s (level %d)" % [weapon_type, weapon_level])
	else:
		if _logger:
			_logger.error("weapon", self, "❌ NEEDS_PLAYER_CHOICE but no action flags set")

## Hide pickup choice prompt
func hide_pickup_choice_prompt() -> void:
	if _weapon_hud != null:
		_weapon_hud.hide_prompt()

## Get replacement HUD (for direct access if needed)
func get_replacement_hud() -> WeaponReplacementHUD:
	return _weapon_hud

## Signal handlers for weapon ammo changes
func _on_left_weapon_ammo_changed(new_ammo: int, max_ammo: int) -> void:
	if not _mount_controller.is_player or _weapon_display_hud == null:
		return
	_weapon_display_hud.update_weapon_ammo(1, new_ammo, max_ammo)
	if _logger:
		_logger.debug("weapon", self, "📊 ammo updated: slot=1, ammo=%d/%d" % [new_ammo, max_ammo])

func _on_right_weapon_ammo_changed(new_ammo: int, max_ammo: int) -> void:
	if not _mount_controller.is_player or _weapon_display_hud == null:
		return
	_weapon_display_hud.update_weapon_ammo(2, new_ammo, max_ammo)
	if _logger:
		_logger.debug("weapon", self, "📊 ammo updated: slot=2, ammo=%d/%d" % [new_ammo, max_ammo])

func _on_weapon_ammo_depleted(weapon_type: String) -> void:
	if _logger:
		_logger.info("weapon", self, "⚠️ weapon ammo depleted: %s" % weapon_type)
