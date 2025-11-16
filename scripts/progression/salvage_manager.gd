extends Node
class_name SalvageManager

signal salvage_changed(amount: int)

var salvage: int = 0

func add(amount: int) -> void:
	var before := salvage
	salvage += amount
	emit_signal("salvage_changed", salvage)
	LoggerInstance.stat_delta("progression", name, "salvage", float(before), float(salvage), "🔋")

func can_spend(cost: int) -> bool:
	return salvage >= cost

func spend(cost: int) -> bool:
	if can_spend(cost):
		var before := salvage
		salvage -= cost
		emit_signal("salvage_changed", salvage)
		LoggerInstance.stat_delta("progression", name, "salvage", float(before), float(salvage), "🔋")
		return true
	LoggerInstance.warn("progression", name, "❌ insufficient salvage: need %d have %d" % [cost, salvage])
	return false
