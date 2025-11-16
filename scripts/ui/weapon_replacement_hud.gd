extends Control
class_name WeaponReplacementHUD

## Reference to the mount controller that owns this HUD
var mount_controller: MountController = null
var pending_weapon_type: String = ""
var pending_weapon_color: Color = Color.WHITE
var _refill_slot: int = 0  # Slot number that can be refilled (0 = no refill option)

@onready var _prompt_panel: Panel = $PromptPanel
@onready var _prompt_label: Label = $PromptPanel/VBoxContainer/PromptLabel
@onready var _option_1_label: Label = $PromptPanel/VBoxContainer/Option1Label
@onready var _option_space_label: Label = $PromptPanel/VBoxContainer/OptionSpaceLabel
@onready var _option_2_label: Label = $PromptPanel/VBoxContainer/Option2Label

var _logger: Node

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	hide_prompt()

func show_replacement_prompt(weapon_type: String, weapon_color: Color, weapon_1_type: String, weapon_2_type: String) -> void:
	pending_weapon_type = weapon_type
	pending_weapon_color = weapon_color
	_refill_slot = 0  # No refill option for standard replacement
	
	# Check if the new weapon matches either existing weapon
	var matches_slot_1: bool = weapon_1_type == weapon_type
	var matches_slot_2: bool = weapon_2_type == weapon_type
	
	# Update labels with current weapon info
	_prompt_label.text = "Replace weapon with: %s?" % weapon_type.replace("_", " ").capitalize()
	
	if matches_slot_1:
		# New weapon matches slot 1 - show refill option for slot 1, replace option for slot 2
		_option_1_label.text = "[1] Refill %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		_refill_slot = 1
	elif matches_slot_2:
		# New weapon matches slot 2 - show replace option for slot 1, refill option for slot 2
		_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Refill %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
		_refill_slot = 2
	else:
		# New weapon doesn't match either - standard replacement
		_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
		_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	
	_option_space_label.text = "[SPACE] Drop new weapon"
	
	_prompt_panel.visible = true
	_logger.info("ui", self, "📋 showing weapon replacement prompt: %s" % weapon_type)

func show_replacement_prompt_with_refill(weapon_type: String, weapon_color: Color, weapon_1_type: String, weapon_2_type: String, refill_slot: int) -> void:
	pending_weapon_type = weapon_type
	pending_weapon_color = weapon_color
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
			# Check if this is a refill option
			if _refill_slot == 1:
				_logger.info("ui", self, "🎯 USER SELECTED: [1] Refill weapon in slot 1")
				_refill_weapon_slot(1)
			else:
				_logger.info("ui", self, "🎯 USER SELECTED: [1] Replace weapon in slot 1")
				_replace_weapon_slot(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_logger.info("ui", self, "🎯 USER SELECTED: [SPACE] Drop new weapon")
			_drop_weapon()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2:
			# Check if this is a refill option
			if _refill_slot == 2:
				_logger.info("ui", self, "🎯 USER SELECTED: [2] Refill weapon in slot 2")
				_refill_weapon_slot(2)
			else:
				_logger.info("ui", self, "🎯 USER SELECTED: [2] Replace weapon in slot 2")
				_replace_weapon_slot(2)
			get_viewport().set_input_as_handled()

func _replace_weapon_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🔄 replacing weapon in slot %d with %s" % [slot, pending_weapon_type])
	mount_controller.replace_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color)
	hide_prompt()

func _refill_weapon_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🔋 refilling weapon in slot %d" % slot)
	mount_controller.refill_weapon_in_slot(slot)
	hide_prompt()

func _drop_weapon() -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🚫 dropping new weapon: %s" % pending_weapon_type)
	mount_controller.drop_pending_weapon()
	hide_prompt()

