@tool
class_name FoliageManager
extends Node3D

## Tự động tìm Terrain (nếu để trống, script sẽ tìm node cha hoặc node cùng cấp)
@export var terrain: MeshInstance3D

## Node Player để theo dõi vị trí và kích hoạt va chạm lân cận (nếu để trống, tự tìm group 'player')
@export var player: Node3D

@export_group("Grid & Spatial Partitioning")
## Khoảng cách lấy mẫu giữa các điểm kiểm tra spawn trên địa hình (mét)
@export_range(2.0, 32.0, 0.5) var spawn_spacing: float = 6.0

## Kích thước mỗi ô trong Spatial Grid (mét). Ví dụ 24m x 24m.
@export_range(8.0, 64.0, 2.0) var cell_size: float = 24.0

## Bán kính ô lân cận quanh Player được kích hoạt va chạm:
## 1 = vùng 3x3 ô (đường kính ~48m-72m quanh Player)
## 2 = vùng 5x5 ô
@export_range(1, 3, 1) var active_cell_radius: int = 1

@export_group("Collision Pool")
## Số lượng collider tối đa trong pool được kích hoạt đồng thời quanh Player
@export_range(10, 100, 5) var max_pooled_colliders: int = 50

@export_group("Foliage Types")
## Danh sách cấu hình các loại cây, đá... sử dụng FoliageItemType Resource
@export var foliage_types: Array[FoliageItemType] = []

@export_group("Debug & Diagnostics")
## In log chi tiết mỗi khi hệ thống quét và kích hoạt collider gần Player
@export var debug_collision_logs: bool = true

@export_group("Editor Tools")
## Bấm để xem trước cây/đá ngay trong Editor
@export var generate_in_editor: bool = false:
	set(v):
		if v:
			_find_references()
			if terrain and terrain.has_method("get_height"):
				generate_foliage(terrain.get("world_seed"))
			generate_in_editor = false

## Bấm để xóa sạch cây/đá xem trước trong Editor
@export var clear_in_editor: bool = false:
	set(v):
		if v:
			_clear_all()
			clear_in_editor = false


# --- Dữ liệu nội bộ ---

# Node chứa các MultiMeshInstance3D
var _multimesh_container: Node3D
# Node chứa các StaticBody3D trong Pool
var _pool_container: Node3D

# Danh sách StaticBody3D được tạo sẵn trong pool
var _collider_pool: Array[StaticBody3D] = []

# Spatial Grid 2D lưu trữ các vật thể có va chạm:
# Key: Vector2i(cell_x, cell_z) -> Value: Array[Dictionary]
# Mỗi Dict: { "transform": Transform3D, "type_index": int, "global_pos": Vector3 }
var _spatial_grid: Dictionary = {}

# Tọa độ ô lưới gần nhất của Player
var _last_player_cell := Vector2i(999999, 999999)

# Timer tích lũy để kiểm tra vị trí Player ngắt quãng (tránh check liên tục mỗi frame)
var _proximity_timer: float = 0.0
const PROXIMITY_CHECK_INTERVAL := 0.1 # Kiểm tra 10 lần / giây


func _ready() -> void:
	_setup_containers()
	_setup_collider_pool()

	if Engine.is_editor_hint():
		return

	_find_references()

	# Kết nối signal nếu Terrain có phát tín hiệu khi cập nhật xong thế giới
	if terrain and terrain.has_signal("terrain_generated"):
		if not terrain.terrain_generated.is_connected(generate_foliage):
			terrain.terrain_generated.connect(generate_foliage)
	else:
		# Nếu Terrain đã sẵn sàng từ trước, gọi tạo foliage sau 1 frame
		call_deferred("_deferred_start")


func _deferred_start() -> void:
	_find_references()
	if terrain and terrain.has_method("get_height"):
		var seed_val: int = terrain.get("world_seed") if "world_seed" in terrain else 0
		generate_foliage(seed_val)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_proximity_timer += delta
	if _proximity_timer < PROXIMITY_CHECK_INTERVAL:
		return
	_proximity_timer = 0.0

	if not player or not is_instance_valid(player):
		_find_player()
		if not player:
			return

	var p_pos := player.global_position
	var curr_cell := Vector2i(
		floori(p_pos.x / cell_size),
		floori(p_pos.z / cell_size)
	)

	# Nếu Player vẫn ở trong cùng 1 ô -> Không cần tính toán gì thêm (0% CPU)
	if curr_cell == _last_player_cell:
		return

	_last_player_cell = curr_cell
	_update_proximity_colliders(p_pos, curr_cell)


# --- Khởi tạo Node Hierarchy tự động ---

