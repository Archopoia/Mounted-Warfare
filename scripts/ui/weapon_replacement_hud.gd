extends Control
class_name WeaponReplacementHUD

## Reference to the mount controller that owns this HUD
var mount_controller: MountController = null
var pending_weapon_type: String = ""
var pending_weapon_color: Color = Color.WHITE
var pending_weapon_level: int = 1  # Store weapon level for upgrades
var _refill_slot: int = 0  # Slot number that can be refilled (0 = no refill option)
var _upgrade_slots: Array[int] = []  # Slots that can be upgraded
var _free_slot: int = 0  # Free slot available (0 = none)

@onready var _prompt_panel: Panel = $PromptPanel
@onready var _prompt_label: Label = $PromptPanel/VBoxContainer/PromptLabel
@onready var _option_1_label: Label = $PromptPanel/VBoxContainer/Option1Label
@onready var _option_space_label: Label = $PromptPanel/VBoxContainer/OptionSpaceLabel
@onready var _option_2_label: Label = $PromptPanel/VBoxContainer/Option2Label

var _logger: Node

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	hide_prompt()

func show_replacement_prompt(weapon_type: String, weapon_color: Color, weapon_1_type: String, weapon_2_type: String, weapon_level: int = 1) -> void:
	pending_weapon_type = weapon_type
	pending_weapon_color = weapon_color
	pending_weapon_level = weapon_level
	_refill_slot = 0  # Will be set if we find a slot that needs refilling
	
	# Check which slots need refilling (same weapon type but depleted)
	if mount_controller != null:
		var slot1_weapon: WeaponAttachment = mount_controller._slot_manager.get_weapon_at_slot(1)
		var slot2_weapon: WeaponAttachment = mount_controller._slot_manager.get_weapon_at_slot(2)
		
		# Check if slot 1 has same weapon type and needs refill
		if slot1_weapon != null and slot1_weapon.weapon_type == weapon_type:
			if slot1_weapon.current_ammo < slot1_weapon.max_ammo:
				_refill_slot = 1
		
		# Check if slot 2 has same weapon type and needs refill (only if slot 1 doesn't)
		if _refill_slot == 0 and slot2_weapon != null and slot2_weapon.weapon_type == weapon_type:
			if slot2_weapon.current_ammo < slot2_weapon.max_ammo:
				_refill_slot = 2
	
	# Update labels with current weapon info
	_prompt_label.text = "Replace weapon with: %s?" % weapon_type.replace("_", " ").capitalize()
	
	if _refill_slot == 1:
		# Slot 1 needs refilling
		_option_1_label.text = "[1] Refill %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	elif _refill_slot == 2:
		# Slot 2 needs refilling
		_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Refill %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	else:
		# No refill needed - standard replacement
		_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	
	_option_space_label.text = "[SPACE] Drop new weapon"
	
	_prompt_panel.visible = true
	_logger.info("ui", self, "📋 showing weapon replacement prompt: %s (refill_slot=%d)" % [weapon_type, _refill_slot])

func show_replacement_prompt_with_refill(weapon_type: String, weapon_color: Color, weapon_1_type: String, weapon_2_type: String, refill_slot: int, weapon_level: int = 1) -> void:
	pending_weapon_type = weapon_type
	pending_weapon_color = weapon_color
	pending_weapon_level = weapon_level
	_refill_slot = refill_slot
	
	# Update labels - show refill option for the matching slot
	_prompt_label.text = "Replace weapon with: %s?" % weapon_type.replace("_", " ").capitalize()
	
	if refill_slot == 1:
		_option_1_label.text = "[1] Refill %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	else:
		_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Refill %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	
	_option_space_label.text = "[SPACE] Drop new weapon"
	
	_prompt_panel.visible = true
	_logger.info("ui", self, "📋 showing weapon replacement prompt with refill: %s (refill slot %d)" % [weapon_type, refill_slot])

func hide_prompt() -> void:
	_prompt_panel.visible = false
	pending_weapon_type = ""
	pending_weapon_level = 1
	_logger.debug("ui", self, "📋 hiding weapon replacement prompt")

