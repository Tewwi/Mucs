class_name EquipmentManager
extends Node

signal equipment_changed(slot: EquipmentData.Slot, new_item: EquipmentData, old_item: EquipmentData)

@export var skeleton: Skeleton3D

## Lưu trữ các món đồ đang mặc theo Slot (EquipmentData.Slot -> EquipmentData)
var equipped_items: Dictionary = {}

## Lưu trữ Mesh và Material gốc ban đầu để khôi phục khi cởi đồ (NodePath -> { "mesh": Mesh, "mat": Material, "visible": bool })
var _default_mesh_states: Dictionary = {}

## Cache các node MeshInstance3D được ánh xạ theo từng bộ phận
var _slot_nodes: Dictionary = {
	"head": null,
	"chest": null,
	"arm_left": null,
	"arm_right": null,
	"leg_left": null,
	"leg_right": null,
}


func _ready() -> void:
	if not skeleton:
		_find_skeleton()
	
	if skeleton:
		_cache_and_store_base_meshes()


func _find_skeleton() -> void:
	# Tìm từ cha hoặc các node con lân cận
	var parent_node := get_parent()
	if parent_node:
		var skeletons := parent_node.find_children("*", "Skeleton3D", true, false)
		if skeletons.size() > 0:
			skeleton = skeletons[0] as Skeleton3D
			return
	
	# Nếu vẫn chưa thấy, tìm trong toàn cây của root node
	var root_skeletons := find_children("*", "Skeleton3D", true, false)
	if root_skeletons.size() > 0:
		skeleton = root_skeletons[0] as Skeleton3D


## Quét và nhận diện các node MeshInstance3D dưới Skeleton3D
func _cache_and_store_base_meshes() -> void:
	if not skeleton:
		return
	
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			var node_name: String = child.name.to_lower()
			
			if "hat" in node_name or "helmet" in node_name:
				_slot_nodes["head"] = child
			elif "body" in node_name or "chest" in node_name or "torso" in node_name:
				_slot_nodes["chest"] = child
			elif "armleft" in node_name or "arm_l" in node_name or "arm.l" in node_name:
				_slot_nodes["arm_left"] = child
			elif "armright" in node_name or "arm_r" in node_name or "arm.r" in node_name:
				_slot_nodes["arm_right"] = child
			elif "legleft" in node_name or "leg_l" in node_name or "leg.l" in node_name:
				_slot_nodes["leg_left"] = child
			elif "legright" in node_name or "leg_r" in node_name or "leg.r" in node_name:
				_slot_nodes["leg_right"] = child
			
			# Lưu trạng thái ban đầu của node
			_default_mesh_states[child.get_path()] = {
				"mesh": child.mesh,
				"mat": child.material_override,
				"visible": child.visible
			}


## Trang bị một món đồ mới vào người
## Trả về món đồ cũ vừa tháo ra (nếu có)
func equip(item: EquipmentData) -> EquipmentData:
	if not item:
		return null
	
	if not skeleton:
		_find_skeleton()
		if skeleton:
			_cache_and_store_base_meshes()
	
	var slot := item.slot_type
	var old_item: EquipmentData = equipped_items.get(slot, null)
	
	match slot:
		EquipmentData.Slot.HEAD:
			_apply_head(item)
		EquipmentData.Slot.CHEST:
			_apply_chest(item)
		EquipmentData.Slot.ARMS:
			_apply_arms(item)
		EquipmentData.Slot.LEGS:
			_apply_legs(item)
			
	equipped_items[slot] = item
	equipment_changed.emit(slot, item, old_item)
	return old_item


## Tháo trang bị tại slot chỉ định
## Trả về món đồ vừa tháo ra
func unequip(slot: EquipmentData.Slot) -> EquipmentData:
	if not equipped_items.has(slot):
		return null
		
	var old_item: EquipmentData = equipped_items[slot]
	equipped_items.erase(slot)
	
	match slot:
		EquipmentData.Slot.HEAD:
			_restore_slot_node("head", true) # Mũ tháo ra thì ẩn đi nếu ban đầu không có
		EquipmentData.Slot.CHEST:
			_restore_slot_node("chest")
		EquipmentData.Slot.ARMS:
			_restore_slot_node("arm_left")
			_restore_slot_node("arm_right")
		EquipmentData.Slot.LEGS:
			_restore_slot_node("leg_left")
			_restore_slot_node("leg_right")
			
	equipment_changed.emit(slot, null, old_item)
	return old_item


