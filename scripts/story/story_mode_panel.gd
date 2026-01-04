extends Control

# 故事模式面板
# 管理故事列表和树状图显示

# 预加载面板
const StoryDialogPanel = preload("res://scenes/story_dialog_panel.tscn")
const StoryCreationPanel = preload("res://scenes/story_creation_panel.tscn")

@onready var close_button: Button = $Panel/VBoxContainer/TitleBar/CloseButton
@onready var plus_button: Button = $Panel/VBoxContainer/HSplitContainer/StoryListPanel/VBoxContainer/ScrollContainer/StoryListContainer/PlusButton
@onready var story_list_container: VBoxContainer = $Panel/VBoxContainer/HSplitContainer/StoryListPanel/VBoxContainer/ScrollContainer/StoryListContainer
@onready var tree_view_container: Control = $Panel/VBoxContainer/HSplitContainer/TreeViewPanel/VBoxContainer/TreeViewContainer

# 操作栏相关
@onready var operation_bar: HBoxContainer = $Panel/VBoxContainer/HSplitContainer/TreeViewPanel/VBoxContainer/OperationBar
@onready var node_text_label: Label = $Panel/VBoxContainer/HSplitContainer/TreeViewPanel/VBoxContainer/OperationBar/NodeTextLabel
@onready var start_from_button: Button = $Panel/VBoxContainer/HSplitContainer/TreeViewPanel/VBoxContainer/OperationBar/StartFromButton

# 故事数据
var stories_data: Dictionary = {}
var current_story_id: String = ""
var selected_story_id: String = ""
var story_buttons: Array[Button] = []

# 选中节点相关
var selected_node_id: String = ""

# 故事对话面板相关
var story_dialog_panel: Control = null

# 故事创建面板相关
var story_creation_panel: Control = null

# 平滑移动相关
var view_tween: Tween = null

# 树状图相关
var tree_nodes: Array = []
var node_positions: Dictionary = {}
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0  # 拖拽阈值，鼠标需要移动5像素才开始拖拽

# 触摸缩放相关
var touch_zoom_active: bool = false
var initial_touch_distance: float = 0.0
var initial_zoom_level: float = 1.0
var touch_positions: Dictionary = {}  # 存储触摸点位置

const NODE_SIZE = Vector2(200, 60)
const NODE_SPACING_X = 250
const NODE_SPACING_Y = 80

signal story_mode_closed

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	plus_button.pressed.connect(_on_plus_button_pressed)
	start_from_button.pressed.connect(_on_start_from_pressed)
	_create_tween()
	_load_stories()
	_refresh_story_list()

func _input(event):
	"""处理输入事件，用于树状图的缩放和移动"""
	if not visible:
		return

	# 检查是否在树状图区域内（用于鼠标事件）
	var tree_view_rect = Rect2(tree_view_container.global_position, tree_view_container.size)
	var mouse_pos = get_viewport().get_mouse_position()

	# 处理触摸事件（移动设备）
	if event is InputEventScreenTouch:
		_handle_touch_event(event)
		return
	elif event is InputEventScreenDrag:
		_handle_drag_event(event)
		return

	# 处理鼠标事件
	if not tree_view_rect.has_point(mouse_pos):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始可能的拖拽
				is_dragging = false
				drag_start_pos = get_viewport().get_mouse_position()
				last_mouse_pos = drag_start_pos
			else:
				# 结束拖拽
				is_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_tree_view(0.1, mouse_pos)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_tree_view(-0.1, mouse_pos)

	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			var current_mouse_pos = get_viewport().get_mouse_position()
			if not is_dragging:
				# 检查是否超过拖拽阈值
				var distance = (current_mouse_pos - drag_start_pos).length()
				if distance > drag_threshold:
					is_dragging = true
					last_mouse_pos = current_mouse_pos
			else:
				# 执行拖拽
				var delta = current_mouse_pos - last_mouse_pos
				pan_offset += delta
				last_mouse_pos = current_mouse_pos
				_redraw_tree()

