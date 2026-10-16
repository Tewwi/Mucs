@tool
class_name CampSpawner
extends Node3D

## Tín hiệu phát ra khi hoàn tất việc spawn các camp
signal camps_generated(count: int)

@export_group("References")
## Node Terrain dùng để tra cứu độ cao và độ dốc (tự động tìm nếu để trống)
@export var terrain: MeshInstance3D

## Node Player để kiểm tra khoảng cách an toàn khi spawn (tự động tìm group 'player')
@export var player: Node3D

@export_group("Camp Settings")
## Danh sách các PackedScene camp để chọn ngẫu nhiên
@export var camp_scenes: Array[PackedScene] = []

## Số lượng camp chỉ định cần sinh ra trên bản đồ
@export_range(1, 30, 1) var camp_count: int = 4

## Bán kính chiếm chỗ của camp (dùng để kiểm tra độ phẳng và cấm cây/đá mọc đè)
@export_range(4.0, 32.0, 0.5) var camp_radius: float = 12.0

## Xoay ngẫu nhiên góc Y (0 - 360 độ) cho mỗi camp
@export var randomize_rotation: bool = true

## Tự động bám dính (snap) các prop và quái vật trong camp sát theo cao độ thực tế của địa hình
@export var snap_props_to_ground: bool = true

@export_group("Placement Constraints")
## Khoảng cách tối thiểu giữa 2 camp bất kỳ (tránh các camp dính chùm)
@export_range(20.0, 150.0, 1.0) var min_distance_between_camps: float = 55.0

## Khoảng cách tối thiểu từ tâm đảo (0, 0) / điểm Player spawn
@export_range(5.0, 100.0, 1.0) var min_distance_from_center: float = 25.0

## Độ cao tối thiểu (mặc định > 1.0m để nằm trên mặt nước biển Y = 0.0)
@export_range(0.0, 50.0, 0.5) var min_height: float = 1.0

## Độ cao tối đa cho phép đặt camp (tránh các mỏm núi đá cao chót vót)
@export_range(5.0, 100.0, 0.5) var max_height: float = 24.0

## Độ dốc tối thiểu tại tâm (normal.y: 1.0 = phẳng hoàn toàn, 0.88 ~ nghiêng 28 độ)
@export_range(0.5, 1.0, 0.02) var min_slope: float = 0.88

## Độ lệch cao độ tối đa cho phép vòng quanh chu vi camp (đảm bảo mặt đất bằng phẳng)
@export_range(0.2, 5.0, 0.1) var max_height_variance: float = 1.4

## Số lần thử tối đa khi tìm tọa độ hợp lệ cho mỗi camp
@export_range(50, 600, 10) var max_attempts_per_camp: int = 350

@export_group("Debug & Diagnostics")
## In log chi tiết quá trình tìm kiếm và đặt camp
@export var debug_logs: bool = true

@export_group("Editor Tools")
## Bấm để sinh thử các camp ngay trong Editor
@export var generate_in_editor: bool = false:
	set(v):
		if v:
			_find_references()
			var s: int = 0
			if terrain and "world_seed" in terrain:
				s = terrain.get("world_seed")
			generate_camps(s, true)
			generate_in_editor = false

## Bấm để dọn dẹp các camp đã sinh thử trong Editor
@export var clear_in_editor: bool = false:
	set(v):
		if v:
			clear_camps()
			clear_in_editor = false


# Container chứa các instance camp
var _camps_container: Node3D

# Danh sách thông tin các camp đã sinh: Array[Dictionary]
# Mỗi Dict: { "position": Vector3, "radius": float, "instance": Node3D }
var _camp_records: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("camp_spawner")
	_setup_container()

	# Khởi tạo mặc định camp_scenes nếu chưa có
	if camp_scenes.is_empty():
		var default_camp := load("res://scenes/camps/camp_1.tscn") as PackedScene
		if default_camp:
			camp_scenes.append(default_camp)

	if Engine.is_editor_hint():
		return

	_find_references()

	# Kết nối signal nếu Terrain có phát tín hiệu khi cập nhật xong thế giới
	if terrain and terrain.has_signal("terrain_generated"):
		if not terrain.terrain_generated.is_connected(generate_camps):
			terrain.terrain_generated.connect(generate_camps)
	else:
		call_deferred("_deferred_start")


