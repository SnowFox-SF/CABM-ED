extends Control

signal closed()

var plots: Array = []
var crops_config: Array = []
var bg: TextureRect
var ui_layer: Control
var items_cache: Dictionary = {}
var current_selected_plot_idx: int = -1

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	bg = TextureRect.new()
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_path = "res://assets/images/farming/background.png"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path)
	add_child(bg)
	ui_layer = Control.new()
	ui_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ui_layer)
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "关闭"
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -120
	close_btn.offset_top = 10
	close_btn.offset_right = -20
	close_btn.offset_bottom = 50
	close_btn.pressed.connect(close_farming)
	add_child(close_btn)
	_load_crops_config()
	_ensure_save_data()
	_create_plots()

	var update_timer = Timer.new()
	update_timer.wait_time = 5.0  # 每5秒检查一次
	update_timer.timeout.connect(_refresh_ui)
	add_child(update_timer)
	update_timer.start()
	_refresh_ui()

func open_farming():
	show()

func close_farming():
	hide()
	closed.emit()

func _load_crops_config():
	crops_config = []
	var path = "res://config/crops.json"
	var f = FileAccess.open(path, FileAccess.READ)
	if f:
		var js = JSON.new()
		var txt = f.get_as_text()
		f.close()
		if js.parse(txt) == OK:
			var d = js.data
			if d.has("crops"):
				crops_config = d.crops

func _ensure_save_data():
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	if not sm.save_data.has("farming_system_data"):
		sm.save_data.farming_system_data = {"plots": []}
	# 确保总是有12个地块
	while sm.save_data.farming_system_data.plots.size() < 12:
		sm.save_data.farming_system_data.plots.append(null)

func _get_plot_data(idx: int):
	if not has_node("/root/SaveManager"):
		return null
	var sm = get_node("/root/SaveManager")
	var arr = sm.save_data.farming_system_data.get("plots", [])
	if idx >= 0 and idx < arr.size():
		return arr[idx]
	return null

func _set_plot_data(idx: int, data):
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	var arr = sm.save_data.farming_system_data.get("plots", [])
	if idx >= 0 and idx < arr.size():
		arr[idx] = data
		sm.save_game(sm.current_slot)

func _create_plots():
	for child in ui_layer.get_children():
		child.queue_free()
	plots.clear()
	# 修改为2行4列
	var cols = 6
	var rows = 2
	var container_size = get_viewport().get_visible_rect().size
	var grid_w = min(1200.0, container_size.x * 1.2)  # 增加宽度以适应更多列
	var grid_h = min(420.0, container_size.y * 0.5)
	# 增加start_y的值来整体下移耕地
	var start_x = (container_size.x - grid_w) * 0.5
	var start_y = (container_size.y - grid_h) * 0.5 + 60  # 增加60像素下移
	var cell_w = grid_w / cols
	var cell_h = grid_h / rows
	for r in range(rows):
		for c in range(cols):
			var idx = r * cols + c
			var plot = Control.new()
			plot.set_anchors_preset(Control.PRESET_TOP_LEFT)
			plot.offset_left = start_x + c * cell_w
			plot.offset_top = start_y + r * cell_h
			plot.offset_right = plot.offset_left + cell_w
			plot.offset_bottom = plot.offset_top + cell_h
			var land = TextureRect.new()
			land.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			land.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			land.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			land.offset_left = -cell_w * 0.4
			land.offset_right = cell_w * 0.4
			land.offset_top = -cell_h * 0.4
			land.offset_bottom = cell_h * 0.4
			var land_path = "res://assets/images/farming/farmland.png"
			if ResourceLoader.exists(land_path):
				land.texture = load(land_path)
			plot.add_child(land)
			
			var crop = TextureRect.new()
			crop.name = "CropSprite"
			crop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			crop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			crop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			crop.offset_left = -cell_w * 0.3
			crop.offset_right = cell_w * 0.3
			crop.offset_top = -cell_h * 0.3
			crop.offset_bottom = cell_h * 0.3
			plot.add_child(crop)
			
			var btn = Button.new()
			btn.text = ""
			btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			btn.pressed.connect(_on_plot_pressed.bind(idx))
			btn.modulate = Color(1,1,1,0)
			plot.add_child(btn)
			
			ui_layer.add_child(plot)
			plots.append(plot)