func _zoom_tree_view(delta_zoom: float, zoom_center: Vector2 = Vector2.ZERO):
	"""缩放树状图"""
	var old_zoom = zoom_level
	zoom_level = clamp(zoom_level + delta_zoom, 0.1, 3.0)

	# 如果提供了缩放中心点，调整偏移量使缩放基于该点
	if zoom_center != Vector2.ZERO:
		var container_rect = Rect2(tree_view_container.global_position, tree_view_container.size)
		if container_rect.has_point(zoom_center):
			# 将屏幕坐标转换为相对于容器的本地坐标
			var local_center = zoom_center - tree_view_container.global_position
			# 计算该点对应的世界坐标（在旧缩放级别下）
			var world_center = (local_center - pan_offset) / old_zoom
			# 重新计算偏移量，使该世界点在新的缩放级别下仍然在相同屏幕位置
			pan_offset = local_center - world_center * zoom_level

	_apply_transform()

func show_panel():
	"""显示故事模式面板"""
	visible = true
	_refresh_story_list()

func hide_panel():
	"""隐藏故事模式面板"""
	visible = false
	# 停止所有动画
	if view_tween and view_tween.is_valid():
		view_tween.kill()
		view_tween = null

func _on_close_pressed():
	"""关闭按钮点击"""
	hide_panel()
	story_mode_closed.emit()


func _create_tween():
	"""创建Tween用于平滑移动"""
	# 只在需要时创建Tween，避免空Tween被启动
	pass

func _clear_node_selection():
	"""清除节点选中状态"""
	selected_node_id = ""
	if start_from_button:
		start_from_button.visible = false
	if node_text_label:
		node_text_label.text = ""
		node_text_label.visible = false
	_redraw_tree()

	# 停止当前的视图动画
	if view_tween and view_tween.is_valid():
		view_tween.kill()
		view_tween = null

func _get_all_parent_nodes(node_id: String, nodes: Dictionary) -> Array:
	"""获取指定节点的所有父节点ID"""
	var parent_nodes = []

	# 遍历所有节点，查找包含此节点作为子节点的节点
	for potential_parent_id in nodes:
		var node_data = nodes[potential_parent_id]
		var child_nodes = node_data.get("child_nodes", [])
		if node_id in child_nodes:
			parent_nodes.append(potential_parent_id)
			# 递归获取父节点的父节点
			parent_nodes.append_array(_get_all_parent_nodes(potential_parent_id, nodes))

	return parent_nodes

func _is_node_highlighted(node_id: String) -> bool:
	"""判断节点是否需要高亮"""
	if selected_node_id.is_empty():
		return false

	# 如果是选中的节点
	if node_id == selected_node_id:
		return true

	# 如果是选中节点的所有父节点
	var story_data = stories_data.get(current_story_id, {})
	var nodes = story_data.get("nodes", {})
	var parent_nodes = _get_all_parent_nodes(selected_node_id, nodes)
	return node_id in parent_nodes

func _is_connection_highlighted(start_node_id: String, end_node_id: String) -> bool:
	"""判断连线是否需要高亮"""
	if selected_node_id.is_empty():
		return false

	# 如果连线的终点是选中节点或其父节点之一
	if _is_node_highlighted(end_node_id):
		# 并且连线的起点也是选中节点或其父节点之一
		if _is_node_highlighted(start_node_id):
			return true

	return false

func _calculate_target_view_position(node_id: String) -> Vector2:
	"""计算将指定节点置于视图中心所需的偏移量"""
	if not node_positions.has(node_id):
		return pan_offset

	var container_size = tree_view_container.size
	var node_pos = node_positions[node_id] + NODE_SIZE / 2  # 节点中心点

	# 计算目标位置：节点中心点位于容器中心
	var target_world_pos = node_pos
	var target_pan_offset = container_size / 2 - target_world_pos * zoom_level

	return target_pan_offset

