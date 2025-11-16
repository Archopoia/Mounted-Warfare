extends Node
class_name Services

var _logger: Node = null


func _ready() -> void:
	_logger = get_node_or_null("/root/LoggerInstance")


func logger() -> Node:
	if _logger == null:
		_logger = get_node_or_null("/root/LoggerInstance")
	return _logger


