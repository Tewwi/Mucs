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
## Thời gian lấy đà trước khi hitbox bật (giây, vd: 0.35)
@export var attack_windup_delay: float = 0.35
## Thời gian hitbox duy trì gây sát thương trong cú chém (giây, vd: 0.35)
@export var attack_active_duration: float = 0.35

@export_group("Weapon Hitbox")
## Tự động tính kích thước và vị trí Hitbox theo Mesh của vũ khí skeleton
@export var auto_hitbox_from_mesh: bool = true
## Kích thước Hitbox nếu tự chỉnh tay (khi auto_hitbox_from_mesh = false)
@export var custom_hitbox_size: Vector3 = Vector3(0.6, 1.5, 0.6)
## Vị trí dịch tâm Hitbox nếu tự chỉnh tay
@export var custom_hitbox_offset: Vector3 = Vector3(0.0, 0.45, 0.0)

@export_group("References")
@export var animation_tree: AnimationTree
@export var target: Node3D

var current_health: float
var isRunning: bool = false
var isAttacking: bool = false
var _attack_timer: float = 0.0
var is_dead: bool = false
var hitbox: Hitbox3D = null
var _anim_event_hit_active: bool = false

@export_group("Hit Feedback")
## Thời gian quái chớp đỏ khi bị trúng đòn (giây)
@export var hit_flash_duration: float = 0.2
## Màu chớp đỏ khi trúng đòn
@export var hit_flash_color: Color = Color(1.0, 0.15, 0.15, 0.75)