func _on_plot_pressed(idx: int):
	# 清除之前的高光
	_clear_highlight()
	
	# 设置当前选中地块
	current_selected_plot_idx = idx
	
	# 添加高光到当前选中地块
	_highlight_plot(idx)
	
	var data = _get_plot_data(idx)
	if data == null:
		_show_planting_list(idx)
	else:
		_show_planted_options(idx)

# 简单的高亮方法 - 改变颜色
func _highlight_plot(idx: int):
	if idx >= 0 and idx < plots.size():
		var plot = plots[idx]
		var land = plot.get_child(0)  # 第一个子节点是 land
		if land:
			land.modulate = Color(1.4, 1.4, 1.0)  # 轻微变亮和变黄

func _clear_highlight():
	if current_selected_plot_idx >= 0 and current_selected_plot_idx < plots.size():
		var plot = plots[current_selected_plot_idx]
		var land = plot.get_child(0)  # 第一个子节点是 land
		if land:
			land.modulate = Color.WHITE  # 恢复原色

func _refresh_ui():
	for i in range(plots.size()):
		var plot = plots[i]
		var data = _get_plot_data(i)
		var crop_sprite = plot.get_node("CropSprite")
		if data == null:
			crop_sprite.texture = null
			continue
		var crop = _get_crop(data.get("crop_id", ""))
		if crop == null:
			crop_sprite.texture = null
			continue
		var stage = _calculate_stage(crop, int(data.get("planted_at_unix", 0)))
		var base = str(crop.get("stage_base", ""))
		var path = "res://assets/images/farming/" + base + str(stage) + ".png"
		if ResourceLoader.exists(path):
			crop_sprite.texture = load(path)
		else:
			crop_sprite.texture = null

func _get_crop(crop_id: String) -> Dictionary:
	for c in crops_config:
		if c.get("id", "") == crop_id:
			return c
	return {}

func _calculate_stage(crop: Dictionary, planted_at_unix: int) -> int:
	var total = int(crop.get("growth_time_seconds", 0))
	if total <= 0 or planted_at_unix <= 0:
		return 0
	var now = Time.get_unix_time_from_system()
	var elapsed = max(0, now - planted_at_unix)
	
	# 获取阶段数量，默认为3（向后兼容）
	var stage_count = int(crop.get("stage_count", 4))
	
	if elapsed >= total:
		return stage_count - 1  # 最后一个阶段是成熟阶段
	
	var ratio = float(elapsed) / float(total)
	return clamp(int(floor(ratio * float(stage_count))), 0, stage_count - 2)

func _is_mature(crop: Dictionary, planted_at_unix: int) -> bool:
	var total = int(crop.get("growth_time_seconds", 0))
	if total <= 0 or planted_at_unix <= 0:
		return false
	var now = Time.get_unix_time_from_system()
	return now - planted_at_unix >= total