func _setup_containers() -> void:
	_multimesh_container = get_node_or_null("MultiMeshContainer") as Node3D
	if not _multimesh_container:
		_multimesh_container = Node3D.new()
		_multimesh_container.name = "MultiMeshContainer"
		add_child(_multimesh_container)

	_pool_container = get_node_or_null("ColliderPoolContainer") as Node3D
	if not _pool_container:
		_pool_container = Node3D.new()
		_pool_container.name = "ColliderPoolContainer"
		_pool_container.top_level = true
		add_child(_pool_container)
	else:
		_pool_container.top_level = true


func _setup_collider_pool() -> void:
	_collider_pool.clear()

	# Dọn dẹp pool cũ nếu có
	for child in _pool_container.get_children():
		child.queue_free()

	if Engine.is_editor_hint():
		return

	if debug_collision_logs:
		print("[FoliageManager][Pool] Đang khởi tạo pool %d StaticBody3D proxies..." % max_pooled_colliders)

	# Tạo sẵn số lượng StaticBody3D cố định trong pool
	for i in range(max_pooled_colliders):
		var body := StaticBody3D.new()
		body.name = "ColliderProxy_%d" % i

		var col_shape := CollisionShape3D.new()
		col_shape.name = "Shape"
		col_shape.disabled = true
		body.add_child(col_shape)

		# Mặc định tắt va chạm và đặt xa khỏi tầm nhìn
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = Vector3(0, -9999, 0)

		_pool_container.add_child(body)
		_collider_pool.append(body)

	if debug_collision_logs:
		print("[FoliageManager][Pool] Khởi tạo hoàn tất %d collider proxies." % _collider_pool.size())


# --- Tìm kiếm tham chiếu tự động ---

func _find_references() -> void:
	if not terrain or not is_instance_valid(terrain):
		var p := get_parent()
		if p is MeshInstance3D and p.has_method("get_height"):
			terrain = p
		else:
			terrain = get_tree().root.find_child("Terrain", true, false) as MeshInstance3D

	if not player or not is_instance_valid(player):
		_find_player()


func _find_player() -> void:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		player = nodes[0] as Node3D
		return

	# Thử tìm CharacterBody3D bất kỳ
	player = get_tree().root.find_child("Player", true, false) as Node3D


# --- Sinh Foliage (MultiMesh + Lập chỉ mục Spatial Grid) ---

