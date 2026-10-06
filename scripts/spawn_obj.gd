## ObjectSpawner — Quản lý logic spawn vật thể trên địa hình
## Sử dụng kỹ thuật Multi-layer Noise để phân vùng từng loại vật thể theo độ dốc.
##
## Cách dùng:
##   var spawner := ObjectSpawner.new()
##   spawner.spawn_objects(terrain_node)
class_name ObjectSpawner
extends RefCounted

## Xóa tất cả node con đã spawn (được đánh dấu bằng group "spawned")
func clear_spawned_objects(terrain: Node3D) -> void:
	for child in terrain.get_children():
		if child.is_in_group("spawned"):
			child.queue_free()

## Điểm vào chính — duyệt lưới địa hình và thử spawn từng loại vật thể
func spawn_objects(terrain: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if not terrain.noise:
		push_warning("ObjectSpawner: terrain.noise chưa được gán, bỏ qua spawn_objects()")
		return

	clear_spawned_objects(terrain)

	var half: float = terrain.size / 2.0
	var x: float = -half
	while x < half:
		var z: float = -half
		while z < half:
			var world_height: float = terrain.get_height(x, z)
			# slope_factor ≈ 1.0 → bằng phẳng | ≈ 0.0 → thẳng đứng
			var slope_factor: float = terrain.get_normal(x, z).y

			_try_spawn_tree(terrain, x, z, world_height, slope_factor)
			_try_spawn_rock(terrain, x, z, world_height, slope_factor)

			z += terrain.spawn_spacing
		x += terrain.spawn_spacing

# --- Internal ---

func _try_spawn_tree(
	terrain: Node3D,
	x: float, z: float,
	world_height: float,
	slope_factor: float
) -> void:
	# Cây chỉ mọc ở vùng phẳng (slope_factor > 0.85)
	if not terrain.tree_scene or not terrain.tree_noise:
		return
	if slope_factor < 0.85:
		return
	# Chuẩn hóa noise từ [-1, 1] về [0, 1]
	var noise_val: float = (terrain.tree_noise.get_noise_2d(x, z) + 1.0) * 0.5
	if noise_val <= terrain.tree_threshold:
		return
	_place_object(terrain, terrain.tree_scene, Vector3(x, world_height, z))

func _try_spawn_rock(
	terrain: Node3D,
	x: float, z: float,
	world_height: float,
	slope_factor: float
) -> void:
	# Đá mọc ở vùng dốc (slope_factor < 0.75)
	if not terrain.rock_scene or not terrain.rock_noise:
		return
	if slope_factor >= 0.75:
		return
	var noise_val: float = (terrain.rock_noise.get_noise_2d(x, z) + 1.0) * 0.5
	if noise_val <= terrain.rock_threshold:
		return
	_place_object(terrain, terrain.rock_scene, Vector3(x, world_height, z))

func _place_object(terrain: Node3D, scene: PackedScene, pos: Vector3) -> void:
	var obj: Node3D = scene.instantiate() as Node3D
	if not obj:
		return
	# Xoay ngẫu nhiên quanh trục Y
	obj.rotation.y = randf() * TAU
	# Scale ngẫu nhiên ±20%
	var scale_factor: float = 0.8 + randf() * 0.4
	obj.scale = Vector3.ONE * scale_factor
	obj.add_to_group("spawned")
	terrain.add_child(obj)
	obj.position = pos