func _smooth_move_to_node(node_id: String):
	"""平滑移动到指定节点"""
	if not node_positions.has(node_id):
		return

	var target_offset = _calculate_target_view_position(node_id)
	var current_offset = pan_offset
	var distance = (target_offset - current_offset).length()

	# 如果距离太小，不需要动画
	if distance < 1.0:
		return

	# 根据距离计算移动时长（距离越远，时间越长）
	var move_duration = clamp(distance / 500.0, 0.3, 1.5)  # 0.3-1.5秒

	# 停止当前动画
	if view_tween and view_tween.is_valid():
		view_tween.kill()
		view_tween = null

	# 创建新的平滑移动动画
	view_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if view_tween == null:
		print("Failed to create tween")
		return

	# 使用tween_method来平滑地更新pan_offset
	var start_offset = current_offset
	var tween_result = view_tween.tween_method(_update_pan_offset, start_offset, target_offset, move_duration)
	if tween_result == null:
		print("Failed to add tween method")
		return

	# 连接完成信号
	view_tween.finished.connect(_on_view_tween_finished)

func _update_pan_offset(new_offset: Vector2):
	"""更新pan_offset并重新应用变换"""
	pan_offset = new_offset
	_apply_transform()

func _on_view_tween_finished():
	"""视图Tween动画完成回调"""
	_apply_transform()
	if view_tween:
		view_tween = null

func _load_stories():
	"""加载所有故事文件"""
	stories_data.clear()

	# 确保故事目录存在
	var user_dir = DirAccess.open("user://")
	if not user_dir.dir_exists("story"):
		user_dir.make_dir("story")

	var story_dir = DirAccess.open("user://story")
	if not story_dir:
		print("无法打开故事目录: user://story")
		return

	story_dir.list_dir_begin()
	var file_name = story_dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var story_data = _load_story_file(file_name)
			if story_data and story_data.has("story_id"):
				stories_data[story_data.story_id] = story_data
		file_name = story_dir.get_next()

	print("已加载 %d 个故事" % stories_data.size())

