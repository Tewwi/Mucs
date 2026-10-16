class_name EquipmentManager
extends Node

signal equipment_changed(slot: EquipmentData.Slot, new_item: EquipmentData, old_item: EquipmentData)

@export var skeleton: Skeleton3D

@export_group("Weapon Slot Offsets")
@export var right_hand_weapon_offset: Vector3 = Vector3(0.0, 0.1, 0.0)
@export var right_hand_weapon_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 90.0)

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
			# 1. Ưu tiên kiểm tra Metadata người dùng đã gán (body, arms_l, arms_r, legs_l, legs_r)
			var matched_slot: String = _detect_slot_from_metadata(child)
			
			# 2. Nếu không có metadata, fallback về quét nhận diện theo tên node
			if matched_slot == "":
				var node_name: String = child.name.to_lower()
				if "hat" in node_name or "helmet" in node_name:
					matched_slot = "head"
				elif "body" in node_name or "chest" in node_name or "torso" in node_name:
					matched_slot = "chest"
				elif "armleft" in node_name or "arm_l" in node_name or "arm.l" in node_name:
					matched_slot = "arm_left"
				elif "armright" in node_name or "arm_r" in node_name or "arm.r" in node_name:
					matched_slot = "arm_right"
				elif "legleft" in node_name or "leg_l" in node_name or "leg.l" in node_name:
					matched_slot = "leg_left"
				elif "legright" in node_name or "leg_r" in node_name or "leg.r" in node_name:
					matched_slot = "leg_right"
			
			if matched_slot != "" and _slot_nodes.has(matched_slot):
				_slot_nodes[matched_slot] = child
			
			# Lưu trạng thái ban đầu của node
			var path_key := child.get_path() if child.is_inside_tree() else NodePath(child.name)
			_default_mesh_states[path_key] = {
				"mesh": child.mesh,
				"mat": child.material_override,
				"visible": child.visible
			}


## Nhận diện slot từ Metadata (hỗ trợ cả meta "slot" = "body" hoặc chính tên meta là "body", "arms_l", v.v.)
func _detect_slot_from_metadata(child: Node) -> String:
	# Kiểm tra nếu có meta "slot", "part", hoặc "type"
	for meta_key in ["slot", "part", "type"]:
		if child.has_meta(meta_key):
			var val: String = str(child.get_meta(meta_key)).to_lower().strip_edges()
			var resolved := _map_alias_to_slot(val)
			if resolved != "":
				return resolved

	# Kiểm tra nếu tên của bất kỳ metadata nào trùng với các alias slot
	for meta_name in child.get_meta_list():
		var resolved := _map_alias_to_slot(str(meta_name).to_lower().strip_edges())
		if resolved != "":
			return resolved

	return ""


## Chuyển đổi tên gọi linh hoạt (alias) sang key slot nội bộ của EquipmentManager
func _map_alias_to_slot(val: String) -> String:
	match val:
		"body", "chest", "torso":
			return "chest"
		"arms_l", "arm_l", "arm_left", "arms_left", "armleft":
			return "arm_left"
		"arms_r", "arm_r", "arm_right", "arms_right", "armright":
			return "arm_right"
		"legs_l", "leg_l", "leg_left", "legs_left", "legleft":
			return "leg_left"
		"legs_r", "leg_r", "leg_right", "legs_right", "legright":
			return "leg_right"
		"head", "hat", "helmet":
			return "head"
	return ""


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
		EquipmentData.Slot.RIGHT_HAND:
			_apply_right_hand(item)
		EquipmentData.Slot.LEFT_HAND:
			_apply_left_hand(item)
			
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
			_clear_attachment("HeadAttachment", "HeadMesh")
		EquipmentData.Slot.CHEST:
			_restore_slot_node("chest")
		EquipmentData.Slot.ARMS:
			_restore_slot_node("arm_left")
			_restore_slot_node("arm_right")
		EquipmentData.Slot.LEGS:
			_restore_slot_node("leg_left")
			_restore_slot_node("leg_right")
		EquipmentData.Slot.RIGHT_HAND:
			_clear_hand("RightHandAttachment")
		EquipmentData.Slot.LEFT_HAND:
			_clear_hand("LeftHandAttachment")
			
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
	var attach := _get_or_create_bone_attachment("head", "HeadAttachment")
	if not attach:
		return
	var mesh_node: MeshInstance3D = attach.get_node_or_null("HeadMesh") as MeshInstance3D
	if not mesh_node:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "HeadMesh"
		attach.add_child(mesh_node)
		
		# Khớp vị trí của mesh về đúng gốc của xương head
		var head_idx := skeleton.find_bone("head")
		if head_idx != -1:
			mesh_node.position = - skeleton.get_bone_global_rest(head_idx).origin
			
	if item and item.main_mesh:
		mesh_node.mesh = item.main_mesh
		mesh_node.material_override = item.material_override
		mesh_node.visible = true
	else:
		mesh_node.visible = false


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
		
	var path := node.get_path() if node.is_inside_tree() else NodePath(node.name)
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
	
	# Đồng bộ Skin từ một mesh gốc trên skeleton nếu có
	for child in skeleton.get_children():
		if child is MeshInstance3D and child.skin:
			new_mesh.skin = child.skin
			break
	return new_mesh


