class_name Inventory
extends Node

signal item_added(item: EquipmentData)
signal item_removed(item: EquipmentData)
signal inventory_full()

@export var max_slots: int = 16
@export var auto_equip_on_pickup: bool = true
@export var equipment_manager: EquipmentManager

var items: Array[EquipmentData] = []


func _ready() -> void:
	if not equipment_manager:
		_find_equipment_manager()


func _find_equipment_manager() -> void:
	# Tìm trên chính node cha
	var parent_node := get_parent()
	if parent_node:
		equipment_manager = parent_node.get_node_or_null("EquipmentManager") as EquipmentManager
		if not equipment_manager:
			var found := parent_node.find_children("*", "EquipmentManager", true, false)
			if found.size() > 0:
				equipment_manager = found[0] as EquipmentManager


## Nhặt vật phẩm vào túi đồ (hoặc mặc thẳng vào người nếu đang trống slot)
func add_item(item: EquipmentData) -> bool:
	if not item:
		return false
	
	if not equipment_manager:
		_find_equipment_manager()
		
	# Nếu bật tự động mặc và vị trí trên người chưa có đồ thì mặc luôn
	if auto_equip_on_pickup and equipment_manager:
		var currently_equipped := equipment_manager.get_equipped_item(item.slot_type)
		if currently_equipped == null:
			equipment_manager.equip(item)
			item_added.emit(item)
			return true
	
	# Nếu không tự mặc hoặc slot đã có đồ thì cất vào túi
	if items.size() < max_slots:
		items.append(item)
		item_added.emit(item)
		return true
	
	inventory_full.emit()
	return false


## Xóa một món đồ khỏi túi (ví dụ vứt đồ)
func remove_item(item: EquipmentData) -> bool:
	var index := items.find(item)
	if index != -1:
		items.remove_at(index)
		item_removed.emit(item)
		return true
	return false


## Mặc một món đồ từ túi vào người
func equip_from_inventory(item: EquipmentData) -> bool:
	if not equipment_manager:
		_find_equipment_manager()
	if not equipment_manager:
		return false
		
	var index := items.find(item)
	if index == -1:
		return false
		
	items.remove_at(index)
	var old_item := equipment_manager.equip(item)
	if old_item:
		items.append(old_item)
		
	return true


## Tháo đồ từ trên người cất lại vào túi
func unequip_to_inventory(slot: EquipmentData.Slot) -> bool:
	if not equipment_manager:
		_find_equipment_manager()
	if not equipment_manager:
		return false
		
	if items.size() >= max_slots:
		inventory_full.emit()
		return false
		
	var old_item := equipment_manager.unequip(slot)
	if old_item:
		items.append(old_item)
		item_added.emit(old_item)
		return true
		
	return false
