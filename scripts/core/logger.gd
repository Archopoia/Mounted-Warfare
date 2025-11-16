extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

var enabled: bool = true
var level: Level = Level.INFO
var file_captures_all: bool = true

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

@export var ui_panel_enabled: bool = false  # If true, displays an on-screen debug panel for logger controls (deprecated: use HUD/LoggerPanel instead)
signal level_changed(new_level: int)
signal category_toggled(category: String, enabled: bool)

func _init() -> void:
	# Truncate log file as early as possible in app lifetime
	var path := "res://log.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("")
		f.flush()
		f.close()
	# Enable engine/editor file logging so ALL messages also go to log.txt
	# These settings mirror Project Settings → Logging → File Logging
	ProjectSettings.set_setting("logging/file_logging/enable_file_logging", true)
	ProjectSettings.set_setting("logging/file_logging/log_path", path)
	# Keep a single rotating file so the latest log is always at res://log.txt
	ProjectSettings.set_setting("logging/file_logging/max_log_files", 1)
	# 0 = Debug in Godot 4 log levels; capture everything
	ProjectSettings.set_setting("logging/file_logging/log_level", 0)

func _ready() -> void:
	pass

func _exit_tree() -> void:
	_flush_collapse_summary()
	_flush_throttle_summaries()

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

func _actor_tag(actor: Variant) -> String:
	if actor is Node:
		var n := actor as Node
		var id := n.get_instance_id()
		if n is CharacterBody3D or n.get_parent() == null:
			return "%s#%d" % [n.name, id]
		else:
			return "%s/%s#%d" % [n.get_parent().name, n.name, id]
	return String(actor)

var _collapse_enabled: bool = true
var _last_line_text: String = ""
var _last_line_repeat_count: int = 0
var _throttle_enabled: bool = true
# Minimum interval between identical log lines (by exact text), per level
var _throttle_debug_secs: float = 1.0
var _throttle_info_secs: float = 0.75
var _throttle_warn_secs: float = 0.50
var _throttle_error_secs: float = 0.00
var _throttle_last_time: Dictionary = {}
var _throttle_suppressed: Dictionary = {}
var _throttle_last_line: Dictionary = {}
var _number_regex: RegEx = RegEx.new()

