@tool
extends Node3D

## Hệ thống thảm cỏ phân vùng không gian (Chunked MultiMesh Grass).
## Tự động chia bản đồ thành các ô chunk độc lập để GPU culling theo khoảng cách,
## tối ưu hiệu năng tối đa cho card đồ họa Intel Iris Xe.

@export_group("Grid & Chunks")
## Khoảng cách giữa các bụi cỏ (càng nhỏ thảm cỏ càng rậm, ví dụ: 1.0 - 2.0m)
@export_range(0.5, 5.0, 0.1) var spacing: float = 1.3

## Độ lệch ngẫu nhiên để tránh cỏ mọc thẳng hàng theo ô bàn cờ
@export_range(0.0, 1.0, 0.05) var jitter: float = 0.45

## Kích thước mỗi khối chunk (mét, ví dụ: 32m chia bản đồ 256m thành 64 chunks)
@export_range(8.0, 128.0, 4.0) var chunk_size: float = 32.0

@export_group("Mesh & Material")
## Mesh 3D dùng cho bụi cỏ
@export var grass_mesh: Mesh = preload("res://meshs/grass_1.tres")

## Material ghi đè (tùy chọn)
@export var material_override: Material

## Đổ bóng: Tắt (OFF) giúp tiết kiệm cực lớn fill-rate GPU trên card onboard
@export var cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

@export_group("Visibility Range (LOD & Culling)")
## Khoảng cách tối đa nhìn thấy ngọn cỏ (GPU tự động loại bỏ các chunk ở xa hơn mức này)
@export_range(10.0, 150.0, 5.0) var visibility_range_end: float = 35.0

## Khoảng đệm mờ dần khi camera đi xa (Dither fade margin)
@export_range(0.0, 20.0, 1.0) var visibility_range_end_margin: float = 8.0

## Chế độ Fade: Self giúp cỏ mờ dần tự nhiên khi ra vào tầm nhìn
@export var visibility_range_fade_mode: GeometryInstance3D.VisibilityRangeFadeMode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

@export_group("Terrain & Slope Filtering")
## Độ cao tối thiểu so với mặt biển (tránh mọc ngập dưới nước)
@export_range(-10.0, 50.0, 0.1) var min_height: float = 0.4

## Độ cao tối đa cho phép mọc cỏ
@export_range(0.0, 256.0, 1.0) var max_height: float = 200.0

## Ngưỡng độ dốc tối thiểu (normal.y: 1.0 là hoàn toàn phẳng, tránh mọc trên vách đá dốc đứng)
@export_range(0.0, 1.0, 0.02) var min_slope: float = 0.72

## Độ lệch trục Y (âm giúp cắm nhẹ gốc cỏ xuống lòng đất, tránh hở chân)
@export_range(-1.0, 1.0, 0.01) var y_offset: float = -0.15

## Mức độ nghiêng theo mặt phẳng dốc của địa hình [0.0 - 1.0]
@export_range(0.0, 1.0, 0.05) var align_to_normal: float = 0.6

@export_group("Noise Distribution")
## FastNoiseLite điều khiển phân bố cụm/vạt cỏ
@export var grass_noise: FastNoiseLite

## Ngưỡng giá trị noise (0.0 -> 1.0) để mọc cỏ. Càng cao thì cỏ càng mọc co cụm thành vạt
@export_range(0.0, 1.0, 0.02) var noise_threshold: float = 0.42

## Giới hạn scale ngẫu nhiên [min, max]
@export_range(0.2, 3.0, 0.05) var min_scale: float = 0.85
@export_range(0.2, 3.0, 0.05) var max_scale: float = 1.35

@export_group("Editor Tools")
## Bấm để sinh / làm mới cỏ ngay trong Editor
@export var generate_in_editor: bool = false:
	set(v):
		if v:
			generate_grass(0)
			generate_in_editor = false

## Bấm để xóa sạch toàn bộ cỏ trong Editor
@export var clear_in_editor: bool = false:
	set(v):
		if v:
			clear_grass()
			clear_in_editor = false

var _terrain: MeshInstance3D


func _ready() -> void:
	# Nếu node này vốn được tạo là MultiMeshInstance3D trong Scene cũ,
	# xóa multimesh đơn khối cũ để nhường chỗ cho các chunk con tối ưu hơn
	if "multimesh" in self:
		set("multimesh", null)

	_find_terrain()

	if not Engine.is_editor_hint():
		# Chờ Terrain sẵn sàng rồi sinh cỏ theo seed của Terrain
		call_deferred("_initial_runtime_spawn")


func _initial_runtime_spawn() -> void:
	_find_terrain()
	var world_seed := 0
	if _terrain and "world_seed" in _terrain:
		world_seed = int(_terrain.get("world_seed"))
	generate_grass(world_seed)


func _find_terrain() -> void:
	if _terrain and is_instance_valid(_terrain):
		return

	var p := get_parent()
	if p is MeshInstance3D and p.has_method("get_height"):
		_terrain = p
	else:
		_terrain = get_tree().root.find_child("Terrain", true, false) as MeshInstance3D

	if _terrain and _terrain.has_signal("terrain_generated"):
		if not _terrain.terrain_generated.is_connected(generate_grass):
			_terrain.terrain_generated.connect(generate_grass)