func _deferred_start() -> void:
	_find_references()
	if terrain and terrain.has_method("get_height"):
		var seed_val: int = terrain.get("world_seed") if "world_seed" in terrain else 0
		generate_camps(seed_val)


func _setup_container() -> void:
	_camps_container = get_node_or_null("CampsContainer") as Node3D
	if not _camps_container:
		_camps_container = Node3D.new()
		_camps_container.name = "CampsContainer"
		add_child(_camps_container)


var _last_generated_seed: int = -99999999
var _has_generated: bool = false


func _find_references() -> void:
	if not terrain or not is_instance_valid(terrain):
		var p := get_parent()
		if p is MeshInstance3D and p.has_method("get_height"):
			terrain = p
		elif is_inside_tree() and get_tree() and get_tree().root:
			terrain = get_tree().root.find_child("Terran", true, false) as MeshInstance3D
			if not terrain:
				terrain = get_tree().root.find_child("Terrain", true, false) as MeshInstance3D

	if not player or not is_instance_valid(player):
		if is_inside_tree() and get_tree():
			var nodes := get_tree().get_nodes_in_group("player")
			if not nodes.is_empty():
				player = nodes[0] as Node3D
			elif get_tree().root:
				player = get_tree().root.find_child("Player", true, false) as Node3D


