extends EquipItem
var applied: Array[int] = []
func _apply_effect(quantity: int) -> void:
	applied.append(quantity)