func _show_planting_list(idx: int):
	for node in get_children():
		if node.name == "PlantingPanel" or node.name == "PlotPanel" or node.name == "Overlay":
			node.queue_free()
	var overlay = Button.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.modulate = Color(0,0,0,0.25)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.text = ""
	overlay.pressed.connect(_close_panel.bind(overlay))
	add_child(overlay)
	var panel = PanelContainer.new()
	panel.name = "PlantingPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(540, 360)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1,0.1,0.1,0.9)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.6,0.6,0.8)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	panel.offset_left = -panel.size.x * 0.5
	panel.offset_right = panel.size.x * 0.5
	panel.offset_top = -panel.size.y * 0.5
	panel.offset_bottom = panel.size.y * 0.5
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var title = Label.new()
	title.text = "选择作物"
	vb.add_child(title)
	var grid = GridContainer.new()
	grid.columns = 2
	vb.add_child(grid)
	for c in crops_config:
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(260, 96)
		var card_sb = StyleBoxFlat.new()
		card_sb.bg_color = Color(0,0,0,0.15)
		card_sb.border_color = Color(0.5,0.5,0.6)
		card_sb.border_width_left = 1
		card_sb.border_width_right = 1
		card_sb.border_width_top = 1
		card_sb.border_width_bottom = 1
		card_sb.corner_radius_top_left = 6
		card_sb.corner_radius_top_right = 6
		card_sb.corner_radius_bottom_left = 6
		card_sb.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", card_sb)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var icon = TextureRect.new()
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var ipath = "res://assets/images/farming/" + str(c.get("icon", ""))
		if ResourceLoader.exists(ipath):
			icon.texture = load(ipath)
		icon.custom_minimum_size = Vector2(48,48)
		row.add_child(icon)
		var right = VBoxContainer.new()
		right.add_theme_constant_override("separation", 2)
		right.size_flags_horizontal = Control.SIZE_FILL
		var name_lbl = Label.new()
		name_lbl.text = str(c.get("name", c.get("id", "")))
		right.add_child(name_lbl)
		var secs = int(c.get("growth_time_seconds", 0))
		var h = c.get("harvest", {})
		var hid = str(h.get("item_id", ""))
		var cnt = h.get("count", [1,1])
		var range_txt = str(int(cnt[0])) + "~" + str(int(cnt[1]))
		var grow_lbl = Label.new()
		grow_lbl.text = "生长:" + _format_time_cn(secs)
		right.add_child(grow_lbl)
		var harvest_lbl = Label.new()
		harvest_lbl.text = "收获:" + _get_item_name(hid) + " " + range_txt
		right.add_child(harvest_lbl)
		row.add_child(right)
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var btn = Button.new()
		btn.text = "种植"
		
		# 种植按钮样式 - 蓝色主题
		var plant_style = StyleBoxFlat.new()
		plant_style.bg_color = Color(0.2, 0.4, 0.6)  # 蓝色背景
		plant_style.border_color = Color(0.3, 0.5, 0.8)
		plant_style.border_width_left = 2
		plant_style.border_width_right = 2
		plant_style.border_width_top = 2
		plant_style.border_width_bottom = 2
		plant_style.corner_radius_top_left = 4
		plant_style.corner_radius_top_right = 4
		plant_style.corner_radius_bottom_left = 4
		plant_style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", plant_style)
		
		# 悬停状态
		var plant_hover_style = plant_style.duplicate()
		plant_hover_style.bg_color = Color(0.3, 0.5, 0.7)
		btn.add_theme_stylebox_override("hover", plant_hover_style)
		
		# 按下状态
		var plant_pressed_style = plant_style.duplicate()
		plant_pressed_style.bg_color = Color(0.1, 0.3, 0.5)
		btn.add_theme_stylebox_override("pressed", plant_pressed_style)
		
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
		
		btn.pressed.connect(_plant_crop.bind(idx, str(c.get("id", ""))))
		row.add_child(btn)
		grid.add_child(card)
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_panel.bind(panel))
	vb.add_child(close_btn)

func _close_panel(panel: Control):
	_clear_highlight()
	current_selected_plot_idx = -1
	
	if is_instance_valid(panel):
		panel.queue_free()
	for node in get_children():
		if node.name == "PlantingPanel" or node.name == "PlotPanel":
			node.queue_free()
	for node in get_children():
		if node.name == "Overlay":
			node.queue_free()

func _plant_crop(idx: int, crop_id: String):
	var data = {"crop_id": crop_id, "planted_at_unix": Time.get_unix_time_from_system()}
	_set_plot_data(idx, data)
	_refresh_ui()
	_clear_highlight()
	current_selected_plot_idx = -1
	
	for node in get_children():
		if node.name == "PlantingPanel":
			node.queue_free()
	for node in get_children():
		if node.name == "Overlay":
			node.queue_free()

