@tool
extends MeshInstance3D

const size := 256.0

@export_range(4, 256, 4) var resolution := 32:
	set(new_resolution):
		resolution = new_resolution
		update_mesh()
		
@export var noise: FastNoiseLite:
	set(new_noise):
		noise = new_noise
		update_mesh()
		
@export_range(4.0, 128.0, 4.0) var height := 64.0:
	set(new_height):
		height = new_height
		update_mesh()

func get_height(x: float, y: float) -> float:
	return noise.get_noise_2d(x, y) * height

func get_normal(x: float, y: float) -> Vector3:
	var epsilon := size / resolution
	var dh_dx := (get_height(x + epsilon, y) - get_height(x - epsilon, y)) / (2.0 * epsilon)
	var dh_dz := (get_height(x, y + epsilon) - get_height(x, y - epsilon)) / (2.0 * epsilon)
	return Vector3(-dh_dx, 1.0, -dh_dz).normalized()

	
func update_collision() -> void:
	if Engine.is_editor_hint() or not noise:
		return

	var count := resolution + 1
	var step := size / resolution
	var half := size / 2.0

	var data := PackedFloat32Array()
	data.resize(count * count)
	for iz in count:
		for ix in count:
			var wx := -half + ix * step + position.x
			var wz := -half + iz * step + position.z
			data[iz * count + ix] = get_height(wx, wz)

	var shape := HeightMapShape3D.new()
	shape.map_width = count
	shape.map_depth = count
	shape.map_data = data

	var body := get_node_or_null("Body") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "Body"
		add_child(body)
		var col := CollisionShape3D.new()
		col.name = "Shape"
		body.add_child(col)

	var col_node := body.get_node("Shape") as CollisionShape3D
	col_node.shape = shape
	col_node.scale = Vector3(step, 1.0, step)

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
			# Chiếu Vector3.RIGHT lên tiếp diện của normal (Gram-Schmidt) để tránh suy biến về 0
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

	var arrays_mesh := ArrayMesh.new()
	arrays_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	mesh = arrays_mesh
	update_collision()
