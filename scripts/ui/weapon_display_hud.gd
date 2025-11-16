extends Control

class_name WeaponDisplayHUD

## Reference to the mount controller that owns this HUD
var mount_controller: MountController = null

@onready var _slot_1_panel: Panel = $WeaponSlotsContainer/Slot1Panel
@onready var _slot_2_panel: Panel = $WeaponSlotsContainer/Slot2Panel
@onready var _slot_1_label: Label = $WeaponSlotsContainer/Slot1Panel/WeaponLabel
@onready var _slot_2_label: Label = $WeaponSlotsContainer/Slot2Panel/WeaponLabel
@onready var _slot_1_visual: Control = $WeaponSlotsContainer/Slot1Panel/WeaponVisual
@onready var _slot_2_visual: Control = $WeaponSlotsContainer/Slot2Panel/WeaponVisual
@onready var _slot_1_ammo_label: Label = $WeaponSlotsContainer/Slot1Panel/AmmoLabel
@onready var _slot_2_ammo_label: Label = $WeaponSlotsContainer/Slot2Panel/AmmoLabel

var _logger: Node
var _weapon_visuals: Dictionary = {}  # Maps slot index to visual node
var _weapon_ammo: Dictionary = {}  # Maps slot index to {current: int, max: int}

func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")
	
	# Initialize slots as empty
	_update_slot_display(1, null)
	_update_slot_display(2, null)
	
	_logger.info("ui", self, "📺 weapon display HUD ready")

func update_weapon_slot(slot: int, weapon: WeaponAttachment) -> void:
	if slot < 1 or slot > 2:
		_logger.error("ui", self, "❌ Invalid weapon slot: %d" % slot)
		return
	
	_logger.debug("ui", self, "📺 update_weapon_slot CALLED: slot=%d, weapon=%s" % [slot, "null" if weapon == null else "%s (id=%d)" % [weapon.weapon_type, weapon.get_instance_id()]])
	
	if weapon != null:
		_logger.debug("ui", self, "📺   weapon details: type=%s, id=%d, ammo=%d/%d" % [weapon.weapon_type, weapon.get_instance_id(), weapon.current_ammo, weapon.max_ammo])
	
	_update_slot_display(slot, weapon)
	
	if weapon != null:
		_logger.debug("ui", self, "✅ updated slot %d: weapon=%s, ammo=%d/%d" % [slot, weapon.weapon_type, weapon.current_ammo, weapon.max_ammo])
	else:
		_logger.debug("ui", self, "✅ cleared slot %d" % slot)

func _update_slot_display(slot: int, weapon: WeaponAttachment) -> void:
	var panel: Panel = null
	var label: Label = null
	var visual_container: Control = null
	var ammo_label: Label = null
	
	if slot == 1:
		panel = _slot_1_panel
		label = _slot_1_label
		visual_container = _slot_1_visual
		ammo_label = _slot_1_ammo_label
	elif slot == 2:
		panel = _slot_2_panel
		label = _slot_2_label
		visual_container = _slot_2_visual
		ammo_label = _slot_2_ammo_label
	
	if panel == null or label == null or visual_container == null or ammo_label == null:
		_logger.error("ui", self, "❌ HUD slot %d UI elements not found" % slot)
		return
	
	# Clear existing visual
	if _weapon_visuals.has(slot):
		var old_visual: Node = _weapon_visuals[slot]
		if is_instance_valid(old_visual):
			old_visual.queue_free()
		_weapon_visuals.erase(slot)
	
	# Clear label
	label.text = ""
	
	if weapon == null:
		# Empty slot - show placeholder
		label.text = "[Slot %d]\nEmpty" % slot
		label.modulate = Color(0.5, 0.5, 0.5, 1.0)
		panel.modulate = Color(0.3, 0.3, 0.3, 0.8)
		ammo_label.text = "Ammo: --/--"
		ammo_label.modulate = Color(0.5, 0.5, 0.5, 0.5)
		ammo_label.visible = false
		_weapon_ammo.erase(slot)
	else:
		# Weapon attached - show weapon info and visual
		_logger.debug("ui", self, "📺 _update_slot_display: slot=%d, weapon_type=%s, weapon_id=%d" % [slot, weapon.weapon_type, weapon.get_instance_id()])
		
		var weapon_name: String = WeaponRegistry.get_weapon_name(weapon.weapon_type)
		label.text = "[Slot %d]\n%s" % [slot, weapon_name.replace("_", " ").capitalize()]
		label.modulate = Color.WHITE
		
		# Always initialize ammo from the actual weapon instance (not cached values)
		# This ensures each weapon instance has its own ammo tracking
		var weapon_ammo_current: int = weapon.current_ammo
		var weapon_ammo_max: int = weapon.max_ammo
		_logger.debug("ui", self, "📺   reading ammo from weapon: current=%d, max=%d" % [weapon_ammo_current, weapon_ammo_max])
		
		_weapon_ammo[slot] = {"current": weapon_ammo_current, "max": weapon_ammo_max}
		_update_ammo_display(slot, weapon_ammo_current, weapon_ammo_max, ammo_label)
		
		var cached_data: Dictionary = _weapon_ammo[slot]
		_logger.debug("ui", self, "📺   cached ammo for slot %d: current=%d, max=%d" % [slot, cached_data.get("current", 0), cached_data.get("max", 0)])
		
		# Get weapon color
		var weapon_color: Color = weapon.weapon_color
		if weapon_color == Color.WHITE:
			weapon_color = WeaponRegistry.get_weapon_color(weapon.weapon_type)
		
		# Create visual representation of the weapon
		_create_weapon_visual(slot, weapon.weapon_type, weapon_color, visual_container)
		
		# Update panel color based on weapon
		panel.modulate = Color(weapon_color.r * 0.5, weapon_color.g * 0.5, weapon_color.b * 0.5, 0.8)

