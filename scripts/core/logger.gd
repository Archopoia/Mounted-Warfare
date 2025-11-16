extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

var enabled: bool = true
var level: Level = Level.INFO

# Per-aspect toggles designers can control at runtime
var categories := {
	"movement": true,
	"combat": true,
	"projectile": true,
	"pickup": true,
	"progression": true,
	"health": true,
	"ai": true,
	"scene": true
}

@export var ui_panel_enabled: bool = true

func _ready() -> void:
	if ui_panel_enabled:
		_create_debug_panel()

func _create_debug_panel() -> void:
	var root := get_tree().root
	if not root:
		return
	var panel := Control.new()
	panel.name = "LoggerPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_right = 0
	panel.offset_left = -260
	panel.offset_top = 10
	panel.offset_bottom = 120
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Logger"
	vb.add_child(title)
	var lvl := OptionButton.new()
	lvl.add_item("DEBUG", Level.DEBUG)
	lvl.add_item("INFO", Level.INFO)
	lvl.add_item("WARN", Level.WARN)
	lvl.add_item("ERROR", Level.ERROR)
	lvl.selected = level
	lvl.connect("item_selected", func(idx): set_level(idx))
	vb.add_child(lvl)
	for k in categories.keys():
		var cb := CheckBox.new()
		cb.text = k
		cb.button_pressed = categories[k]
		cb.connect("toggled", func(p): enable_category(k, p))
		vb.add_child(cb)

func set_level(new_level: Level) -> void:
	level = new_level

func enable_category(category: String, is_enabled: bool) -> void:
	categories[category] = is_enabled

func is_enabled(category: String, wanted_level: Level) -> bool:
	if not enabled:
		return false
	if not categories.has(category):
		return false
	return wanted_level >= level and bool(categories[category])

func _fmt(actor: String, msg: String) -> String:
	return "[%s] %s" % [actor, msg]

func debug(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.DEBUG):
		print_rich(_fmt(actor, "[color=GRAY]🐞 DEBUG[/color] " + msg))

func info(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.INFO):
		print_rich(_fmt(actor, "ℹ️ " + msg))

func warn(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.WARN):
		push_warning(_fmt(actor, "⚠️ " + msg))

func error(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.ERROR):
		push_error(_fmt(actor, "❌ " + msg))

func stat_delta(category: String, actor: String, stat_name: String, before_val: float, after_val: float, emoji: String) -> void:
	if is_enabled(category, Level.INFO):
		var delta := after_val - before_val
		print_rich(_fmt(actor, "%s %s %s -> %s (Δ %s)" % [emoji, stat_name, str(before_val), str(after_val), str(delta)]))