## Xóa sạch toàn bộ các chunk cỏ hiện tại
func clear_grass() -> void:
	for child in get_children():
		child.queue_free()


## Sinh thảm cỏ phân vùng Chunked MultiMesh theo seed thế giới
func generate_grass(world_seed: int = 0) -> void:
	var start_us := Time.get_ticks_usec()
	_find_terrain()

	if not _terrain or not _terrain.has_method("get_height") or not _terrain.has_method("get_normal"):
		push_warning("[Grass] Không tìm thấy Terrain hợp lệ để sinh cỏ!")
		return

	clear_grass()

	var active_mesh: Mesh = grass_mesh
	if not active_mesh:
		active_mesh = load("res://meshs/grass_1.tres") as Mesh
	if not active_mesh:
		push_warning("[Grass] Chưa có Mesh cho cỏ!")
		return

	# Chuẩn bị FastNoiseLite cho cỏ
	var active_noise: FastNoiseLite = grass_noise
	if not active_noise:
		active_noise = FastNoiseLite.new()
		active_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		active_noise.frequency = 0.025
		active_noise.fractal_octaves = 2
	active_noise.seed = world_seed + 7777

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 9999

	# Xác định kích thước hòn đảo
	var map_size: float = 256.0
	if "size" in _terrain:
		map_size = float(_terrain.get("size"))
	elif _terrain.mesh:
		map_size = _terrain.mesh.get_aabb().size.x

	var half_size := map_size * 0.5
	var step := maxf(spacing, 0.4)

	# Bảng gom cụm Transform3D theo tọa độ ô Chunk (Vector2i -> Array[Transform3D])
	var chunks: Dictionary = {}

	var x := -half_size
	while x < half_size:
		var z := -half_size
		while z < half_size:
			var px := x + rng.randf_range(-jitter, jitter)
			var pz := z + rng.randf_range(-jitter, jitter)

			if absf(px) < half_size and absf(pz) < half_size:
				# 1. Kiểm tra noise cụm cỏ
				var noise_val: float = (active_noise.get_noise_2d(px, pz) + 1.0) * 0.5
				if noise_val >= noise_threshold:
					# 2. Kiểm tra độ cao bề mặt lưới 3D thực tế
					var h: float = _terrain.get_mesh_height(px, pz) if _terrain.has_method("get_mesh_height") else _terrain.get_height(px, pz)
					if h >= min_height and h <= max_height:
						# 3. Kiểm tra độ dốc địa hình
						var norm: Vector3 = _terrain.get_normal(px, pz)
						if norm.y >= min_slope:
							var angle := rng.randf() * TAU
							var rot_basis := Basis.from_euler(Vector3(0.0, angle, 0.0))

							if align_to_normal > 0.001 and norm.length_squared() > 0.001:
								var target_up := Vector3.UP.slerp(norm, align_to_normal).normalized()
								rot_basis = Basis(Quaternion(Vector3.UP, target_up)) * rot_basis

							# Cỏ ở tâm vạt (noise_val cao) mọc to hơn rìa
							var density_factor := remap(noise_val, noise_threshold, 1.0, 0.9, 1.25)
							var s := rng.randf_range(min_scale, max_scale) * density_factor
							# Bù độ lún trên sườn dốc để các lá cỏ ngoài rìa khóm không bị hổng chân
							var slope_sink: float = (1.0 - clampf(norm.y, 0.0, 1.0)) * 0.15 * s
							var final_y := h + (y_offset * s) - slope_sink
							var basis := rot_basis.scaled(Vector3(s, s, s))
							var origin := Vector3(px, final_y, pz)
							var trans := Transform3D(basis, origin)

							# Phân vào ô Chunk tương ứng
							var chunk_coord := Vector2i(
								floori(px / chunk_size),
								floori(pz / chunk_size)
							)

							if not chunks.has(chunk_coord):
								chunks[chunk_coord] = []
							chunks[chunk_coord].append(trans)

			z += step
		x += step

	# Khởi tạo các MultiMeshInstance3D cho từng Chunk
	var total_instances := 0
	for chunk_coord: Vector2i in chunks:
		var transforms: Array = chunks[chunk_coord]
		if transforms.is_empty():
			continue

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = active_mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])

		mmi.multimesh = mm

		if material_override:
			mmi.material_override = material_override

		# Thiết lập GPU Distance Culling độc lập cho từng Chunk
		mmi.visibility_range_end = visibility_range_end
		mmi.visibility_range_end_margin = visibility_range_end_margin
		mmi.visibility_range_fade_mode = visibility_range_fade_mode
		mmi.cast_shadow = cast_shadow

		add_child(mmi)
		total_instances += transforms.size()

	var elapsed_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	print("[Grass] Đã tạo %d bụi cỏ trên %d Chunks độc lập (Thời gian: %.2f ms)." % [
		total_instances,
		chunks.size(),
		elapsed_ms
	])
