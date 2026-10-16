class_name PlayerUI
extends CanvasLayer

@export var player: Player

@onready var main_panel: Control = $MainPanel
@onready var close_button: Button = %CloseButton

# Các nút Slot Trang bị
@onready var head_slot_btn: Button = %SlotHead
@onready var chest_slot_btn: Button = %SlotChest
@onready var arms_slot_btn: Button = %SlotArms
@onready var legs_slot_btn: Button = %SlotLegs
@onready var left_hand_slot_btn: Button = %SlotLeftHand
@onready var right_hand_slot_btn: Button = %SlotRightHand

# Label Chỉ số
@onready var stats_health_label: Label = %StatsHealth
@onready var stats_shield_label: Label = %StatsShield
@onready var stats_armor_label: Label = %StatsArmor
@onready var stats_strength_label: Label = %StatsStrength
@onready var stats_crit_label: Label = %StatsCrit
@onready var stats_attack_speed_label: Label = %StatsAttackSpeed
@onready var stats_speed_label: Label = %StatsSpeed
@onready var stats_damage_label: Label = %StatsDamage

# Preview 3D
@onready var preview_root: Node3D = %PreviewRoot
@onready var preview_sub_viewport: SubViewport = %PreviewSubViewport

# Lưới túi đồ và Tooltip
@onready var inventory_grid: GridContainer = %InventoryGrid
@onready var item_info_title: Label = %ItemInfoTitle
@onready var item_info_desc: Label = %ItemInfoDesc
@onready var item_info_stats: Label = %ItemInfoStats

# Silhouette Icons mặc định
const ICON_WEAPON = preload("res://assets/ui/icons/slot_weapon.svg")
const ICON_SHIELD = preload("res://assets/ui/icons/slot_shield.svg")
const ICON_HEAD = preload("res://assets/ui/icons/slot_head.svg")
const ICON_CHEST = preload("res://assets/ui/icons/slot_chest.svg")
const ICON_LEGS = preload("res://assets/ui/icons/slot_legs.svg")
const ICON_BOOTS = preload("res://assets/ui/icons/slot_boots.svg")

var _is_open: bool = false
var _inventory: Inventory
var _equipment_manager: EquipmentManager

var _slot_normal_style: StyleBoxFlat
var _slot_hover_style: StyleBoxFlat
var _slot_pressed_style: StyleBoxFlat


func _ready() -> void:
	visible = false
	_is_open = false
	_init_styles()
	
	if close_button:
		close_button.pressed.connect(close_ui)
		
	_connect_slot_buttons()
	_find_player_references()


func _init_styles() -> void:
	_slot_normal_style = StyleBoxFlat.new()
	_slot_normal_style.bg_color = Color(0.329, 0.2, 0.161, 1.0)
	_slot_normal_style.border_width_left = 2
	_slot_normal_style.border_width_top = 2
	_slot_normal_style.border_width_right = 2
	_slot_normal_style.border_width_bottom = 2
	_slot_normal_style.border_color = Color(0.180, 0.110, 0.086, 1.0)
	_slot_normal_style.set_corner_radius_all(8)
	
	_slot_hover_style = StyleBoxFlat.new()
	_slot_hover_style.bg_color = Color(0.380, 0.231, 0.184, 1.0)
	_slot_hover_style.border_width_left = 2
	_slot_hover_style.border_width_top = 2
	_slot_hover_style.border_width_right = 2
	_slot_hover_style.border_width_bottom = 2
	_slot_hover_style.border_color = Color(0.851, 0.651, 0.302, 1.0)
	_slot_hover_style.set_corner_radius_all(8)
	
	_slot_pressed_style = StyleBoxFlat.new()
	_slot_pressed_style.bg_color = Color(0.251, 0.149, 0.118, 1.0)
	_slot_pressed_style.border_width_left = 2
	_slot_pressed_style.border_width_top = 2
	_slot_pressed_style.border_width_right = 2
	_slot_pressed_style.border_width_bottom = 2
	_slot_pressed_style.border_color = Color(0.953, 0.753, 0.353, 1.0)
	_slot_pressed_style.set_corner_radius_all(8)


func is_open() -> bool:
	return _is_open


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toogle_bag"):
		get_viewport().set_input_as_handled()
		toggle_ui()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB or event.physical_keycode == KEY_I or event.physical_keycode == KEY_B:
			get_viewport().set_input_as_handled()
			toggle_ui()
		elif event.physical_keycode == KEY_ESCAPE and _is_open:
			get_viewport().set_input_as_handled()
			close_ui()


func toggle_ui() -> void:
	if _is_open:
		close_ui()
	else:
		open_ui()


func open_ui() -> void:
	_is_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_find_player_references()
	refresh_ui()


