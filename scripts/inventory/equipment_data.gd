class_name EquipmentData
extends Resource

enum Slot {
	HEAD,
	CHEST,
	ARMS,
	LEGS,
	WEAPON
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
