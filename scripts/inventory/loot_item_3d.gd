@tool
class_name LootItem3D
extends Area3D

@export_group("Equipment Data")
@export var item_data: EquipmentData:
	set(value):
		item_data = value
		_update_visuals()

@export_group("Position & Centering")
## Tự động tính toán AABB để đưa trọng tâm vật thể về đúng giữa Area3D (hết bị lơ lửng trên trời)
@export var auto_center_mesh: bool = true:
	set(value):
		auto_center_mesh = value
		_update_visuals()

## Độ cao lơ lửng của vật phẩm so với tâm Area3D
@export var float_height: float = 0.4:
	set(value):
		float_height = value
		_update_visuals()

## Tùy chỉnh vị trí thủ công (X, Y, Z) nếu muốn dịch chuyển thêm lên/xuống/ngang
@export var mesh_offset: Vector3 = Vector3.ZERO:
	set(value):
		mesh_offset = value
		_update_visuals()

## Góc xoay cố định ban đầu của vật thể (độ)
@export var mesh_rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		mesh_rotation_degrees = value
		_update_visuals()

## Tỷ lệ phóng to / thu nhỏ vật thể khi nằm dưới đất
@export var mesh_scale: Vector3 = Vector3.ONE:
	set(value):
		mesh_scale = value
		_update_visuals()

@export_group("Animation & Visuals")
@export var rotate_speed: float = 2.0
@export var bob_amplitude: float = 0.08
@export var bob_frequency: float = 2.5


@onready var visual_pivot: Node3D = $VisualPivot if has_node("VisualPivot") else null
@onready var visual_mesh: MeshInstance3D = $VisualPivot/VisualMesh if has_node("VisualPivot/VisualMesh") else get_node_or_null("VisualMesh")
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: Node3D = null
var _time_passed: float = 0.0


func _ready() -> void:
	_ensure_nodes()
	_update_visuals()
	
	if Engine.is_editor_hint():
		return
		
	# Bật theo dõi va chạm với Player (Layer 2)
	collision_layer = 16 # Layer 5: Items
	collision_mask = 2 # Layer 2: Player (đã khai báo trong project.godot)
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	
	if prompt_label:
		prompt_label.visible = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	_time_passed += delta
	
	# Hiệu ứng xoay và nhấp nhô quanh tâm vật phẩm
	if visual_pivot:
		visual_pivot.rotate_y(rotate_speed * delta)
		visual_pivot.position.y = float_height + sin(_time_passed * bob_frequency) * bob_amplitude
	elif visual_mesh:
		visual_mesh.rotate_y(rotate_speed * delta)
		visual_mesh.position.y = float_height + sin(_time_passed * bob_frequency) * bob_amplitude



func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
		
	var is_interact_action := event.is_action_pressed("interact")
	var is_e_key = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E)
	
	if is_interact_action or is_e_key:
		get_viewport().set_input_as_handled()
		_pickup()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = body
		if prompt_label:
			var display_name: String = item_data.item_name if item_data else "Vật phẩm"
			prompt_label.text = "[E] Nhặt %s" % display_name
			prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if prompt_label:
			prompt_label.visible = false


func _pickup() -> void:
	if not _player_in_range or not item_data:
		return
		
	# 1. Tìm Inventory trên Player
	var inventory: Inventory = _player_in_range.get_node_or_null("Inventory") as Inventory
	if not inventory:
		var inv_nodes := _player_in_range.find_children("*", "Inventory", true, false)
		if inv_nodes.size() > 0:
			inventory = inv_nodes[0] as Inventory
			
	if inventory:
		if inventory.add_item(item_data):
			_on_picked_up_success()
			return
			
	# 2. Nếu Player không có Inventory nhưng có EquipmentManager thì mặc thẳng
	var equip_mgr: EquipmentManager = _player_in_range.get_node_or_null("EquipmentManager") as EquipmentManager
	if not equip_mgr:
		var eq_nodes := _player_in_range.find_children("*", "EquipmentManager", true, false)
		if eq_nodes.size() > 0:
			equip_mgr = eq_nodes[0] as EquipmentManager
			
	if equip_mgr:
		equip_mgr.equip(item_data)
		_on_picked_up_success()
		return
		
	print_debug("Player không có Inventory hoặc EquipmentManager!")


func _on_picked_up_success() -> void:
	# Có thể spawn hiệu ứng hạt (particle) hoặc âm thanh ở đây trước khi giải phóng
	queue_free()


func _ensure_nodes() -> void:
	if not visual_pivot:
		visual_pivot = get_node_or_null("VisualPivot")
	
	if not visual_mesh:
		if visual_pivot and visual_pivot.has_node("VisualMesh"):
			visual_mesh = visual_pivot.get_node("VisualMesh")
		else:
			visual_mesh = get_node_or_null("VisualMesh")
			
	if not prompt_label:
		prompt_label = get_node_or_null("PromptLabel")


func _update_visuals() -> void:
	_ensure_nodes()
	if not visual_mesh:
		return
		
	if item_data and item_data.main_mesh:
		visual_mesh.mesh = item_data.main_mesh
		visual_mesh.material_override = item_data.material_override
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.35, 0.35)
		visual_mesh.mesh = box
		visual_mesh.material_override = null
		
	# Tự động tính tâm hình học (AABB) của Mesh để đưa về đúng tâm (0, 0, 0)
	var center_offset := Vector3.ZERO
	if auto_center_mesh and visual_mesh.mesh:
		center_offset = -visual_mesh.mesh.get_aabb().get_center()
		
	visual_mesh.position = center_offset + mesh_offset
	visual_mesh.rotation_degrees = mesh_rotation_degrees
	visual_mesh.scale = mesh_scale
	
	if visual_pivot:
		visual_pivot.position = Vector3(0, float_height, 0)
	else:
		visual_mesh.position += Vector3(0, float_height, 0)
		
	if prompt_label:
		prompt_label.position.y = float_height + 0.65
		if item_data:
			var display_name: String = item_data.item_name if item_data.item_name != "" else "Trang bị"
			prompt_label.text = "[E] Nhặt %s" % display_name
		else:
			prompt_label.text = "[E] Nhặt"