func close_ui() -> void:
	_is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _find_player_references() -> void:
	if not player:
		var parent_node := get_parent()
		if parent_node is Player:
			player = parent_node
		elif is_inside_tree() and get_tree():
			player = get_tree().get_first_node_in_group("player") as Player
			
	if player:
		if not _inventory:
			_inventory = player.get_node_or_null("Inventory") as Inventory
			if not _inventory:
				_inventory = player.find_child("Inventory", true, false) as Inventory
			if _inventory:
				if not _inventory.item_added.is_connected(_on_inventory_changed):
					_inventory.item_added.connect(_on_inventory_changed)
				if not _inventory.item_removed.is_connected(_on_inventory_changed):
					_inventory.item_removed.connect(_on_inventory_changed)
					
		if not _equipment_manager:
			_equipment_manager = player.get_node_or_null("EquipmentManager") as EquipmentManager
			if not _equipment_manager:
				_equipment_manager = player.find_child("EquipmentManager", true, false) as EquipmentManager
			if _equipment_manager:
				if not _equipment_manager.equipment_changed.is_connected(_on_equipment_changed):
					_equipment_manager.equipment_changed.connect(_on_equipment_changed)


func _connect_slot_buttons() -> void:
	if head_slot_btn:
		head_slot_btn.pressed.connect(func(): _unequip_slot(EquipmentData.Slot.HEAD))
		head_slot_btn.mouse_entered.connect(func(): _show_slot_info(EquipmentData.Slot.HEAD))
	if chest_slot_btn:
		chest_slot_btn.pressed.connect(func(): _unequip_slot(EquipmentData.Slot.CHEST))
		chest_slot_btn.mouse_entered.connect(func(): _show_slot_info(EquipmentData.Slot.CHEST))
	if arms_slot_btn:
		arms_slot_btn.pressed.connect(func(): _unequip_slot(EquipmentData.Slot.ARMS))
		arms_slot_btn.mouse_entered.connect(func(): _show_slot_info(EquipmentData.Slot.ARMS))
	if legs_slot_btn:
		legs_slot_btn.pressed.connect(func(): _unequip_slot(EquipmentData.Slot.LEGS))
		legs_slot_btn.mouse_entered.connect(func(): _show_slot_info(EquipmentData.Slot.LEGS))
	if left_hand_slot_btn:
		left_hand_slot_btn.pressed.connect(func(): _unequip_slot(EquipmentData.Slot.LEFT_HAND))
		left_hand_slot_btn.mouse_entered.connect(func(): _show_slot_info(EquipmentData.Slot.LEFT_HAND))
	if right_hand_slot_btn:
		right_hand_slot_btn.pressed.connect(func(): _unequip_slot(EquipmentData.Slot.RIGHT_HAND))
		right_hand_slot_btn.mouse_entered.connect(func(): _show_slot_info(EquipmentData.Slot.RIGHT_HAND))


func refresh_ui() -> void:
	_update_stats_display()
	_update_equipment_slots()
	_update_inventory_grid()
	_update_character_preview()


func _update_character_preview() -> void:
	if not preview_root or not player:
		return
		
	# Xóa preview cũ
	for child in preview_root.get_children():
		child.queue_free()
		
	if player.rig:
		var clone := player.rig.duplicate() as Node3D
		clone.position = Vector3(0, 0, 0)
		clone.rotation = Vector3(0, 0, 0) # Hướng nhân vật
		preview_root.add_child(clone)


func _update_stats_display() -> void:
	if not player:
		return
	
	if stats_health_label:
		stats_health_label.text = "%d" % int(player.current_health)
	if stats_shield_label:
		stats_shield_label.text = "0"
	if stats_armor_label:
		stats_armor_label.text = "%d" % int(player.current_armor)
	if stats_strength_label:
		stats_strength_label.text = "0"
	if stats_crit_label:
		stats_crit_label.text = "10%"
	if stats_attack_speed_label:
		stats_attack_speed_label.text = "0"
	if stats_speed_label:
		stats_speed_label.text = "%d" % int(player.move_speed)
		
	if stats_damage_label:
		var dmg: float = 2.0
		if _equipment_manager:
			var w_dmg := _equipment_manager.get_total_weapon_damage()
			if w_dmg > 0.0:
				dmg = w_dmg
		stats_damage_label.text = "%d" % int(dmg)


func _update_equipment_slots() -> void:
	if not _equipment_manager:
		return
		
	_render_equipment_slot(head_slot_btn, EquipmentData.Slot.HEAD)
	_render_equipment_slot(chest_slot_btn, EquipmentData.Slot.CHEST)
	_render_equipment_slot(arms_slot_btn, EquipmentData.Slot.ARMS)
	_render_equipment_slot(legs_slot_btn, EquipmentData.Slot.LEGS)
	_render_equipment_slot(left_hand_slot_btn, EquipmentData.Slot.LEFT_HAND)
	_render_equipment_slot(right_hand_slot_btn, EquipmentData.Slot.RIGHT_HAND)


