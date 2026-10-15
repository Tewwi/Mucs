@tool
class_name ExportSkeletonMeshes
extends EditorScript

## Thư mục lưu các file mesh xuất ra
const OUTPUT_BASE_DIR := "res://meshs/characters"

## Thư mục chứa các file model .glb của nhân vật
const CHARACTERS_GLB_DIR := "res://assets/character"


func _run() -> void:
	print("================ BẮT ĐẦU AUTO EXPORT MESH ================")
	
	# Kiểm tra xem người dùng có đang chọn một node cụ thể trong Scene tree không
	var selected_nodes: Array[Node] = []
	var editor_interface := get_editor_interface()
	if editor_interface:
		selected_nodes = editor_interface.get_selection().get_selected_nodes()
	
	if selected_nodes.size() > 0:
		# Cách 1: Xuất mesh từ node đang được chọn trong Scene (ví dụ Skeleton3D hoặc Barbarian)
		for node in selected_nodes:
			export_meshes_from_node(node)
	else:
		# Cách 2: Nếu không chọn node nào, tự động quét và xuất TOÀN BỘ .glb trong assets/character
		print("Không có node nào được chọn trong Scene Tree. Tiến hành quét và xuất toàn bộ model trong: ", CHARACTERS_GLB_DIR)
		export_all_character_glbs()
		
	print("================ HOÀN TẤT AUTO EXPORT MESH ================")


## Xuất toàn bộ MeshInstance3D dưới một node cụ thể (ví dụ Skeleton3D)
func export_meshes_from_node(root_node: Node) -> void:
	if not root_node:
		return
		
	var character_name: String = root_node.name
	# Nếu node được chọn là Skeleton3D thì lấy tên node cha làm tên nhân vật
	if root_node is Skeleton3D and root_node.get_parent():
		character_name = root_node.get_parent().name
		
	var target_dir := "%s/%s" % [OUTPUT_BASE_DIR, character_name]
	DirAccess.make_dir_recursive_absolute(target_dir)
	
	var mesh_instances: Array[Node] = []
	if root_node is MeshInstance3D:
		mesh_instances.append(root_node)
	mesh_instances.append_array(root_node.find_children("*", "MeshInstance3D", true, false))
	
	var count := 0
	for node in mesh_instances:
		var mi := node as MeshInstance3D
		if mi and mi.mesh:
			_save_mesh(mi.mesh, mi.name, target_dir)
			count += 1
			
	print("✅ [%s]: Đã xuất thành công %d mesh vào '%s'" % [character_name, count, target_dir])


## Tự động quét và xuất tất cả model .glb trong thư mục assets/character
func export_all_character_glbs() -> void:
	var dir := DirAccess.open(CHARACTERS_GLB_DIR)
	if not dir:
		printerr("Không thể mở thư mục: ", CHARACTERS_GLB_DIR)
		return
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var total_characters := 0
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".glb"):
			var glb_path := "%s/%s" % [CHARACTERS_GLB_DIR, file_name]
			var char_name := file_name.get_basename()
			
			var scene: PackedScene = load(glb_path)
			if scene:
				var inst := scene.instantiate()
				export_meshes_from_node(inst)
				inst.queue_free()
				total_characters += 1
			else:
				printerr("Không thể load file: ", glb_path)
				
		file_name = dir.get_next()
		
	print("🎉 Đã xuất toàn bộ mesh của %d nhân vật!" % total_characters)


## Hàm lưu một mesh ra file .res (hoặc .tres)
func _save_mesh(mesh: Mesh, file_base_name: String, target_dir: String) -> void:
	var target_path := "%s/%s.res" % [target_dir, file_base_name]
	
	# Duplicate để tạo resource độc lập không bị dính vào file gốc glb
	var mesh_copy: Mesh = mesh.duplicate(true)
	
	var err := ResourceSaver.save(mesh_copy, target_path)
	if err == OK:
		print("  -> Đã lưu: ", target_path)
	else:
		printerr("  ❌ Lỗi khi lưu: ", target_path, " (Mã lỗi: ", err, ")")