func _apply_right_hand(item: EquipmentData) -> void:
	var attach := _get_or_create_bone_attachment("hand.r", "RightHandAttachment")
	if not attach:
		return
	var mesh_node: MeshInstance3D = attach.get_node_or_null("WeaponMesh") as MeshInstance3D
	if not mesh_node:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "WeaponMesh"
		attach.add_child(mesh_node)
		
	mesh_node.position = right_hand_weapon_offset
	mesh_node.rotation_degrees = right_hand_weapon_rotation_degrees
		
	if item and item.main_mesh:
		mesh_node.mesh = item.main_mesh
		mesh_node.material_override = item.material_override
		mesh_node.visible = true
	else:
		mesh_node.visible = false
		
	_update_weapon_hitbox_shape(item)


func _apply_left_hand(item: EquipmentData) -> void:
	var attach := _get_or_create_bone_attachment("hand.l", "LeftHandAttachment")
	if not attach:
		return
	var mesh_node: MeshInstance3D = attach.get_node_or_null("WeaponMesh") as MeshInstance3D
	if not mesh_node:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "WeaponMesh"
		attach.add_child(mesh_node)
		
	var m: Mesh = item.left_mesh if item.left_mesh else item.main_mesh
	if item and m:
		mesh_node.mesh = m
		mesh_node.material_override = item.material_override
		mesh_node.visible = true
	else:
		mesh_node.visible = false


func _clear_attachment(attach_name: String, mesh_name: String = "WeaponMesh") -> void:
	if not skeleton:
		return
	var attach := skeleton.get_node_or_null(attach_name)
	if attach:
		var mesh_node: MeshInstance3D = attach.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh_node:
			mesh_node.mesh = null
			mesh_node.visible = false


func _clear_hand(attach_name: String) -> void:
	_clear_attachment(attach_name, "WeaponMesh")
	if attach_name == "RightHandAttachment":
		_update_weapon_hitbox_shape(null)


func _get_or_create_bone_attachment(bone_name: String, node_name: String) -> BoneAttachment3D:
	if not skeleton:
		_find_skeleton()
	if not skeleton:
		return null
	var attach: BoneAttachment3D = skeleton.get_node_or_null(node_name) as BoneAttachment3D
	if not attach:
		attach = BoneAttachment3D.new()
		attach.name = node_name
		skeleton.add_child(attach)
		
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx != -1:
			attach.bone_name = bone_name
			attach.bone_idx = bone_idx
		else:
			var alt_name := "handslot." + bone_name.get_slice(".", 1) if "." in bone_name else bone_name
			var alt_idx := skeleton.find_bone(alt_name)
			if alt_idx != -1:
				attach.bone_name = alt_name
				attach.bone_idx = alt_idx
	return attach


func _get_or_create_hand_attachment(bone_name: String, node_name: String) -> BoneAttachment3D:
	return _get_or_create_bone_attachment(bone_name, node_name)


func get_total_weapon_damage() -> float:
	var total: float = 0.0
	var r_item: EquipmentData = get_equipped_item(EquipmentData.Slot.RIGHT_HAND)
	if r_item:
		total += r_item.weapon_damage
	var l_item: EquipmentData = get_equipped_item(EquipmentData.Slot.LEFT_HAND)
	if l_item:
		total += l_item.weapon_damage
	return total


## Lấy hoặc tạo Hitbox3D cho vũ khí tay phải
func get_or_create_weapon_hitbox() -> Hitbox3D:
	var attach := _get_or_create_bone_attachment("hand.r", "RightHandAttachment")
	if not attach:
		return null
		
	var mesh_node: MeshInstance3D = attach.get_node_or_null("WeaponMesh") as MeshInstance3D
	if not mesh_node:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "WeaponMesh"
		mesh_node.position = right_hand_weapon_offset
		mesh_node.rotation_degrees = right_hand_weapon_rotation_degrees
		attach.add_child(mesh_node)
		
	# Dọn dẹp hitbox cũ nếu trước đó từng gắn trực tiếp vào attach
	var legacy_hitbox := attach.get_node_or_null("WeaponHitbox")
	if legacy_hitbox and legacy_hitbox.get_parent() == attach:
		legacy_hitbox.queue_free()
		
	var hitbox: Hitbox3D = mesh_node.get_node_or_null("WeaponHitbox") as Hitbox3D
	if not hitbox:
		hitbox = Hitbox3D.new()
		hitbox.name = "WeaponHitbox"
		hitbox.target_group = "enemy"
		hitbox.owner_character = get_parent() as Node3D
		hitbox.collision_layer = 0
		hitbox.collision_mask = 0xFFFFFFFF # Quét tất cả các layer, lọc qua target_group = "enemy"
		
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		col.shape = shape
		hitbox.add_child(col)
		mesh_node.add_child(hitbox)
		
		var r_item: EquipmentData = get_equipped_item(EquipmentData.Slot.RIGHT_HAND)
		_update_weapon_hitbox_shape(r_item)
		
	return hitbox


