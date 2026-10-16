class_name PlayerUI
extends CanvasLayer

@export var player: Player

@onready var main_panel: Control = $MainPanel
@onready var close_button: Button = %CloseButton

# Các nút Slot Trang bị đang mặc
@onready var head_slot_btn: Button = %SlotHead
@onready var chest_slot_btn: Button = %SlotChest
@onready var arms_slot_btn: Button = %SlotArms
@onready var legs_slot_btn: Button = %SlotLegs
@onready var left_hand_slot_btn: Button = %SlotLeftHand
@onready var right_hand_slot_btn: Button = %SlotRightHand

# Label Chỉ số
@onready var stats_health_label: Label = %StatsHealth
@onready var stats_armor_label: Label = %StatsArmor
@onready var stats_damage_label: Label = %StatsDamage

# Lưới túi đồ và Tooltip
@onready var inventory_grid: GridContainer = %InventoryGrid
@onready var item_info_title: Label = %ItemInfoTitle
@onready var item_info_desc: Label = %ItemInfoDesc
@onready var item_info_stats: Label = %ItemInfoStats

var _is_open: bool = false
var _inventory: Inventory
var _equipment_manager: EquipmentManager


func _ready() -> void:
	visible = false
	_is_open = false
	
	if close_button:
		close_button.pressed.connect(close_ui)
		
	_connect_slot_buttons()
	_find_player_references()


func is_open() -> bool:
	return _is_open


func _input(event: InputEvent) -> void:
	# Bấm action "toogle_bag" (hoặc Tab / I) để bật/tắt túi đồ
	if event.is_action_pressed("toogle_bag"):
		get_viewport().set_input_as_handled()
		toggle_ui()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB or event.physical_keycode == KEY_I:
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
		# Tìm từ cha hoặc trong scene
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


func _update_stats_display() -> void:
	if not player:
		return
	
	if stats_health_label:
		stats_health_label.text = "❤️ Máu: %d / %d" % [int(player.current_health), int(player.base_max_health)]
		
	if stats_armor_label:
		stats_armor_label.text = "🛡️ Giáp: %d" % int(player.current_armor)
		
	if stats_damage_label:
		var dmg: float = 15.0 # Sát thương tay không cơ bản
		if _equipment_manager:
			var w_dmg := _equipment_manager.get_total_weapon_damage()
			if w_dmg > 0.0:
				dmg = w_dmg
		stats_damage_label.text = "⚔️ Sát thương: %d" % int(dmg)


func _update_equipment_slots() -> void:
	if not _equipment_manager:
		return
		
	_set_slot_button_text(head_slot_btn, "🎩 Mũ", EquipmentData.Slot.HEAD)
	_set_slot_button_text(chest_slot_btn, "🛡️ Áo giáp", EquipmentData.Slot.CHEST)
	_set_slot_button_text(arms_slot_btn, "🧤 Giáp tay", EquipmentData.Slot.ARMS)
	_set_slot_button_text(legs_slot_btn, "👖 Quần giáp", EquipmentData.Slot.LEGS)
	_set_slot_button_text(left_hand_slot_btn, "🛡️ Tay Trái", EquipmentData.Slot.LEFT_HAND)
	_set_slot_button_text(right_hand_slot_btn, "⚔️ Tay Phải", EquipmentData.Slot.RIGHT_HAND)


func _set_slot_button_text(btn: Button, default_title: String, slot: EquipmentData.Slot) -> void:
	if not btn:
		return
	var item := _equipment_manager.get_equipped_item(slot)
	if item:
		btn.text = "%s:\n%s" % [default_title, item.item_name]
		btn.modulate = Color(1.0, 1.0, 1.0)
	else:
		btn.text = "%s:\n[Trống]" % default_title
		btn.modulate = Color(0.7, 0.7, 0.7)


func _update_inventory_grid() -> void:
	if not inventory_grid:
		return
		
	# Xóa các nút cũ trong grid
	for child in inventory_grid.get_children():
		child.queue_free()
		
	var items: Array[EquipmentData] = []
	if _inventory:
		items = _inventory.items
	var max_slots: int = _inventory.max_slots if _inventory else 16
	
	for i in range(max_slots):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 70)
		btn.clip_text = true
		
		if i < items.size():
			var item := items[i]
			btn.text = item.item_name
			btn.tooltip_text = "%s\n%s" % [item.item_name, item.description]
			btn.pressed.connect(func(): _equip_item(item))
			btn.mouse_entered.connect(func(): _show_item_info(item))
		else:
			btn.text = "---"
			btn.disabled = true
			btn.modulate = Color(0.4, 0.4, 0.4, 0.5)
			
		inventory_grid.add_child(btn)


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
		item_info_title.text = "Chọn một món đồ"
	if item_info_desc:
		item_info_desc.text = "Bấm chuột trái vào đồ trong túi để mặc vào người. Bấm vào ô trang bị để tháo đồ ra."
	if item_info_stats:
		item_info_stats.text = ""


func _on_inventory_changed(_item: EquipmentData = null) -> void:
	if _is_open:
		refresh_ui()


func _on_equipment_changed(_slot: EquipmentData.Slot, _new_item: EquipmentData, _old_item: EquipmentData) -> void:
	if _is_open:
		refresh_ui()