func _create_weapon_visual(slot: int, weapon_type: String, weapon_color: Color, container: Control) -> void:
	# Create a simple colored panel to represent the weapon visually
	var weapon_icon: Panel = Panel.new()
	weapon_icon.custom_minimum_size = Vector2(120, 100)
	
	# Create style with weapon color
	var style_box: StyleBoxFlat = StyleBoxFlat.new()
	style_box.bg_color = weapon_color
	style_box.border_width_left = 3
	style_box.border_width_top = 3
	style_box.border_width_right = 3
	style_box.border_width_bottom = 3
	style_box.border_color = weapon_color * 1.5  # Brighter border
	style_box.corner_radius_top_left = 5
	style_box.corner_radius_top_right = 5
	style_box.corner_radius_bottom_right = 5
	style_box.corner_radius_bottom_left = 5
	weapon_icon.add_theme_stylebox_override("panel", style_box)
	
	# Add weapon name label
	var name_label: Label = Label.new()
	name_label.text = WeaponRegistry.get_weapon_name(weapon_type).substr(0, 12)  # Truncate if too long
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	
	container.add_child(weapon_icon)
	weapon_icon.add_child(name_label)
	
	# Center the label in the panel
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_left = 5
	name_label.offset_top = 5
	name_label.offset_right = -5
	name_label.offset_bottom = -5
	
	# Store reference
	_weapon_visuals[slot] = weapon_icon
	
	_logger.debug("ui", self, "🎨 created weapon visual for slot %d: %s" % [slot, weapon_type])

func update_weapon_ammo(slot: int, current_ammo: int, max_ammo: int) -> void:
	if slot < 1 or slot > 2:
		_logger.error("ui", self, "❌ Invalid weapon slot for ammo update: %d" % slot)
		return
	
	# Update ammo tracking
	_weapon_ammo[slot] = {"current": current_ammo, "max": max_ammo}
	
	# Get ammo label
	var ammo_label: Label = null
	if slot == 1:
		ammo_label = _slot_1_ammo_label
	elif slot == 2:
		ammo_label = _slot_2_ammo_label
	
	if ammo_label == null:
		_logger.error("ui", self, "❌ HUD slot %d ammo label not found" % slot)
		return
	
	# Update ammo display
	_update_ammo_display(slot, current_ammo, max_ammo, ammo_label)
	
	_logger.debug("ui", self, "📊 updated ammo display: slot=%d, ammo=%d/%d" % [slot, current_ammo, max_ammo])

## Clear cached ammo data for a slot (used when replacing weapons)
func clear_slot_cache(slot: int) -> void:
	if _weapon_ammo.has(slot):
		_weapon_ammo.erase(slot)
		_logger.debug("ui", self, "🗑️ cleared cache for slot %d" % slot)

func _update_ammo_display(slot: int, current_ammo: int, max_ammo: int, ammo_label: Label) -> void:
	if ammo_label == null:
		return
	
	# Update ammo text
	ammo_label.text = "Ammo: %d/%d" % [current_ammo, max_ammo]
	ammo_label.visible = true
	
	# Change color based on ammo level
	if current_ammo == 0:
		ammo_label.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red when empty
	elif current_ammo <= max_ammo * 0.2:
		ammo_label.modulate = Color(1.0, 0.7, 0.3, 1.0)  # Orange when low
	else:
		ammo_label.modulate = Color.WHITE  # White when normal
	
	# Make ammo label more prominent with larger font
	var font_size: int = 14
	if current_ammo <= max_ammo * 0.2:
		font_size = 16  # Slightly larger when low
	
	# Note: Font size changes would require a DynamicFont or theme setup
	# For now, we'll use the color modulation which is more immediate