func _write_raw_line(line: String) -> void:
	var f := FileAccess.open("res://log.txt", FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.flush()
	f.close()

func _flush_collapse_summary() -> void:
	if not _collapse_enabled:
		return
	if _last_line_repeat_count > 0 and _last_line_text != "":
		var summary := "… (+%d repeats)" % _last_line_repeat_count
		_write_raw_line(summary)
		_last_line_repeat_count = 0
		_last_line_text = ""

func _write_line(line: String) -> void:
	if _collapse_enabled:
		if _last_line_text == "":
			_last_line_text = line
			_write_raw_line(line)
			return
		if line == _last_line_text:
			_last_line_repeat_count += 1
			return
		# different line: flush summary if any, then write new line
		_flush_collapse_summary()
		_last_line_text = line
		_write_raw_line(line)
	else:
		_write_raw_line(line)

func _clock_now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _normalize_line_for_throttle(line: String) -> String:
	# Lazy compile number regex
	if _number_regex.get_pattern() == "":
		_number_regex.compile("[-+]?\\d+(?:\\.\\d+)?")
	# Replace numeric values so small value changes do not break throttling
	return _number_regex.sub(line, "#", true)

func _write_throttled(line: String, level_for_throttle: Level, normalized: bool = false) -> void:
	if not _throttle_enabled:
		_write_line(line)
		return
	var key := line if not normalized else _normalize_line_for_throttle(line)
	var now := _clock_now()
	var min_interval := 0.0
	match level_for_throttle:
		Level.DEBUG:
			min_interval = _throttle_debug_secs
		Level.INFO:
			min_interval = _throttle_info_secs
		Level.WARN:
			min_interval = _throttle_warn_secs
		Level.ERROR:
			min_interval = _throttle_error_secs
	if min_interval <= 0.0:
		_write_line(line)
		return
	var last_time: float = float(_throttle_last_time.get(key, -1.0))
	if last_time >= 0.0 and (now - last_time) < min_interval:
		var prev := int(_throttle_suppressed.get(key, 0))
		_throttle_suppressed[key] = prev + 1
		_throttle_last_line[key] = line
		return
	# emit with suppressed summary if any
	var suppressed := int(_throttle_suppressed.get(key, 0))
	if suppressed > 0:
		line = line + " … (+" + str(suppressed) + " suppressed)"
		_throttle_suppressed[key] = 0
	_throttle_last_time[key] = now
	_throttle_last_line[key] = line
	_write_line(line)

func _flush_throttle_summaries() -> void:
	for key in _throttle_suppressed.keys():
		var count := int(_throttle_suppressed[key])
		if count <= 0:
			continue
		var base_line := String(_throttle_last_line.get(key, key))
		var summary := base_line + " … (+" + str(count) + " suppressed)"
		_write_line(summary)
		_throttle_suppressed[key] = 0

func debug(category: String, actor: Variant, msg: String) -> void:
	var tag := _actor_tag(actor)
	var line := _fmt(tag, "🐞 DEBUG " + msg)
	if is_enabled(category, Level.DEBUG):
		print_rich("[color=GRAY]" + line + "[/color]")
		_write_throttled(line, Level.DEBUG, true)
	elif file_captures_all:
		_write_throttled(line, Level.DEBUG, true)

func info(category: String, actor: Variant, msg: String) -> void:
	var tag := _actor_tag(actor)
	var line := _fmt(tag, "ℹ️ " + msg)
	if is_enabled(category, Level.INFO):
		print_rich(line)
		_write_throttled(line, Level.INFO, true)
	elif file_captures_all:
		_write_throttled(line, Level.INFO, true)

func warn(category: String, actor: Variant, msg: String) -> void:
	var tag := _actor_tag(actor)
	var line := _fmt(tag, "⚠️ " + msg)
	if is_enabled(category, Level.WARN):
		push_warning(line)
		_write_line("W " + line)
	elif file_captures_all:
		_write_line("W " + line)

func error(category: String, actor: Variant, msg: String) -> void:
	var tag := _actor_tag(actor)
	var line := _fmt(tag, "❌ " + msg)
	if is_enabled(category, Level.ERROR):
		push_error(line)
		_write_line("E " + line)
	elif file_captures_all:
		_write_line("E " + line)

func stat_delta(category: String, actor: Variant, stat_name: String, before_val: float, after_val: float, emoji: String) -> void:
	if is_enabled(category, Level.INFO):
		var delta := after_val - before_val
		var tag := _actor_tag(actor)
		var line := _fmt(tag, "%s %s %s -> %s (Δ %s)" % [emoji, stat_name, str(before_val), str(after_val), str(delta)])
		print_rich(line)
		_write_line(line)

# ---------- Guard & helper utilities ----------
var _once_keys: Dictionary = {}

func once(category: String, actor: Variant, key: String, msg: String, wanted_level: Level = Level.WARN) -> void:
	if _once_keys.has(key):
		return
	_once_keys[key] = true
	match wanted_level:
		Level.DEBUG:
			debug(category, actor, msg)
		Level.INFO:
			info(category, actor, msg)
		Level.WARN:
			warn(category, actor, msg)
		Level.ERROR:
			error(category, actor, msg)

func guard_not_null(category: String, actor: Variant, value: Variant, what: String) -> bool:
	if value == null:
		error(category, actor, "Missing " + what)
		return false
	return true

func guard_has_node(category: String, actor: Node, parent: Node, path: String) -> Node:
	if parent == null:
		error(category, actor, "Parent is null while checking for node '" + path + "'")
		return null
	var n := parent.get_node_or_null(path)
	if n == null:
		warn(category, actor, "Node not found at path '" + path + "'")
	return n

func safe_connect_signal(category: String, actor: Variant, emitter: Object, signal_name: String, target: Object, method_name: String) -> bool:
	if emitter == null:
		error(category, actor, "Cannot connect '" + signal_name + "': emitter is null")
		return false
	if target == null:
		error(category, actor, "Cannot connect '" + signal_name + "': target is null")
		return false
	if not emitter.has_signal(signal_name):
		warn(category, actor, "Emitter has no signal '" + signal_name + "'")
		return false
	var err := OK
	# Avoid duplicate connections
	if (emitter as Object).is_connected(signal_name, Callable(target, method_name)):
		once(category, actor, "dup_conn:" + str(emitter) + ":" + signal_name + ":" + str(target), "Duplicate connection prevented for '" + signal_name + "'", Level.DEBUG)
		return true
	err = (emitter as Object).connect(signal_name, Callable(target, method_name))
	if err != OK:
		error(category, actor, "Failed to connect signal '" + signal_name + "': code " + str(err))
		return false
	debug(category, actor, "Connected signal '" + signal_name + "'")
	return true

func assert_dev(condition: bool, category: String, actor: Variant, msg: String) -> void:
	if not condition:
		error(category, actor, "ASSERT: " + msg)
		assert(condition)
