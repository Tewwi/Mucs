@tool
extends SceneTree

## Script công cụ tự động tạo StaticBody3D và CollisionShape3D cho tất cả các prop trong scene Camp
##
## CÁCH CHẠY:
## 1. Bằng dòng lệnh (Console/Terminal):
##    godot --headless -s res://scripts/tools/setup_camp_collisions.gd
##
## 2. Hoặc trong Godot Editor:
##    Đặt script này làm Main Scene tạm thời hoặc chạy qua SceneTree.

const DEFAULT_CAMP_SCENE := "res://scenes/camps/camp_1.tscn"

# Danh sách từ khóa các đồ vật nhỏ / đồ trang trí / đèn KHÔNG CẦN tạo va chạm
const IGNORE_KEYWORDS := [
	"candle",
	"bottle",
	"torch",
	"keyring",
	"omnilight",
	"light"
]


func _init() -> void:
	process_camp_scene(DEFAULT_CAMP_SCENE)
	quit()


## Hàm xử lý chính: Đọc scene camp, duyệt qua Items và tự động gắn StaticBody3D + Collision
static func process_camp_scene(scene_path: String) -> void:
	print("[CampCollisionTool] Đang xử lý scene: ", scene_path)
	
	if not ResourceLoader.exists(scene_path):
		printerr("[CampCollisionTool] LỖI: Không tìm thấy file scene: ", scene_path)
		return

	var packed_scene := load(scene_path) as PackedScene
	if not packed_scene:
		printerr("[CampCollisionTool] LỖI: Không thể tải PackedScene từ: ", scene_path)
		return

	var camp_root := packed_scene.instantiate() as Node3D
	if not camp_root:
		printerr("[CampCollisionTool] LỖI: Không thể instantiate scene!")
		return

	var items_node := camp_root.get_node_or_null("Items")
	if not items_node:
		printerr("[CampCollisionTool] LỖI: Không tìm thấy node 'Items' trong scene!")
		camp_root.queue_free()
		return

	var added_count := 0
	var skipped_count := 0

	for child in items_node.get_children():
		var child_name_lower := child.name.to_lower()

		# 1. Bỏ qua các vật phẩm trang trí nhỏ
		var should_ignore := false
		for kw in IGNORE_KEYWORDS:
			if kw in child_name_lower:
				should_ignore = true
				break

		if should_ignore:
			print("  - [Bỏ qua - đồ nhỏ]: ", child.name)
			skipped_count += 1
			continue

		# 2. Kiểm tra nếu prop này đã có StaticBody3D
		var already_has_body := false
		for sub in child.get_children():
			if sub is StaticBody3D:
				already_has_body = true
				break

		if already_has_body:
			print("  - [Đã có collider]: ", child.name)
			continue

		# 3. Tìm MeshInstance3D bên trong prop
		var mesh_instance := _find_mesh_instance(child)
		if not mesh_instance or not mesh_instance.mesh:
			print("  - [Không tìm thấy mesh]: ", child.name)
			continue

		# 4. Tạo StaticBody3D và CollisionShape3D
		var static_body := StaticBody3D.new()
		static_body.name = "StaticBody3D"
		# Layer 1 = World/Terrain/Obstacles (chặn Player và Enemy)
		static_body.collision_layer = 1
		static_body.collision_mask = 0

		var col_shape := CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"

		# Tạo khối convex tối ưu ôm sát hình dạng 3D của mesh
		var convex_shape := mesh_instance.mesh.create_convex_shape(true, true)
		col_shape.shape = convex_shape

		static_body.add_child(col_shape)
		child.add_child(static_body)

		# Thiết lập owner để Godot lưu node mới vào file .tscn
		col_shape.owner = camp_root
		static_body.owner = camp_root

		added_count += 1
		print("  + [ĐÃ THÊM COLLIDER]: ", child.name)

	if added_count > 0:
		var new_packed := PackedScene.new()
		var pack_err := new_packed.pack(camp_root)
		if pack_err == OK:
			var save_err := ResourceSaver.save(new_packed, scene_path)
			if save_err == OK:
				print("\n[CampCollisionTool] THÀNH CÔNG: Đã thêm collision cho %d prop và lưu vào '%s'!" % [added_count, scene_path])
			else:
				printerr("\n[CampCollisionTool] LỖI khi lưu file: ", save_err)
		else:
			printerr("\n[CampCollisionTool] LỖI khi đóng gói scene: ", pack_err)
	else:
		print("\n[CampCollisionTool] Không có prop nào cần thêm collider (Tất cả đã có sẵn hoặc đã được bỏ qua).")

	camp_root.queue_free()


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null
