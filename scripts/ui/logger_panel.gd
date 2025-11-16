extends Control
class_name LoggerPanel

@onready var _content: VBoxContainer = $Content
@onready var _logger = get_node("/root/LoggerInstance")

func _ready() -> void:
	if _logger == null:
		return
	_build_ui()

func _build_ui() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Logger"
	_content.add_child(title)
	var lvl := OptionButton.new()
	lvl.add_item("DEBUG", 0)
	lvl.add_item("INFO", 1)
	lvl.add_item("WARN", 2)
	lvl.add_item("ERROR", 3)
	lvl.selected = _logger.level
	lvl.item_selected.connect(func(idx): _logger.set_level(idx))
	_content.add_child(lvl)
	for k in _logger.categories.keys():
		var cb := CheckBox.new()
		cb.text = k
		cb.button_pressed = _logger.categories[k]
		cb.toggled.connect(func(p): _logger.enable_category(k, p))
		_content.add_child(cb)
