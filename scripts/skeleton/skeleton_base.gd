class_name SkeletonBase
extends CharacterBody3D

@export_group("Stats")
@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var armor: float = 5.0

@export_group("Movement")
@export var move_speed: float = 4.0
@export var turn_speed: float = 10.0

@export_group("Combat / AI")
@export var detect_range: float = 25.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.2

@export_group("References")
@export var animation_tree: AnimationTree
@export var target: Node3D

var current_health: float
var isRunning: bool = false
var isAttacking: bool = false
var _attack_timer: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	current_health = max_health
	_find_references()
	if animation_tree:
		if animation_tree.tree_root:
			animation_tree.tree_root = animation_tree.tree_root.duplicate(true)
		animation_tree.active = true


func _physics_process(delta: float) -> void:
	# Áp dụng trọng lực
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _attack_timer > 0.0:
		_attack_timer -= delta

	_process_ai(delta)
	move_and_slide()


# Xử lý logic đuổi và đánh mục tiêu
func _process_ai(delta: float) -> void:
	if not target or not is_instance_valid(target) or target is SkeletonBase:
		_stop_movement()
		_set_animation_state(false, false)
		_find_player_target()
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist > detect_range:
		_stop_movement()
		_set_animation_state(false, false)
		return

	# Xoay mặt về hướng mục tiêu (Model hướng +Z)
	if to_target.length_squared() > 0.001:
		var target_yaw := atan2(to_target.x, to_target.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	if dist > attack_range and not isAttacking:
		var dir := to_target.normalized()
		var separation := _get_separation_vector()
		dir = (dir + separation * 0.7).normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		_set_animation_state(true, false)
	else:
		_stop_movement()
		_set_animation_state(false, isAttacking)

		if dist <= attack_range and _attack_timer <= 0.0 and not isAttacking:
			_start_attack()


# Lực tách nhẹ giúp các skeleton tránh đâm sầm hoặc đẩy trượt lẫn nhau
func _get_separation_vector() -> Vector3:
	var separation := Vector3.ZERO
	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		var enemy_node := enemy as Node3D
		if not enemy_node or enemy_node == self:
			continue
		var to_self: Vector3 = global_position - enemy_node.global_position
		to_self.y = 0.0
		var d_sq: float = to_self.length_squared()
		# Bán kính tách 1.4m
		if d_sq > 0.0001 and d_sq < 1.96:
			var d: float = sqrt(d_sq)
			separation += (to_self / d) * (1.4 - d)
	return separation


func _stop_movement() -> void:
	velocity.x = move_toward(velocity.x, 0.0, move_speed)
	velocity.z = move_toward(velocity.z, 0.0, move_speed)


# Kích hoạt đòn tấn công và đồng bộ cờ
func _start_attack() -> void:
	isAttacking = true
	_attack_timer = attack_cooldown
	_set_animation_state(false, true)
	_perform_attack()

	# Reset cờ isAttacking sau 0.1s để State Machine kết thúc đòn qua 'At End'
	var timer := get_tree().create_timer(0.1)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			isAttacking = false
			if animation_tree:
				animation_tree.set("parameters/conditions/isAttacking", false)
	)


# Cập nhật cờ AnimationTree
func _set_animation_state(running: bool, attacking: bool) -> void:
	isRunning = running
	isAttacking = attacking
	if animation_tree:
		animation_tree.set("parameters/conditions/isRunning", isRunning)
		animation_tree.set("parameters/conditions/isAttacking", isAttacking)
		animation_tree.set("parameters/conditions/isIdle", not isRunning and not isAttacking)


func _find_references() -> void:
	if not animation_tree:
		animation_tree = get_node_or_null("AnimationTree")
		if not animation_tree:
			animation_tree = get_node_or_null("Rig_Medium3")
		if not animation_tree:
			var trees := find_children("*", "AnimationTree", true, false)
			if trees.size() > 0:
				animation_tree = trees[0] as AnimationTree

	_find_player_target()


func _find_player_target() -> void:
	if not target or not is_instance_valid(target) or target is SkeletonBase:
		target = get_tree().get_first_node_in_group("player") as Node3D


# Virtual hooks cho các lớp kế thừa mở rộng
func _perform_attack() -> void:
	pass


func _on_attack_hit() -> void:
	pass


func take_damage(amount: float) -> void:
	var actual_damage := maxf(1.0, amount - armor)
	current_health = maxf(0.0, current_health - actual_damage)
	if current_health <= 0.0:
		_die()


func _die() -> void:
	set_physics_process(false)
	_stop_movement()
	_set_animation_state(false, false)