func get_equipped_item(slot: EquipmentData.Slot) -> EquipmentData:
	return equipped_items.get(slot, null)


## Tính tổng chỉ số giáp cộng thêm từ các trang bị đang mặc
func get_total_armor_bonus() -> float:
	var total: float = 0.0
	for item: EquipmentData in equipped_items.values():
		if item:
			total += item.armor_bonus
	return total


func get_total_health_bonus() -> float:
	var total: float = 0.0
	for item: EquipmentData in equipped_items.values():
		if item:
			total += item.health_bonus
	return total


func get_total_speed_bonus() -> float:
	var total: float = 0.0
	for item: EquipmentData in equipped_items.values():
		if item:
			total += item.move_speed_bonus
	return total


# ================== ÁP DỤNG TRANG PHỤC VÀO SKELETON ==================

func _apply_head(item: EquipmentData) -> void:
	var node: MeshInstance3D = _slot_nodes.get("head")
	if not node:
		node = _create_modular_mesh_node("Equipped_Head")
		_slot_nodes["head"] = node
		
	if node and item.main_mesh:
		node.mesh = item.main_mesh
		node.material_override = item.material_override
		node.visible = true


func _apply_chest(item: EquipmentData) -> void:
	var node: MeshInstance3D = _slot_nodes.get("chest")
	if not node:
		node = _create_modular_mesh_node("Equipped_Body")
		_slot_nodes["chest"] = node
		
	if node and item.main_mesh:
		node.mesh = item.main_mesh
		node.material_override = item.material_override
		node.visible = true


func _apply_arms(item: EquipmentData) -> void:
	var left_node: MeshInstance3D = _slot_nodes.get("arm_left")
	var right_node: MeshInstance3D = _slot_nodes.get("arm_right")
	
	if not left_node:
		left_node = _create_modular_mesh_node("Equipped_ArmLeft")
		_slot_nodes["arm_left"] = left_node
	if not right_node:
		right_node = _create_modular_mesh_node("Equipped_ArmRight")
		_slot_nodes["arm_right"] = right_node
		
	var mesh_l: Mesh = item.left_mesh if item.left_mesh else item.main_mesh
	var mesh_r: Mesh = item.right_mesh if item.right_mesh else item.main_mesh
	
	if left_node and mesh_l:
		left_node.mesh = mesh_l
		left_node.material_override = item.material_override
		left_node.visible = true
	if right_node and mesh_r:
		right_node.mesh = mesh_r
		right_node.material_override = item.material_override
		right_node.visible = true


func _apply_legs(item: EquipmentData) -> void:
	var left_node: MeshInstance3D = _slot_nodes.get("leg_left")
	var right_node: MeshInstance3D = _slot_nodes.get("leg_right")
	
	if not left_node:
		left_node = _create_modular_mesh_node("Equipped_LegLeft")
		_slot_nodes["leg_left"] = left_node
	if not right_node:
		right_node = _create_modular_mesh_node("Equipped_LegRight")
		_slot_nodes["leg_right"] = right_node
		
	var mesh_l: Mesh = item.left_mesh if item.left_mesh else item.main_mesh
	var mesh_r: Mesh = item.right_mesh if item.right_mesh else item.main_mesh
	
	if left_node and mesh_l:
		left_node.mesh = mesh_l
		left_node.material_override = item.material_override
		left_node.visible = true
	if right_node and mesh_r:
		right_node.mesh = mesh_r
		right_node.material_override = item.material_override
		right_node.visible = true


## Khôi phục lại Mesh gốc ban đầu cho slot
func _restore_slot_node(slot_key: String, hide_if_no_default: bool = false) -> void:
	var node: MeshInstance3D = _slot_nodes.get(slot_key)
	if not node:
		return
		
	var path := node.get_path()
	if _default_mesh_states.has(path):
		var state: Dictionary = _default_mesh_states[path]
		node.mesh = state["mesh"]
		node.material_override = state["mat"]
		node.visible = state["visible"]
	elif hide_if_no_default:
		node.mesh = null
		node.visible = false


## Tạo mới một MeshInstance3D động làm con của Skeleton3D
func _create_modular_mesh_node(node_name: String) -> MeshInstance3D:
	if not skeleton:
		return null
	var new_mesh := MeshInstance3D.new()
	new_mesh.name = node_name
	skeleton.add_child(new_mesh)
	new_mesh.skeleton = NodePath("..")
	return new_mesh
