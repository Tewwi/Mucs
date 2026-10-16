class_name EquipmentData
extends Resource

enum Slot {
	HEAD,
	CHEST,
	ARMS,
	LEGS,
	RIGHT_HAND,
	LEFT_HAND,
	WEAPON = RIGHT_HAND ## Tương thích ngược với code cũ dùng Slot.WEAPON
}

@export_group("Basic Info")
@export var item_id: String = ""
@export var item_name: String = "Trang bị mới"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var slot_type: Slot = Slot.CHEST

@export_group("Meshes")
## Mesh chính: dùng cho HEAD (Mũ/Nón), CHEST (Áo thân) hoặc bộ giáp / Vũ khí
@export var main_mesh: Mesh
## Mesh bên trái: dùng cho ARMS (Tay trái) hoặc LEGS (Chân trái)
@export var left_mesh: Mesh
## Mesh bên phải: dùng cho ARMS (Tay phải) hoặc LEGS (Chân phải)
@export var right_mesh: Mesh
## Vật liệu / Texture tương ứng nếu trang bị dùng texture riêng
@export var material_override: Material

@export_group("Bonus Stats")
@export var armor_bonus: float = 0.0
@export var health_bonus: float = 0.0
@export var move_speed_bonus: float = 0.0

@export_group("Weapon Animations & Combat")
## Animation tấn công chính (vd: "skeleton/Melee_1H_Attack_Chop")
@export var attack_animation: StringName = &""
## Danh sách các animation nếu vũ khí có nhiều đòn đánh combo/random
@export var attack_animations: Array[StringName] = []
@export var attack_cooldown: float = 0.6
@export var weapon_damage: float = 15.0
## Thời gian lấy đà trước khi hitbox bật gây sát thương (giây, vd: 0.15)
@export var attack_windup_delay: float = 0.15
## Thời gian hitbox duy trì gây sát thương trong vệt chém (giây, vd: 0.25)
@export var attack_active_duration: float = 0.25

@export_group("Weapon Hitbox")
## Tự động tính kích thước và vị trí Hitbox theo Mesh của vũ khí (khớp 100% với lưỡi kiếm)
@export var auto_hitbox_from_mesh: bool = true
## Kích thước Hitbox nếu tự chỉnh tay (khi auto_hitbox_from_mesh = false)
@export var custom_hitbox_size: Vector3 = Vector3(0.5, 1.4, 0.5)
## Vị trí dịch tâm Hitbox nếu tự chỉnh tay
@export var custom_hitbox_offset: Vector3 = Vector3(0.0, 0.6, 0.0)
