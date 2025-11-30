extends Node
class_name WeaponInputHandler

## Handles weapon input tracking and attack coordination
## Separates input logic from mount controller for better organization

## Signal emitted when primary attack should be performed
signal primary_attack_requested(slot: int)
## Signal emitted when secondary attack starts
signal secondary_attack_started(slot: int)
## Signal emitted when secondary attack should be updated (during charge)
signal secondary_attack_updated(slot: int, delta: float)
## Signal emitted when secondary attack should be released
signal secondary_attack_released(slot: int)

var _mount_controller: MountController = null
var _logger: Node = null
# Track secondary attack state
var _left_button_held: bool = false
var _right_button_held: bool = false
var _left_button_press_time: float = 0.0
var _right_button_press_time: float = 0.0
var _click_threshold: float = 0.2  # Time in seconds to distinguish click from hold

func initialize(mount_controller: MountController, logger: Node) -> void:
	_mount_controller = mount_controller
	_logger = logger
	
	if _logger:
		_logger.debug("weapon", self, "🔧 WeaponInputHandler initialized")

func _input(event: InputEvent) -> void:
	# Only handle weapon input for player mounts
	if not _mount_controller.is_player:
		return
	
	# Handle mouse button events for primary and secondary attacks
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Button just pressed - start tracking
				_left_button_held = true
				_left_button_press_time = 0.0
				if _logger:
					_logger.debug("weapon", self, "🖱️ left mouse button pressed")
			else:
				# Button released
				if _left_button_held:
					# Check if it was a click (quick press/release) or hold
					if _left_button_press_time < _click_threshold:
						# Quick click - primary attack
						if _logger:
							_logger.debug("weapon", self, "🖱️ left mouse button released (click) - primary attack")
						primary_attack_requested.emit(1)  # Slot 1 = left
					else:
						# Hold - secondary attack release
						if _logger:
							_logger.debug("weapon", self, "🖱️ left mouse button released (hold) - secondary attack")
						secondary_attack_released.emit(1)  # Slot 1 = left
					_left_button_held = false
					_left_button_press_time = 0.0
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Button just pressed - start tracking
				_right_button_held = true
				_right_button_press_time = 0.0
				if _logger:
					_logger.debug("weapon", self, "🖱️ right mouse button pressed")
			else:
				# Button released
				if _right_button_held:
					# Check if it was a click (quick press/release) or hold
					if _right_button_press_time < _click_threshold:
						# Quick click - primary attack
						if _logger:
							_logger.debug("weapon", self, "🖱️ right mouse button released (click) - primary attack")
						primary_attack_requested.emit(2)  # Slot 2 = right
					else:
						# Hold - secondary attack release
						if _logger:
							_logger.debug("weapon", self, "🖱️ right mouse button released (hold) - secondary attack")
						secondary_attack_released.emit(2)  # Slot 2 = right
					_right_button_held = false
					_right_button_press_time = 0.0

func _process(delta: float) -> void:
	# Only handle weapon input for player mounts
	if not _mount_controller.is_player:
		return
	
	# Update button hold timers
	if _left_button_held:
		var old_time: float = _left_button_press_time
		_left_button_press_time += delta
		# If we just crossed the threshold, start secondary attack
		if old_time < _click_threshold and _left_button_press_time >= _click_threshold:
			secondary_attack_started.emit(1)  # Slot 1 = left
		# Update secondary charge if already started
		if _left_button_press_time >= _click_threshold:
			secondary_attack_updated.emit(1, delta)
	
	if _right_button_held:
		var old_time: float = _right_button_press_time
		_right_button_press_time += delta
		# If we just crossed the threshold, start secondary attack
		if old_time < _click_threshold and _right_button_press_time >= _click_threshold:
			secondary_attack_started.emit(2)  # Slot 2 = right
		# Update secondary charge if already started
		if _right_button_press_time >= _click_threshold:
			secondary_attack_updated.emit(2, delta)