func _load_story_file(file_name: String) -> Dictionary:
	"""加载单个故事文件"""
	var file_path = "user://story/" + file_name

	if not FileAccess.file_exists(file_path):
		print("故事文件不存在: ", file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("无法打开故事文件: ", file_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("JSON解析错误: ", file_path)
		return {}

	return json.data

func _refresh_story_list():
	"""刷新故事列表"""
	# 清空现有按钮（除了"+"按钮）
	for button in story_buttons:
		if button != plus_button:
			button.queue_free()
	story_buttons.clear()

	# "+"按钮已经在tscn中，不需要重新添加，只需要添加到数组中
	story_buttons.append(plus_button)

	# 创建故事按钮
	for story_id in stories_data:
		var story_data = stories_data[story_id]
		var button = Button.new()
		var is_selected = (story_id == selected_story_id)

		button.size_flags_horizontal = Control.SIZE_FILL

		# 设置按钮文本 - 使用RichTextLabel来支持BBCode
		var title = story_data.get("story_title", "未知标题")
		var summary = story_data.get("story_summary", "")
		var last_played = story_data.get("last_played_at", "")

		# 清空按钮默认文本
		button.text = ""

		# 使用RichTextLabel来支持BBCode格式
		var rich_text = RichTextLabel.new()
		rich_text.bbcode_enabled = true
		rich_text.fit_content = true
		rich_text.size_flags_horizontal = Control.SIZE_FILL
		rich_text.size_flags_vertical = Control.SIZE_FILL
		rich_text.scroll_active = false
		rich_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		# 设置RichTextLabel填充整个按钮
		rich_text.anchor_right = 1.0
		rich_text.anchor_bottom = 1.0
		rich_text.offset_left = 8
		rich_text.offset_top = 4
		rich_text.offset_right = -8
		rich_text.offset_bottom = -4
		rich_text.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不拦截鼠标事件，让按钮能接收点击

		# 设置字体大小和颜色
		rich_text.add_theme_font_size_override("normal_font_size", 14)
		rich_text.add_theme_font_size_override("bold_font_size", 16)
		rich_text.add_theme_font_size_override("italics_font_size", 12)
		rich_text.add_theme_color_override("default_color", Color(1.0, 1.0, 1.0, 1.0))

		var button_text = ""
		if is_selected:
			# 选中时显示完整文本
			button_text = "[b]%s[/b]\n%s\n[i]最后游玩: %s[/i]" % [title, summary, last_played]
		else:
			# 默认状态下只截断故事内容，标题和最后游玩时间保持完整
			var safe_title = title if title else ""
			var safe_summary = summary if summary else ""
			var safe_last_played = last_played if last_played else ""
			var truncated_summary = _truncate_text(safe_summary, 40)
			button_text = "[b]%s[/b]\n%s\n[i]最后游玩: %s[/i]" % [safe_title, truncated_summary, safe_last_played]
		rich_text.text = button_text

		button.add_child(rich_text)
		button.add_theme_font_size_override("font_size", 14)

		# 设置按钮对齐
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP

		# 根据选中状态设置按钮样式
		var style_normal = StyleBoxFlat.new()
		if is_selected:
			style_normal.bg_color = Color(0.5, 0.7, 1.0, 0.9)  # 选中时更亮的背景
			style_normal.border_color = Color(1.0, 1.0, 0.5, 1.0)  # 选中时金色边框
		else:
			style_normal.bg_color = Color(0.3, 0.5, 0.9, 0.8)
			style_normal.border_color = Color(0.8, 0.8, 1.0, 1.0)
		style_normal.border_width_left = 1
		style_normal.border_width_right = 1
		style_normal.border_width_top = 1
		style_normal.border_width_bottom = 1
		style_normal.shadow_color = Color(0.0, 0.0, 0.0, 0.2)
		style_normal.shadow_size = 2
		style_normal.corner_radius_top_left = 6
		style_normal.corner_radius_top_right = 6
		style_normal.corner_radius_bottom_left = 6
		style_normal.corner_radius_bottom_right = 6

		var style_hover = StyleBoxFlat.new()
		if is_selected:
			style_hover.bg_color = Color(0.6, 0.8, 1.0, 1.0)  # 选中时悬停更亮
			style_hover.border_color = Color(1.0, 1.0, 0.8, 1.0)
		else:
			style_hover.bg_color = Color(0.4, 0.6, 1.0, 0.9)
			style_hover.border_color = Color(1.0, 1.0, 1.0, 1.0)
		style_hover.border_width_left = 1
		style_hover.border_width_right = 1
		style_hover.border_width_top = 1
		style_hover.border_width_bottom = 1
		style_hover.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
		style_hover.shadow_size = 3
		style_hover.corner_radius_top_left = 6
		style_hover.corner_radius_top_right = 6
		style_hover.corner_radius_bottom_left = 6
		style_hover.corner_radius_bottom_right = 6

		var style_pressed = StyleBoxFlat.new()
		style_pressed.bg_color = Color(0.2, 0.4, 0.8, 0.9)
		style_pressed.border_color = Color(0.6, 0.6, 1.0, 1.0)
		style_pressed.border_width_left = 1
		style_pressed.border_width_right = 1
		style_pressed.border_width_top = 1
		style_pressed.border_width_bottom = 1
		style_pressed.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
		style_pressed.shadow_size = 1
		style_pressed.corner_radius_top_left = 6
		style_pressed.corner_radius_top_right = 6
		style_pressed.corner_radius_bottom_left = 6
		style_pressed.corner_radius_bottom_right = 6

		button.add_theme_stylebox_override("normal", style_normal)
		button.add_theme_stylebox_override("hover", style_hover)
		button.add_theme_stylebox_override("pressed", style_pressed)
		button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 1.0, 1.0))

		# 先添加按钮到容器，让其正确计算尺寸
		story_list_container.add_child(button)
		story_buttons.append(button)

		# 然后根据是否选中设置高度
		if is_selected:
			# 选中时，让RichTextLabel计算内容高度，然后设置按钮的最小高度
			rich_text.fit_content = true
			# 延迟一帧来获取正确的尺寸
			call_deferred("_adjust_button_height", button, rich_text)
		else:
			button.custom_minimum_size = Vector2(0, 80)  # 默认固定高度

		# 连接信号
		button.pressed.connect(_on_story_selected.bind(story_id))