## Hàm chính: Sinh toàn bộ cây/đá theo seed chỉ định
func generate_foliage(world_seed: int = 0) -> void:
	var start_gen_us := Time.get_ticks_usec()
	_find_references()
	if not terrain or not terrain.has_method("get_height"):
		push_warning("FoliageManager: Không tìm thấy node Terrain hợp lệ!")
		return

	_clear_all()

	var valid_types: Array[FoliageItemType] = []
	for t in foliage_types:
		if t != null and t.mesh != null:
			valid_types.append(t)

	if valid_types.is_empty():
		print("[FoliageManager] Chưa có FoliageItemType hợp lệ nào được gán.")
		return

	if debug_collision_logs:
		print("[FoliageManager] Bắt đầu sinh Foliage (seed=%d, số loại=%d)..." % [world_seed, valid_types.size()])

	# Áp dụng seed cho noise của từng loại
	for i in range(valid_types.size()):
		var t := valid_types[i]
		if t.noise:
			t.noise.seed = world_seed + (i + 1) * 31

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	# Xác định kích thước đảo từ terrain
	var map_size: float = 256.0
	if "size" in terrain:
		map_size = float(terrain.get("size"))
	elif terrain.mesh:
		map_size = terrain.mesh.get_aabb().size.x

	var half_size := map_size * 0.5
	var step := maxf(spawn_spacing, 2.0)

	# 1. Thu thập danh sách tọa độ ứng viên (Grid + Jitter)
	var points: Array[Vector3] = []
	var x := -half_size
	while x < half_size:
		var z := -half_size
		while z < half_size:
			var px := x + rng.randf_range(-step * 0.35, step * 0.35)
			var pz := z + rng.randf_range(-step * 0.35, step * 0.35)
			if absf(px) < half_size and absf(pz) < half_size:
				points.append(Vector3(px, 0.0, pz))
			z += step
		x += step

	_shuffle_points(points, rng)

	# Mảng chứa danh sách Transform3D cho từng type
	var type_transforms: Array[Array] = []
	var type_cell_transforms: Array[Dictionary] = []
	for i in range(valid_types.size()):
		type_transforms.append([])
		type_cell_transforms.append({})

	# 2. Phân loại từng điểm ứng viên
	for p: Vector3 in points:
		var px: float = p.x
		var pz: float = p.z
		var h: float = terrain.get_height(px, pz)
		var norm: Vector3 = terrain.get_normal(px, pz)
		var slope: float = norm.y

		# Thử khớp với từng type theo thứ tự ưu tiên
		for t_idx in range(valid_types.size()):
			var t := valid_types[t_idx]
			if type_transforms[t_idx].size() >= t.max_count:
				continue

			if h < t.min_height or h > t.max_height:
				continue
			if slope < t.min_slope or slope > t.max_slope:
				continue

			if t.noise:
				var n_val := (t.noise.get_noise_2d(px, pz) + 1.0) * 0.5
				if n_val < t.noise_threshold:
					continue

			# Điểm hợp lệ -> Tạo Transform3D
			var pos := Vector3(px, h + t.y_offset, pz)
			var angle := rng.randf() * TAU
			var rot_basis := Basis.from_euler(Vector3(0.0, angle, 0.0))

			# Xoay ôm theo pháp tuyến địa hình (normal) nếu được cấu hình (đặc biệt cho đá)
			if t.align_to_normal > 0.001 and norm.length_squared() > 0.001:
				var target_up := Vector3.UP.slerp(norm, t.align_to_normal).normalized()
				var tilt := Quaternion(Vector3.UP, target_up)
				rot_basis = Basis(tilt) * rot_basis

			var s := rng.randf_range(t.min_scale, t.max_scale)
			var basis := rot_basis.scaled(Vector3(s, s, s))
			var trans := Transform3D(basis, pos)

			type_transforms[t_idx].append(trans)

			var cell := Vector2i(
				floori(pos.x / cell_size),
				floori(pos.z / cell_size)
			)

			# Gom theo ô lưới để hỗ trợ Visibility Range culling
			if not type_cell_transforms[t_idx].has(cell):
				type_cell_transforms[t_idx][cell] = []
			type_cell_transforms[t_idx][cell].append(trans)

			# Nếu có collision, lưu vào Spatial Grid
			if t.collision_shape != null:
				if not _spatial_grid.has(cell):
					_spatial_grid[cell] = []
				_spatial_grid[cell].append({
					"transform": trans,
					"type_index": t_idx,
					"global_pos": pos
				})

			# Mỗi điểm chỉ mọc 1 loại vật thể
			break

	# 3. Tạo MultiMesh cho từng loại
	for t_idx in range(valid_types.size()):
		var t := valid_types[t_idx]
		_create_multimesh_instances_for_type(t, type_transforms[t_idx], type_cell_transforms[t_idx], t_idx)

	var total_spawned := 0
	for arr in type_transforms:
		total_spawned += arr.size()

	var gen_elapsed_ms := float(Time.get_ticks_usec() - start_gen_us) / 1000.0
	print("[FoliageManager] Đã tạo %d vật thể qua MultiMesh trên %d ô Spatial Grid (Thời gian: %.2f ms)." % [
		total_spawned,
		_spatial_grid.size(),
		gen_elapsed_ms
	])

	# Reset player cell để kích hoạt collider ngay lập tức khi xuất hiện
	_last_player_cell = Vector2i(999999, 999999)


func _create_multimesh_instances_for_type(type_info: FoliageItemType, transforms: Array, type_cell_map: Dictionary, index: int) -> void:
	if transforms.is_empty():
		return

	# Nếu có visibility_range_end > 0: Chia nhỏ MultiMesh theo từng ô lưới (Cell Chunking)
	# để Godot có thể culling / fade out các cụm ở xa camera
	if type_info.visibility_range_end > 0.0 and not type_cell_map.is_empty():
		for cell: Vector2i in type_cell_map:
			var cell_transforms: Array = type_cell_map[cell]
			if cell_transforms.is_empty():
				continue
			var mmi := _build_mmi_node(
				type_info,
				cell_transforms,
				"MMI_%s_%d_c%d_%d" % [type_info.name.validate_node_name(), index, cell.x, cell.y]
			)
			_apply_visibility_range(mmi, type_info)
			_multimesh_container.add_child(mmi)
	else:
		# Không giới hạn tầm nhìn: Gom tất cả vào 1 node duy nhất (1 Draw Call toàn bản đồ)
		var mmi := _build_mmi_node(
			type_info,
			transforms,
			"MMI_%s_%d" % [type_info.name.validate_node_name(), index]
		)
		if type_info.visibility_range_end > 0.0:
			_apply_visibility_range(mmi, type_info)
		_multimesh_container.add_child(mmi)


