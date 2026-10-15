extends SceneTree

const OUTPUT_BASE_DIR := "res://meshs/characters"
const CHARACTERS_GLB_DIR := "res://assets/character"

func _init() -> void:
	print("Bắt đầu tự động trích xuất toàn bộ Mesh...")
	var dir := DirAccess.open(CHARACTERS_GLB_DIR)
	if not dir:
		print("Không thể mở: ", CHARACTERS_GLB_DIR)
		quit()
		return
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var total_saved := 0
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".glb"):
			var glb_path := "%s/%s" % [CHARACTERS_GLB_DIR, file_name]
			var char_name := file_name.get_basename()
			var target_dir := "%s/%s" % [OUTPUT_BASE_DIR, char_name]
			DirAccess.make_dir_recursive_absolute(target_dir)
			
			var scene: PackedScene = load(glb_path)
			if scene:
				var inst := scene.instantiate()
				var meshes := inst.find_children("*", "MeshInstance3D", true, false)
				for m: MeshInstance3D in meshes:
					if m.mesh:
						var dup: Mesh = m.mesh.duplicate(true)
						var target_path := "%s/%s.res" % [target_dir, m.name]
						ResourceSaver.save(dup, target_path)
						print(" -> Đã lưu: ", target_path)
						total_saved += 1
				inst.queue_free()
		file_name = dir.get_next()
		
	print("HOÀN TẤT! Đã trích xuất tổng cộng %d file mesh!" % total_saved)
	quit()