func _adjust_button_height(button: Button, rich_text: RichTextLabel):
	"""调整按钮高度以适应内容"""
	# 强制更新RichTextLabel的布局
	rich_text.fit_content = true
	rich_text.queue_redraw()
	
	# 获取RichTextLabel的实际内容高度
	var content_height = rich_text.get_content_height()
	# 添加一些内边距
	var padding = 16
	var final_height = max(80, content_height + padding)  # 确保至少有80像素高
	
	button.custom_minimum_size = Vector2(0, final_height)
	
	# 重新设置size_flags_vertical以确保按钮可以扩展
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _on_plus_button_pressed():
	"""+按钮点击处理"""
	_create_story_creation_panel()

func _on_story_selected(story_id: String):
	"""故事被选中"""
	# 处理故事选中状态切换
	var was_selected = (selected_story_id == story_id)

	if was_selected:
		# 再次点击已选中的故事，取消选中
		selected_story_id = ""
	else:
		selected_story_id = story_id

	current_story_id = story_id
	_clear_node_selection()  # 清除之前的选中状态

	# 切换故事时重置视角和缩放
	zoom_level = 1.0
	pan_offset = Vector2.ZERO

	_refresh_story_list()  # 刷新故事列表显示
	_render_story_tree()

func _render_story_tree():
	"""渲染故事树状图"""
	if not current_story_id or not stories_data.has(current_story_id):
		return

	var story_data = stories_data[current_story_id]
	if not story_data.has("nodes") or not story_data.has("root_node"):
		return

	tree_nodes.clear()
	node_positions.clear()

	# 获取容器尺寸
	var container_size = tree_view_container.size
	var start_pos = Vector2(container_size.x * 0.1, container_size.y * 0.5)  # 从容器左侧10%位置开始，垂直居中

	# 计算节点位置
	_calculate_node_positions(story_data.root_node, story_data.nodes, start_pos)

	# 重绘树状图
	_redraw_tree()

func _calculate_node_positions(node_id: String, nodes: Dictionary, node_position: Vector2, depth: int = 0):
	"""计算节点位置"""
	if not nodes.has(node_id):
		return

	var node_data = nodes[node_id]
	tree_nodes.append({"id": node_id, "data": node_data, "depth": depth})

	# 设置节点位置
	node_positions[node_id] = node_position

	# 处理子节点 - 使用简单均匀分布
	var child_nodes = node_data.get("child_nodes", [])
	if child_nodes.size() > 0:
		# 计算需要的垂直空间：每个子节点至少需要 NODE_SPACING_Y 的间距
		var total_height = child_nodes.size() * NODE_SPACING_Y
		var start_y = node_position.y - total_height / 2.0 + NODE_SPACING_Y / 2.0

		for i in range(child_nodes.size()):
			var child_id = child_nodes[i]
			var child_y = start_y + i * NODE_SPACING_Y
			_calculate_node_positions(child_id, nodes, Vector2(node_position.x + NODE_SPACING_X, child_y), depth + 1)

func _redraw_tree():
	"""重绘树状图"""
	# 清空现有节点
	for child in tree_view_container.get_children():
		child.queue_free()

	if tree_nodes.is_empty():
		return

	# 绘制连线
	_draw_connections()

	# 绘制节点
	_draw_nodes()

	# 应用缩放和移动变换
	_apply_transform()