func _input(event: InputEvent) -> void:
	if not _prompt_panel.visible:
		return
	
	if mount_controller == null:
		return
	
	# Only handle input if this is the player's mount
	if not mount_controller.is_player:
		return
	
		# Check for key presses (only handle pressed events, not released)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			# Check if this is a refill, upgrade, attach to free slot, or replace option
			if _refill_slot == 1:
				_logger.info("ui", self, "🎯 USER SELECTED: [1] Refill weapon in slot 1")
				_refill_weapon_slot(1)
			elif _free_slot == 1:
				_logger.info("ui", self, "🎯 USER SELECTED: [1] Attach to free slot 1")
				_attach_to_free_slot(1)
			elif _upgrade_slots.has(1):
				_logger.info("ui", self, "🎯 USER SELECTED: [1] Upgrade weapon in slot 1")
				_upgrade_weapon_slot(1)
			else:
				_logger.info("ui", self, "🎯 USER SELECTED: [1] Replace weapon in slot 1")
				_replace_weapon_slot(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_logger.info("ui", self, "🎯 USER SELECTED: [SPACE] Drop new weapon")
			_drop_weapon()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2:
			# Check if this is a refill, upgrade, attach to free slot, or replace option
			if _refill_slot == 2:
				_logger.info("ui", self, "🎯 USER SELECTED: [2] Refill weapon in slot 2")
				_refill_weapon_slot(2)
			elif _free_slot == 2:
				_logger.info("ui", self, "🎯 USER SELECTED: [2] Attach to free slot 2")
				_attach_to_free_slot(2)
			elif _upgrade_slots.has(2):
				_logger.info("ui", self, "🎯 USER SELECTED: [2] Upgrade weapon in slot 2")
				_upgrade_weapon_slot(2)
			else:
				_logger.info("ui", self, "🎯 USER SELECTED: [2] Replace weapon in slot 2")
				_replace_weapon_slot(2)
			get_viewport().set_input_as_handled()

func _replace_weapon_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🔄 replacing weapon in slot %d with %s (level %d)" % [slot, pending_weapon_type, pending_weapon_level])
	mount_controller.replace_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color, pending_weapon_level)
	hide_prompt()

func _refill_weapon_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	# Check if weapon needs refill and if there are remaining levels for upgrades
	var weapon: WeaponAttachment = null
	if slot == 1:
		weapon = mount_controller._slot_manager.get_weapon_at_slot(1)
	elif slot == 2:
		weapon = mount_controller._slot_manager.get_weapon_at_slot(2)
	
	var needs_refill: bool = false
	if weapon != null:
		needs_refill = weapon.current_ammo < weapon.max_ammo
	
	# If weapon level > 1, refill first (uses 1 level), then apply remaining levels as upgrades
	if pending_weapon_level > 1:
		if needs_refill:
			# Refill first (consumes 1 level), then apply remaining levels as upgrades
			_logger.info("ui", self, "🔋⬆️ refilling and upgrading weapon in slot %d: refill (1 level) + %d upgrades" % [slot, pending_weapon_level - 1])
			
			# Step 1: Refill missing ammo (consumes 1 level conceptually)
			mount_controller.refill_weapon_in_slot(slot)
			
			# Step 2: Apply remaining levels as upgrades (weapon_level - 1, since 1 was used for refill)
			var remaining_levels: int = pending_weapon_level - 1
			if remaining_levels > 0:
				for i in range(remaining_levels):
					mount_controller.upgrade_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color)
		else:
			# Weapon is at full ammo, apply all levels as upgrades
			_logger.info("ui", self, "⬆️ upgrading weapon in slot %d with %d levels (weapon already at full ammo)" % [slot, pending_weapon_level])
			for i in range(pending_weapon_level):
				mount_controller.upgrade_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color)
	else:
		# Level 1 pickup - just refill
		_logger.info("ui", self, "🔋 refilling weapon in slot %d" % slot)
		mount_controller.refill_weapon_in_slot(slot)
	
	hide_prompt()

func _upgrade_weapon_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	# Check if weapon needs refill first
	var weapon: WeaponAttachment = null
	if slot == 1:
		weapon = mount_controller._slot_manager.get_weapon_at_slot(1)
	elif slot == 2:
		weapon = mount_controller._slot_manager.get_weapon_at_slot(2)
	
	# CRITICAL: Check if weapon types match - if not, replace instead of upgrade
	if weapon != null and weapon.weapon_type != pending_weapon_type:
		_logger.info("ui", self, "🔄 weapon type mismatch: slot %d has %s, pickup is %s - replacing instead of upgrading" % [slot, weapon.weapon_type, pending_weapon_type])
		_replace_weapon_slot(slot)
		return
	
	var needs_refill: bool = false
	var missing_ammo: int = 0
	if weapon != null:
		missing_ammo = weapon.max_ammo - weapon.current_ammo
		needs_refill = missing_ammo > 0
	
	if needs_refill and pending_weapon_level > 1:
		# Refill first (consumes 1 level), then apply remaining levels as upgrades
		_logger.info("ui", self, "🔋⬆️ refilling and upgrading weapon in slot %d: refill (1 level) + %d upgrades" % [slot, pending_weapon_level - 1])
		
		# Step 1: Refill missing ammo (consumes 1 level)
		mount_controller.refill_weapon_in_slot(slot)
		
		# Step 2: Apply remaining levels as upgrades (weapon_level - 1, since 1 was used for refill)
		var remaining_levels: int = pending_weapon_level - 1
		if remaining_levels > 0:
			for i in range(remaining_levels):
				mount_controller.upgrade_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color)
	else:
		# Weapon is at full ammo, apply all levels as upgrades
		_logger.info("ui", self, "⬆️ upgrading weapon in slot %d with %d levels (weapon already at full ammo)" % [slot, pending_weapon_level])
		for i in range(pending_weapon_level):
			mount_controller.upgrade_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color)
	
	hide_prompt()

