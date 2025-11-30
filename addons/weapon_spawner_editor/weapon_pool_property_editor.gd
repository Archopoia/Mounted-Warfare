@tool
extends EditorProperty

const WeaponPoolEntryClass = preload("res://scripts/pickups/weapon_pool_entry.gd")

var _container: VBoxContainer
var _array_elements: Array[Control] = []
var _add_button: Button
var _current_value: Array[WeaponPoolEntry] = []

func _init() -> void:
	_container = VBoxContainer.new()
	add_child(_container)
	
	# Add button to add new elements
	_add_button = Button.new()
	_add_button.text = "Add Weapon to Pool"
	_add_button.pressed.connect(_on_add_button_pressed)
	_container.add_child(_add_button)
	
	print("Weapon Pool Editor: Initialized property editor")

func _update_property() -> void:
	var edited_object = get_edited_object()
	var property_name = get_edited_property()
	
	if not edited_object:
		print("Weapon Pool Editor: ERROR - No edited object in _update_property!")
		return
	
	var new_value = edited_object.get(property_name)
	if new_value == null:
		new_value = []
	
	print("Weapon Pool Editor: Updating property '%s' with value: %s" % [property_name, new_value])
	
	var value_array: Array = new_value
	_current_value = []
	for item in value_array:
		if item is WeaponPoolEntry:
			_current_value.append(item)
		elif item is Dictionary:
			# Convert dictionary to WeaponPoolEntry (backwards compatibility)
			var entry: WeaponPoolEntry = WeaponPoolEntryClass.new()
			entry.weapon_type = item.get("weapon_type", "rocket_launcher")
			entry.level = item.get("level", 1)
			_current_value.append(entry)
		else:
			# Legacy string support - convert to WeaponPoolEntry
			var entry: WeaponPoolEntry = WeaponPoolEntryClass.new()
			entry.weapon_type = str(item)
			entry.level = 1
			_current_value.append(entry)
	
	_update_ui()

func _update_ui() -> void:
	# Clear existing UI elements (except add button)
	for element in _array_elements:
		if is_instance_valid(element):
			element.queue_free()
	_array_elements.clear()
	
	# Get available weapon types using helper function
	var available_weapons: Array[String] = _get_available_weapons()
	
	# Create UI for each array element
	for i in range(_current_value.size()):
		var entry: WeaponPoolEntry = _current_value[i]
		_create_element_ui(i, entry, available_weapons)
	
	# Move add button to the end
	_container.move_child(_add_button, _container.get_child_count() - 1)

func _create_element_ui(index: int, entry: WeaponPoolEntry, available_weapons: Array[String]) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	
	# Create weapon type dropdown
	var option_button: OptionButton = OptionButton.new()
	option_button.custom_minimum_size = Vector2(180, 0)
	
	# Populate dropdown with available weapons
	var selected_index: int = -1
	for i in range(available_weapons.size()):
		var weapon_type: String = available_weapons[i]
		var display_name: String = WeaponRegistry.get_weapon_name(weapon_type)
		option_button.add_item("%s (%s)" % [display_name, weapon_type])
		if weapon_type == entry.weapon_type:
			selected_index = i
	
	# If current weapon not found, add it as custom option
	if selected_index == -1:
		option_button.add_item("%s (custom)" % entry.weapon_type)
		selected_index = available_weapons.size()
	
	option_button.selected = selected_index
	option_button.item_selected.connect(func(idx): _on_weapon_selected(index, idx, available_weapons))
	
	# Create level label
	var level_label: Label = Label.new()
	level_label.text = "Lvl:"
	level_label.custom_minimum_size = Vector2(30, 0)
	
	# Create level spinbox
	var level_spinbox: SpinBox = SpinBox.new()
	level_spinbox.custom_minimum_size = Vector2(60, 0)
	level_spinbox.min_value = 1
	level_spinbox.max_value = 10
	level_spinbox.value = entry.level
	level_spinbox.value_changed.connect(func(value): _on_level_changed(index, int(value)))
	
	# Create remove button
	var remove_button: Button = Button.new()
	remove_button.text = "×"
	remove_button.custom_minimum_size = Vector2(30, 0)
	remove_button.pressed.connect(func(): _on_remove_button_pressed(index))
	
	hbox.add_child(option_button)
	hbox.add_child(level_label)
	hbox.add_child(level_spinbox)
	hbox.add_child(remove_button)
	
	_array_elements.append(hbox)
	_container.add_child(hbox)
	
	# Move add button to the end
	_container.move_child(_add_button, _container.get_child_count() - 1)

