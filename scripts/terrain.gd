@tool
extends MeshInstance3D

const size := 256.0

@export_range(4, 256, 4) var resolution := 32:
	set(new_resolution):
		resolution = new_resolution
		update_mesh()
		
@export var noise: FastNoiseLite:
	set(new_noise):
		if noise and noise.changed.is_connected(update_mesh):
			noise.changed.disconnect(update_mesh)
		noise = new_noise
		if noise and not noise.changed.is_connected(update_mesh):
			noise.changed.connect(update_mesh)
		update_mesh()
		
@export_range(4.0, 128.0, 4.0) var height := 64.0:
	set(new_height):
		height = new_height
		update_mesh()

# --- Multi-layer Noise cho Object Spawning ---
@export_group("Object Spawning")

## Noise riêng cho cây cối (mọc ở vùng phẳng)
@export var tree_noise: FastNoiseLite:
	set(v):
		tree_noise = v
		update_mesh()

## Ngưỡng spawn cây [0.0 - 1.0]: cao hơn = mọc thưa hơn
@export_range(0.0, 1.0, 0.05) var tree_threshold := 0.2

## Cảnh scene của cây để spawn
@export var tree_scene: PackedScene

## Độ lệch Y cho cây (giá trị âm giúp cắm ngập nhẹ gốc cây xuống lòng đất, tránh hở chân)
@export_range(-2.0, 2.0, 0.05) var tree_y_offset: float = -0.3

## Ngưỡng độ phẳng tối thiểu cho cây (slope_factor = normal.y, 1.0 là hoàn toàn phẳng)
@export_range(0.0, 1.0, 0.01) var tree_min_slope := 0.85

## Noise riêng cho đá (mọc ở vùng dốc)
@export var rock_noise: FastNoiseLite:
	set(v):
		rock_noise = v
		update_mesh()

## Ngưỡng spawn đá [0.0 - 1.0]
@export_range(0.0, 1.0, 0.05) var rock_threshold := 0.3

## Cảnh scene của đá để spawn
@export var rock_scene: PackedScene

## Độ lệch Y cho đá / bụi cây
@export_range(-2.0, 2.0, 0.05) var rock_y_offset: float = -0.1

## Ngưỡng độ phẳng tối đa cho đá (nhỏ hơn ngưỡng này mới mọc, tức là vùng sườn đồi dốc)
@export_range(0.0, 1.0, 0.01) var rock_max_slope := 0.75

## Khoảng cách tối thiểu giữa các điểm thử spawn (units)
@export_range(2.0, 32.0, 1.0) var spawn_spacing := 8.0

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

func _enter_tree() -> void:
	if noise and not noise.changed.is_connected(update_mesh):
		noise.changed.connect(update_mesh)

func _ready() -> void:
	if not Engine.is_editor_hint():
		update_mesh()
		update_collision()
		spawn_objects()


# --- Hàm địa hình cơ bản ---

func get_height(x: float, y: float) -> float:
	return noise.get_noise_2d(x, y) * height

func get_normal(x: float, y: float) -> Vector3:
	var epsilon := size / resolution
	var dh_dx := (get_height(x + epsilon, y) - get_height(x - epsilon, y)) / (2.0 * epsilon)
	var dh_dz := (get_height(x, y + epsilon) - get_height(x, y - epsilon)) / (2.0 * epsilon)
	return Vector3(-dh_dx, 1.0, -dh_dz).normalized()

# --- Collision ---

func update_collision() -> void:
	if Engine.is_editor_hint() or not mesh:
		return

	var body := get_node_or_null("Body") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "Body"
		add_child(body)
		var col := CollisionShape3D.new()
		col.name = "Shape"
		body.add_child(col)

	var col_node := body.get_node("Shape") as CollisionShape3D
	col_node.shape = mesh.create_trimesh_shape()

# --- Mesh ---