func _draw_connections():
	"""绘制节点间的连线"""
	for node_info in tree_nodes:
		var node_id = node_info.id
		var node_data = node_info.data
		var start_pos = node_positions[node_id] + NODE_SIZE / 2

		var child_nodes = node_data.get("child_nodes", [])
		for child_id in child_nodes:
			if node_positions.has(child_id):
				var end_pos = node_positions[child_id] + NODE_SIZE / 2
				_draw_line(start_pos, end_pos, node_id, child_id)

func _draw_line(start_pos: Vector2, end_pos: Vector2, start_node_id: String = "", end_node_id: String = ""):
	"""绘制一条连线"""
	var line = Line2D.new()
	line.points = [start_pos, end_pos]
	line.width = 3.0  # 稍微加粗

	# 根据是否高亮设置颜色
	var is_highlighted = _is_connection_highlighted(start_node_id, end_node_id)
	if is_highlighted:
		line.default_color = Color(1.0, 1.0, 0.0, 0.9)  # 黄色高亮
	else:
		line.default_color = Color(0.9, 0.9, 1.0, 0.9)  # 普通颜色

	line.set_meta("original_points", [start_pos, end_pos])  # 保存原始点
	tree_view_container.add_child(line)

func _draw_nodes():
	"""绘制节点"""
	for node_info in tree_nodes:
		var node_id = node_info.id
		var node_data = node_info.data
		var node_position = node_positions[node_id]

		var node_panel = Panel.new()
		node_panel.custom_minimum_size = NODE_SIZE
		node_panel.position = node_position
		node_panel.set_meta("original_position", node_position)

		var label = Label.new()
		var full_text = node_data.get("display_text", "")

		# 设置Label属性
		label.text = full_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER  # 水平居中
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER  # 垂直居中
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_FILL
		label.size_flags_vertical = Control.SIZE_FILL
		label.clip_text = false
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.max_lines_visible = 3  # 限制最多3行

		# 设置Label填充整个Panel
		label.anchor_left = 0
		label.anchor_top = 0
		label.anchor_right = 1
		label.anchor_bottom = 1
		label.offset_left = 5
		label.offset_top = 5
		label.offset_right = -5
		label.offset_bottom = -5

		label.add_theme_font_size_override("font_size", 14)

		node_panel.add_child(label)
		
		# 设置样式 - 根据是否高亮使用不同颜色
		var style_box = StyleBoxFlat.new()
		var is_highlighted = _is_node_highlighted(node_id)
		if is_highlighted:
			style_box.bg_color = Color(1.0, 1.0, 0.0, 0.8)  # 黄色高亮背景
			style_box.border_color = Color(1.0, 0.8, 0.0, 1.0)  # 金色边框
		else:
			style_box.bg_color = Color(0.4, 0.6, 1.0, 0.6)  # 普通蓝色背景
			style_box.border_color = Color(1.0, 1.0, 1.0, 1.0)  # 白色边框
		style_box.border_width_left = 2
		style_box.border_width_right = 2
		style_box.border_width_top = 2
		style_box.border_width_bottom = 2
		style_box.shadow_color = Color(0.0, 0.0, 0.0, 0.3)  # 添加阴影
		style_box.shadow_size = 4
		style_box.corner_radius_top_left = 8
		style_box.corner_radius_top_right = 8
		style_box.corner_radius_bottom_left = 8
		style_box.corner_radius_bottom_right = 8
		node_panel.add_theme_stylebox_override("panel", style_box)

		# 设置标签颜色
		if is_highlighted:
			label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.0, 1.0))  # 高亮时深黄色文字
		else:
			label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))  # 普通时深色文字

		# 添加点击事件（暂时不显示详细内容）
		node_panel.gui_input.connect(_on_node_clicked.bind(node_id))

		tree_view_container.add_child(node_panel)