## Sinh danh sách các camp lên bản đồ theo world_seed
func generate_camps(world_seed: int = 0, force: bool = false) -> void:
	if not force and _has_generated and _last_generated_seed == world_seed and not _camp_records.is_empty():
		return

	_find_references()
	_setup_container()
	clear_camps()
	_last_generated_seed = world_seed
	_has_generated = true

	if not terrain or not terrain.has_method("get_height"):
		push_warning("CampSpawner: Không tìm thấy node Terrain hợp lệ!")
		return

	var valid_scenes: Array[PackedScene] = []
	for sc in camp_scenes:
		if sc != null:
			valid_scenes.append(sc)

	if valid_scenes.is_empty():
		var default_camp := load("res://scenes/camps/camp_1.tscn") as PackedScene
		if default_camp:
			valid_scenes.append(default_camp)

	if valid_scenes.is_empty():
		push_warning("CampSpawner: Không có PackedScene nào hợp lệ để spawn camp!")
		return

	var rng := RandomNumberGenerator.new()
	# Dùng offset seed để không trùng pattern với foliage
	rng.seed = world_seed + 98765

	# Xác định kích thước đảo / bán kính tìm kiếm
	var map_size: float = 256.0
	if "size" in terrain:
		map_size = float(terrain.get("size"))
	elif terrain.mesh:
		map_size = terrain.mesh.get_aabb().size.x

	var search_radius: float = (map_size * 0.5) - camp_radius
	if "island_radius" in terrain:
		search_radius = minf(search_radius, float(terrain.get("island_radius")) - camp_radius)

	if debug_logs:
		print("[CampSpawner] Bắt đầu sinh camp (yêu cầu=%d, seed=%d, bán kính quét=%.1fm)..." % [camp_count, world_seed, search_radius])

	var player_pos_2d := Vector2.ZERO
	if player and is_instance_valid(player):
		var gp: Vector3 = player.global_position
		player_pos_2d = Vector2(gp.x, gp.z)

	var spawned_count := 0
	# Góc xoay ngẫu nhiên của toàn bản đồ để vị trí các sector không bị cố định qua mỗi seed
	var map_angle_offset := rng.randf() * TAU

	for camp_idx in range(camp_count):
		var found_spot := false
		var best_pos := Vector3.ZERO

		# Tâm góc và độ rộng của sector dành riêng cho camp này
		var sector_center := map_angle_offset + (float(camp_idx) * (TAU / float(camp_count)))
		var sector_half_width := (TAU / float(camp_count)) * 0.48

		for attempt in range(max_attempts_per_camp):
			var progress := float(attempt) / float(max_attempts_per_camp)

			# 1. Phân chia cung góc theo sector (60% lượt thử đầu ưu tiên đúng sector để dàn đều khắp bản đồ)
			var theta: float
			if progress < 0.6:
				theta = sector_center + rng.randf_range(-sector_half_width, sector_half_width)
			else:
				theta = rng.randf() * TAU

			# 2. Phân bố bán kính vành đai: Đẩy camp ra khu vực chơi tự nhiên của đảo (không dồn ở tâm)
			var min_r := maxf(min_distance_from_center, search_radius * 0.30)
			var r := rng.randf_range(min_r, search_radius * 0.95)
			var px := r * cos(theta)
			var pz := r * sin(theta)
			var pos_2d := Vector2(px, pz)

			# 3. Điều kiện thích ứng mượt mà (Adaptive relaxation) khi gặp địa hình gồ ghề
			var cur_min_dist := min_distance_between_camps if progress < 0.45 else lerpf(min_distance_between_camps, 40.0, (progress - 0.45) * 1.8)
			var cur_min_slope := min_slope if progress < 0.35 else lerpf(min_slope, 0.78, (progress - 0.35) * 1.5)
			var cur_max_variance := max_height_variance if progress < 0.35 else lerpf(max_height_variance, 2.4, (progress - 0.35) * 1.5)

			# 1. Kiểm tra khoảng cách tới tâm bản đồ (0, 0)
			if pos_2d.length() < min_distance_from_center:
				continue

			# 2. Kiểm tra khoảng cách tới Player
			if player and pos_2d.distance_to(player_pos_2d) < min_distance_from_center:
				continue

			# 3. Kiểm tra khoảng cách tới các camp đã đặt trước đó
			var too_close := false
			for rec in _camp_records:
				var c_pos: Vector3 = rec["position"]
				var dist := pos_2d.distance_to(Vector2(c_pos.x, c_pos.z))
				if dist < cur_min_dist:
					too_close = true
					break
			if too_close:
				continue

			# 4. Kiểm tra cao độ và độ dốc tại tâm
			var h: float = terrain.get_mesh_height(px, pz) if terrain.has_method("get_mesh_height") else terrain.get_height(px, pz)
			if h < min_height or h > max_height:
				continue

			var norm: Vector3 = terrain.get_normal(px, pz)
			if norm.y < cur_min_slope:
				continue

			# 5. Kiểm tra độ bằng phẳng chu vi quanh camp (Perimeter Flatness Check)
			var is_perimeter_flat := true
			var min_sample_h := h
			var max_sample_h := h
			var sample_r := camp_radius * 0.65

			for step_i in range(8):
				var angle := step_i * (TAU / 8.0)
				var sx := px + cos(angle) * sample_r
				var sz := pz + sin(angle) * sample_r
				var sh: float = terrain.get_mesh_height(sx, sz) if terrain.has_method("get_mesh_height") else terrain.get_height(sx, sz)
				var snorm: Vector3 = terrain.get_normal(sx, sz)

				if snorm.y < (cur_min_slope - 0.05) or sh < min_height:
					is_perimeter_flat = false
					break

				min_sample_h = minf(min_sample_h, sh)
				max_sample_h = maxf(max_sample_h, sh)
				if (max_sample_h - min_sample_h) > cur_max_variance:
					is_perimeter_flat = false
					break

			if not is_perimeter_flat:
				continue

			# Vị trí hoàn toàn thỏa mãn
			found_spot = true
			best_pos = Vector3(px, h, pz)
			break

		if found_spot:
			var scene_idx := rng.randi() % valid_scenes.size()
			var chosen_scene: PackedScene = valid_scenes[scene_idx]
			var rot_y := (rng.randf() * TAU) if randomize_rotation else 0.0

			var camp_node := _instantiate_camp(chosen_scene, best_pos, rot_y)
			if camp_node:
				_camp_records.append({
					"position": best_pos,
					"radius": camp_radius,
					"instance": camp_node
				})
				spawned_count += 1
				if debug_logs:
					print("[CampSpawner] Đã spawn Camp #%d tại vị trí (%.1f, %.1f, %.1f) góc xoay %.1f°" % [
						spawned_count, best_pos.x, best_pos.y, best_pos.z, rad_to_deg(rot_y)
					])
		else:
			if debug_logs:
				push_warning("[CampSpawner] Không tìm được vị trí hợp lệ cho Camp #%d sau %d lần thử." % [
					camp_idx + 1, max_attempts_per_camp
				])

	if debug_logs:
		print("[CampSpawner] Hoàn tất sinh camp: Đã tạo %d / %d camp yêu cầu." % [spawned_count, camp_count])

	camps_generated.emit(spawned_count)


