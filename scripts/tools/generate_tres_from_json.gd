extends SceneTree

const JSON_PATH := "res://resources/items/equipment_database.json"
const TARGET_DIR := "res://resources/items"

func _init() -> void:
	print("Bắt đầu sinh file .tres từ equipment_database.json...")
	if not FileAccess.file_exists(JSON_PATH):
		printerr("Không tìm thấy file: ", JSON_PATH)
		quit()
		return
		
	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	
	var json_data = JSON.parse_string(content)
	if typeof(json_data) != TYPE_DICTIONARY:
		printerr("JSON không hợp lệ!")
		quit()
		return
		
	var all_items: Array = []
	if json_data.has("armors"):
		all_items.append_array(json_data["armors"])
	if json_data.has("weapons"):
		all_items.append_array(json_data["weapons"])
		
	var slot_map := {
		"HEAD": EquipmentData.Slot.HEAD,
		"CHEST": EquipmentData.Slot.CHEST,
		"ARMS": EquipmentData.Slot.ARMS,
		"LEGS": EquipmentData.Slot.LEGS,
		"WEAPON": EquipmentData.Slot.WEAPON
	}
	
	var total_created := 0
	for item_dict: Dictionary in all_items:
		var item := EquipmentData.new()
		item.item_id = item_dict.get("item_id", "")
		item.item_name = item_dict.get("item_name", "")
		item.description = item_dict.get("description", "")
		
		var slot_str: String = item_dict.get("slot_type", "CHEST")
		item.slot_type = slot_map.get(slot_str, EquipmentData.Slot.CHEST)
		
		var main_mesh_path: String = item_dict.get("main_mesh", "")
		if main_mesh_path != "" and ResourceLoader.exists(main_mesh_path):
			item.main_mesh = load(main_mesh_path)
			
		var left_mesh_path: String = item_dict.get("left_mesh", "")
		if left_mesh_path != "" and ResourceLoader.exists(left_mesh_path):
			item.left_mesh = load(left_mesh_path)
			
		var right_mesh_path: String = item_dict.get("right_mesh", "")
		if right_mesh_path != "" and ResourceLoader.exists(right_mesh_path):
			item.right_mesh = load(right_mesh_path)
			
		var mat_path: String = item_dict.get("material_override", "")
		if mat_path != "" and ResourceLoader.exists(mat_path):
			if mat_path.ends_with(".tres") or mat_path.ends_with(".res") or mat_path.ends_with(".material"):
				item.material_override = load(mat_path)
			elif mat_path.ends_with(".png"):
				var tex = load(mat_path)
				var mat := StandardMaterial3D.new()
				mat.albedo_texture = tex
				item.material_override = mat
			
		item.armor_bonus = float(item_dict.get("armor_bonus", 0.0))
		item.health_bonus = float(item_dict.get("health_bonus", 0.0))
		item.move_speed_bonus = float(item_dict.get("move_speed_bonus", 0.0))
		
		item.weapon_damage = float(item_dict.get("weapon_damage", 15.0))
		item.attack_cooldown = float(item_dict.get("attack_cooldown", 0.6))
		
		var anim_str: String = item_dict.get("attack_animation", "")
		if anim_str != "":
			item.attack_animation = StringName(anim_str)
			
		var anims_arr: Array = item_dict.get("attack_animations", [])
		var anim_names: Array[StringName] = []
		for a in anims_arr:
			anim_names.append(StringName(a))
		item.attack_animations = anim_names
		
		var out_path := "%s/%s.tres" % [TARGET_DIR, item.item_id]
		var err := ResourceSaver.save(item, out_path)
		if err == OK:
			total_created += 1
		else:
			printerr("Lỗi khi lưu: ", out_path)
			
	print("🎉 HOÀN TẤT! Đã sinh %d file .tres vào thư mục '%s'!" % [total_created, TARGET_DIR])
	quit()
