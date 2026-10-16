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
## Thời gian lấy đà trước khi hitbox bật khi đánh tay không (giây, vd: 0.12)
@export var default_attack_windup: float = 0.12
## Thời gian hitbox duy trì gây sát thương khi đánh tay không (giây, vd: 0.22)
@export var default_attack_duration: float = 0.22

const DEFAULT_UNARMED_ATTACKS: Array[StringName] = [
	&"skeleton/Melee_Unarmed_Attack_Punch_A",
	&"skeleton/Melee_Unarmed_Attack_Kick"
]

var current_attack_animations: Array[StringName] = DEFAULT_UNARMED_ATTACKS

@export_group("UI")
@export var player_ui_scene: PackedScene = preload("res://scenes/player_ui.tscn")

var current_armor: float = 0.0
var current_health: float = 100.0
var is_attacking: bool = false
var _attack_timer: float = 0.0
@export var unarmed_damage: float = 12.0
var _anim_event_hit_active: bool = false

var _camera_input_dir := Vector2.ZERO
var player_ui: PlayerUI

@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera: Camera3D = %Camera3D
@onready var inventory: Inventory = get_node_or_null("Inventory")
@onready var equipment_manager: EquipmentManager = get_node_or_null("EquipmentManager")
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var rig: Node3D = get_node_or_null("Rig_Medium")

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2 # Layer 2: Player
	collision_mask = 1 | 4 # Layer 1: Terrain, Layer 3: Enemy
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	current_armor = base_armor
	current_health = base_max_health
	
	player_ui = get_node_or_null("PlayerUI") as PlayerUI
	if not player_ui and player_ui_scene:
		player_ui = player_ui_scene.instantiate() as PlayerUI
		add_child(player_ui)
	
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
		
	if equipment_manager and not equipment_manager.equipment_changed.is_connected(_on_equipment_changed):
		equipment_manager.equipment_changed.connect(_on_equipment_changed)

func _on_equipment_changed(slot: EquipmentData.Slot, new_item: EquipmentData, _old_item: EquipmentData) -> void:
	if equipment_manager:
		current_armor = base_armor + equipment_manager.get_total_armor_bonus()
		
	# Khi đổi vũ khí (slot RIGHT_HAND hoặc WEAPON)
	if slot == EquipmentData.Slot.RIGHT_HAND or slot == EquipmentData.Slot.WEAPON:
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
	if player_ui and player_ui.is_open():
		return
		
	if event.is_action_pressed("escape_focus"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("left_click"):
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			attack()

func attack() -> void:
	if is_attacking or _attack_timer > 0.0 or current_health <= 0.0:
		return
		
	is_attacking = true
	_attack_timer = attack_cooldown
	_anim_event_hit_active = false
	
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

	# Lấy sát thương vũ khí hiện tại
	var dmg := get_current_damage()

	# Cơ chế Hybrid: Tự động chạy Hit Window theo nhịp vung kiếm
	# Lấy thời gian delay lấy đà và thời gian duy trì hitbox từ vũ khí hoặc mặc định
	var windup_delay := default_attack_windup
	var active_duration := default_attack_duration
	if equipment_manager:
		var w_item := equipment_manager.get_equipped_item(EquipmentData.Slot.RIGHT_HAND)
		if w_item:
			windup_delay = w_item.attack_windup_delay
			active_duration = w_item.attack_active_duration
	
	var hit_start_timer := get_tree().create_timer(windup_delay)
	hit_start_timer.timeout.connect(func():
		if is_attacking and not _anim_event_hit_active:
			start_hit_window(dmg)
	)
	
	var hit_end_timer := get_tree().create_timer(windup_delay + active_duration)
	hit_end_timer.timeout.connect(func():
		if not _anim_event_hit_active:
			end_hit_window()
	)
	
	var finish_timer := get_tree().create_timer(attack_cooldown)
	finish_timer.timeout.connect(func():
		is_attacking = false
		end_hit_window()
	)


func get_current_damage() -> float:
	var dmg := 0.0
	if equipment_manager:
		dmg = equipment_manager.get_total_weapon_damage()
	if dmg <= 0.0:
		dmg = unarmed_damage
	return dmg


## Sự kiện mở Hit Window (có thể gọi tự động qua timer hoặc trực tiếp từ Animation Call Method Track)
func start_hit_window(damage_amount: float = -1.0) -> void:
	if damage_amount <= 0.0:
		damage_amount = get_current_damage()
	_anim_event_hit_active = true
	if equipment_manager:
		equipment_manager.enable_weapon_hitbox(damage_amount)


## Sự kiện đóng Hit Window (có thể gọi tự động qua timer hoặc trực tiếp từ Animation Call Method Track)
func end_hit_window() -> void:
	_anim_event_hit_active = false
	if equipment_manager:
		equipment_manager.disable_weapon_hitbox()


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

	# Nếu UI đang mở thì đứng yên và không xoay chuyển
	if player_ui and player_ui.is_open():
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		_update_animation_tree()
		move_and_slide()
		return

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


func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return
		
	var actual_damage := maxf(1.0, amount - current_armor)
	current_health = maxf(0.0, current_health - actual_damage)
	
	if player_ui:
		player_ui.refresh_ui()
	
	print('player take dmg ', current_health)

	if current_health <= 0.0:
		_die()


func _die() -> void:
	is_attacking = false
	end_hit_window()
	set_physics_process(false)
	
	if animation_tree:
		animation_tree.active = false
		
	var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if anim_player and anim_player.has_animation("skeleton/Death_A"):
		anim_player.play("skeleton/Death_A")
