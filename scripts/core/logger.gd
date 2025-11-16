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

@export var ui_panel_enabled: bool = false
signal level_changed(new_level: int)
signal category_toggled(category: String, enabled: bool)

func _ready() -> void:
	# Truncate log file at startup so each run starts fresh
	var path := "res://log.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("")
		f.flush()
		f.close()

func _create_debug_panel() -> void:
	# Deprecated: UI should live in HUD/LoggerPanel
	pass
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
	root.call_deferred("add_child", panel)
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
	emit_signal("level_changed", int(new_level))

func enable_category(category: String, enabled_flag: bool) -> void:
	categories[category] = enabled_flag
	emit_signal("category_toggled", category, enabled_flag)

func is_enabled(category: String, wanted_level: Level) -> bool:
	if not enabled:
		return false
	if not categories.has(category):
		return false
	return wanted_level >= level and bool(categories[category])

func _fmt(actor: String, msg: String) -> String:
	return "[%s] %s" % [actor, msg]

func _write_line(line: String) -> void:
	var f := FileAccess.open("res://log.txt", FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.flush()
	f.close()

func debug(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.DEBUG):
		var line := _fmt(actor, "🐞 DEBUG " + msg)
		print_rich("[color=GRAY]" + line + "[/color]")
		_write_line(line)

func info(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.INFO):
		var line := _fmt(actor, "ℹ️ " + msg)
		print_rich(line)
		_write_line(line)

func warn(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.WARN):
		var line := _fmt(actor, "⚠️ " + msg)
		push_warning(line)
		_write_line("W " + line)

func error(category: String, actor: String, msg: String) -> void:
	if is_enabled(category, Level.ERROR):
		var line := _fmt(actor, "❌ " + msg)
		push_error(line)
		_write_line("E " + line)

func stat_delta(category: String, actor: String, stat_name: String, before_val: float, after_val: float, emoji: String) -> void:
	if is_enabled(category, Level.INFO):
		var delta := after_val - before_val
		var line := _fmt(actor, "%s %s %s -> %s (Δ %s)" % [emoji, stat_name, str(before_val), str(after_val), str(delta)])
		print_rich(line)
		_write_line(line)
