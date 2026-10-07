@tool
class_name FoliageItemType
extends Resource

## Tên định danh (ví dụ: "Pine Tree", "Rock Medium", ...)
@export var name: String = "Foliage"

@export_group("Auto-Extract from Scene")
## Kéo Scene (.tscn) cây/đá đã căn chỉnh sẵn vào đây để tự động lấy Mesh và Collision
@export var source_scene: PackedScene:
	set(v):
		source_scene = v
		if source_scene != null:
			extract_from_scene(source_scene)

## Bấm tick vào đây để ép trích xuất lại từ source_scene
@export var extract_now: bool = false:
	set(v):
		if v and source_scene != null:
			extract_from_scene(source_scene)
		extract_now = false

@export_group("Visual (MultiMesh)")
## Mesh 3D của vật thể (bắt buộc, tự điền nếu dùng source_scene)
@export var mesh: Mesh

## Material ghi đè (tùy chọn)
@export var material_override: Material

@export_group("Physics (Collision)")
## Shape va chạm (CapsuleShape3D, CylinderShape3D, ConvexPolygonShape3D... tự điền nếu dùng source_scene)
## Để trống nếu vật thể này KHÔNG cần va chạm (ví dụ: cỏ, hoa, đá nhỏ).
@export var collision_shape: Shape3D

## Độ lệch tâm của CollisionShape3D so với gốc tọa độ của Mesh (tự điền nếu dùng source_scene)
@export var collision_offset: Vector3 = Vector3.ZERO

@export_group("Spawn Rules")
## FastNoiseLite riêng điều khiển mật độ xuất hiện của vật thể này
@export var noise: FastNoiseLite

## Ngưỡng noise [0.0 - 1.0]: càng cao thì vật thể mọc càng thưa / thành cụm cô đọng
@export_range(0.0, 1.0, 0.05) var noise_threshold: float = 0.3

## Ngưỡng độ dốc tối thiểu [0.0 - 1.0] (normal.y: 1.0 là hoàn toàn phẳng, 0.0 là vách đứng)
@export_range(0.0, 1.0, 0.01) var min_slope: float = 0.85

## Ngưỡng độ dốc tối đa [0.0 - 1.0] (dùng cho đá: chỉ mọc ở sườn dốc <= 0.75)
@export_range(0.0, 1.0, 0.01) var max_slope: float = 1.0

## Độ cao tối thiểu để spawn (tránh mọc dưới nước hoặc sát mép biển)
@export_range(-16.0, 64.0, 0.5) var min_height: float = 1.0

## Độ cao tối đa để spawn (ví dụ tránh mọc trên đỉnh núi tuyết)
@export_range(0.0, 256.0, 1.0) var max_height: float = 128.0

## Độ lệch trục Y (âm giúp cắm nhẹ gốc cây xuống lòng đất, tránh hở chân)
@export_range(-2.0, 2.0, 0.05) var y_offset: float = -0.2

## Giới hạn scale ngẫu nhiên [min, max]
@export_range(0.2, 3.0, 0.05) var min_scale: float = 0.85
@export_range(0.2, 5.0, 0.05) var max_scale: float = 1.25

## Số lượng tối đa cho loại vật thể này trên toàn đảo
@export_range(0, 5000, 10) var max_count: int = 300


## Tự động duyệt qua node cây trong Scene để bóc tách MeshInstance3D và CollisionShape3D
func extract_from_scene(scn: PackedScene) -> void:
	if not scn:
		return

	var instance: Node = scn.instantiate()
	if not instance:
		return

	if name == "Foliage" or name.is_empty():
		name = instance.name

	var found_mesh := false
	var found_col := false

	# Tìm kiếm MeshInstance3D và CollisionShape3D trong toàn bộ cây node
	var nodes_to_check: Array[Node] = [instance]
	while not nodes_to_check.is_empty():
		var current: Node = nodes_to_check.pop_front()

		# Lấy Mesh
		if not found_mesh and current is MeshInstance3D:
			var mi := current as MeshInstance3D
			if mi.mesh:
				mesh = mi.mesh
				if mi.material_override:
					material_override = mi.material_override
				found_mesh = true

		# Lấy Collision Shape & Offset
		if not found_col and current is CollisionShape3D:
			var cs := current as CollisionShape3D
			if cs.shape:
				# Tạo bản sao của shape để độc lập với scene gốc
				collision_shape = cs.shape.duplicate()
				collision_offset = cs.position
				found_col = true

		for child in current.get_children():
			nodes_to_check.append(child)

	instance.free()

	print("[FoliageItemType] Đã trích xuất từ '%s': Mesh=%s | Collision=%s" % [
		scn.resource_path.get_file(),
		found_mesh,
		found_col
	])
	notify_property_list_changed()
