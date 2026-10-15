class_name Player
extends CharacterBody3D

@export var JUMP_VELOCITY = 4.5

@export_group("Camera Settings")
@export var mouse_sensitivity := 0.003
@export var min_pitch := -60.0 # Góc nhìn xuống tối đa (độ)
@export var max_pitch := 60.0 # Góc nhìn lên tối đa (độ)

@export_group("Player Controller")
@export var move_speed := 6.0
@export var acceleration := 20.0

@export_group("Stats & Inventory")
@export var base_armor: float = 0.0
@export var base_max_health: float = 100.0

@export_group("Combat")
@export var attack_cooldown: float = 0.6

const DEFAULT_UNARMED_ATTACKS: Array[StringName] = [
	&"skeleton/Melee_Unarmed_Attack_Punch_A",
	&"skeleton/Melee_Unarmed_Attack_Kick"
]

var current_attack_animations: Array[StringName] = DEFAULT_UNARMED_ATTACKS

var current_armor: float = 0.0
var current_health: float = 100.0
var is_attacking: bool = false
var _attack_timer: float = 0.0

var _camera_input_dir := Vector2.ZERO

@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera: Camera3D = %Camera3D
@onready var inventory: Inventory = get_node_or_null("Inventory")
@onready var equipment_manager: EquipmentManager = get_node_or_null("EquipmentManager")
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var rig: Node3D = get_node_or_null("Rig_Medium")

func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	current_armor = base_armor
	current_health = base_max_health
	
	if not equipment_manager:
		equipment_manager = find_child("EquipmentManager", true, false) as EquipmentManager
	if not inventory:
		inventory = find_child("Inventory", true, false) as Inventory
	if not animation_tree:
		animation_tree = find_child("AnimationTree", true, false) as AnimationTree
	if not rig:
		rig = find_child("Rig_Medium", true, false) as Node3D
		
	if animation_tree:
		animation_tree.active = true
		_set_attack_node_animation(current_attack_animations[0])
		
	if equipment_manager:
		equipment_manager.equipment_changed.connect(_on_equipment_changed)

func _on_equipment_changed(slot: EquipmentData.Slot, new_item: EquipmentData, _old_item: EquipmentData) -> void:
	if equipment_manager:
		current_armor = base_armor + equipment_manager.get_total_armor_bonus()
		
	# Khi đổi vũ khí (slot WEAPON)
	if slot == EquipmentData.Slot.WEAPON:
		if new_item:
			var anims: Array[StringName] = []
			if new_item.attack_animations.size() > 0:
				anims.append_array(new_item.attack_animations)
			elif new_item.attack_animation != &"":
				anims.append(new_item.attack_animation)
				
			if anims.size() > 0:
				current_attack_animations = anims
				attack_cooldown = new_item.attack_cooldown
			else:
				current_attack_animations = DEFAULT_UNARMED_ATTACKS
				attack_cooldown = 0.6
		else:
			current_attack_animations = DEFAULT_UNARMED_ATTACKS
			attack_cooldown = 0.6

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape_focus"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("left_click"):
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			attack()

func attack() -> void:
	if is_attacking or _attack_timer > 0.0:
		return
		
	is_attacking = true
	_attack_timer = attack_cooldown
	
	# Chọn ngẫu nhiên hoặc theo thứ tự đòn đánh trong danh sách đòn của vũ khí hiện tại
	var chosen_anim: StringName = current_attack_animations.pick_random() if current_attack_animations.size() > 0 else &"skeleton/Melee_Unarmed_Attack_Punch_A"
	_set_attack_node_animation(chosen_anim)
	
	if animation_tree:
		animation_tree.set("parameters/conditions/isAttacking", true)
		animation_tree.set("parameters/conditions/isRunning", false)
		animation_tree.set("parameters/conditions/isIdle", false)
		animation_tree.set("parameters/conditions/isJump", false)
		
		# Reset cờ isAttacking sau 0.1s để State Machine kết thúc đòn qua 'At End'
		var timer := get_tree().create_timer(0.1)
		timer.timeout.connect(func():
			if animation_tree:
				animation_tree.set("parameters/conditions/isAttacking", false)
		)
	
	var finish_timer := get_tree().create_timer(attack_cooldown)
	finish_timer.timeout.connect(func():
		is_attacking = false
	)

func _set_attack_node_animation(anim_name: StringName) -> void:
	if not animation_tree:
		return
	var sm := animation_tree.tree_root as AnimationNodeStateMachine
	if sm and sm.has_node("Attack"):
		var attack_node := sm.get_node("Attack") as AnimationNodeAnimation
		if attack_node:
			attack_node.animation = anim_name

func set_attack_animations(anims: Array[StringName], cooldown: float = 0.6) -> void:
	current_attack_animations = anims if anims.size() > 0 else DEFAULT_UNARMED_ATTACKS
	attack_cooldown = cooldown

func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion := (event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	if is_camera_motion:
		_camera_input_dir += event.relative * mouse_sensitivity

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _attack_timer > 0.0:
		_attack_timer -= delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Hướng di chuyển phụ thuộc vào góc quay của Camera (Yaw)
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (Vector3(input_dir.x, 0, input_dir.y)).rotated(Vector3.UP, camera_pivot.global_rotation.y).normalized()
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		
		# Xoay model nhân vật theo hướng di chuyển (Model hướng +Z)
		if rig:
			var target_yaw := atan2(direction.x, direction.z)
			rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, 15.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	_update_animation_tree()
	handle_camera()
	move_and_slide()

func _update_animation_tree() -> void:
	if not animation_tree:
		return
		
	var in_air := not is_on_floor()
	var h_velocity := Vector2(velocity.x, velocity.z)
	var is_moving := h_velocity.length() > 0.2
	
	if in_air:
		animation_tree.set("parameters/conditions/isJump", true)
		animation_tree.set("parameters/conditions/isRunning", false)
		animation_tree.set("parameters/conditions/isIdle", false)
	elif not is_attacking:
		animation_tree.set("parameters/conditions/isJump", false)
		animation_tree.set("parameters/conditions/isRunning", is_moving)
		animation_tree.set("parameters/conditions/isIdle", not is_moving)
	else:
		animation_tree.set("parameters/conditions/isJump", false)

func handle_camera() -> void:
	# Xoay camera theo chuyển động chuột
	camera_pivot.rotation.x -= _camera_input_dir.y
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	camera_pivot.rotation.y -= _camera_input_dir.x

	_camera_input_dir = Vector2.ZERO
