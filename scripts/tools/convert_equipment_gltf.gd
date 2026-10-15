extends SceneTree

const SOURCE_DIR := "res://assets/equipment"
const TARGET_DIR := "res://meshs/equipments"

func _init() -> void:
	print("================ BẮT ĐẦU CHUYỂN ĐỔI EQUIPMENT GLTF -> MESH ================")
	
	DirAccess.make_dir_recursive_absolute(TARGET_DIR)
	
	var dir := DirAccess.open(SOURCE_DIR)
	if not dir:
		printerr("Không thể mở thư mục: ", SOURCE_DIR)
		quit()
		return
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var total_gltf := 0
	var total_meshes := 0
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gltf"):
			var gltf_path := "%s/%s" % [SOURCE_DIR, file_name]
			var base_name := file_name.get_basename()
			
			var scene: PackedScene = load(gltf_path)
			if scene:
				total_gltf += 1
				var inst := scene.instantiate()
				var mesh_nodes := inst.find_children("*", "MeshInstance3D", true, false)
				if inst is MeshInstance3D:
					mesh_nodes.append(inst)
					
				if mesh_nodes.size() == 1:
					# Chỉ có 1 mesh: lưu theo tên file (ví dụ: axe_A.res, sword_A.res)
					var m := mesh_nodes[0] as MeshInstance3D
					if m and m.mesh:
						var dup: Mesh = m.mesh.duplicate(true)
						var out_path := "%s/%s.res" % [TARGET_DIR, base_name]
						var err := ResourceSaver.save(dup, out_path)
						if err == OK:
							print("  ✅ [Single] ", out_path)
							total_meshes += 1
						else:
							printerr("  ❌ Lỗi lưu: ", out_path, " (code: ", err, ")")
				else:
					# Có nhiều mesh bên trong: lưu từng mesh theo tên của node
					for node in mesh_nodes:
						var m := node as MeshInstance3D
						if m and m.mesh:
							var dup: Mesh = m.mesh.duplicate(true)
							var out_name: String = m.name if m.name != "" else base_name
							var out_path := "%s/%s.res" % [TARGET_DIR, out_name]
							var err := ResourceSaver.save(dup, out_path)
							if err == OK:
								print("  ✅ [Multi]  ", out_path)
								total_meshes += 1
							else:
								printerr("  ❌ Lỗi lưu: ", out_path, " (code: ", err, ")")
								
				inst.queue_free()
			else:
				printerr("❌ Không thể load scene: ", gltf_path)
				
		file_name = dir.get_next()
		
	print("==========================================================================")
	print("🎉 HOÀN TẤT! Đã xử lý %d file gltf, xuất thành công %d file mesh .res vào '%s'" % [total_gltf, total_meshes, TARGET_DIR])
	quit()