func _attach_to_free_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "➕ attaching to free slot %d (level %d)" % [slot, pending_weapon_level])
	mount_controller.attach_weapon_to_slot(slot, pending_weapon_type, pending_weapon_color, pending_weapon_level)
	hide_prompt()

func show_upgrade_prompt(weapon_type: String, weapon_color: Color, weapon_1_type: String, weapon_2_type: String, upgrade_slots: Array[int], free_slot: int, weapon_level: int = 1) -> void:
	pending_weapon_type = weapon_type
	pending_weapon_color = weapon_color
	pending_weapon_level = weapon_level
	_upgrade_slots = upgrade_slots
	_free_slot = free_slot
	_refill_slot = 0  # Will be set if we find a slot that needs refilling
	
	# Check which slots need refilling (same weapon type but depleted)
	if mount_controller != null:
		var slot1_weapon: WeaponAttachment = mount_controller._slot_manager.get_weapon_at_slot(1)
		var slot2_weapon: WeaponAttachment = mount_controller._slot_manager.get_weapon_at_slot(2)
		
		# Check if slot 1 has same weapon type and needs refill
		if slot1_weapon != null and slot1_weapon.weapon_type == weapon_type:
			if slot1_weapon.current_ammo < slot1_weapon.max_ammo:
				_refill_slot = 1
		
		# Check if slot 2 has same weapon type and needs refill (only if slot 1 doesn't)
		if _refill_slot == 0 and slot2_weapon != null and slot2_weapon.weapon_type == weapon_type:
			if slot2_weapon.current_ammo < slot2_weapon.max_ammo:
				_refill_slot = 2
	
	# Update labels
	_prompt_label.text = "Upgrade weapon with: %s?" % weapon_type.replace("_", " ").capitalize()
	
	# Determine what options to show
	if upgrade_slots.size() > 0 and free_slot > 0:
		# Can upgrade slot(s) OR attach to free slot
		if free_slot == 1:
			_option_1_label.text = "[1] Attach to free slot 1"
		elif _refill_slot == 1:
			_option_1_label.text = "[1] Refill %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		elif upgrade_slots.has(1):
			_option_1_label.text = "[1] Upgrade %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		else:
			_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		
		if free_slot == 2:
			_option_2_label.text = "[2] Attach to free slot 2"
		elif _refill_slot == 2:
			_option_2_label.text = "[2] Refill %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		elif upgrade_slots.has(2):
			_option_2_label.text = "[2] Upgrade %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		else:
			_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	elif upgrade_slots.size() > 0:
		# Can only upgrade
		if _refill_slot == 1:
			_option_1_label.text = "[1] Refill %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		elif upgrade_slots.has(1):
			_option_1_label.text = "[1] Upgrade %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		else:
			_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		
		if _refill_slot == 2:
			_option_2_label.text = "[2] Refill %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		elif upgrade_slots.has(2):
			_option_2_label.text = "[2] Upgrade %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		else:
			_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	else:
		# Standard replacement - but check for refill slots
		if _refill_slot == 1:
			_option_1_label.text = "[1] Refill %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		else:
			_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		
		if _refill_slot == 2:
			_option_2_label.text = "[2] Refill %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		else:
			_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	
	_option_space_label.text = "[SPACE] Drop new weapon"
	
	_prompt_panel.visible = true
	_logger.info("ui", self, "📋 showing upgrade prompt: %s (upgrade_slots=%s, free_slot=%d, refill_slot=%d)" % [weapon_type, str(upgrade_slots), free_slot, _refill_slot])

func _drop_weapon() -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🚫 dropping new weapon: %s" % pending_weapon_type)
	mount_controller.drop_pending_weapon()
	hide_prompt()

