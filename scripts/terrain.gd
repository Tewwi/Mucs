@tool
extends MeshInstance3D

const size := 256.0

## Khoảng cách lấy mẫu khi tính normal / độ dốc.
## Cố định, KHÔNG phụ thuộc resolution để luật spawn không đổi theo độ phân giải mesh.
const NORMAL_EPS := 1.0

@export_range(4, 256, 4) var resolution := 32:
	set(new_resolution):
		resolution = new_resolution
		if is_node_ready():
			update_mesh()

@export var noise: FastNoiseLite:
	set(new_noise):
		if noise and noise.changed.is_connected(update_mesh):
			noise.changed.disconnect(update_mesh)
		noise = new_noise
		if noise and not noise.changed.is_connected(update_mesh):
			noise.changed.connect(update_mesh)
		if is_node_ready():
			update_mesh()

@export_range(4.0, 128.0, 4.0) var height := 64.0:
	set(new_height):
		height = new_height
		if is_node_ready():
			update_mesh()

# --- Hình dạng đảo ---
@export_group("Island")

## Bán kính đảo (đơn vị thế giới). Ngoài bán kính này là đáy biển phẳng.
@export_range(16.0, 512.0, 1.0) var island_radius := 120.0:
	set(v):
		island_radius = v
		if is_node_ready():
			update_mesh()

## Độ sâu đáy biển ở rìa (mặt nước đặt tại y = 0)
@export_range(0.0, 32.0, 0.5) var sea_depth := 8.0:
	set(v):
		sea_depth = v
		if is_node_ready():
			update_mesh()

# --- Va chạm (Collision) ---
@export_group("Collision")

## Bật/tắt tạo Collision ngay trong Editor (hữu ích để xem trước wireframe hoặc debug raycast)
@export var generate_collision_in_editor: bool = false:
	set(v):
		generate_collision_in_editor = v
		if is_node_ready():
			update_collision()

# --- Seed thế giới ---
@export_group("World")

## Seed của thế giới. Cùng seed => cùng địa hình + cùng vị trí cây/đá.
@export var world_seed := 0

## Bật: mỗi lần chạy game sẽ random seed mới. Tắt: dùng world_seed ở trên.
@export var randomize_seed_on_start := true

# --- Multi-layer Noise cho Object Spawning ---
@export_group("Object Spawning")

## Noise riêng cho cây cối (mọc ở vùng phẳng)
@export var tree_noise: FastNoiseLite

## Ngưỡng spawn cây [0.0 - 1.0]: cao hơn = mọc thưa hơn
@export_range(0.0, 1.0, 0.05) var tree_threshold := 0.2

## Danh sách các scene của cây để spawn (chọn ngẫu nhiên). Root của scene phải là Node3D.
@export var tree_scenes: Array[PackedScene] = []

## Độ lệch Y cho cây (giá trị âm giúp cắm ngập nhẹ gốc cây xuống lòng đất, tránh hở chân)
@export_range(-2.0, 2.0, 0.05) var tree_y_offset: float = -0.3

## Ngưỡng độ phẳng tối thiểu cho cây (slope_factor = normal.y, 1.0 là hoàn toàn phẳng)
@export_range(0.0, 1.0, 0.01) var tree_min_slope := 0.85

## Số cây tối đa (giới hạn an toàn tránh nghẽn CPU/GPU)
@export_range(0, 2000, 10) var max_trees := 250

## Noise riêng cho đá (mọc ở vùng dốc)
@export var rock_noise: FastNoiseLite

## Ngưỡng spawn đá [0.0 - 1.0]
@export_range(0.0, 1.0, 0.05) var rock_threshold := 0.3

## Danh sách các scene của đá để spawn (chọn ngẫu nhiên). Root của scene phải là Node3D.
@export var rock_scenes: Array[PackedScene] = []

## Độ lệch Y cho đá / bụi cây
@export_range(-2.0, 2.0, 0.05) var rock_y_offset: float = -0.1

## Ngưỡng độ phẳng tối đa cho đá (nhỏ hơn ngưỡng này mới mọc, tức là vùng sườn đồi dốc)
@export_range(0.0, 1.0, 0.01) var rock_max_slope := 0.75

## Số đá tối đa
@export_range(0, 2000, 10) var max_rocks := 150

## Khoảng cách giữa các điểm thử spawn (units)
@export_range(4.0, 32.0, 1.0) var spawn_spacing := 8.0

## Độ cao tối thiểu để được spawn (tránh mọc dưới nước / sát bờ biển)
@export_range(-8.0, 32.0, 0.5) var min_spawn_height := 1.0