func _build_mmi_node(type_info: FoliageItemType, transforms: Array, node_name: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = type_info.mesh
	mm.instance_count = transforms.size()

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	mmi.multimesh = mm
	if type_info.material_override:
		mmi.material_override = type_info.material_override
	return mmi


func _apply_visibility_range(mmi: MultiMeshInstance3D, type_info: FoliageItemType) -> void:
	mmi.visibility_range_begin = type_info.visibility_range_begin
	mmi.visibility_range_begin_margin = type_info.visibility_range_begin_margin
	mmi.visibility_range_end = type_info.visibility_range_end
	mmi.visibility_range_end_margin = type_info.visibility_range_end_margin
	mmi.visibility_range_fade_mode = type_info.visibility_range_fade_mode


# --- Dynamic Proximity Collision Update ---

## Thu thập các vật thể trong các ô lân cận Player và gán vào Pool
func _update_proximity_colliders(p_pos: Vector3, center_cell: Vector2i) -> void:
	if _collider_pool.is_empty():
		if debug_collision_logs:
			push_warning("[FoliageManager][Collision] _collider_pool đang rỗng! Chưa khởi tạo pool.")
		return
	if _spatial_grid.is_empty():
		if debug_collision_logs:
			print("[FoliageManager][Collision] _spatial_grid đang rỗng (chưa sinh vật thể hoặc không có vật thể nào có collision).")
		return

	var start_us := Time.get_ticks_usec()
	var candidate_items: Array[Dictionary] = []

	# Quét các ô xung quanh Player (bán kính active_cell_radius)
	var scanned_cells := 0
	for dx in range(-active_cell_radius, active_cell_radius + 1):
		for dz in range(-active_cell_radius, active_cell_radius + 1):
			scanned_cells += 1
			var cell := center_cell + Vector2i(dx, dz)
			if _spatial_grid.has(cell):
				for item in _spatial_grid[cell]:
					candidate_items.append(item)

	var total_candidates := candidate_items.size()

	# Nếu số lượng ứng viên vượt quá pool, sắp xếp theo khoảng cách và lấy những cái gần nhất
	if candidate_items.size() > max_pooled_colliders:
		candidate_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var d_a: float = p_pos.distance_squared_to(a["global_pos"])
			var d_b: float = p_pos.distance_squared_to(b["global_pos"])
			return d_a < d_b
		)
		candidate_items.resize(max_pooled_colliders)

	var active_count := candidate_items.size()

	# Cập nhật các collider đang được dùng
	var shapes_swapped := 0
	var transforms_updated := 0
	for i in range(active_count):
		var item: Dictionary = candidate_items[i]
		var t_idx: int = item["type_index"]
		if t_idx < 0 or t_idx >= foliage_types.size():
			push_error("[FoliageManager][Collision] type_index không hợp lệ: %d" % t_idx)
			continue

		var t: FoliageItemType = foliage_types[t_idx]
		if not t or not t.collision_shape:
			continue

		var body: StaticBody3D = _collider_pool[i]
		var col_shape: CollisionShape3D = body.get_node_or_null("Shape") as CollisionShape3D

		if col_shape:
			# CHỈ gán lại shape khi thực sự thay đổi để tránh PhysicsServer3D rebuild liên tục gây treo
			if col_shape.shape != t.collision_shape:
				col_shape.shape = t.collision_shape
				shapes_swapped += 1
			if col_shape.position != t.collision_offset:
				col_shape.position = t.collision_offset
			if col_shape.disabled:
				col_shape.disabled = false

		if body.global_transform != item["transform"]:
			body.global_transform = item["transform"]
			transforms_updated += 1

		if body.collision_layer != 1:
			body.collision_layer = 1
			body.collision_mask = 1

	# Tắt các collider còn thừa trong pool
	var disabled_count := 0
	for i in range(active_count, _collider_pool.size()):
		var body: StaticBody3D = _collider_pool[i]
		if body.collision_layer != 0:
			var col_shape: CollisionShape3D = body.get_node_or_null("Shape") as CollisionShape3D
			if col_shape and not col_shape.disabled:
				col_shape.disabled = true
			body.collision_layer = 0
			body.collision_mask = 0
			body.position = Vector3(0, -9999, 0)
			disabled_count += 1

	var elapsed_ms := float(Time.get_ticks_usec() - start_us) / 1000.0

	if debug_collision_logs:
		print("[FoliageManager][Collision] Ô hiện tại: %s | Quét: %d ô (%d vật thể) | Bật: %d/%d (Shape đổi: %d, Pos đổi: %d, Tắt dư: %d) | Thời gian xử lý: %.2f ms" % [
			center_cell,
			scanned_cells,
			total_candidates,
			active_count,
			max_pooled_colliders,
			shapes_swapped,
			transforms_updated,
			disabled_count,
			elapsed_ms
		])


# --- Dọn dẹp ---

func _clear_all() -> void:
	_spatial_grid.clear()
	_last_player_cell = Vector2i(999999, 999999)

	if _multimesh_container:
		for child in _multimesh_container.get_children():
			child.queue_free()

	for body in _collider_pool:
		var col_shape: CollisionShape3D = body.get_node_or_null("Shape") as CollisionShape3D
		if col_shape:
			col_shape.disabled = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = Vector3(0, -9999, 0)


func _shuffle_points(arr: Array[Vector3], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector3 = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
