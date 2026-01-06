extends Control
class_name UniversalInventoryUI

# 通用背包UI - 可在任何场景使用
# 布局：左侧玩家背包 | 中间容器（可选） | 右侧详细信息

signal closed()

var player_panel: PanelContainer
var player_grid: GridContainer
var player_title: Label

var container_panel: PanelContainer
var container_grid: GridContainer
var container_title: Label

var info_panel: PanelContainer
var info_name: Label
var info_icon: TextureRect
var info_desc: Label
var button_container: HBoxContainer
var use_button: Button
var split_button: Button

var split_container: HBoxContainer
var split_slider: HSlider
var split_count_label: Label
var split_confirm_button: Button
var split_cancel_button: Button

var close_button: Button

var player_container: StorageContainer
var other_container: StorageContainer  # 可选的第二个容器（宝箱、仓库等）

var player_slots: Array = []
var other_slots: Array = []
var player_weapon_slot: Control = null
var other_weapon_slot: Control = null

var selected_slot_index: int = -1
var selected_storage_type: String = ""  # "player" 或 "other"
var selected_is_weapon_slot: bool = false

# 拖拽相关
var is_dragging: bool = false
var dragging_slot_index: int = -1
var dragging_storage_type: String = ""
var dragging_is_weapon_slot: bool = false
var drag_preview: Control = null

const SLOT_SCENE = preload("res://scenes/inventory_slot.tscn")
const WEAPON_SLOT_SCENE = preload("res://scenes/weapon_slot.tscn")

func _ready():
	# 获取节点引用
	_get_node_references()

	hide()
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# 连接按钮信号
	if use_button:
		use_button.pressed.connect(_on_use_button_pressed)
	if split_button:
		split_button.pressed.connect(_on_split_button_pressed)

	# 确保全屏布局
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _get_node_references():
	"""获取节点引用"""
	player_panel = get_node_or_null("Panel/HBoxContainer/PlayerPanel")
	player_grid = get_node_or_null("Panel/HBoxContainer/PlayerPanel/VBox/InventoryContainer/ScrollContainer/Grid")
	player_title = get_node_or_null("Panel/HBoxContainer/PlayerPanel/VBox/Title")
	
	container_panel = get_node_or_null("Panel/HBoxContainer/ContainerPanel")
	container_grid = get_node_or_null("Panel/HBoxContainer/ContainerPanel/VBox/InventoryContainer/ScrollContainer/Grid")
	container_title = get_node_or_null("Panel/HBoxContainer/ContainerPanel/VBox/Title")
	
	info_panel = get_node_or_null("Panel/HBoxContainer/InfoPanel")
	info_name = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/ItemName")
	info_icon = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/ItemIcon")
	info_desc = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/ScrollContainer/ItemDescription")

	button_container = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/ButtonContainer")
	use_button = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/ButtonContainer/UseButton")
	split_button = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/ButtonContainer/SplitButton")

	split_container = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/SplitContainer")
	split_slider = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/SplitContainer/SplitSlider")
	split_count_label = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/SplitContainer/SplitCountLabel")
	split_confirm_button = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/SplitContainer/SplitConfirmButton")
	split_cancel_button = get_node_or_null("Panel/HBoxContainer/InfoPanel/VBox/SplitContainer/SplitCancelButton")

	close_button = get_node_or_null("Panel/CloseButton")

func setup_player_inventory(container: StorageContainer, title: String = "背包"):
	"""设置玩家背包"""
	player_container = container
	if player_title:
		player_title.text = title
	_create_player_slots()
	
	if player_container:
		player_container.storage_changed.connect(_refresh_player_slots)

func setup_other_container(container: StorageContainer, title: String = "容器"):
	"""设置其他容器（宝箱、仓库等）"""
	# 断开旧容器的信号
	if other_container and other_container.storage_changed.is_connected(_refresh_other_slots):
		other_container.storage_changed.disconnect(_refresh_other_slots)
	
	other_container = container
	if container_title:
		container_title.text = title
	_create_other_slots()
	
	# 连接新容器的信号
	if other_container and not other_container.storage_changed.is_connected(_refresh_other_slots):
		other_container.storage_changed.connect(_refresh_other_slots)

func open_inventory_only():
	"""只打开玩家背包（无其他容器）"""
	if container_panel:
		container_panel.hide()
	_refresh_player_slots()
	_clear_selection()
	_clear_item_info()
	show()

func open_with_container():
	"""打开背包和容器"""
	if container_panel:
		container_panel.show()
	_refresh_all_slots()
	_clear_selection()
	_clear_item_info()
	show()

func close_inventory():
	"""关闭背包"""
	hide()
	_clear_selection()
	_clear_item_info()
	closed.emit()