## Bật/tắt để spawn thử cây/đá ngay trong Editor
@export var test_spawn_in_editor: bool = false:
	set(v):
		if v:
			update_mesh()
			spawn_objects()
			test_spawn_in_editor = false

## Bật/tắt để xoá sạch object xem trước trong Editor
@export var clear_spawned_in_editor: bool = false:
	set(v):
		if v:
			_clear_spawned_objects()
			clear_spawned_in_editor = false

# Danh sách scene hợp lệ (đã lọc null), được dựng một lần mỗi lần spawn
var _tree_pool: Array[PackedScene] = []
var _rock_pool: Array[PackedScene] = []

func _enter_tree() -> void:
	if noise and not noise.changed.is_connected(update_mesh):
		noise.changed.connect(update_mesh)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if randomize_seed_on_start:
		world_seed = randi() & 0x7fffffff
	generate_world(world_seed)


## Dựng lại toàn bộ thế giới với một seed (dùng được cho co-op: mọi máy gọi cùng seed).
func generate_world(new_seed: int) -> void:
	world_seed = new_seed
	_apply_seed_to_noises()
	update_mesh() # Tự động cập nhật đồng bộ cả mesh lẫn collision
	spawn_objects()


# --- Seed ---

func _apply_seed_to_noises() -> void:
	_set_noise_seed(noise, world_seed)
	_set_noise_seed(tree_noise, world_seed + 1)
	_set_noise_seed(rock_noise, world_seed + 2)

# Đổi seed mà không kích hoạt update_mesh() thêm lần nữa qua signal "changed".
# Lưu ý: mỗi biến noise nên là một Resource riêng, nếu dùng chung một Resource thì seed sẽ bị ghi đè.
func _set_noise_seed(n: FastNoiseLite, s: int) -> void:
	if n == null:
		return
	var was_connected := n.changed.is_connected(update_mesh)
	if was_connected:
		n.changed.disconnect(update_mesh)
	n.seed = s
	if was_connected:
		n.changed.connect(update_mesh)


# --- Hàm địa hình cơ bản ---

## Độ cao tại toạ độ cục bộ (x, z): noise [0..1] * height * mask đảo, rìa chìm xuống đáy biển.
func get_height(x: float, z: float) -> float:
	if not noise:
		return 0.0
	var n := (noise.get_noise_2d(x, z) + 1.0) * 0.5
	var d := Vector2(x, z).length() / island_radius
	var mask := clampf(1.0 - pow(d, 3.0), 0.0, 1.0)
	return n * height * mask - sea_depth * (1.0 - mask)


func get_normal(x: float, z: float) -> Vector3:
	var dh_dx := (get_height(x + NORMAL_EPS, z) - get_height(x - NORMAL_EPS, z)) / (2.0 * NORMAL_EPS)
	var dh_dz := (get_height(x, z + NORMAL_EPS) - get_height(x, z - NORMAL_EPS)) / (2.0 * NORMAL_EPS)
	return Vector3(-dh_dx, 1.0, -dh_dz).normalized()


# --- Collision (HeightMapShape3D) ---

const TERRAIN_BODY_NAME := "TerrainBody"
const TERRAIN_SHAPE_NAME := "TerrainCollisionShape"

## Lấy hoặc khởi tạo StaticBody3D dành riêng cho địa hình
func _get_or_create_terrain_body() -> StaticBody3D:
	var body := get_node_or_null(TERRAIN_BODY_NAME) as StaticBody3D
	if not body:
		body = get_node_or_null("Body") as StaticBody3D
	if not body:
		for child in get_children():
			if child is StaticBody3D and not child.is_in_group("spawned"):
				body = child as StaticBody3D
				break
	if not body:
		body = StaticBody3D.new()
		body.name = TERRAIN_BODY_NAME
		add_child(body)
	return body

## Lấy hoặc khởi tạo CollisionShape3D bên trong StaticBody3D
func _get_or_create_collision_shape(body: StaticBody3D) -> CollisionShape3D:
	var col_node := body.get_node_or_null(TERRAIN_SHAPE_NAME) as CollisionShape3D
	if not col_node:
		col_node = body.get_node_or_null("Shape") as CollisionShape3D
	if not col_node:
		for child in body.get_children():
			if child is CollisionShape3D:
				col_node = child as CollisionShape3D
				break
	if not col_node:
		col_node = CollisionShape3D.new()
		col_node.name = TERRAIN_SHAPE_NAME
		body.add_child(col_node)
	return col_node

