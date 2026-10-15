@tool
class_name LootItem3D
extends Area3D

@export_group("Equipment Data")
@export var item_data: EquipmentData:
	set(value):
		item_data = value
		_update_visuals()

@export_group("Animation & Visuals")
@export var rotate_speed: float = 2.0
@export var bob_amplitude: float = 0.08
@export var bob_frequency: float = 2.5


@onready var visual_mesh: MeshInstance3D = $VisualMesh
@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: Node3D = null
var _base_y: float = 0.0
var _time_passed: float = 0.0


func _ready() -> void:
	if not visual_mesh:
		visual_mesh = get_node_or_null("VisualMesh")
	if not prompt_label:
		prompt_label = get_node_or_null("PromptLabel")
		
	_base_y = visual_mesh.position.y if visual_mesh else 0.4
	_update_visuals()
	
	if Engine.is_editor_hint():
		return
		
	# Bật theo dõi va chạm với Player (Layer 2)
	collision_layer = 16 # Layer 5: Items
	collision_mask = 2 # Layer 2: Player (đã khai báo trong project.godot)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if prompt_label:
		prompt_label.visible = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	_time_passed += delta
	
	# Hiệu ứng xoay và nhấp nhô khi trong game
	if visual_mesh:
		visual_mesh.rotate_y(rotate_speed * delta)
		visual_mesh.position.y = _base_y + sin(_time_passed * bob_frequency) * bob_amplitude



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


func _update_visuals() -> void:
	if not visual_mesh:
		visual_mesh = get_node_or_null("VisualMesh")
	if not prompt_label:
		prompt_label = get_node_or_null("PromptLabel")
		
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
		
	if prompt_label and item_data:
		var display_name: String = item_data.item_name if item_data.item_name != "" else "Trang bị"
		prompt_label.text = "[E] Nhặt %s" % display_name