func _apply_transform():
	"""应用缩放和移动变换"""
	# 直接使用pan_offset和zoom_level进行变换
	for child in tree_view_container.get_children():
		if child is Line2D:
			# 处理连线
			var original_points = child.get_meta("original_points", child.points)
			var transformed_points = []
			for point in original_points:
				var transformed_point = point * zoom_level + pan_offset
				transformed_points.append(transformed_point)
			child.points = transformed_points
		else:
			# 处理节点
			var original_pos = child.get_meta("original_position", child.position)
			child.position = original_pos * zoom_level + pan_offset
			child.scale = Vector2(zoom_level, zoom_level)

func _handle_touch_event(event: InputEventScreenTouch):
	"""处理触摸事件"""
	var touch_index = event.index

	if event.pressed:
		# 记录触摸点位置
		touch_positions[touch_index] = event.position

		# 如果有两个触摸点，开始缩放
		if touch_positions.size() == 2:
			touch_zoom_active = true
			var touch_points = touch_positions.values()
			initial_touch_distance = touch_points[0].distance_to(touch_points[1])
			initial_zoom_level = zoom_level
	else:
		# 移除触摸点
		touch_positions.erase(touch_index)

		# 如果少于两个触摸点，结束缩放
		if touch_positions.size() < 2:
			touch_zoom_active = false

func _handle_drag_event(event: InputEventScreenDrag):
	"""处理拖拽事件"""
	var touch_index = event.index

	# 更新触摸点位置
	touch_positions[touch_index] = event.position

	# 只有当前正好有两个触摸点时才进行缩放
	if touch_positions.size() == 2:
		var touch_points = touch_positions.values()
		var touch_center = (touch_points[0] + touch_points[1]) / 2.0

		# 确保缩放模式已激活
		if not touch_zoom_active:
			touch_zoom_active = true
			initial_touch_distance = touch_points[0].distance_to(touch_points[1])
			initial_zoom_level = zoom_level

		# 计算缩放
		var current_distance = touch_points[0].distance_to(touch_points[1])

		if initial_touch_distance > 0:
			var old_zoom = zoom_level
			var zoom_factor = current_distance / initial_touch_distance
			zoom_level = clamp(initial_zoom_level * zoom_factor, 0.1, 3.0)

			# 调整偏移量使缩放基于触摸中心点
			var container_rect = Rect2(tree_view_container.global_position, tree_view_container.size)
			if container_rect.has_point(touch_center):
				var local_center = touch_center - tree_view_container.global_position
				# 计算触摸中心对应的世界坐标（在旧缩放级别下）
				var world_center = (local_center - pan_offset) / old_zoom
				# 重新计算偏移量，使该世界点在新的缩放级别下仍然在相同屏幕位置
				pan_offset = local_center - world_center * zoom_level

			_apply_transform()
	elif touch_positions.size() == 1:
		# 单指拖拽（移动视图）- 确保缩放模式未激活
		touch_zoom_active = false
		var delta = event.relative
		pan_offset += delta
		_redraw_tree()