## Cập nhật HeightMapShape3D khớp chính xác 100% với PlaneMesh
func update_collision() -> void:
	if not noise:
		return

	# Chỉ dựng va chạm trong Editor nếu người dùng bật generate_collision_in_editor
	if Engine.is_editor_hint() and not generate_collision_in_editor:
		var existing_body := get_node_or_null(TERRAIN_BODY_NAME) as StaticBody3D
		if not existing_body:
			existing_body = get_node_or_null("Body") as StaticBody3D
		if existing_body:
			existing_body.queue_free()
		return

	var body := _get_or_create_terrain_body()
	var col_node := _get_or_create_collision_shape(body)

	# PlaneMesh có subdivide_width/depth = resolution:
	# -> Số đoạn chia (quad segments) mỗi cạnh: resolution + 1
	# -> Số đỉnh (grid vertices) mỗi cạnh: w = resolution + 2
	# -> Khoảng cách giữa các đỉnh: cell_size = size / (resolution + 1)
	var w := resolution + 2
	var cell_size := size / float(resolution + 1)
	var half_size := size * 0.5

	# Dữ liệu độ cao mảng phẳng (row-major: iz * w + ix)
	var data := PackedFloat32Array()
	data.resize(w * w)
	for iz in w:
		var z := -half_size + iz * cell_size
		var row_offset := iz * w
		for ix in w:
			var x := -half_size + ix * cell_size
			data[row_offset + ix] = get_height(x, z)

	# Tái sử dụng HeightMapShape3D nếu có sẵn để tránh tạo rác bộ nhớ
	var shape := col_node.shape as HeightMapShape3D
	if not shape:
		shape = HeightMapShape3D.new()
		col_node.shape = shape

	shape.map_width = w
	shape.map_depth = w
	shape.map_data = data

	# HeightMapShape3D trong Godot có khoảng cách giữa các điểm là 1.0 unit
	# và được căn giữa tại gốc (0, 0, 0).
	# Scale CollisionShape3D theo Vector3(cell_size, 1.0, cell_size) giúp lưới va chạm
	# trùng khớp hoàn toàn từng vị trí đỉnh với PlaneMesh.
	col_node.position = Vector3.ZERO
	col_node.scale = Vector3(cell_size, 1.0, cell_size)


# --- Mesh ---

func update_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.subdivide_depth = resolution
	plane.subdivide_width = resolution
	plane.size = Vector2(size, size)

	var plane_arrays := plane.get_mesh_arrays()
	var vertex_array: PackedVector3Array = plane_arrays[Mesh.ARRAY_VERTEX]
	var normal_array: PackedVector3Array = plane_arrays[Mesh.ARRAY_NORMAL]

	# Chuẩn bị tangent_array với kích thước chính xác (mỗi đỉnh cần đúng 4 float: x, y, z, orientation)
	var tangent_array := PackedFloat32Array()
	tangent_array.resize(vertex_array.size() * 4)

	for i in vertex_array.size():
		var vertex := vertex_array[i]
		var normal := Vector3.UP
		var tangent := Vector3.RIGHT
		if noise:
			vertex.y = get_height(vertex.x, vertex.z)
			normal = get_normal(vertex.x, vertex.z)
			# Chiếu Vector3.RIGHT lên tiếp diện của normal (Gram-Schmidt)
			var projected := Vector3.RIGHT - normal * normal.dot(Vector3.RIGHT)
			tangent = projected.normalized() if projected.length_squared() > 0.001 else Vector3.FORWARD
		vertex_array[i] = vertex
		normal_array[i] = normal
		var idx4 := i * 4
		tangent_array[idx4] = tangent.x
		tangent_array[idx4 + 1] = tangent.y
		tangent_array[idx4 + 2] = tangent.z
		tangent_array[idx4 + 3] = 1.0 # Thành phần thứ 4 (bi-tangent sign) bắt buộc trong Godot

	plane_arrays[Mesh.ARRAY_VERTEX] = vertex_array
	plane_arrays[Mesh.ARRAY_NORMAL] = normal_array
	plane_arrays[Mesh.ARRAY_TANGENT] = tangent_array

	var arrays_mesh := ArrayMesh.new()
	arrays_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	mesh = arrays_mesh
	update_collision()


# --- Multi-layer Noise Object Spawning ---

## Xóa tất cả object đã spawn trước đó (node con trong group "spawned")
func _clear_spawned_objects() -> void:
	for child in get_children():
		if child.is_in_group("spawned"):
			remove_child(child) # gỡ ngay để không còn collider "ma" trong frame hiện tại
			child.queue_free()

