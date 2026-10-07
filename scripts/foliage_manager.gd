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
		add_child(_pool_container)


func _setup_collider_pool() -> void:
	_collider_pool.clear()

	# Dọn dẹp pool cũ nếu có
	for child in _pool_container.get_children():
		child.queue_free()

	if Engine.is_editor_hint():
		return

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
	var points: Array[Vector2] = []
	var x := -half_size
	while x < half_size:
		var z := -half_size
		while z < half_size:
			var px := x + rng.randf_range(-step * 0.35, step * 0.35)
			var pz := z + rng.randf_range(-step * 0.35, step * 0.35)
			if absf(px) < half_size and absf(pz) < half_size:
				points.append(Vector2(px, pz))
			z += step
		x += step

	_shuffle_points(points, rng)

	# Mảng chứa danh sách Transform3D cho từng type
	var type_transforms: Array[Array] = []
	for i in range(valid_types.size()):
		type_transforms.append([])

	# 2. Phân loại từng điểm ứng viên
	for p in points:
		var h: float = terrain.get_height(p.x, p.y)
		var norm: Vector3 = terrain.get_normal(p.x, p.y)
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
				var n_val := (t.noise.get_noise_2d(p.x, p.y) + 1.0) * 0.5
				if n_val < t.noise_threshold:
					continue

			# Điểm hợp lệ -> Tạo Transform3D
			var pos := Vector3(p.x, h + t.y_offset, p.y)
			var angle := rng.randf() * TAU
			var s := rng.randf_range(t.min_scale, t.max_scale)
			var basis := Basis.from_euler(Vector3(0.0, angle, 0.0)).scaled(Vector3(s, s, s))
			var trans := Transform3D(basis, pos)

			type_transforms[t_idx].append(trans)

			# Nếu có collision, lưu vào Spatial Grid
			if t.collision_shape != null:
				var cell := Vector2i(
					floori(pos.x / cell_size),
					floori(pos.z / cell_size)
				)
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
		var transforms: Array = type_transforms[t_idx]
		_create_multimesh_instance(t, transforms, t_idx)

	var total_spawned := 0
	for arr in type_transforms:
		total_spawned += arr.size()

	print("[FoliageManager] Đã tạo %d vật thể qua MultiMesh trên %d ô Spatial Grid." % [
		total_spawned,
		_spatial_grid.size()
	])

	# Reset player cell để kích hoạt collider ngay lập tức khi xuất hiện
	_last_player_cell = Vector2i(999999, 999999)


func _create_multimesh_instance(type_info: FoliageItemType, transforms: Array, index: int) -> void:
	if transforms.is_empty():
		return

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MMI_%s_%d" % [type_info.name.validate_node_name(), index]

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = type_info.mesh
	mm.instance_count = transforms.size()

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	mmi.multimesh = mm
	if type_info.material_override:
		mmi.material_override = type_info.material_override

	_multimesh_container.add_child(mmi)


# --- Dynamic Proximity Collision Update ---

## Thu thập các vật thể trong các ô lân cận Player và gán vào Pool
func _update_proximity_colliders(p_pos: Vector3, center_cell: Vector2i) -> void:
	if _collider_pool.is_empty() or _spatial_grid.is_empty():
		return

	var candidate_items: Array[Dictionary] = []

	# Quét các ô xung quanh Player (bán kính active_cell_radius)
	for dx in range(-active_cell_radius, active_cell_radius + 1):
		for dz in range(-active_cell_radius, active_cell_radius + 1):
			var cell := center_cell + Vector2i(dx, dz)
			if _spatial_grid.has(cell):
				for item in _spatial_grid[cell]:
					candidate_items.append(item)

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
	for i in range(active_count):
		var item: Dictionary = candidate_items[i]
		var t_idx: int = item["type_index"]
		var t: FoliageItemType = foliage_types[t_idx]
		var body: StaticBody3D = _collider_pool[i]
		var col_shape: CollisionShape3D = body.get_node_or_null("Shape") as CollisionShape3D

		if col_shape:
			col_shape.shape = t.collision_shape
			# Offset tương đối của shape so với body
			col_shape.position = t.collision_offset
			col_shape.disabled = false

		# Gán transform cho StaticBody
		body.global_transform = item["transform"]
		body.collision_layer = 1
		body.collision_mask = 1

	# Tắt các collider còn thừa trong pool
	for i in range(active_count, _collider_pool.size()):
		var body: StaticBody3D = _collider_pool[i]
		var col_shape: CollisionShape3D = body.get_node_or_null("Shape") as CollisionShape3D
		if col_shape:
			col_shape.disabled = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = Vector3(0, -9999, 0)


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


func _shuffle_points(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