func _show_planted_options(idx: int):
	for node in get_children():
		if node.name == "PlantingPanel" or node.name == "PlotPanel" or node.name == "Overlay":
			node.queue_free()
	var data = _get_plot_data(idx)
	var crop = _get_crop(str(data.get("crop_id", "")))
	var overlay = Button.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.modulate = Color(0,0,0,0.25)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.text = ""
	overlay.pressed.connect(_close_panel.bind(overlay))
	add_child(overlay)
	var panel = PanelContainer.new()
	panel.name = "PlotPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(150, 100)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1,0.1,0.1,0.9)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.6,0.6,0.8)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	panel.offset_left = -panel.size.x * 0.5
	panel.offset_right = panel.size.x * 0.5
	panel.offset_top = -panel.size.y * 0.5
	panel.offset_bottom = panel.size.y * 0.5
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var crop_name = str(crop.get("name", crop.get("id", "")))
	var secs_total = int(crop.get("growth_time_seconds", 0))
	var planted = int(data.get("planted_at_unix", 0))
	var now = Time.get_unix_time_from_system()
	var remain = max(0, secs_total - (now - planted))
	var name_lbl = Label.new()
	name_lbl.text = crop_name
	vb.add_child(name_lbl)
	var remain_lbl = Label.new()
	var mature = _is_mature(crop, planted)
	if mature:
		remain_lbl.text = "可收获"
	else:
		remain_lbl.text = "剩余:" + _format_time_cn(remain)
	vb.add_child(remain_lbl)
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	if mature:
		var harvest_btn = Button.new()
		harvest_btn.text = "收获"
		
		# 收获按钮样式 - 绿色主题
		var harvest_style = StyleBoxFlat.new()
		harvest_style.bg_color = Color(0.2, 0.6, 0.2)  # 绿色背景
		harvest_style.border_color = Color(0.3, 0.8, 0.3)
		harvest_style.border_width_left = 2
		harvest_style.border_width_right = 2
		harvest_style.border_width_top = 2
		harvest_style.border_width_bottom = 2
		harvest_style.corner_radius_top_left = 4
		harvest_style.corner_radius_top_right = 4
		harvest_style.corner_radius_bottom_left = 4
		harvest_style.corner_radius_bottom_right = 4
		harvest_btn.add_theme_stylebox_override("normal", harvest_style)
		
		# 悬停状态
		var harvest_hover_style = harvest_style.duplicate()
		harvest_hover_style.bg_color = Color(0.3, 0.7, 0.3)
		harvest_btn.add_theme_stylebox_override("hover", harvest_hover_style)
		
		# 按下状态
		var harvest_pressed_style = harvest_style.duplicate()
		harvest_pressed_style.bg_color = Color(0.1, 0.5, 0.1)
		harvest_btn.add_theme_stylebox_override("pressed", harvest_pressed_style)
		
		harvest_btn.add_theme_color_override("font_color", Color(1, 1, 1))
		harvest_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		harvest_btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
		
		harvest_btn.pressed.connect(_harvest.bind(idx, panel))
		hb.add_child(harvest_btn)
	else:
		var remove_btn = Button.new()
		remove_btn.text = "移除"
		
		# 移除按钮样式 - 红色主题
		var remove_style = StyleBoxFlat.new()
		remove_style.bg_color = Color(0.6, 0.2, 0.2)  # 红色背景
		remove_style.border_color = Color(0.8, 0.3, 0.3)
		remove_style.border_width_left = 2
		remove_style.border_width_right = 2
		remove_style.border_width_top = 2
		remove_style.border_width_bottom = 2
		remove_style.corner_radius_top_left = 4
		remove_style.corner_radius_top_right = 4
		remove_style.corner_radius_bottom_left = 4
		remove_style.corner_radius_bottom_right = 4
		remove_btn.add_theme_stylebox_override("normal", remove_style)
		
		# 悬停状态
		var remove_hover_style = remove_style.duplicate()
		remove_hover_style.bg_color = Color(0.7, 0.3, 0.3)
		remove_btn.add_theme_stylebox_override("hover", remove_hover_style)
		
		# 按下状态
		var remove_pressed_style = remove_style.duplicate()
		remove_pressed_style.bg_color = Color(0.5, 0.1, 0.1)
		remove_btn.add_theme_stylebox_override("pressed", remove_pressed_style)
		
		remove_btn.add_theme_color_override("font_color", Color(1, 1, 1))
		remove_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		remove_btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
		
		remove_btn.pressed.connect(_remove.bind(idx, panel))
		hb.add_child(remove_btn)
	vb.add_child(hb)