var _mesh_instances: Array[MeshInstance3D] = []
var _flash_counter: int = 0
static var _hit_flash_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4 # Layer 3: Enemy
	collision_mask = 1 | 2 # Layer 1: Terrain, Layer 2: Player
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

	if dist > attack_range and not isAttacking:
		var dir := to_target.normalized()
		var separation := _get_separation_vector()
		if separation.length_squared() > 0.0001:
			dir = (dir + separation * 0.7).normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		_set_animation_state(true, false)

		# Xoay mặt theo hướng di chuyển thực tế (dùng global_rotation vì skeleton nằm trong Camp bị xoay)
		if dir.length_squared() > 0.001:
			var move_yaw := atan2(dir.x, dir.z)
			global_rotation.y = lerp_angle(global_rotation.y, move_yaw, turn_speed * delta)
	else:
		_stop_movement()
		_set_animation_state(false, isAttacking)

		# Khi dừng lại hoặc tấn công, xoay mặt trực tiếp về phía mục tiêu
		if to_target.length_squared() > 0.001:
			var target_yaw := atan2(to_target.x, to_target.z)
			global_rotation.y = lerp_angle(global_rotation.y, target_yaw, turn_speed * delta)

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

	# Reset cờ isAttacking của AnimationTree sau 0.1s để State Machine không bị loop đòn
	var timer := get_tree().create_timer(0.1)
	timer.timeout.connect(func():
		if is_instance_valid(self) and animation_tree:
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
	_setup_weapon_hitbox()
	_cache_mesh_instances()


func _find_player_target() -> void:
	if not target or not is_instance_valid(target) or target is SkeletonBase:
		if is_inside_tree() and get_tree():
			target = get_tree().get_first_node_in_group("player") as Node3D


## Thiết lập Hitbox3D gắn vào vũ khí (hoặc tay phải) quái vật để gây sát thương cho Player
func _setup_weapon_hitbox() -> void:
	if hitbox:
		return
		
	var hand_attach: BoneAttachment3D = null
	var attachments := find_children("*", "BoneAttachment3D", true, false)
	for a in attachments:
		var ba := a as BoneAttachment3D
		if ba and ("hand.r" in ba.bone_name or ba.name == "BoneAttachment3D" or "hand" in ba.name.to_lower()):
			hand_attach = ba
			break
			
	if not hand_attach:
		var skels := find_children("*", "Skeleton3D", true, false)
		if skels.size() > 0:
			var skel := skels[0] as Skeleton3D
			hand_attach = BoneAttachment3D.new()
			hand_attach.name = "RightHandAttachment"
			skel.add_child(hand_attach)
			var b_idx := skel.find_bone("hand.r")
			if b_idx != -1:
				hand_attach.bone_name = "hand.r"
				hand_attach.bone_idx = b_idx
				
	if hand_attach:
		# Tìm node vũ khí dưới hand_attach nếu có (ví dụ Skeleton_Blade2)
		var weapon_node: Node3D = null
		for child in hand_attach.get_children():
			if child is Node3D and child.name != "Hitbox3D":
				weapon_node = child
				break
				
		var parent_node: Node3D = weapon_node if weapon_node else hand_attach
		
		# Dọn dẹp hitbox cũ nếu gắn nhầm vào hand_attach khi đã có weapon_node
		if weapon_node and hand_attach.has_node("Hitbox3D"):
			var old_hitbox := hand_attach.get_node("Hitbox3D")
			if old_hitbox != hitbox:
				old_hitbox.queue_free()
		
		hitbox = parent_node.get_node_or_null("Hitbox3D") as Hitbox3D
		if not hitbox:
			hitbox = Hitbox3D.new()
			hitbox.name = "Hitbox3D"
			hitbox.target_group = "player"
			hitbox.owner_character = self
			hitbox.damage = attack_damage
			hitbox.collision_layer = 0
			hitbox.collision_mask = 0xFFFFFFFF # Quét tất cả các layer, lọc qua target_group = "player"
			
			var col := CollisionShape3D.new()
			col.name = "CollisionShape3D"
			var shape := BoxShape3D.new()
			col.shape = shape
			hitbox.add_child(col)
			parent_node.add_child(hitbox)
			
		_update_hitbox_shape(weapon_node)


## Cập nhật kích thước & vị trí Hitbox theo Mesh của vũ khí skeleton
func _update_hitbox_shape(weapon_node: Node3D) -> void:
	if not hitbox:
		return
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not col:
		return
	var shape := col.shape as BoxShape3D
	if not shape:
		shape = BoxShape3D.new()
		col.shape = shape
		
	if not auto_hitbox_from_mesh and custom_hitbox_size != Vector3.ZERO:
		shape.size = custom_hitbox_size
		col.position = custom_hitbox_offset
	elif weapon_node:
		var weapon_mesh_instance: MeshInstance3D = null
		if weapon_node is MeshInstance3D:
			weapon_mesh_instance = weapon_node
		else:
			var meshes := weapon_node.find_children("*", "MeshInstance3D", true, false)
			if meshes.size() > 0:
				weapon_mesh_instance = meshes[0] as MeshInstance3D
				
		if weapon_mesh_instance and weapon_mesh_instance.mesh:
			var aabb := weapon_mesh_instance.mesh.get_aabb()
			var length := aabb.size.y
			# Bề rộng & bề dày mở rộng thêm một chút (+0.3m) để chém dễ trúng hơn
			var width := maxf(0.8, aabb.size.x + 0.3)
			var depth := maxf(0.8, aabb.size.z + 0.3)
			shape.size = Vector3(width, length, depth)
			col.position = aabb.get_center()
		else:
			shape.size = Vector3(0.8, 1.5, 0.8)
			col.position = Vector3(0.0, 0.45, 0.0)
	else:
		# Khi quái đánh tay không
		shape.size = Vector3(0.6, 0.6, 0.6)
		col.position = Vector3(0.0, 0.1, 0.0)


# Kích hoạt sự kiện chém đòn
func _perform_attack() -> void:
	_anim_event_hit_active = false
	var windup := attack_windup_delay
	var active_dur := attack_active_duration
	
	var hit_start_timer := get_tree().create_timer(windup)
	hit_start_timer.timeout.connect(func():
		if not is_dead and not _anim_event_hit_active:
			start_hit_window(attack_damage)
	)
	
	var hit_end_timer := get_tree().create_timer(windup + active_dur)
	hit_end_timer.timeout.connect(func():
		if not _anim_event_hit_active:
			end_hit_window()
	)
	
	# Kết thúc hoàn toàn lượt đánh sau attack_cooldown
	var finish_timer := get_tree().create_timer(attack_cooldown)
	finish_timer.timeout.connect(func():
		if is_instance_valid(self):
			isAttacking = false
			end_hit_window()
	)


## Sự kiện mở Hit Window của quái (có thể gọi tự động qua timer hoặc từ Call Method Track)
func start_hit_window(damage_amount: float = -1.0) -> void:
	if is_dead:
		return
	if damage_amount <= 0.0:
		damage_amount = attack_damage
	_anim_event_hit_active = true
	if hitbox:
		hitbox.start_hit(damage_amount)
	_on_attack_hit()


## Sự kiện đóng Hit Window của quái
func end_hit_window() -> void:
	_anim_event_hit_active = false
	if hitbox:
		hitbox.end_hit()


func _on_attack_hit() -> void:
	pass


func _cache_mesh_instances() -> void:
	_mesh_instances.clear()
	for child in find_children("*", "MeshInstance3D", true, false):
		_mesh_instances.append(child as MeshInstance3D)


func _get_hit_flash_material() -> StandardMaterial3D:
	if not _hit_flash_material:
		_hit_flash_material = StandardMaterial3D.new()
		_hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash_material.albedo_color = hit_flash_color
		_hit_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		_hit_flash_material.albedo_color = hit_flash_color
	return _hit_flash_material


## Đổi màu quái sang đỏ trong khoảng hit_flash_duration (mặc định 0.2s)
func _flash_hit() -> void:
	if _mesh_instances.is_empty():
		_cache_mesh_instances()
		
	var mat := _get_hit_flash_material()
	for m in _mesh_instances:
		if is_instance_valid(m):
			m.material_overlay = mat
			
	_flash_counter += 1
	var current_flash_id := _flash_counter
	
	if is_inside_tree() and get_tree():
		var timer := get_tree().create_timer(hit_flash_duration)
		timer.timeout.connect(func():
			if _flash_counter == current_flash_id:
				for m in _mesh_instances:
					if is_instance_valid(m):
						m.material_overlay = null
		)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	var actual_damage := maxf(1.0, amount - armor)
	current_health = maxf(0.0, current_health - actual_damage)
	
	_flash_hit()
	
	if current_health <= 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	set_physics_process(false)
	_stop_movement()
	end_hit_window()
	
	# Hủy hiệu ứng flash đỏ nếu đang chớp
	_flash_counter += 1
	for m in _mesh_instances:
		if is_instance_valid(m):
			m.material_overlay = null
			
	_set_animation_state(false, false)
	remove_from_group("enemy")
	
	# Vô hiệu hóa va chạm cơ thể để Player không bị cản đường
	var col := find_child("CollisionShape3D", true, false) as CollisionShape3D
	if col:
		col.set_deferred("disabled", true)
		
	if animation_tree:
		animation_tree.active = false
		
	var anim_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		var death_anim := "skeleton/Death_A" if anim_player.has_animation("skeleton/Death_A") else "Death_A"
		if anim_player.has_animation(death_anim):
			anim_player.play(death_anim)
			
	# Tự động dọn dẹp xác sau khi hoạt ảnh ngã hoàn tất (2.5s)
	if is_inside_tree() and get_tree():
		var cleanup_timer := get_tree().create_timer(2.5)
		cleanup_timer.timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)
	else:
		queue_free()