func _on_weapon_selected(element_index: int, dropdown_index: int, available_weapons: Array[String]) -> void:
	if element_index < 0 or element_index >= _current_value.size():
		return
	
	var selected_weapon: String
	if dropdown_index < available_weapons.size():
		selected_weapon = available_weapons[dropdown_index]
	else:
		# Custom weapon (fallback)
		selected_weapon = _current_value[element_index].weapon_type
	
	var entry: WeaponPoolEntry = _current_value[element_index]
	entry.weapon_type = selected_weapon
	_commit_changes()

func _on_level_changed(element_index: int, new_level: int) -> void:
	if element_index < 0 or element_index >= _current_value.size():
		return
	
	var entry: WeaponPoolEntry = _current_value[element_index]
	entry.level = new_level
	_commit_changes()

func _on_remove_button_pressed(index: int) -> void:
	if index >= 0 and index < _current_value.size():
		_current_value.remove_at(index)
		_update_ui()
		_commit_changes()

func _get_available_weapons() -> Array[String]:
	# Try to get weapons from registry
	var available_weapons: Array[String] = []
	
	# Try accessing the static dictionary directly using the class name
	var weapon_defs = WeaponRegistry.weapon_definitions
	if weapon_defs != null and weapon_defs is Dictionary:
		for weapon_type in weapon_defs.keys():
			available_weapons.append(str(weapon_type))
		print("Weapon Pool Editor: Found ", available_weapons.size(), " weapons via static dictionary: ", available_weapons)
	
	# Try using the static method as backup
	if available_weapons.is_empty():
		available_weapons = WeaponRegistry.get_all_weapon_types()
		if not available_weapons.is_empty():
			print("Weapon Pool Editor: Found ", available_weapons.size(), " weapons via static method")
	
	# Final fallback - hardcoded list
	if available_weapons.is_empty():
		available_weapons = ["rocket_launcher", "mine_layer", "autocannon"]
		print("Weapon Pool Editor: Using fallback hardcoded list")
	
	return available_weapons

func _on_add_button_pressed() -> void:
	print("Weapon Pool Editor: ADD BUTTON PRESSED!")
	
	if not Engine.is_editor_hint():
		print("Weapon Pool Editor: ERROR - Not in editor!")
		return
	
	var available_weapons: Array[String] = _get_available_weapons()
	print("Weapon Pool Editor: Available weapons count: ", available_weapons.size())
	
	if available_weapons.size() > 0:
		# Create a new WeaponPoolEntry
		var new_entry: WeaponPoolEntry = WeaponPoolEntryClass.new()
		new_entry.weapon_type = available_weapons[0]
		new_entry.level = 1
		
		_current_value.append(new_entry)
		print("Weapon Pool Editor: Adding weapon '%s' level %d to pool. New size: %d" % [new_entry.weapon_type, new_entry.level, _current_value.size()])
		_update_ui()
		_commit_changes()
	else:
		print("Weapon Pool Editor: ERROR - No available weapons found!")

func _commit_changes() -> void:
	var edited_object = get_edited_object()
	var property_name = get_edited_property()
	
	if not edited_object:
		print("Weapon Pool Editor: ERROR - No edited object!")
		return
	
	if property_name.is_empty():
		print("Weapon Pool Editor: ERROR - No property name!")
		return
	
	# Create array of WeaponPoolEntry resources
	var array_value: Array[WeaponPoolEntry] = []
	for entry in _current_value:
		# Ensure we have valid entries
		if entry != null and entry is WeaponPoolEntry:
			array_value.append(entry)
	
	print("Weapon Pool Editor: Committing changes - property: '%s', entries: %d" % [property_name, array_value.size()])
	
	# Set the property value and emit changed signal
	edited_object.set(property_name, array_value)
	emit_changed(property_name, array_value)