func _on_node_clicked(event: InputEvent, node_id: String):
	"""节点点击事件处理"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 处理节点选中/取消选中
		if selected_node_id == node_id:
			# 再次点击已选中的节点，取消选中
			_clear_node_selection()
		else:
			# 选中新节点
			selected_node_id = node_id
			start_from_button.visible = true

			# 在操作栏显示完整节点文本
			if node_text_label and current_story_id and stories_data.has(current_story_id):
				var story_data = stories_data[current_story_id]
				var nodes = story_data.get("nodes", {})
				if nodes.has(node_id):
					var node_data = nodes[node_id]
					var full_text = node_data.get("full_text", node_data.get("display_text", ""))
					node_text_label.text = full_text
					node_text_label.visible = true

			_redraw_tree()

			# 平滑移动到选中节点
			_smooth_move_to_node(node_id)

		print("节点被点击: ", node_id, "(取消选中)" if selected_node_id.is_empty() else "(选中)")

func _on_start_from_pressed():
	"""从此开始按钮点击处理"""
	if selected_node_id.is_empty() or current_story_id.is_empty():
		return

	print("从节点开始故事: ", selected_node_id)

	# 创建故事对话面板
	_create_story_dialog_panel()

func _create_story_creation_panel():
	"""创建故事创建面板"""
	if story_creation_panel:
		story_creation_panel.queue_free()

	story_creation_panel = StoryCreationPanel.instantiate()
	get_parent().add_child(story_creation_panel)

	# 连接信号
	story_creation_panel.story_created.connect(_on_story_created)
	story_creation_panel.creation_cancelled.connect(_on_creation_cancelled)

	# 显示创建面板
	story_creation_panel.show_panel()

	# 隐藏故事模式面板
	hide_panel()

func _create_story_dialog_panel():
	"""创建故事对话面板"""
	if story_dialog_panel:
		story_dialog_panel.queue_free()

	story_dialog_panel = StoryDialogPanel.instantiate()
	get_parent().add_child(story_dialog_panel)

	# 初始化对话面板，传递故事ID和节点ID
	story_dialog_panel.initialize(current_story_id, selected_node_id)

	# 连接关闭信号
	story_dialog_panel.dialog_closed.connect(_on_dialog_closed)
	story_dialog_panel.story_needs_reload.connect(_on_story_needs_reload)

	# 显示对话面板
	story_dialog_panel.show_panel()

	# 隐藏故事模式面板
	hide_panel()

func _on_story_created():
	"""故事创建完成处理"""
	if story_creation_panel:
		story_creation_panel.queue_free()
		story_creation_panel = null

	# 重新加载故事列表
	_load_stories()
	_refresh_story_list()

	# 重新显示故事模式面板
	show_panel()

func _on_creation_cancelled():
	"""故事创建取消处理"""
	if story_creation_panel:
		story_creation_panel.queue_free()
		story_creation_panel = null

	# 重新显示故事模式面板
	show_panel()

func _on_dialog_closed():
	"""对话面板关闭处理"""
	if story_dialog_panel:
		story_dialog_panel.queue_free()
		story_dialog_panel = null

	# 重新显示故事模式面板
	show_panel()

func _on_story_needs_reload():
	"""故事需要重载处理"""
	# 保存当前选中的节点ID，用于重载后重新选中
	var last_selected_node_id = selected_node_id

	if story_dialog_panel:
		story_dialog_panel.queue_free()
		story_dialog_panel = null

	# 重新加载故事数据
	_load_stories()

	# 刷新故事列表和树状图显示
	_refresh_story_list()
	if current_story_id and stories_data.has(current_story_id):
		_render_story_tree()

		# 如果之前有选中的节点，尝试重新选中它
		if not last_selected_node_id.is_empty() and node_positions.has(last_selected_node_id):
			selected_node_id = last_selected_node_id
			start_from_button.visible = true

			# 更新操作栏显示
			if node_text_label:
				var story_data = stories_data[current_story_id]
				var nodes = story_data.get("nodes", {})
				if nodes.has(last_selected_node_id):
					var node_data = nodes[last_selected_node_id]
					var full_text = node_data.get("full_text", node_data.get("display_text", ""))
					node_text_label.text = full_text
					node_text_label.visible = true

			# 平滑移动到选中的节点
			_smooth_move_to_node(last_selected_node_id)

		_redraw_tree()

	# 重新显示故事模式面板
	show_panel()

func _truncate_text(text: String, max_length: int) -> String:
	"""截断文本并添加省略号"""
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

func _estimate_text_height(text: String, font_size: int, max_width: float) -> float:
	"""估算文本高度"""
	if text.is_empty():
		return 0.0

	# 简单估算：假设每行大约有50个字符，行高为font_size * 1.2
	var chars_per_line = max_width / (font_size * 0.6)  # 估算每行字符数
	var line_count = ceil(text.length() / chars_per_line)
	return line_count * font_size * 1.2
