extends Control
class_name WeaponReplacementHUD

## Reference to the mount controller that owns this HUD
var mount_controller: MountController = null
var pending_weapon_type: String = ""
var pending_weapon_color: Color = Color.WHITE

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
	
	# Update labels with current weapon info
	_prompt_label.text = "Replace weapon with: %s?" % weapon_type.replace("_", " ").capitalize()
	_option_1_label.text = "[1] Replace %s (Slot 1)" % weapon_1_type.replace("_", " ").capitalize()
	_option_space_label.text = "[SPACE] Drop new weapon"
	_option_2_label.text = "[2] Replace %s (Slot 2)" % weapon_2_type.replace("_", " ").capitalize()
	
	_prompt_panel.visible = true
	_logger.info("ui", self, "📋 showing weapon replacement prompt: %s" % weapon_type)

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
			_logger.info("ui", self, "🎯 USER SELECTED: [1] Replace weapon in slot 1")
			_replace_weapon_slot(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_logger.info("ui", self, "🎯 USER SELECTED: [SPACE] Drop new weapon")
			_drop_weapon()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2:
			_logger.info("ui", self, "🎯 USER SELECTED: [2] Replace weapon in slot 2")
			_replace_weapon_slot(2)
			get_viewport().set_input_as_handled()

func _replace_weapon_slot(slot: int) -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🔄 replacing weapon in slot %d with %s" % [slot, pending_weapon_type])
	mount_controller.replace_weapon_in_slot(slot, pending_weapon_type, pending_weapon_color)
	hide_prompt()

func _drop_weapon() -> void:
	if mount_controller == null:
		return
	
	_logger.info("ui", self, "🚫 dropping new weapon: %s" % pending_weapon_type)
	mount_controller.drop_pending_weapon()
	hide_prompt()