func _get_item_config(item_id: String) -> Dictionary:
	if has_node("/root/InventoryManager"):
		var inv = get_node("/root/InventoryManager")
		if inv.has_method("get_item_config"):
			return inv.get_item_config(item_id)
	# 备用：本地缓存从 items.json 加载
	if items_cache.is_empty():
		var path = "res://config/items.json"
		if ResourceLoader.exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			if f:
				var js = JSON.new()
				var txt = f.get_as_text()
				f.close()
				if js.parse(txt) == OK:
					items_cache = js.data.get("items", {})
	return items_cache.get(item_id, {})

func _get_item_name(item_id: String) -> String:
	var cfg = _get_item_config(item_id)
	return str(cfg.get("name", item_id))

func _get_item_icon_path(item_id: String) -> String:
	var cfg = _get_item_config(item_id)
	var icon = str(cfg.get("icon", ""))
	if icon == "":
		return ""
	return "res://assets/images/items/" + icon

func _format_time_cn(secs: int) -> String:
	var s = max(0, int(secs))
	var h = s / 3600
	var m = (s % 3600) / 60
	var ss = s % 60
	var parts: Array = []
	if h > 0:
		parts.append(str(h) + "时")
	if m > 0 or (h > 0 and ss == 0):
		parts.append(str(m) + "分")
	parts.append(str(ss) + "秒")
	return "".join(parts)

func _remove(idx: int, panel: Control):
	_set_plot_data(idx, null)
	_refresh_ui()
	_clear_highlight()
	current_selected_plot_idx = -1
	if is_instance_valid(panel):
		panel.queue_free()
	for node in get_children():
		if node.name == "Overlay":
			node.queue_free()

func _harvest(idx: int, panel: Control):
	var data = _get_plot_data(idx)
	var crop = _get_crop(str(data.get("crop_id", "")))
	var h = crop.get("harvest", {})
	var hid = str(h.get("item_id", ""))
	var cnt = h.get("count", [1,1])
	var minc = int(cnt[0])
	var maxc = int(cnt[1])
	var give = randi_range(minc, maxc)
	if has_node("/root/InventoryManager"):
		var inv = get_node("/root/InventoryManager")
		inv.add_item_to_inventory(hid, give)
	# 播放收获动画
	var from_pos = Vector2()
	if idx >= 0 and idx < plots.size():
		var plot: Control = plots[idx]
		from_pos = plot.global_position + plot.size * 0.5
	_play_harvest_anim(hid, give, from_pos)
	_set_plot_data(idx, null)
	_refresh_ui()
	_clear_highlight()
	current_selected_plot_idx = -1
	if is_instance_valid(panel):
		panel.queue_free()
	for node in get_children():
		if node.name == "Overlay":
			node.queue_free()

func _get_top_right_target() -> Vector2:
	var dest = Vector2(get_viewport().get_visible_rect().size.x - 24, 24)
	if has_node("CloseButton"):
		var b: Control = get_node("CloseButton")
		dest = b.global_position + b.size * 0.5
	return dest

func _play_harvest_anim(item_id: String, count: int, from_pos: Vector2):
	var dest = _get_top_right_target()
	var ipath = _get_item_icon_path(item_id)
	for i in range(count):
		var icon = TextureRect.new()
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon.size = Vector2(128, 128)
		icon.global_position = from_pos - icon.size * 0.5 + Vector2(randf()*80.0 - 40.0, randf()*80.0 - 40.0)
		if ipath != "" and ResourceLoader.exists(ipath):
			icon.texture = load(ipath)
		add_child(icon)
		var tween = create_tween()
		var mid = icon.global_position + Vector2(0, 20 + randf()*20.0)
		tween.tween_property(icon, "global_position", mid, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(icon, "global_position", dest - icon.size * 0.5, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(icon, "modulate:a", 0.0, 0.8).set_delay(0.4)
		tween.parallel().tween_property(icon, "scale", Vector2(0.5, 0.5), 0.8)
		tween.finished.connect(func(): icon.queue_free())