func _render_equipment_slot(btn: Button, slot: EquipmentData.Slot) -> void:
	if not btn:
		return
	var item := _equipment_manager.get_equipped_item(slot)
	var placeholder: TextureRect = btn.get_node_or_null("Placeholder")
	var icon: TextureRect = btn.get_node_or_null("Icon")
	
	if item:
		if placeholder: 
			placeholder.visible = false
		if icon:
			icon.visible = true
			icon.texture = _get_item_icon(item)
			icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
		btn.tooltip_text = "%s\n%s" % [item.item_name, item.description]
	else:
		if placeholder: 
			placeholder.visible = true
		if icon: 
			icon.visible = false
		btn.tooltip_text = "[Trống]"


func _get_item_icon(item: EquipmentData) -> Texture2D:
	if not item:
		return null
	if item.icon:
		return item.icon
	# Fallback theo từng loại slot nếu item chưa có file icon
	match item.slot_type:
		EquipmentData.Slot.RIGHT_HAND, EquipmentData.Slot.WEAPON:
			return ICON_WEAPON
		EquipmentData.Slot.LEFT_HAND:
			return ICON_SHIELD
		EquipmentData.Slot.HEAD:
			return ICON_HEAD
		EquipmentData.Slot.CHEST:
			return ICON_CHEST
		EquipmentData.Slot.LEGS:
			return ICON_LEGS
		EquipmentData.Slot.ARMS:
			return ICON_BOOTS
		_:
			return ICON_WEAPON


func _update_inventory_grid() -> void:
	if not inventory_grid:
		return
		
	for child in inventory_grid.get_children():
		child.queue_free()
		
	var items: Array[EquipmentData] = []
	if _inventory:
		items = _inventory.items
	# 8 cột, 3 hàng = 24 ô
	var max_slots: int = maxi(_inventory.max_slots if _inventory else 24, 24)
	
	for i in range(max_slots):
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(54, 54)
		slot_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# Gán viền và nền ô theo phong cách ảnh tham chiếu
		slot_btn.add_theme_stylebox_override("normal", _slot_normal_style)
		slot_btn.add_theme_stylebox_override("hover", _slot_hover_style)
		slot_btn.add_theme_stylebox_override("pressed", _slot_pressed_style)
		slot_btn.add_theme_stylebox_override("focus", _slot_hover_style)
		
		if i < items.size():
			var item := items[i]
			slot_btn.tooltip_text = "%s\n%s" % [item.item_name, item.description]
			slot_btn.pressed.connect(func(): _equip_item(item))
			slot_btn.mouse_entered.connect(func(): _show_item_info(item))
			
			# Hiển thị Texture icon
			var icon_rect := TextureRect.new()
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.offset_left = 6
			icon_rect.offset_top = 6
			icon_rect.offset_right = -6
			icon_rect.offset_bottom = -6
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_rect.texture = _get_item_icon(item)
			slot_btn.add_child(icon_rect)
		else:
			slot_btn.text = ""
			
		inventory_grid.add_child(slot_btn)


func _equip_item(item: EquipmentData) -> void:
	if _inventory and item:
		_inventory.equip_from_inventory(item)
		refresh_ui()
		_show_item_info(item)


func _unequip_slot(slot: EquipmentData.Slot) -> void:
	if _inventory:
		_inventory.unequip_to_inventory(slot)
		refresh_ui()
		_clear_info()


func _show_item_info(item: EquipmentData) -> void:
	if not item:
		_clear_info()
		return
		
	if item_info_title:
		item_info_title.text = item.item_name
		
	if item_info_desc:
		item_info_desc.text = item.description
		
	if item_info_stats:
		var stats_text := ""
		if item.armor_bonus > 0.0:
			stats_text += "🛡️ Giáp: +%d  " % int(item.armor_bonus)
		if item.health_bonus > 0.0:
			stats_text += "❤️ Máu: +%d  " % int(item.health_bonus)
		if item.weapon_damage > 0.0:
			stats_text += "⚔️ Sát thương: %d  " % int(item.weapon_damage)
		if item.attack_cooldown > 0.0 and item.weapon_damage > 0.0:
			stats_text += "⏱️ Tốc độ: %.1fs  " % item.attack_cooldown
		if item.move_speed_bonus != 0.0:
			stats_text += "👟 Tốc độ chạy: %+.1f" % item.move_speed_bonus
		item_info_stats.text = stats_text


func _show_slot_info(slot: EquipmentData.Slot) -> void:
	if _equipment_manager:
		var item := _equipment_manager.get_equipped_item(slot)
		if item:
			_show_item_info(item)
		else:
			_clear_info()


func _clear_info() -> void:
	if item_info_title:
		item_info_title.text = "Chọn vật phẩm"
	if item_info_desc:
		item_info_desc.text = "Bấm chuột trái vào đồ trong túi để mặc vào người. Bấm vào ô trang bị để cởi đồ ra."
	if item_info_stats:
		item_info_stats.text = ""


func _on_inventory_changed(_item: EquipmentData = null) -> void:
	if _is_open:
		refresh_ui()


func _on_equipment_changed(_slot: EquipmentData.Slot, _new_item: EquipmentData, _old_item: EquipmentData) -> void:
	if _is_open:
		refresh_ui()