## Cập nhật kích thước & vị trí Hitbox khớp chính xác 100% theo Mesh của vũ khí
func _update_weapon_hitbox_shape(item: EquipmentData) -> void:
	if not skeleton:
		return
	var attach: BoneAttachment3D = skeleton.get_node_or_null("RightHandAttachment") as BoneAttachment3D
	if not attach:
		return
	var mesh_node: MeshInstance3D = attach.get_node_or_null("WeaponMesh") as MeshInstance3D
	if not mesh_node:
		return
	var hitbox: Hitbox3D = mesh_node.get_node_or_null("WeaponHitbox") as Hitbox3D
	if not hitbox:
		return
	var col: CollisionShape3D = hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not col:
		return
		
	var shape := col.shape as BoxShape3D
	if not shape:
		shape = BoxShape3D.new()
		col.shape = shape
		
	if item:
		if not item.auto_hitbox_from_mesh and item.custom_hitbox_size != Vector3.ZERO:
			shape.size = item.custom_hitbox_size
			col.position = item.custom_hitbox_offset
		elif item.main_mesh:
			var aabb := item.main_mesh.get_aabb()
			var length := aabb.size.y
			# Bề rộng & bề dày mở rộng thêm một chút (+0.15m) để chém dễ trúng hơn
			var width := maxf(0.5, aabb.size.x + 0.15)
			var depth := maxf(0.5, aabb.size.z + 0.15)
			shape.size = Vector3(width, length, depth)
			col.position = aabb.get_center()
		else:
			shape.size = Vector3(0.5, 1.4, 0.5)
			col.position = Vector3(0.0, 0.6, 0.0)
	else:
		# Khi không cầm vũ khí (đấm tay không)
		shape.size = Vector3(0.5, 0.6, 0.5)
		col.position = Vector3(0.0, 0.2, 0.0)


## Lấy hoặc tạo Hitbox3D cho tay trái (đấm tay không hoặc vũ khí tay trái)
func get_or_create_left_hand_hitbox() -> Hitbox3D:
	var attach := _get_or_create_bone_attachment("hand.l", "LeftHandAttachment")
	if not attach:
		return null
		
	var mesh_node: MeshInstance3D = attach.get_node_or_null("WeaponMesh") as MeshInstance3D
	if not mesh_node:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "WeaponMesh"
		attach.add_child(mesh_node)
		
	var hitbox: Hitbox3D = mesh_node.get_node_or_null("WeaponHitbox") as Hitbox3D
	if not hitbox:
		hitbox = Hitbox3D.new()
		hitbox.name = "WeaponHitbox"
		hitbox.target_group = "enemy"
		hitbox.owner_character = get_parent() as Node3D
		hitbox.collision_layer = 0
		hitbox.collision_mask = 0xFFFFFFFF
		
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5, 0.6, 0.5)
		col.position = Vector3(0.0, 0.2, 0.0)
		col.shape = shape
		hitbox.add_child(col)
		mesh_node.add_child(hitbox)
		
	return hitbox


## Bật Hitbox gây sát thương khi vung kiếm / đấm
func enable_weapon_hitbox(damage: float = -1.0) -> void:
	if damage <= 0.0:
		damage = get_total_weapon_damage()

	var r_hitbox := get_or_create_weapon_hitbox()
	if r_hitbox:
		r_hitbox.start_hit(damage)

	# Bật hitbox tay trái khi đấm tay không hoặc cầm vũ khí tay trái
	var l_hitbox := get_or_create_left_hand_hitbox()
	if l_hitbox:
		l_hitbox.start_hit(damage)


## Tắt Hitbox khi kết thúc vung kiếm / đấm
func disable_weapon_hitbox() -> void:
	if not skeleton:
		return
	var r_attach: BoneAttachment3D = skeleton.get_node_or_null("RightHandAttachment") as BoneAttachment3D
	if r_attach:
		var mesh_node := r_attach.get_node_or_null("WeaponMesh")
		var hitbox: Hitbox3D = null
		if mesh_node:
			hitbox = mesh_node.get_node_or_null("WeaponHitbox") as Hitbox3D
		if not hitbox:
			hitbox = r_attach.get_node_or_null("WeaponHitbox") as Hitbox3D
		if hitbox:
			hitbox.end_hit()

	var l_attach: BoneAttachment3D = skeleton.get_node_or_null("LeftHandAttachment") as BoneAttachment3D
	if l_attach:
		var mesh_node := l_attach.get_node_or_null("WeaponMesh")
		var hitbox: Hitbox3D = null
		if mesh_node:
			hitbox = mesh_node.get_node_or_null("WeaponHitbox") as Hitbox3D
		if not hitbox:
			hitbox = l_attach.get_node_or_null("WeaponHitbox") as Hitbox3D
		if hitbox:
			hitbox.end_hit()