func update_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.subdivide_depth = resolution
	plane.subdivide_width = resolution
	plane.size = Vector2(size, size)
	
	var plane_arrays := plane.get_mesh_arrays()
	var vertex_array: PackedVector3Array = plane_arrays[Mesh.ARRAY_VERTEX]
	var normal_array: PackedVector3Array = plane_arrays[Mesh.ARRAY_NORMAL]
	var tangent_array: PackedFloat32Array = plane_arrays[Mesh.ARRAY_TANGENT]
	
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
		tangent_array[4 * i] = tangent.x
		tangent_array[4 * i + 1] = tangent.y
		tangent_array[4 * i + 2] = tangent.z

	plane_arrays[Mesh.ARRAY_VERTEX] = vertex_array
	plane_arrays[Mesh.ARRAY_NORMAL] = normal_array
	plane_arrays[Mesh.ARRAY_TANGENT] = tangent_array

	_cached_vertices = vertex_array
	_cached_normals = normal_array

	var arrays_mesh := ArrayMesh.new()
	arrays_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	mesh = arrays_mesh
	update_collision()

# --- Multi-layer Noise Object Spawning ---

var _cached_vertices: PackedVector3Array
var _cached_normals: PackedVector3Array

## Xóa tất cả object đã spawn trước đó (node con trong group "spawned")
func _clear_spawned_objects() -> void:
	for child in get_children():
		if child.is_in_group("spawned"):
			child.queue_free()

## Spawn vật thể theo kỹ thuật Multi-layer Noise (lấy toạ độ trực tiếp từ đỉnh của Mesh).
func spawn_objects() -> void:
	if not noise:
		push_warning("terrain: noise chưa được gán, bỏ qua spawn_objects()")
		return

	if _cached_vertices.is_empty():
		update_mesh()

	if _cached_vertices.is_empty():
		return

	_clear_spawned_objects()

	var total_verts := _cached_vertices.size()
	var cols := int(round(sqrt(total_verts)))
	if cols <= 1:
		return

	var vertex_step_dist := size / float(cols - 1)
	var stride := maxi(1, int(round(spawn_spacing / vertex_step_dist)))

	var row := 0
	while row < cols:
		var col := 0
		while col < cols:
			var index := row * cols + col
			var vert := _cached_vertices[index]
			var norm := _cached_normals[index]
			var slope_factor := norm.y

			_try_spawn_tree(vert.x, vert.z, vert.y, slope_factor)
			_try_spawn_rock(vert.x, vert.z, vert.y, slope_factor)

			col += stride
		row += stride


func _try_spawn_tree(x: float, z: float, world_height: float, slope_factor: float) -> void:
	# Cây chỉ mọc ở vùng phẳng (slope_factor >= tree_min_slope) và noise_val vượt ngưỡng
	if not tree_scene or not tree_noise:
		return
	if slope_factor < tree_min_slope:
		return
	var noise_val: float = (tree_noise.get_noise_2d(x, z) + 1.0) * 0.5 # chuẩn hóa về [0, 1]
	if noise_val <= tree_threshold:
		return
	_place_object(tree_scene, Vector3(x, world_height + tree_y_offset, z), slope_factor)

func _try_spawn_rock(x: float, z: float, world_height: float, slope_factor: float) -> void:
	# Đá mọc ở vùng dốc hơn (slope_factor <= rock_max_slope)
	if not rock_scene or not rock_noise:
		return
	if slope_factor > rock_max_slope:
		return
	var noise_val: float = (rock_noise.get_noise_2d(x, z) + 1.0) * 0.5
	if noise_val <= rock_threshold:
		return
	_place_object(rock_scene, Vector3(x, world_height + rock_y_offset, z), slope_factor)

func _place_object(scene: PackedScene, pos: Vector3, slope_factor: float) -> void:
	var obj := scene.instantiate()
	obj.add_to_group("spawned")
	add_child(obj)
	obj.position = pos
