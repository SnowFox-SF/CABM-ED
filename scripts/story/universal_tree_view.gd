extends Control

# 通用树状图视图组件
# 可以被故事模式面板和故事对话页面复用

signal node_selected(node_id: String)
signal node_deselected

# 树状图相关变量
@onready var tree_view_container: Control = $TreeViewContainer

# 节点数据
var tree_nodes: Array = []
var node_positions: Dictionary = {}
var nodes_data: Dictionary = {}

# 选中节点相关
var selected_node_id: String = ""
var selection_disabled: bool = false  # 是否禁用节点选中功能

# 平滑移动相关
var view_tween: Tween = null

# 树状图相关
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

func _ready():
	"""初始化"""
	_create_tween()

func _input(event):
	"""处理输入事件，用于树状图的缩放和移动"""
	if not visible or input_disabled:
		return

	# 检查输入保护（用于故事对话页面）
	if input_protected:
		var parent_panel = get_parent()
		while parent_panel and not (parent_panel is Window):
			if parent_panel is Control and not parent_panel.visible:
				return
			parent_panel = parent_panel.get_parent()

	# 检查是否在树状图区域内（用于鼠标和触摸事件）
	var tree_view_rect = Rect2(tree_view_container.global_position, tree_view_container.size)
	var mouse_pos = get_viewport().get_mouse_position()

	# 处理触摸事件（移动设备）- 只有在区域内才处理
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if tree_view_rect.has_point(event.position):
			# 触摸点在区域内，正常处理
			if event is InputEventScreenTouch:
				_handle_touch_event(event)
			else:
				_handle_drag_event(event)
		else:
			# 触摸点不在区域内
			if event is InputEventScreenTouch and event.pressed:
				# 如果是按下事件且在区域外，忽略
				return
			else:
				# 如果是拖拽事件或释放事件在区域外，重置触摸状态
				touch_positions.clear()
				touch_zoom_active = false
				initial_touch_distance = 0.0
				initial_zoom_level = 1.0
		return

	# 处理鼠标事件
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 只有在区域内按下时才开始可能的拖拽
				if tree_view_rect.has_point(mouse_pos):
					is_dragging = false
					drag_start_pos = get_viewport().get_mouse_position()
					last_mouse_pos = drag_start_pos
			else:
				# 结束拖拽（无论鼠标在哪里都可以释放）
				is_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if tree_view_rect.has_point(mouse_pos):
				_zoom_tree_view(0.1, mouse_pos)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if tree_view_rect.has_point(mouse_pos):
				_zoom_tree_view(-0.1, mouse_pos)

	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT and drag_start_pos != Vector2.ZERO:
			var current_mouse_pos = get_viewport().get_mouse_position()
			if not is_dragging:
				# 检查是否超过拖拽阈值，开始拖拽
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

func _create_tween():
	"""创建Tween用于平滑移动"""
	# 只在需要时创建Tween，避免空Tween被启动
	pass

func _clear_node_selection():
	"""清除节点选中状态"""
	selected_node_id = ""
	_redraw_tree()
	node_deselected.emit()

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
	var parent_nodes = _get_all_parent_nodes(selected_node_id, nodes_data)
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
	var node_pos = node_positions[node_id] + NODE_SIZE / 2  # 节点中心点（世界坐标）

	# 计算目标位置：节点中心点位于容器中心
	# target_pan_offset = container_center - node_world_pos * zoom_level
	var target_pan_offset = container_size / 2 - node_pos * zoom_level

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

func render_tree(root_node_id: String, nodes: Dictionary):
	"""渲染树状图"""
	nodes_data = nodes
	tree_nodes.clear()
	node_positions.clear()

	# 获取容器尺寸
	var container_size = tree_view_container.size
	var start_pos = Vector2(container_size.x * 0.1, container_size.y * 0.5)  # 从容器左侧10%位置开始，垂直居中

	# 计算节点位置
	_calculate_node_positions(root_node_id, nodes, start_pos)

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

	# 处理子节点 - 考虑每个子节点及其子树的空间需求
	var child_nodes = node_data.get("child_nodes", [])
	if child_nodes.size() > 0:
		# 计算每个子节点及其子树需要的垂直空间
		var child_spaces = []
		var total_space = 0.0

		for child_id in child_nodes:
			var space = _calculate_node_vertical_space(child_id, nodes, depth + 1)
			child_spaces.append(space)
			total_space += space

		# 计算起始位置，使所有子节点居中分布
		var start_y = node_position.y - total_space / 2.0
		var current_y = start_y

		for i in range(child_nodes.size()):
			var child_id = child_nodes[i]
			var child_space = child_spaces[i]
			var child_center_y = current_y + child_space / 2.0

			_calculate_node_positions(child_id, nodes, Vector2(node_position.x + NODE_SPACING_X, child_center_y), depth + 1)
			current_y += child_space

func _calculate_node_vertical_space(node_id: String, nodes: Dictionary, depth: int) -> float:
	"""计算节点及其子树需要的垂直空间"""
	if not nodes.has(node_id):
		return NODE_SIZE.y + NODE_SPACING_Y

	var node_data = nodes[node_id]
	var child_nodes = node_data.get("child_nodes", [])

	if child_nodes.is_empty():
		return NODE_SIZE.y + NODE_SPACING_Y

	# 计算所有子节点的空间
	var total_child_space = 0.0
	for child_id in child_nodes:
		total_child_space += _calculate_node_vertical_space(child_id, nodes, depth + 1)

	return max(total_child_space, NODE_SIZE.y + NODE_SPACING_Y)

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

		# 添加点击事件
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
	# 注意：区域检查已在 _input 中完成，这里直接处理
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
	# 注意：区域检查已在 _input 中完成，这里直接处理
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
		# 如果禁用选中功能，直接返回
		if selection_disabled:
			return

		# 处理节点选中/取消选中
		if selected_node_id == node_id:
			# 再次点击已选中的节点，取消选中
			_clear_node_selection()
		else:
			# 选中新节点
			selected_node_id = node_id
			_redraw_tree()
			node_selected.emit(node_id)

			# 平滑移动到选中节点
			_smooth_move_to_node(node_id)

		print("节点被点击: ", node_id, "(取消选中)" if selected_node_id.is_empty() else "(选中)")

func select_node(node_id: String):
	"""外部调用：选中指定节点"""
	if nodes_data.has(node_id):
		selected_node_id = node_id
		_redraw_tree()
		_smooth_move_to_node(node_id)

func clear_selection():
	"""外部调用：清除选中状态"""
	_clear_node_selection()

func clear_tree():
	"""清除树状图"""
	# 清除所有数据
	tree_nodes.clear()
	node_positions.clear()
	nodes_data.clear()
	selected_node_id = ""

	# 重绘（会清空所有可视元素）
	_redraw_tree()

func reset_view():
	"""重置视图到初始状态"""
	zoom_level = 1.0
	pan_offset = Vector2.ZERO
	_redraw_tree()

func get_selected_node_id() -> String:
	"""获取当前选中的节点ID"""
	return selected_node_id

func set_selection_disabled(disabled: bool):
	"""设置是否禁用节点选中功能"""
	selection_disabled = disabled
	if disabled and not selected_node_id.is_empty():
		_clear_node_selection()

var input_protected: bool = false
var input_disabled: bool = false  # 完全禁用输入的标志

func set_input_protected(protected: bool):
	"""设置是否启用输入保护（检查父级面板可见性）"""
	input_protected = protected

func set_input_disabled(disabled: bool):
	"""设置是否完全禁用输入（用于对话页面打开时）"""
	input_disabled = disabled