## Spawn vật thể theo toạ độ thế giới thực kết hợp Noise.
## Dùng RandomNumberGenerator riêng theo world_seed => kết quả tái lập được.
func spawn_objects() -> void:
	if not noise:
		push_warning("terrain: noise chưa được gán, bỏ qua spawn_objects()")
		return

	_clear_spawned_objects()

	_tree_pool = _build_pool(tree_scenes)
	_rock_pool = _build_pool(rock_scenes)

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var half_size := size * 0.5
	var step := maxf(spawn_spacing, 4.0) # Đảm bảo khoảng cách tối thiểu giữa các vị trí kiểm tra >= 4m

	# 1) Gom toàn bộ điểm ứng viên (lưới + jitter để cây không xếp thành hàng thẳng tắp)
	var points: Array[Vector2] = []
	var x := -half_size
	while x < half_size:
		var z := -half_size
		while z < half_size:
			var px := x + rng.randf_range(-step * 0.3, step * 0.3)
			var pz := z + rng.randf_range(-step * 0.3, step * 0.3)
			if absf(px) < half_size and absf(pz) < half_size:
				points.append(Vector2(px, pz))
			z += step
		x += step

	# 2) Xáo trộn để khi chạm giới hạn số lượng, cây/đá vẫn phân bố đều khắp đảo
	_shuffle_with_rng(points, rng)

	# 3) Duyệt từng điểm và thử spawn
	var tree_count := 0
	var rock_count := 0
	for p in points:
		if tree_count >= max_trees and rock_count >= max_rocks:
			break
		var h := get_height(p.x, p.y)
		if h < min_spawn_height:
			continue # dưới nước / sát bờ biển
		var slope_factor := get_normal(p.x, p.y).y
		if tree_count < max_trees and _try_spawn_tree(p.x, p.y, h, slope_factor, rng):
			tree_count += 1
		elif rock_count < max_rocks and _try_spawn_rock(p.x, p.y, h, slope_factor, rng):
			rock_count += 1

	print("[Terrain] seed ", world_seed, " | Đã spawn: ", tree_count, " cây | ", rock_count, " đá")


func _try_spawn_tree(x: float, z: float, world_height: float, slope_factor: float, rng: RandomNumberGenerator) -> bool:
	# Cây chỉ mọc ở vùng phẳng (slope_factor >= tree_min_slope) và noise_val vượt ngưỡng
	if _tree_pool.is_empty() or not tree_noise:
		return false
	if slope_factor < tree_min_slope:
		return false
	var noise_val: float = (tree_noise.get_noise_2d(x, z) + 1.0) * 0.5 # chuẩn hóa về [0, 1]
	if noise_val <= tree_threshold:
		return false
	var scene := _pick_scene(_tree_pool, rng)
	return _place_object(scene, Vector3(x, world_height + tree_y_offset, z), rng)

func _try_spawn_rock(x: float, z: float, world_height: float, slope_factor: float, rng: RandomNumberGenerator) -> bool:
	# Đá mọc ở vùng dốc hơn (slope_factor <= rock_max_slope)
	if _rock_pool.is_empty() or not rock_noise:
		return false
	if slope_factor > rock_max_slope:
		return false
	var noise_val: float = (rock_noise.get_noise_2d(x, z) + 1.0) * 0.5
	if noise_val <= rock_threshold:
		return false
	var scene := _pick_scene(_rock_pool, rng)
	return _place_object(scene, Vector3(x, world_height + rock_y_offset, z), rng)

func _build_pool(scenes: Array[PackedScene]) -> Array[PackedScene]:
	var pool: Array[PackedScene] = []
	for s in scenes:
		if s != null:
			pool.append(s)
	return pool

func _pick_scene(pool: Array[PackedScene], rng: RandomNumberGenerator) -> PackedScene:
	return pool[rng.randi_range(0, pool.size() - 1)]

func _place_object(scene: PackedScene, pos: Vector3, rng: RandomNumberGenerator) -> bool:
	var inst := scene.instantiate()
	var obj := inst as Node3D
	if obj == null:
		push_warning("terrain: scene spawn phải có root là Node3D")
		inst.free()
		return false
	obj.add_to_group("spawned")
	add_child(obj)
	obj.position = pos
	obj.rotation.y = rng.randf() * TAU
	var s := rng.randf_range(0.85, 1.25)
	obj.scale = Vector3(s, s, s)
	return true

# Fisher-Yates dùng RNG riêng (Array.shuffle() dùng RNG toàn cục nên không tái lập được)
func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
