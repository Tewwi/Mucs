# @tool
# extends MultiMeshInstance3D

# @export_group("Spawn Settings")
# ## Khoảng cách giữa các bụi cỏ (càng nhỏ càng dày, ví dụ: 1.0 - 2.5)
# @export_range(0.5, 10.0, 0.1) var spacing: float = 3.0

# ## Độ lệch ngẫu nhiên để tránh cỏ mọc thẳng hàng theo ô bàn cờ
# @export_range(0.0, 2.0, 0.05) var jitter: float = 0.8

# ## Độ dốc tối thiểu cho phép cỏ mọc (normal.y, 1.0 = hoàn toàn phẳng, 0.7 = hơi dốc)
# @export_range(0.0, 1.0, 0.01) var min_slope: float = 0.75

# ## Độ lệch trục Y (âm = cắm nhẹ xuống đất, dương = nâng lên)
# @export_range(-1.0, 1.0, 0.05) var y_offset: float = -0.05

# ## Giới hạn scale ngẫu nhiên [min, max] (đã nhân 4 lần để dễ quan sát khi test)
# @export var min_scale: float = 2.8
# @export var max_scale: float = 4.8

# @export_group("Noise Distribution")
# ## Noise quyết định phân bố mật độ cỏ (nếu để trống sẽ tự tạo noise cụm tự nhiên)
# @export var grass_noise: FastNoiseLite

# ## Ngưỡng giá trị noise (0.0 -> 1.0) để mọc cỏ. Càng cao thì cỏ mọc thành từng cụm/bụi càng cô đọng
# @export_range(0.0, 1.0, 0.02) var noise_threshold: float = 0.45

# @export_group("Mesh & Texture")
# ## Mesh dùng cho cỏ (nếu để trống, script sẽ tự tạo 1 QuadMesh billboard)
# @export var grass_mesh: Mesh

# ## Texture ảnh cỏ/hoa (dùng khi tự tạo QuadMesh)
# @export var grass_texture: Texture2D

# @export_group("Editor Tools")
# ## Bấm để tạo / làm mới cỏ ngay trong Editor
# @export var generate_in_editor: bool = false:
# 	set(v):
# 		if v:
# 			generate_grass()
# 			generate_in_editor = false

# ## Bấm để xóa sạch cỏ trong Editor
# @export var clear_in_editor: bool = false:
# 	set(v):
# 		if v:
# 			clear_grass()
# 			clear_in_editor = false


# func _ready() -> void:
# 	if not Engine.is_editor_hint():
# 		# Cảnh báo nếu spacing quá nhỏ sẽ spawn hàng chục nghìn instance
# 		var estimated := int((256.0 / spacing) * (256.0 / spacing))
# 		if estimated > 10000:
# 			push_warning("[Grass] spacing=%.1f sẽ spawn ~%d instances, có thể gây lag! Tăng spacing lên >=4.0 khi test." % [spacing, estimated])
# 		# Chờ node cha (Terrain) hoàn tất _ready() và khởi tạo noise trước khi generate cỏ
# 		call_deferred("generate_grass")


# ## Xóa sạch cỏ hiện tại
# func clear_grass() -> void:
# 	if multimesh:
# 		multimesh.instance_count = 0


# ## Tạo thảm cỏ phủ trên toàn bộ diện tích của Terrain (parent)
# func generate_grass() -> void:
# 	var terrain := get_parent() as MeshInstance3D
# 	print("[Grass] parent: ", terrain)
# 	if not terrain:
# 		return
# 	print("[Grass] has get_height: ", terrain.has_method("get_height"),
# 		" | has get_normal: ", terrain.has_method("get_normal"))
# 	print("[Grass] noise: ", terrain.get("noise"), " | mesh: ", terrain.mesh)
# 	if not terrain.has_method("get_height") or not terrain.has_method("get_normal"):
# 		return

# 	var terrain_size: float = terrain.mesh.get_aabb().size.x
# 	var half_size := terrain_size / 2.0
# 	print("[Grass] size: ", terrain_size)

# 	# Chuẩn bị noise cho cỏ (ưu tiên grass_noise, nếu không có thì tạo noise với tần số phù hợp)
# 	var active_noise: FastNoiseLite = grass_noise
# 	if not active_noise:
# 		active_noise = FastNoiseLite.new()
# 		active_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
# 		active_noise.frequency = 0.03
# 		active_noise.fractal_octaves = 2

# 	var transforms: Array[Transform3D] = []
# 	var rejected_slope := 0
# 	var rejected_noise := 0
# 	var x := -half_size
# 	while x < half_size:
# 		var z := -half_size
# 		while z < half_size:
# 			var px := x + randf_range(-jitter, jitter)
# 			var pz := z + randf_range(-jitter, jitter)
# 			if abs(px) < half_size and abs(pz) < half_size:
# 				# Chuẩn hóa noise từ [-1, 1] về [0.0, 1.0]
# 				var noise_val: float = (active_noise.get_noise_2d(px, pz) + 1.0) * 0.5
# 				if noise_val >= noise_threshold:
# 					var normal: Vector3 = terrain.get_normal(px, pz)
# 					if normal.y >= min_slope:
# 						var angle := randf() * TAU
# 						# Cỏ ở vùng tâm cụm (noise_val cao) có thể mọc to/cao hơn
# 						var density_factor := remap(noise_val, noise_threshold, 1.0, 0.8, 1.2)
# 						var s := randf_range(min_scale, max_scale) * density_factor
# 						# Xoay cố định trục X = -90 độ, kết hợp xoay ngẫu nhiên quanh trục Y và scale
# 						var basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), angle, 0.0)).scaled(Vector3(s, s, s))
# 						var origin := Vector3(px, terrain.get_height(px, pz) + y_offset, pz)
# 						transforms.append(Transform3D(basis, origin))
# 					else:
# 						rejected_slope += 1
# 				else:
# 					rejected_noise += 1
# 			z += spacing
# 		x += spacing

# 	print("[Grass] spawned: ", transforms.size(), " | rejected slope: ", rejected_slope, " | rejected noise: ", rejected_noise)
# 	if transforms.is_empty():
# 		clear_grass()
# 		return

# 	if not multimesh:
# 		multimesh = MultiMesh.new()
# 	multimesh.transform_format = MultiMesh.TRANSFORM_3D
# 	multimesh.mesh = grass_mesh if grass_mesh else _create_default_quad_mesh()
# 	multimesh.instance_count = transforms.size()
# 	for i in transforms.size():
# 		multimesh.set_instance_transform(i, transforms[i])

# 	if Engine.is_editor_hint():
# 		update_gizmos()

# func _create_default_quad_mesh() -> QuadMesh:
# 	var quad := QuadMesh.new()
# 	quad.size = Vector2(1.0, 1.0)
# 	# Dịch tâm lên 0.5 để gốc cỏ nằm ngay mặt đất (y = 0)
# 	quad.center_offset = Vector3(0.0, 0.5, 0.0)

# 	var mat := StandardMaterial3D.new()
# 	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
# 	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
# 	# Y-Billboard giúp sprite luôn quay về camera nhưng vẫn đứng thẳng trên địa hình
# 	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
# 	if grass_texture:
# 		mat.albedo_texture = grass_texture

# 	quad.material = mat
# 	return quad
# # 
