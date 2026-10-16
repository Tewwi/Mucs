class_name Hitbox3D
extends Area3D

## Tín hiệu phát ra khi đánh trúng một đối tượng
signal hit_landed(target: Node3D, damage_dealt: float)

@export_group("Combat Config")
## Sát thương mặc định gây ra
@export var damage: float = 15.0

## Nhóm mục tiêu hợp lệ để gây sát thương ("enemy" hoặc "player")
@export var target_group: String = "enemy"

## Tự động bỏ qua chính nhân vật sở hữu (chủ nhân)
@export var owner_character: Node3D

@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")

## Danh sách các mục tiêu đã trúng trong đòn đánh hiện tại (đảm bảo mỗi nhát chỉ trúng 1 lần)
var _hit_targets: Array[Node3D] = []
var _is_active: bool = false


func _ready() -> void:
	# Luôn bật monitoring để Physics Server liên tục cập nhật bộ nhớ đệm va chạm
	monitoring = true
	monitorable = false
	_is_active = false
	
	if not collision_shape:
		collision_shape = find_child("CollisionShape3D", true, false) as CollisionShape3D
		
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func _physics_process(_delta: float) -> void:
	# Quét va chạm liên tục mỗi frame vật lý trong lúc đòn đánh đang diễn ra
	if _is_active:
		_check_overlapping()


## Kích hoạt Hitbox khi bắt đầu vệt chém (hỗ trợ cả Call Method Track trong Animation lẫn code)
func start_hit(damage_amount: float = -1.0) -> void:
	if damage_amount > 0.0:
		damage = damage_amount
		
	_hit_targets.clear()
	_is_active = true
	_check_overlapping()


## Kết thúc vệt chém, tắt cờ hoạt động (không cần can thiệp monitorable tránh lỗi blocked signal)
func end_hit() -> void:
	_is_active = false
	_hit_targets.clear()


## Alias hỗ trợ gọi trực tiếp từ Call Method Track trong AnimationPlayer
func start_hit_window(damage_amount: float = -1.0) -> void:
	start_hit(damage_amount)


func end_hit_window() -> void:
	end_hit()


func _on_body_entered(body: Node3D) -> void:
	_try_hit(body)


func _on_area_entered(area: Area3D) -> void:
	# Nếu đối phương có Hurtbox hoặc kiểm tra parent của area
	var potential_target := area.get_parent() as Node3D
	if potential_target:
		_try_hit(potential_target)


func _try_hit(target: Node3D) -> void:
	if not _is_active or not is_instance_valid(target):
		return
		
	# Không tự đánh trúng chính mình hoặc chủ nhân
	if target == owner_character or target == get_parent():
		return
		
	# Đã trúng trong đòn đánh này rồi -> bỏ qua (Single-hit per swing)
	if target in _hit_targets:
		return
		
	# Kiểm tra mục tiêu có thuộc group yêu cầu hay không
	if target_group != "" and not target.is_in_group(target_group):
		return
		
	# Kiểm tra mục tiêu có hàm nhận sát thương take_damage không
	if target.has_method("take_damage"):
		_hit_targets.append(target)
		target.take_damage(damage)
		hit_landed.emit(target, damage)


## Quét các body đang overlap sẵn
func _check_overlapping() -> void:
	for body in get_overlapping_bodies():
		_try_hit(body)