func _instantiate_camp(scene: PackedScene, pos: Vector3, rot_y: float) -> Node3D:
	if not scene:
		return null
	var inst := scene.instantiate() as Node3D
	if not inst:
		return null

	inst.position = pos
	inst.rotation.y = rot_y

	if snap_props_to_ground:
		_snap_camp_to_ground(inst)

	_camps_container.add_child(inst)
	return inst


## Tự động snap tất cả các vật thể (props) và quái vật trong camp bám sát theo độ cao địa hình thực tế
func _snap_camp_to_ground(camp_node: Node3D) -> void:
	_find_references()
	if not terrain or not terrain.has_method("get_mesh_height"):
		return

	var camp_trans: Transform3D = camp_node.transform
	var camp_base_y: float = camp_node.position.y

	# 1. Snap tất cả các prop trong node "Items"
	var items_node := camp_node.get_node_or_null("Items") as Node3D
	if items_node:
		var items_world_trans: Transform3D = camp_trans * items_node.transform
		for child in items_node.get_children():
			if child is Node3D:
				_snap_node_to_terrain(child, items_world_trans, camp_base_y)

	# 2. Snap tất cả quái vật trong node "Enemies"
	var enemies_node := camp_node.get_node_or_null("Enemies") as Node3D
	if enemies_node:
		var enemies_world_trans: Transform3D = camp_trans * enemies_node.transform
		for child in enemies_node.get_children():
			if child is Node3D:
				_snap_node_to_terrain(child, enemies_world_trans, camp_base_y)

	# 3. Snap các node 3D khác nằm trực tiếp dưới camp_node (nếu có quái vật hoặc vật thể đặt ở root)
	for child in camp_node.get_children():
		if child.name != "Items" and child.name != "Enemies" and child.name != "CampsContainer" and child is Node3D:
			_snap_node_to_terrain(child, camp_trans, camp_base_y)


func _snap_node_to_terrain(node: Node3D, parent_world_trans: Transform3D, camp_base_y: float) -> void:
	# Bỏ qua các thành phần nội bộ không phải là prop độc lập
	if node is MeshInstance3D or node is OmniLight3D or node is DirectionalLight3D or node is CollisionShape3D or node is Skeleton3D or node is BoneAttachment3D:
		return

	var world_pos: Vector3 = parent_world_trans * node.position
	var ground_h: float = terrain.get_mesh_height(world_pos.x, world_pos.z) if terrain.has_method("get_mesh_height") else terrain.get_height(world_pos.x, world_pos.z)

	var prefab_y_offset: float = node.position.y
	node.position.y = (ground_h - camp_base_y) + prefab_y_offset


## Kiểm tra xem một tọa độ (x, z) có nằm trong bán kính của bất kỳ camp nào không
func is_point_in_camp(x: float, z: float, extra_margin: float = 2.0) -> bool:
	for rec in _camp_records:
		var c_pos: Vector3 = rec["position"]
		var r: float = rec.get("radius", camp_radius) + extra_margin
		var dx := x - c_pos.x
		var dz := z - c_pos.z
		if (dx * dx + dz * dz) <= (r * r):
			return true
	return false


## Trả về danh sách vị trí Vector3 của tất cả các camp hiện tại
func get_camp_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for rec in _camp_records:
		result.append(rec["position"])
	return result


## Trả về danh sách các Node camp hiện tại
func get_camps() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for rec in _camp_records:
		if is_instance_valid(rec.get("instance")):
			result.append(rec["instance"])
	return result


## Xóa sạch tất cả các camp đã sinh
func clear_camps() -> void:
	_camp_records.clear()
	if _camps_container and is_instance_valid(_camps_container):
		for child in _camps_container.get_children():
			child.queue_free()


## Hàm hỗ trợ spawn động một camp tại vị trí chỉ định
func spawn_camp_at(pos: Vector3, scene: PackedScene = null, rot_y: float = 0.0) -> Node3D:
	_setup_container()
	var sc: PackedScene = scene
	if not sc and not camp_scenes.is_empty():
		sc = camp_scenes[0]
	if not sc:
		sc = load("res://scenes/camps/camp_1.tscn") as PackedScene
	if not sc:
		return null

	var camp_node := _instantiate_camp(sc, pos, rot_y)
	if camp_node:
		_camp_records.append({
			"position": pos,
			"radius": camp_radius,
			"instance": camp_node
		})
	return camp_node