func _create_player_slots():
	"""创建玩家背包格子"""
	if not player_grid:
		push_error("player_grid 节点未找到")
		return
	
	# 清空普通格子
	for child in player_grid.get_children():
		child.queue_free()
	player_slots.clear()
	
	# 清空武器槽
	var weapon_container = player_panel.get_node_or_null("VBox/WeaponContainer")
	if weapon_container:
		for child in weapon_container.get_children():
			child.queue_free()
	player_weapon_slot = null
	
	if not player_container:
		return
	
	# 如果有武器栏，创建武器槽到独立容器
	if player_container.has_weapon_slot and weapon_container:
		var weapon_slot = WEAPON_SLOT_SCENE.instantiate()
		weapon_slot.setup("player")
		weapon_slot.slot_clicked.connect(_on_weapon_slot_clicked)
		weapon_slot.slot_double_clicked.connect(_on_weapon_slot_double_clicked)
		weapon_slot.drag_started.connect(_on_weapon_drag_started)
		weapon_slot.drag_ended.connect(_on_weapon_drag_ended)
		weapon_container.add_child(weapon_slot)
		player_weapon_slot = weapon_slot
	
	# 创建普通格子
	for i in range(player_container.size):
		var slot = SLOT_SCENE.instantiate()
		slot.setup(i, "player")
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_double_clicked.connect(_on_slot_double_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_shift_clicked.connect(_on_slot_shift_clicked)
		slot.drag_started.connect(_on_drag_started)
		slot.drag_ended.connect(_on_drag_ended)
		player_grid.add_child(slot)
		player_slots.append(slot)

func _create_other_slots():
	"""创建其他容器格子"""
	if not container_grid:
		push_error("container_grid 节点未找到")
		return
	
	# 清空普通格子
	for child in container_grid.get_children():
		child.queue_free()
	other_slots.clear()
	
	# 清空武器槽
	var weapon_container = container_panel.get_node_or_null("VBox/WeaponContainer")
	if weapon_container:
		for child in weapon_container.get_children():
			child.queue_free()
	other_weapon_slot = null
	
	if not other_container:
		return
	
	# 如果有武器栏，创建武器槽到独立容器
	if other_container.has_weapon_slot and weapon_container:
		var weapon_slot = WEAPON_SLOT_SCENE.instantiate()
		weapon_slot.setup("other")
		weapon_slot.slot_clicked.connect(_on_weapon_slot_clicked)
		weapon_slot.slot_double_clicked.connect(_on_weapon_slot_double_clicked)
		weapon_slot.drag_started.connect(_on_weapon_drag_started)
		weapon_slot.drag_ended.connect(_on_weapon_drag_ended)
		weapon_container.add_child(weapon_slot)
		other_weapon_slot = weapon_slot
	
	# 创建普通格子
	for i in range(other_container.size):
		var slot = SLOT_SCENE.instantiate()
		slot.setup(i, "other")
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_double_clicked.connect(_on_slot_double_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_shift_clicked.connect(_on_slot_shift_clicked)
		slot.drag_started.connect(_on_drag_started)
		slot.drag_ended.connect(_on_drag_ended)
		container_grid.add_child(slot)
		other_slots.append(slot)

func _refresh_player_slots():
	"""刷新玩家背包格子"""
	if not player_container:
		return
	
	# 刷新武器槽
	if player_weapon_slot and player_container.has_weapon_slot:
		player_weapon_slot.set_item(player_container.weapon_slot)
	
	# 刷新普通格子
	for i in range(player_slots.size()):
		if i < player_container.storage.size():
			player_slots[i].set_item(player_container.storage[i])

func _refresh_other_slots():
	"""刷新其他容器格子"""
	if not other_container:
		return
	
	# 刷新武器槽
	if other_weapon_slot and other_container.has_weapon_slot:
		other_weapon_slot.set_item(other_container.weapon_slot)
	
	# 刷新普通格子
	for i in range(other_slots.size()):
		if i < other_container.storage.size():
			other_slots[i].set_item(other_container.storage[i])

func _refresh_all_slots():
	"""刷新所有格子"""
	_refresh_player_slots()
	_refresh_other_slots()

func _on_slot_clicked(slot_index: int, storage_type: String):
	"""格子被点击（单击）"""
	var container = player_container if storage_type == "player" else other_container
	if not container:
		return
	
	var clicked_item = container.storage[slot_index] if slot_index < container.storage.size() else null
	
	# 没有选中物品时
	if selected_slot_index == -1:
		if clicked_item != null:
			_select_slot(slot_index, storage_type)
			_show_item_info(clicked_item)
	else:
		# 已有选中物品时
		if selected_slot_index == slot_index and selected_storage_type == storage_type:
			# 点击同一个格子，取消选中
			_clear_selection()
			_clear_item_info()
		else:
			# 点击不同格子，切换选中
			if clicked_item != null:
				_select_slot(slot_index, storage_type)
				_show_item_info(clicked_item)
			else:
				_clear_selection()
				_clear_item_info()

func _on_slot_double_clicked(slot_index: int, storage_type: String):
	"""格子被双击 - 快速转移整格物品"""
	var container = player_container if storage_type == "player" else other_container
	if not container:
		return

	var item = container.storage[slot_index]
	if item == null:
		return

	# 执行快速转移
	var success = _quick_transfer_item(slot_index, storage_type)

	# 如果转移成功，清除选中状态
	if success:
		_clear_selection()
		_clear_item_info()

func _on_slot_shift_clicked(slot_index: int, storage_type: String):
	"""Shift+左键点击 - 快速转移整格物品"""
	var container = player_container if storage_type == "player" else other_container
	if not container:
		return

	var item = container.storage[slot_index]
	if item == null:
		return

	# 执行快速转移
	var success = _quick_transfer_item(slot_index, storage_type)

	# 如果转移成功，清除选中状态
	if success:
		_clear_selection()
		_clear_item_info()

func _on_slot_right_clicked(slot_index: int, storage_type: String):
	"""右键点击 - 快速转移一个物品（仅在选中状态下）"""
	if selected_slot_index != slot_index or selected_storage_type != storage_type:
		return

	var container = player_container if storage_type == "player" else other_container
	if not container:
		return

	var item = container.storage[slot_index]
	if item == null or int(item.count) < 1:
		return

	# 执行快速转移一个物品
	var success = _quick_transfer_item(slot_index, storage_type, 1)

	# 刷新显示但保持选中状态
	if success:
		if storage_type == "player":
			_refresh_player_slots()
		else:
			_refresh_other_slots()

		# 重新显示物品信息
		var updated_item = container.storage[slot_index]
		if updated_item != null:
			_show_item_info(updated_item)
		else:
			_clear_selection()
			_clear_item_info()

func _on_drag_started(slot_index: int, storage_type: String):
	"""开始拖拽"""
	var container = player_container if storage_type == "player" else other_container
	if not container:
		return
	
	var item = container.storage[slot_index]
	if item == null:
		return
	
	is_dragging = true
	dragging_slot_index = slot_index
	dragging_storage_type = storage_type
	
	# 创建拖拽预览
	_create_drag_preview(item)
	
	# 选中被拖拽的格子
	_select_slot(slot_index, storage_type)

func _on_drag_ended(_slot_index: int, _storage_type: String):
	"""结束拖拽"""
	if not is_dragging or dragging_is_weapon_slot:
		return
	
	# 销毁拖拽预览
	_destroy_drag_preview()
	
	# 查找鼠标下的目标格子
	var target_slot = _get_slot_under_mouse()
	
	if not target_slot.is_empty() and target_slot.has("index") and target_slot.has("type"):
		var target_index = target_slot["index"]
		var target_type = target_slot["type"]
		var target_is_weapon = target_slot.get("is_weapon_slot", false)
		
		# 执行移动/合并/交换
		if target_index != dragging_slot_index or target_type != dragging_storage_type or target_is_weapon:
			_move_item(dragging_slot_index, dragging_storage_type, target_index, target_type, target_is_weapon)
	
	# 清除拖拽状态
	is_dragging = false
	dragging_slot_index = -1
	dragging_storage_type = ""
	dragging_is_weapon_slot = false
	
	# 清除选中
	_clear_selection()
	_clear_item_info()

func _move_item(from_index: int, from_type: String, to_index: int, to_type: String, to_is_weapon: bool = false):
	"""移动物品"""
	var from_container = player_container if from_type == "player" else other_container
	var to_container = player_container if to_type == "player" else other_container
	
	if not from_container or not to_container:
		return
	
	# 如果目标是武器槽
	if to_is_weapon:
		var from_item = from_container.storage[from_index]
		if from_item == null:
			return
		
		var item_config = from_container.get_item_config(from_item.item_id)
		
		# 检查是否是武器
		if item_config.get("type") == "武器":
			# 武器放入武器槽
			var to_weapon = to_container.weapon_slot
			
			# 保留或初始化ammo字段
			var new_weapon = from_item.duplicate()
			if item_config.get("subtype") == "远程":
				# 如果原来有ammo字段，保留；否则初始化为0
				if not new_weapon.has("ammo"):
					new_weapon["ammo"] = 0
			
			# 交换
			to_container.weapon_slot = new_weapon
			if not to_weapon.is_empty():
				# 保留原武器槽中武器的ammo字段
				from_container.storage[from_index] = to_weapon.duplicate()
			else:
				from_container.storage[from_index] = null
			
			from_container.storage_changed.emit()
			to_container.storage_changed.emit()
		# 检查是否是弹药
		elif item_config.get("type") == "弹药":
			# 弹药放入武器栏 - 尝试装弹
			var weapon = to_container.weapon_slot
			if weapon.is_empty():
				print("武器槽中没有武器")
				return
			
			var weapon_config = to_container.get_item_config(weapon.item_id)
			if weapon_config.get("subtype") != "远程":
				print("只有远程武器需要弹药")
				return
			
			# 检查弹药类型是否匹配
			var ammo_type = item_config.get("caliber", "")
			var weapon_ammo_type = weapon_config.get("ammo_type", "")
			if ammo_type != weapon_ammo_type:
				print("弹药类型不匹配: 需要 " + weapon_ammo_type + ", 当前是 " + ammo_type)
				return
			
			# 尝试装弹
			var magazine_size = weapon_config.get("magazine_size", 30)
			var current_ammo = weapon.get("ammo", 0)
			var needed_ammo = magazine_size - current_ammo
			
			if needed_ammo <= 0:
				print("弹匣已满")
				return
			
			# 消耗弹药
			var ammo_to_use = min(needed_ammo, from_item.count)
			weapon["ammo"] = current_ammo + ammo_to_use
			to_container.weapon_slot = weapon
			
			# 从背包移除使用的弹药
			if ammo_to_use >= from_item.count:
				from_container.storage[from_index] = null
			else:
				from_item.count = from_item.count - ammo_to_use
			
			from_container.storage_changed.emit()
			to_container.storage_changed.emit()
		else:
			print("只有武器或弹药可以放入武器槽")
			return
	elif from_type == to_type:
		# 同一容器内移动
		if from_container:
			from_container.move_item_internal(from_index, to_index)
	else:
		# 跨容器移动
		if from_container and to_container:
			from_container.transfer_to(from_index, to_container, to_index)

func _select_slot(slot_index: int, storage_type: String):
	"""选中格子"""
	_clear_selection()
	selected_slot_index = slot_index
	selected_storage_type = storage_type
	selected_is_weapon_slot = false
	
	var slots = player_slots if storage_type == "player" else other_slots
	if slot_index < slots.size():
		slots[slot_index].set_selected(true)

func _select_weapon_slot(storage_type: String):
	"""选中武器槽"""
	_clear_selection()
	selected_slot_index = -1
	selected_storage_type = storage_type
	selected_is_weapon_slot = true
	
	if storage_type == "player" and player_weapon_slot:
		player_weapon_slot.set_selected(true)
	elif storage_type == "other" and other_weapon_slot:
		other_weapon_slot.set_selected(true)

func _clear_selection():
	"""清除选中状态"""
	# 还原按钮栏（如果有分离界面显示）
	_restore_split_ui_if_needed()

	if selected_is_weapon_slot:
		# 清除武器槽选中
		if selected_storage_type == "player" and player_weapon_slot:
			player_weapon_slot.set_selected(false)
		elif selected_storage_type == "other" and other_weapon_slot:
			other_weapon_slot.set_selected(false)
	elif selected_slot_index != -1:
		# 清除普通槽选中
		var slots = player_slots if selected_storage_type == "player" else other_slots
		if selected_slot_index < slots.size():
			slots[selected_slot_index].set_selected(false)

	selected_slot_index = -1
	selected_storage_type = ""
	selected_is_weapon_slot = false

func _setup_info_icon():
	"""专门设置信息图标的显示参数 - 保持原始比例"""
	if not info_icon:
		return
	
	# Godot 4 设置 - 保持原始比例，在容器内居中显示
	info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	# 确保能够填满容器但保持比例
	info_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _show_item_info(item_data: Dictionary):
	"""显示物品信息"""
	if not player_container or not info_name or not info_desc or not info_icon:
		return
	
	var item_config = player_container.get_item_config(item_data.item_id)
	var is_unknown = item_config.is_empty()
	
	info_name.text = item_config.get("name", "未知物品")
	if is_unknown:
		info_desc.text = "该物品可能已被删除，可以丢弃到地图上"
	else:
		info_desc.text = item_config.get("description", "无描述")
	
	if is_unknown:
		info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		info_icon.texture = load("res://assets/images/error.png")
	elif item_config.has("icon"):
		var icon_path = "res://assets/images/items/" + item_config.icon
		# 设置保持比例的缩放模式
		info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if ResourceLoader.exists(icon_path): 
			# 加载纹理
			var texture = load(icon_path)
			info_icon.texture = texture
			
			# 调试信息
			print("图标原始尺寸: ", texture.get_size())
			print("容器尺寸: ", info_icon.size)
		else:
			var texture = load("res://assets/images/error.png")
			info_icon.texture = texture
			push_warning("图标文件不存在: " + icon_path)
	else:
		info_icon.texture = load("res://assets/images/error.png")

	
	# 显示详细属性
	var details = "\n\n属性\n"
	details += "类型: " + item_config.get("type", "未知") + "\n"
	details += "数量: " + str(int(item_data.count)) + "\n"
	
	if item_config.has("weight"):
		details += "重量: " + str(item_config.weight) + "\n"
	if item_config.has("max_stack"):
		details += "最大堆叠: " + str(int(item_config.max_stack)) + "\n"
	
	# 武器属性
	if item_config.get("type") == "武器":
		if item_config.has("ammo_type"):
			details += "弹药: " + str(item_config.ammo_type) + "\n"
		if item_config.has("magazine_size"):
			details += "弹匣: " + str(int(item_config.magazine_size)) + "\n"
		if item_config.has("damage"):
			details += "伤害: " + str(item_config.damage) + "\n"
		if item_config.has("fire_rate"):
			details += "射速: " + str(item_config.fire_rate) + "\n"
	
	# 医疗属性
	if item_config.get("type") == "药品":
		if item_config.has("heal_amount"):
			details += "恢复量: " + str(item_config.heal_amount) + "\n"
	# 食材属性
	if item_config.get("type") == "食材":
		if item_config.has("cook_time"):
			details += "烹饪时长: " + str(item_config.cook_time) + "\n"
	
	info_desc.text += details

	# 更新按钮状态
	var can_use = not is_unknown and item_config.get("type") == "药品" and _is_in_explore_scene() and not selected_is_weapon_slot and selected_storage_type == "player" and selected_slot_index != -1
	var can_split = not selected_is_weapon_slot and selected_slot_index != -1 and int(item_data.count) > 1

	if use_button:
		use_button.disabled = not can_use
		if can_use:
			# 如果玩家已满血则禁用
			var scene = get_tree().current_scene
			var disabled := false
			if scene and scene.has_node("Player"):
				var p = scene.player
				if p:
					disabled = int(p.health) >= int(p.max_health)
			use_button.disabled = disabled

	# 更新分离按钮状态
	if split_button:
		split_button.disabled = not can_split

func _clear_item_info():
	"""清空物品信息"""
	if info_name:
		info_name.text = "选择物品查看详情"
	if info_desc:
		info_desc.text = ""
	if info_icon:
		info_icon.texture = null
	if use_button:
		use_button.disabled = true
	if split_button:
		split_button.disabled = true

func _on_use_button_pressed():
	if selected_is_weapon_slot:
		return
	if selected_storage_type != "player" or selected_slot_index < 0:
		return
	if not player_container:
		return
	var item = player_container.storage[selected_slot_index]
	if item == null:
		return
	var cfg = player_container.get_item_config(item.item_id)
	if cfg.get("type") != "药品":
		return
	var heal_amount = int(cfg.get("heal_amount", 0))
	var scene = get_tree().current_scene
	if scene and scene.has_node("Player"):
		var p = scene.player
		if p:
			var max_h = int(p.max_health)
			p.health = min(max_h, int(p.health) + heal_amount)
			p.health_changed.emit(int(p.health), max_h)
	# 消耗一个
	if int(item.count) > 1:
		item.count = int(item.count) - 1
		player_container.storage[selected_slot_index] = item
	else:
		player_container.storage[selected_slot_index] = null
	player_container.storage_changed.emit()
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		sm.save_game(sm.current_slot)
	_clear_selection()
	_clear_item_info()

func _is_in_explore_scene() -> bool:
	var s = get_tree().current_scene
	return s != null and s.has_method("get_checkpoint_data")

func _input(event: InputEvent):
	if not visible:
		return
	
	# E键或ESC键关闭背包
	if event is InputEventKey:
		if event.pressed and (event.keycode == KEY_E or event.keycode == KEY_ESCAPE):
			close_inventory()
			get_viewport().set_input_as_handled()

func _on_close_pressed():
	"""关闭按钮"""
	close_inventory()

func _find_nearest_empty_slot(from_index: int, storage_type: String) -> int:
	"""查找最近的空格子"""
	var container = player_container if storage_type == "player" else other_container
	if not container:
		return -1
	
	# 先向后查找
	for i in range(from_index + 1, container.size):
		if container.storage[i] == null:
			return i
	
	# 再向前查找
	for i in range(from_index):
		if container.storage[i] == null:
			return i
	
	return -1

func _create_drag_preview(item_data: Dictionary):
	"""创建拖拽预览"""
	if drag_preview != null:
		_destroy_drag_preview()
	
	# 创建预览容器（使用透明的Control而不是Panel）
	drag_preview = Control.new()
	drag_preview.custom_minimum_size = Vector2(64, 64)
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 添加图标
	var icon = TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	
	var item_config = player_container.get_item_config(item_data.item_id) if player_container else {}
	if item_config.has("icon"):
		var icon_path = "res://assets/images/items/" + item_config.icon
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		else:
			icon.texture = load("res://assets/images/error.png")
	
	drag_preview.add_child(icon)
	
	# 添加数量标签
	if int(item_data.count) > 1:
		var label = Label.new()
		label.text = str(int(item_data.count))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		label.offset_left = -24
		label.offset_top = -20
		label.offset_right = -4
		label.offset_bottom = -4
		drag_preview.add_child(label)
	
	# 设置半透明
	drag_preview.modulate = Color(1, 1, 1, 0.7)
	
	add_child(drag_preview)

func _destroy_drag_preview():
	"""销毁拖拽预览"""
	if drag_preview != null:
		drag_preview.queue_free()
		drag_preview = null

func _process(_delta):
	"""更新拖拽预览位置"""
	if is_dragging and drag_preview != null:
		drag_preview.global_position = get_global_mouse_position() - drag_preview.size / 2

func _get_slot_under_mouse() -> Dictionary:
	"""获取鼠标下的格子（包括间隔容差）"""
	var mouse_pos = get_global_mouse_position()
	var tolerance = 10  # 间隔容差（像素）
	
	# 检查玩家武器槽
	if player_weapon_slot:
		var rect = Rect2(player_weapon_slot.global_position, player_weapon_slot.size)
		if rect.has_point(mouse_pos):
			return {"index": -1, "type": "player", "is_weapon_slot": true}
	
	# 检查玩家背包格子
	for i in range(player_slots.size()):
		var slot = player_slots[i]
		var rect = Rect2(slot.global_position, slot.size)
		if rect.has_point(mouse_pos):
			return {"index": i, "type": "player", "is_weapon_slot": false}
	
	# 检查其他容器武器槽
	if other_weapon_slot:
		var rect = Rect2(other_weapon_slot.global_position, other_weapon_slot.size)
		if rect.has_point(mouse_pos):
			return {"index": -1, "type": "other", "is_weapon_slot": true}
	
	# 检查其他容器格子
	for i in range(other_slots.size()):
		var slot = other_slots[i]
		var rect = Rect2(slot.global_position, slot.size)
		if rect.has_point(mouse_pos):
			return {"index": i, "type": "other", "is_weapon_slot": false}
	
	# 如果没有直接命中，查找最近的格子（带容差）
	var nearest_slot = {}
	var nearest_distance = tolerance
	
	# 检查玩家武器槽（带容差）
	if player_weapon_slot:
		var rect = Rect2(player_weapon_slot.global_position, player_weapon_slot.size)
		var distance = _distance_to_rect(mouse_pos, rect)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_slot = {"index": -1, "type": "player", "is_weapon_slot": true}
	
	# 检查玩家背包格子（带容差）
	for i in range(player_slots.size()):
		var slot = player_slots[i]
		var rect = Rect2(slot.global_position, slot.size)
		var distance = _distance_to_rect(mouse_pos, rect)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_slot = {"index": i, "type": "player", "is_weapon_slot": false}
	
	# 检查其他容器武器槽（带容差）
	if other_weapon_slot:
		var rect = Rect2(other_weapon_slot.global_position, other_weapon_slot.size)
		var distance = _distance_to_rect(mouse_pos, rect)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_slot = {"index": -1, "type": "other", "is_weapon_slot": true}
	
	# 检查其他容器格子（带容差）
	for i in range(other_slots.size()):
		var slot = other_slots[i]
		var rect = Rect2(slot.global_position, slot.size)
		var distance = _distance_to_rect(mouse_pos, rect)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_slot = {"index": i, "type": "other", "is_weapon_slot": false}
	
	return nearest_slot

func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	"""计算点到矩形的最短距离"""
	# 如果点在矩形内，距离为0
	if rect.has_point(point):
		return 0.0

	# 计算点到矩形边界的最短距离
	var dx = max(rect.position.x - point.x, 0.0, point.x - rect.end.x)
	var dy = max(rect.position.y - point.y, 0.0, point.y - rect.end.y)
	return sqrt(dx * dx + dy * dy)


func _on_split_button_pressed():
	"""分离按钮点击"""
	if selected_is_weapon_slot or selected_slot_index < 0:
		return

	var container = player_container if selected_storage_type == "player" else other_container
	if not container:
		return

	var item = container.storage[selected_slot_index]
	if item == null or int(item.count) <= 1:
		return

	# 显示分离界面
	_show_split_ui(item)

func _show_split_ui(item_data: Dictionary):
	"""显示分离界面"""
	if not split_container or not split_slider or not split_count_label or not split_confirm_button or not split_cancel_button:
		return

	# 隐藏按钮容器
	if button_container:
		button_container.hide()

	# 配置滑杆
	split_slider.min_value = 1
	split_slider.max_value = int(item_data.count) - 1
	split_slider.value = int((split_slider.min_value + split_slider.max_value) / 2)  # 默认中间值
	split_slider.step = 1

	# 更新数量标签
	split_count_label.text = str(int(split_slider.value))

	# 连接滑杆值改变信号来更新文本框
	split_slider.value_changed.connect(_on_split_slider_value_changed)

	# 连接按钮信号
	split_confirm_button.pressed.connect(_on_split_confirm_pressed)
	split_cancel_button.pressed.connect(_on_split_cancel_pressed)

	# 显示分离容器
	split_container.show()

func _on_split_confirm_pressed():
	"""确认分离"""
	if not split_slider:
		return

	var split_count = int(split_slider.value)
	if split_count <= 0:
		_restore_button_container()
		return

	var container = player_container if selected_storage_type == "player" else other_container
	if not container:
		_restore_button_container()
		return

	# 查找空格子
	var target_index = _find_empty_slot_for_quick_transfer(container)
	if target_index == -1:
		push_warning("没有空格子可以分离物品")
		_restore_button_container()
		return

	# 执行分离
	container.split_item(selected_slot_index, target_index, split_count)

	# 刷新显示
	if selected_storage_type == "player":
		_refresh_player_slots()
	else:
		_refresh_other_slots()

	# 保持选中状态并更新信息
	var updated_item = container.storage[selected_slot_index]
	if updated_item != null:
		_show_item_info(updated_item)
	else:
		_clear_selection()
		_clear_item_info()

	_restore_button_container()

func _on_split_cancel_pressed():
	"""取消分离"""
	_restore_button_container()

func _on_split_slider_value_changed(value: float):
	"""滑杆值改变"""
	if split_count_label:
		split_count_label.text = str(int(value))

func _restore_button_container():
	"""还原按钮容器"""
	if not split_container:
		return

	# 断开信号连接
	if split_slider and split_slider.value_changed.is_connected(_on_split_slider_value_changed):
		split_slider.value_changed.disconnect(_on_split_slider_value_changed)
	if split_confirm_button and split_confirm_button.pressed.is_connected(_on_split_confirm_pressed):
		split_confirm_button.pressed.disconnect(_on_split_confirm_pressed)
	if split_cancel_button and split_cancel_button.pressed.is_connected(_on_split_cancel_pressed):
		split_cancel_button.pressed.disconnect(_on_split_cancel_pressed)

	# 隐藏分离容器
	split_container.hide()

	# 显示按钮容器
	if button_container:
		button_container.show()

func _restore_split_ui_if_needed():
	"""如果有分离界面显示，则还原"""
	if split_container and split_container.visible:
		_restore_button_container()


func _on_weapon_slot_clicked(storage_type: String):
	"""武器槽被点击"""
	var container = player_container if storage_type == "player" else other_container
	if not container or not container.has_weapon_slot:
		return
	
	var weapon_item = container.weapon_slot
	
	# 没有选中物品时
	if selected_slot_index == -1 and not selected_is_weapon_slot:
		if not weapon_item.is_empty():
			_select_weapon_slot(storage_type)
			_show_item_info(weapon_item)
	else:
		# 已有选中物品时
		if selected_is_weapon_slot and selected_storage_type == storage_type:
			# 点击同一个武器槽，取消选中
			_clear_selection()
			_clear_item_info()
		else:
			# 点击不同槽，切换选中
			if not weapon_item.is_empty():
				_select_weapon_slot(storage_type)
				_show_item_info(weapon_item)
			else:
				_clear_selection()
				_clear_item_info()

func _on_weapon_slot_double_clicked(_storage_type: String):
	"""武器槽被双击（暂不支持分离）"""
	pass

func _on_weapon_drag_started(storage_type: String):
	"""开始拖拽武器槽"""
	var container = player_container if storage_type == "player" else other_container
	if not container or not container.has_weapon_slot:
		return
	
	var weapon_item = container.weapon_slot
	if weapon_item.is_empty():
		return
	
	is_dragging = true
	dragging_slot_index = -1
	dragging_storage_type = storage_type
	dragging_is_weapon_slot = true
	
	# 创建拖拽预览
	_create_drag_preview(weapon_item)
	
	# 选中被拖拽的武器槽
	_select_weapon_slot(storage_type)

func _on_weapon_drag_ended(_storage_type: String):
	"""结束拖拽武器槽"""
	if not is_dragging or not dragging_is_weapon_slot:
		return
	
	# 销毁拖拽预览
	_destroy_drag_preview()
	
	# 查找鼠标下的目标格子
	var target_slot = _get_slot_under_mouse()
	
	if not target_slot.is_empty() and target_slot.has("index") and target_slot.has("type"):
		var target_index = target_slot["index"]
		var target_type = target_slot["type"]
		var target_is_weapon = target_slot.get("is_weapon_slot", false)
		
		# 执行移动
		if target_index != dragging_slot_index or target_type != dragging_storage_type or target_is_weapon != dragging_is_weapon_slot:
			_move_weapon_item(dragging_storage_type, target_index, target_type, target_is_weapon)
	
	# 清除拖拽状态
	is_dragging = false
	dragging_slot_index = -1
	dragging_storage_type = ""
	dragging_is_weapon_slot = false
	
	# 清除选中
	_clear_selection()
	_clear_item_info()

func _move_weapon_item(from_type: String, to_index: int, to_type: String, to_is_weapon: bool):
	"""移动武器槽中的物品"""
	var from_container = player_container if from_type == "player" else other_container
	var to_container = player_container if to_type == "player" else other_container
	
	if not from_container or not to_container:
		return
	
	var from_item = from_container.weapon_slot
	
	if to_is_weapon:
		# 目标也是武器槽
		if from_type == to_type:
			# 同一个槽，不做任何操作
			return
		else:
			# 跨容器，交换武器槽
			var to_item = to_container.weapon_slot
			to_container.weapon_slot = from_item.duplicate() if not from_item.is_empty() else {}
			from_container.weapon_slot = to_item.duplicate() if not to_item.is_empty() else {}
			from_container.storage_changed.emit()
			to_container.storage_changed.emit()
	else:
		# 目标是普通槽
		var to_item = to_container.storage[to_index] if to_index < to_container.storage.size() else null
		
		# 检查目标槽的物品是否是武器
		if to_item != null:
			var to_item_config = to_container.get_item_config(to_item.item_id)
			if to_item_config.get("type") == "武器":
				# 目标槽有武器，交换
				# 保留武器的ammo字段
				var to_weapon_copy = to_item.duplicate()
				# 确保目标武器有ammo字段
				if not to_weapon_copy.has("ammo"):
					var to_weapon_config = to_container.get_item_config(to_item.item_id)
					if to_weapon_config.get("subtype") == "远程":
						to_weapon_copy["ammo"] = 0
				
				to_container.storage[to_index] = from_item.duplicate()
				from_container.weapon_slot = to_weapon_copy
			else:
				# 目标槽不是武器，不能放入
				print("武器只能与武器交换或放入空槽")
				return
		else:
			# 目标槽为空，移动武器到普通槽
			# 保留ammo字段
			to_container.storage[to_index] = from_item.duplicate()
			from_container.weapon_slot = {}
		
		from_container.storage_changed.emit()
		to_container.storage_changed.emit()

func _quick_transfer_item(from_index: int, from_type: String, transfer_count: int = -1):
	"""快速转移物品
	transfer_count: -1表示转移全部，否则转移指定数量"""
	var from_container = player_container if from_type == "player" else other_container
	if not from_container:
		return false

	var from_item = from_container.storage[from_index]
	if from_item == null:
		return false

	# 确定目标容器（另一侧）
	var to_type = "other" if from_type == "player" else "player"
	var to_container = player_container if to_type == "player" else other_container
	if not to_container:
		return false

	# 确定转移数量
	var remaining_count = transfer_count if transfer_count != -1 else int(from_item.count)

	# 获取物品配置
	var item_config = from_container.get_item_config(from_item.item_id)
	var max_stack = item_config.get("max_stack", 99)

	# 递归转移，直到转移完毕或没有空间
	while remaining_count > 0:
		var transferred = false

		# 1. 优先查找同物品且未满堆叠的格子
		var target_index = _find_matching_slot_for_quick_transfer(from_item.item_id, to_container, max_stack)
		if target_index != -1:
			# 转移到同物品格子
			var actual_transferred = _transfer_to_matching_slot(from_index, from_type, target_index, to_type, remaining_count, max_stack)
			remaining_count -= actual_transferred
			transferred = true

		if not transferred:
			# 2. 查找空格子
			target_index = _find_empty_slot_for_quick_transfer(to_container)
			if target_index != -1:
				# 转移到空格子
				var actual_transferred = _transfer_to_empty_slot(from_index, from_type, target_index, to_type, remaining_count)
				remaining_count -= actual_transferred
				transferred = true

		if not transferred:
			# 没有合适位置，停止转移
			break

	# 返回是否成功（只要转移了至少1个物品就算成功）
	return transfer_count == -1 or (transfer_count - remaining_count) > 0

func _find_matching_slot_for_quick_transfer(item_id: String, container: StorageContainer, max_stack: int) -> int:
	"""查找可以合并的同物品格子（未满堆叠）"""
	for i in range(container.storage.size()):
		var item = container.storage[i]
		if item != null and item.item_id == item_id:
			var current_count = int(item.count)
			if current_count < max_stack:
				return i
	return -1

func _find_empty_slot_for_quick_transfer(container: StorageContainer) -> int:
	"""查找空格子"""
	for i in range(container.storage.size()):
		if container.storage[i] == null:
			return i
	return -1

func _transfer_to_matching_slot(from_index: int, from_type: String, to_index: int, to_type: String, transfer_count: int, max_stack: int) -> int:
	"""转移到同物品格子（合并），返回实际转移的数量"""
	var from_container = player_container if from_type == "player" else other_container
	var to_container = player_container if to_type == "player" else other_container

	var from_item = from_container.storage[from_index]
	var to_item = to_container.storage[to_index]

	var current_to_count = int(to_item.count)
	var available_space = max_stack - current_to_count

	# 实际转移数量不能超过可用空间
	var actual_transfer = min(transfer_count, available_space)

	# 执行转移
	to_item.count = current_to_count + actual_transfer

	if actual_transfer >= int(from_item.count):
		# 转移全部，清除源格子
		from_container.storage[from_index] = null
	else:
		# 部分转移
		from_item.count = int(from_item.count) - actual_transfer
		from_container.storage[from_index] = from_item

	from_container.storage_changed.emit()
	to_container.storage_changed.emit()
	return actual_transfer

func _transfer_to_empty_slot(from_index: int, from_type: String, to_index: int, to_type: String, transfer_count: int) -> int:
	"""转移到空格子，返回实际转移的数量"""
	var from_container = player_container if from_type == "player" else other_container
	var to_container = player_container if to_type == "player" else other_container

	var from_item = from_container.storage[from_index]

	# 空格子可以容纳任意数量，直接转移
	var actual_transfer = transfer_count

	# 创建新物品数据
	var new_item = from_item.duplicate()
	new_item.count = transfer_count

	# 放置到目标格子
	to_container.storage[to_index] = new_item

	if transfer_count >= int(from_item.count):
		# 转移全部，清除源格子
		from_container.storage[from_index] = null
	else:
		# 部分转移
		from_item.count = int(from_item.count) - transfer_count
		from_container.storage[from_index] = from_item

	from_container.storage_changed.emit()
	to_container.storage_changed.emit()
	return actual_transfer
