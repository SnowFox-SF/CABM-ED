extends Control

# 故事对话面板
# 显示故事对话界面，包含树状图和对话栏

signal dialog_closed
signal story_needs_reload

@onready var story_info_label: TextEdit = $Panel/HBoxContainer/LeftPanel/InfoBar/InfoHBox/StoryInfoLabel
@onready var create_checkpoint_button: Button = $Panel/HBoxContainer/LeftPanel/InfoBar/InfoHBox/CreateCheckpointButton
@onready var tree_view: Control = $Panel/HBoxContainer/LeftPanel/TreeView
@onready var back_button: Button = $Panel/HBoxContainer/LeftPanel/BackButton
@onready var message_container: VBoxContainer = $Panel/HBoxContainer/RightPanel/DialogPanel/ScrollContainer/MessageContainer
@onready var message_input: TextEdit = $Panel/HBoxContainer/RightPanel/MessageInputPanel/HBoxContainer/MessageInput
@onready var send_button: Button = $Panel/HBoxContainer/RightPanel/MessageInputPanel/HBoxContainer/SendButton
@onready var toggle_size_button: Button = $Panel/HBoxContainer/RightPanel/MessageInputPanel/HBoxContainer/ToggleSizeButton
@onready var load_previous_button: Button = $Panel/HBoxContainer/RightPanel/DialogPanel/LoadPreviousButton

# 故事数据
var current_story_id: String = ""
var current_node_id: String = ""      # 用于树状图导航和UI显示
var dialog_node_id: String = ""       # 始终指向用户实际对话的节点，用于创建子节点
var story_data: Dictionary = {}
var nodes_data: Dictionary = {}

# 缓存的经历节点（避免每次重新查找）
var cached_experienced_nodes: Array = []

# 消息数据
var messages: Array = []

# AI相关
var story_ai: StoryAI = null

# 上下文加载器
var context_loader: Node = null

# 保存管理器
var save_manager: Node = null

# 流式输出相关
var current_streaming_bubble: Control = null  # 当前正在流式输出的气泡
var accumulated_streaming_text: String = ""   # 累积的流式文本

# 输入框模式
var is_multi_line_mode: bool = false  # false = 单行模式，true = 多行模式

# AI响应状态
var is_ai_responding: bool = false  # 跟踪AI是否正在响应

# 脉冲动画相关
var checkpoint_pulse_tween: Tween = null  # 存档点按钮脉冲动画
func _ready():
	"""初始化"""
	create_checkpoint_button.pressed.connect(_on_create_checkpoint_pressed)
	send_button.pressed.connect(_on_send_message_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	message_input.text_changed.connect(_on_message_input_changed)
	message_input.gui_input.connect(_on_message_input_gui_input)
	toggle_size_button.pressed.connect(_on_toggle_size_pressed)
	load_previous_button.pressed.connect(_on_load_previous_button_pressed)

	# 连接树状图信号
	tree_view.node_selected.connect(_on_tree_node_selected)
	tree_view.node_deselected.connect(_on_tree_node_deselected)

	# 连接滚动容器信号用于翻页检测
	var scroll_container = message_container.get_parent() as ScrollContainer
	if scroll_container:
		scroll_container.get_v_scroll_bar().changed.connect(_on_scroll_changed)

	# 初始化StoryAI
	_initialize_story_ai()

	# 初始化发送按钮样式
	_update_send_button_style()

	# 初始化输入框为单行模式
	_set_input_mode(false)

	# 初始化保存管理器
	_initialize_save_manager()

func initialize(story_id: String, node_id: String):
	"""初始化对话面板"""
	current_story_id = story_id
	current_node_id = node_id
	dialog_node_id = node_id  # 初始时对话节点和当前节点相同

	# 重置存档标记（开始新的对话会话）
	if save_manager:
		save_manager.reset_checkpoint_flag()

	_load_story_data()
	_setup_ui()
	_initialize_tree_view()
	_initialize_dialog()

	# 检查当前节点是否已经有子节点，如果有则标记为已存档
	_check_existing_checkpoints()

func _check_existing_checkpoints():
	"""检查当前节点是否已经有存档点（子节点）"""
	if not save_manager or nodes_data.is_empty():
		return

	var current_node_data = nodes_data.get(current_node_id, {})
	var child_nodes = current_node_data.get("child_nodes", [])

	# 如果当前节点有子节点（除了临时节点"……"），说明已经创建过存档点
	for child_id in child_nodes:
		if nodes_data.has(child_id):
			var child_data = nodes_data[child_id]
			var display_text = child_data.get("display_text", "")
			if display_text != "……":  # 排除临时节点
				save_manager.has_saved_checkpoint = true
				break

func _load_story_data():
	"""加载故事数据"""
	var story_dir = DirAccess.open("user://story")
	if not story_dir:
		print("无法打开故事目录: user://story")
		return

	story_dir.list_dir_begin()
	var file_name = story_dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var story_file_data = _load_story_file(file_name)
			if story_file_data and story_file_data.has("story_id") and story_file_data.story_id == current_story_id:
				story_data = story_file_data
				nodes_data = story_data.get("nodes", {})
				break
		file_name = story_dir.get_next()

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

func _setup_ui():
	"""设置UI"""
	if story_data.is_empty():
		return

	var story_title = story_data.get("story_title", "未知故事")
	var story_summary = story_data.get("story_summary", "")

	story_info_label.text = "故事：《%s》\n简介：%s" % [story_title, story_summary]

func _initialize_tree_view():
	"""初始化树状图"""
	if nodes_data.is_empty():
		return

	# 创建故事节点数据的副本，用于添加新节点
	var extended_nodes = nodes_data.duplicate(true)

	# 在对话节点后添加一个空白节点"……"（确保临时节点出现在正确的对话节点下）
	var dialog_node_data = extended_nodes.get(dialog_node_id, {})
	var child_nodes = dialog_node_data.get("child_nodes", [])

	# 生成新节点的ID
	var new_node_id = "dialog_temp_node_" + current_node_id

	# 创建新节点数据
	var new_node_data = {
		"display_text": "……",
		"full_text": "……",
		"child_nodes": []
	}
	extended_nodes[new_node_id] = new_node_data

	# 将新节点添加到对话节点的子节点列表中
	child_nodes.append(new_node_id)
	extended_nodes[dialog_node_id]["child_nodes"] = child_nodes

	# 重置树状图视角
	tree_view.zoom_level = 1.0
	tree_view.pan_offset = Vector2.ZERO

	# 渲染树状图
	tree_view.render_tree(story_data.get("root_node", ""), extended_nodes)

	# 禁用节点选中功能（只能查看，不能选择）
	tree_view.set_selection_disabled(true)

	# 延迟一帧后选中新建的"……"节点，确保渲染完成后再进行平滑移动
	call_deferred("_select_new_node", new_node_id)

func _select_new_node(node_id: String):
	"""延迟选中新节点"""
	tree_view.select_node(node_id)

func _initialize_dialog():
	"""初始化对话"""
	_clear_messages()

	# 预计算经历的节点
	_precompute_experienced_nodes()

	# 延迟到下一帧，确保UI完全初始化
	await get_tree().process_frame

	# 初始化存档点按钮脉冲效果
	_update_checkpoint_button_pulse()

	# 初始化上下文加载器状态
	if context_loader:
		context_loader.clear_cache()
		# 初始化滚动位置
		var scroll_container = message_container.get_parent() as ScrollContainer
		if scroll_container:
			context_loader.last_scroll_position = scroll_container.scroll_vertical

		var system_messages = context_loader.initialize_story_context()

		# 显示系统消息
		for system_msg in system_messages:
			_add_system_message(system_msg)

	# 隐藏加载按钮（初始状态）
	load_previous_button.visible = false

func _clear_messages():
	"""清空消息"""
	messages.clear()
	for child in message_container.get_children():
		child.queue_free()

func _add_system_message(text: String):
	"""添加系统消息"""
	var should_scroll = _is_near_bottom()

	var message_item = _create_message_item(text, "system")
	message_container.add_child(message_item)
	messages.append({"type": "system", "text": text})

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

	# 如果之前接近底部，则在气泡创建后平滑滚动到底部
	if should_scroll:
		call_deferred("_smooth_scroll_to_bottom")

func _add_user_message(text: String):
	"""添加用户消息"""
	var should_scroll = _is_near_bottom()

	var message_item = _create_message_item(text, "user")
	message_container.add_child(message_item)
	messages.append({"type": "user", "text": text})

	# 记录到保存管理器
	if save_manager:
		save_manager.add_current_node_message("user", text)

	# 更新存档点按钮脉冲效果
	call_deferred("_update_checkpoint_button_pulse")

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

	# 如果之前接近底部，则在气泡创建后平滑滚动到底部
	if should_scroll or true: #用户发送消息每次都滚动到底部
		call_deferred("_smooth_scroll_to_bottom")

func _add_ai_message(text: String):
	"""添加AI消息"""
	var should_scroll = _is_near_bottom()

	var message_item = _create_message_item(text, "ai")
	message_container.add_child(message_item)
	messages.append({"type": "ai", "text": text})

	# 记录到保存管理器
	if save_manager:
		save_manager.add_current_node_message("ai", text)

	# 更新存档点按钮脉冲效果
	call_deferred("_update_checkpoint_button_pulse")

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

	# 如果之前接近底部，则在气泡创建后平滑滚动到底部
	if should_scroll:
		call_deferred("_smooth_scroll_to_bottom")

func _create_message_item(text: String, type: String) -> Control:
	"""创建消息项"""
	# 加载气泡场景
	var bubble_scene = load("res://scenes/message_bubble.tscn")
	if not bubble_scene:
		print("无法加载气泡场景: res://scenes/message_bubble.tscn")
		return null

	# 实例化气泡
	var bubble_instance = bubble_scene.instantiate()
	if not bubble_instance:
		print("无法实例化气泡场景")
		return null

	# 设置消息内容和类型
	if bubble_instance.has_method("set_message"):
		bubble_instance.set_message(text, type)

	return bubble_instance

func _adjust_bubble_size(_message_item: Control):
	"""调整气泡大小"""
	# 气泡现在使用RichTextLabel的fit_content自动调整大小
	# 这里不需要额外的处理，Godot会自动处理
	pass

func _is_near_bottom() -> bool:
	"""检查是否接近底部"""
	var scroll_container = message_container.get_parent() as ScrollContainer
	if not scroll_container:
		return false

	var v_scroll_bar = scroll_container.get_v_scroll_bar()
	var current_scroll = scroll_container.scroll_vertical
	var max_scroll = v_scroll_bar.max_value
	var page_size = v_scroll_bar.page
	# 如果剩余可滚动距离小于等于页面大小的1.2倍，认为接近底部
	# 这样可以给用户更多的容忍空间，同时避免过于频繁的自动滚动
	return (max_scroll - current_scroll) <= (page_size * 1.2)

func _smooth_scroll_to_bottom():
	"""平滑滚动到底部"""
	var scroll_container = message_container.get_parent() as ScrollContainer
	if not scroll_container:
		return

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	var target_scroll = scroll_container.get_v_scroll_bar().max_value
	tween.tween_property(scroll_container, "scroll_vertical", target_scroll, 0.3)

func _is_near_top() -> bool:
	"""检查是否接近顶部"""
	var scroll_container = message_container.get_parent() as ScrollContainer
	if not scroll_container:
		return false

	var v_scroll_bar = scroll_container.get_v_scroll_bar()
	var current_scroll = scroll_container.scroll_vertical
	var page_size = v_scroll_bar.page

	# 如果滚动位置小于等于页面大小的0.2倍，认为接近顶部
	return current_scroll <= (page_size * 0.2)

func _check_scroll_for_pagination():
	"""检查滚动位置，控制加载上一章节按钮的显示"""
	var scroll_container = message_container.get_parent() as ScrollContainer
	if not scroll_container or not context_loader:
		load_previous_button.visible = false
		return

	var current_scroll = scroll_container.scroll_vertical

	# 当滚动到顶部附近时，检查是否可以加载上一章节
	if _is_near_top():
		var can_load_previous = context_loader.can_load_previous_context(current_node_id)
		load_previous_button.visible = can_load_previous
	else:
		load_previous_button.visible = false

	# 更新上次滚动位置
	context_loader.last_scroll_position = current_scroll

func _add_context_messages_at_top(context_messages: Array):
	"""在消息容器顶部添加上下文消息

	Args:
		context_messages: 上下文消息数组
	"""
	if context_messages.is_empty():
		return

	# 记录当前滚动位置
	var scroll_container = message_container.get_parent() as ScrollContainer
	var current_scroll = scroll_container.scroll_vertical if scroll_container else 0

	# 在顶部添加消息
	for msg in context_messages:
		var msg_type = msg.get("type", "")
		var msg_text = msg.get("text", "")

		if msg_type == "system":
			_add_system_message_at_top(msg_text)
		elif msg_type == "user":
			_add_user_message_at_top(msg_text)
		elif msg_type == "ai":
			_add_ai_message_at_top(msg_text)

	# 恢复滚动位置（保持用户视角不变）
	call_deferred("_restore_scroll_position", current_scroll)

func _add_system_message_at_top(text: String):
	"""在顶部添加系统消息"""
	var _should_scroll = false  # 顶部添加不需要自动滚动

	var message_item = _create_message_item(text, "system")
	message_container.add_child(message_item)
	message_container.move_child(message_item, 0)  # 移动到顶部
	messages.insert(0, {"type": "system", "text": text})  # 插入到消息数组开头

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

func _add_user_message_at_top(text: String):
	"""在顶部添加用户消息"""
	var _should_scroll = false  # 顶部添加不需要自动滚动

	var message_item = _create_message_item(text, "user")
	message_container.add_child(message_item)
	message_container.move_child(message_item, 0)  # 移动到顶部
	messages.insert(0, {"type": "user", "text": text})  # 插入到消息数组开头

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

func _add_ai_message_at_top(text: String):
	"""在顶部添加AI消息"""
	var _should_scroll = false  # 顶部添加不需要自动滚动

	var message_item = _create_message_item(text, "ai")
	message_container.add_child(message_item)
	message_container.move_child(message_item, 0)  # 移动到顶部
	messages.insert(0, {"type": "ai", "text": text})  # 插入到消息数组开头

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

func _restore_scroll_position(previous_scroll: float):
	"""恢复滚动位置"""
	var scroll_container = message_container.get_parent() as ScrollContainer
	if not scroll_container:
		return

	# 计算新的滚动位置（加上添加的消息高度）
	var added_height = 0
	for i in range(min(10, message_container.get_child_count())):  # 只计算前几个消息的高度
		var child = message_container.get_child(i)
		if child and child.has_method("get_minimum_size"):
			added_height += child.get_minimum_size().y

	scroll_container.scroll_vertical = previous_scroll + added_height

func _on_scroll_changed():
	"""滚动条改变时的处理"""
	_check_scroll_for_pagination()

func _on_load_previous_button_pressed():
	"""加载上一章节按钮点击"""
	if not context_loader:
		return

	var previous_context = context_loader.load_previous_node_context()
	if not previous_context["messages"].is_empty():
		# 在顶部添加上下文消息
		_add_context_messages_at_top(previous_context["messages"])

		# 更新当前节点ID到父节点（用于UI显示，因为已经加载了上一层的上下文）
		if not previous_context["new_current_node_id"].is_empty():
			current_node_id = previous_context["new_current_node_id"]
			# 注意：dialog_node_id 保持不变，确保创建存档点时在正确的对话节点下创建

		# 检查是否还能继续加载
		var can_load_more = context_loader.can_load_previous_context(current_node_id)
		load_previous_button.visible = can_load_more

func _on_create_checkpoint_pressed():
	"""创建存档点按钮点击"""
	if save_manager:
		# 改变按钮状态为"正在创建..."
		create_checkpoint_button.text = "正在创建..."
		create_checkpoint_button.disabled = true

		var result = await save_manager.create_checkpoint()
		if result.success:
			print("存档点创建成功")
			var summary_text = result.summary
			_add_system_message("↑\n" + summary_text)
			# 停止脉冲动画，因为已经创建了存档点
			_stop_checkpoint_pulse_animation()
		else:
			print("存档点创建失败")
			_add_system_message("创建存档点失败")

		# 恢复按钮状态
		create_checkpoint_button.text = "创建存档点"
		create_checkpoint_button.disabled = false
	else:
		print("保存管理器未初始化")
		_add_system_message("保存管理器未初始化，无法创建存档点")

func _on_back_button_pressed():
	"""返回按钮点击"""
	print("返回按钮点击 - 检查状态:")
	print("  save_manager 存在:", save_manager != null)
	if save_manager:
		print("  should_confirm_back:", save_manager.should_confirm_back())
		print("  is_back_confirm_mode:", save_manager.is_back_confirm_mode())
		print("  has_checkpoint_saved:", save_manager.has_checkpoint_saved())
		print("  current_node_messages.size:", save_manager.get_current_node_messages().size())

	# 检查是否需要确认退出
	if save_manager and save_manager.should_confirm_back():
		if not save_manager.is_back_confirm_mode():
			print("进入确认模式")
			# 进入确认模式
			save_manager.enter_back_confirm_mode()
			return

	# 确认退出或不需要确认，直接退出
	if save_manager and save_manager.has_checkpoint_saved():
		print("发出重载信号")
		story_needs_reload.emit()
	else:
		print("发出关闭信号")
		dialog_closed.emit()

	hide_panel()

func _on_send_message_pressed():
	"""发送消息按钮点击"""
	var message_text = message_input.text.strip_edges()
	if message_text.is_empty():
		return

	# 添加用户消息
	_add_user_message(message_text)

	# 清空输入框
	message_input.text = ""

	# 更新发送按钮样式（现在输入框为空）
	_update_send_button_style()

	# 发送消息到AI
	_send_message_to_ai(message_text)


func _on_message_input_changed():
	"""消息输入改变"""
	# 只更新发送按钮样式，不再自动调整高度
	_update_send_button_style()

func _update_send_button_style():
	"""更新发送按钮样式"""
	var has_content = not message_input.text.strip_edges().is_empty()

	if has_content and not is_ai_responding:
		# 有内容且AI未响应时：激活状态，绿色背景
		send_button.modulate = Color(0.2, 0.8, 0.2)  # 绿色
		send_button.disabled = false
	else:
		# 无内容或AI正在响应时：禁用状态，灰色背景
		send_button.modulate = Color(0.5, 0.5, 0.5)  # 灰色
		send_button.disabled = true

func _disable_input_during_ai_response():
	"""在AI响应期间禁用输入控件"""
	is_ai_responding = true
	message_input.editable = false
	message_input.modulate = Color(0.7, 0.7, 0.7)  # 变暗表示禁用
	_update_send_button_style()

func _enable_input_after_ai_response():
	"""AI响应完成后启用输入控件"""
	is_ai_responding = false
	message_input.editable = true
	message_input.modulate = Color(1, 1, 1)  # 恢复正常颜色
	_update_send_button_style()

func _set_input_mode(multi_line: bool):
	"""设置输入框模式"""
	is_multi_line_mode = multi_line

	# 获取消息输入面板
	var message_input_panel = message_input.get_parent().get_parent() as Panel
	if not message_input_panel:
		return

	if multi_line:
		# 多行模式：最大高度，不显示发送按钮
		message_input_panel.custom_minimum_size.y = 140  # 120 + 20内边距
		toggle_size_button.text = "↓"
		send_button.visible = false
	else:
		# 单行模式：基础高度，显示发送按钮
		message_input_panel.custom_minimum_size.y = 60  # 40 + 20内边距
		toggle_size_button.text = "↑"
		send_button.visible = true

	# 强制更新布局
	message_input_panel.queue_redraw()

func _on_toggle_size_pressed():
	"""切换输入框大小按钮点击"""
	_set_input_mode(!is_multi_line_mode)

func _on_message_input_gui_input(event: InputEvent):
	"""处理消息输入框的GUI输入事件"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER:
			# 检查是否有修饰键
			var has_modifier = event.ctrl_pressed or event.shift_pressed or event.alt_pressed

			if not has_modifier:
				# 普通回车：发送消息
				_on_send_message_pressed()
				# 阻止默认行为（换行）
				get_viewport().set_input_as_handled()
			# 如果有修饰键，则允许默认行为（换行）

func _on_tree_node_selected(node_id: String):
	"""树状图节点选中"""
	print("树状图节点选中: ", node_id)

	# 如果切换到不同的节点，重置上下文加载器状态
	if node_id != current_node_id and context_loader:
		context_loader.clear_cache()
		# 重新初始化滚动位置
		var scroll_container = message_container.get_parent() as ScrollContainer
		if scroll_container:
			context_loader.last_scroll_position = scroll_container.scroll_vertical

	# 更新当前节点ID（用于UI显示）
	current_node_id = node_id
	# 同时更新对话节点ID（用户选择节点时，对话也切换到该节点）
	dialog_node_id = node_id

	# 隐藏加载按钮
	load_previous_button.visible = false

	# TODO: 处理节点选中逻辑，比如跳转到对应对话位置

func _on_tree_node_deselected():
	"""树状图节点取消选中"""
	print("树状图节点取消选中")
	# TODO: 处理节点取消选中逻辑

func show_panel():
	"""显示对话面板"""
	visible = true

func hide_panel():
	"""隐藏对话面板"""
	visible = false
	dialog_closed.emit()

func get_current_story_id() -> String:
	"""获取当前故事ID"""
	return current_story_id

func get_current_node_id() -> String:
	"""获取当前节点ID（UI显示的节点）"""
	return current_node_id

func get_dialog_node_id() -> String:
	"""获取对话节点ID（实际用于对话和创建子节点的节点）"""
	return dialog_node_id

func _initialize_story_ai():
	"""初始化StoryAI"""
	story_ai = StoryAI.new()
	add_child(story_ai)

	# 连接AI信号
	story_ai.reply_ready.connect(_on_ai_reply_ready)
	story_ai.text_chunk_ready.connect(_on_ai_text_chunk_ready)
	story_ai.streaming_completed.connect(_on_streaming_completed)
	story_ai.streaming_interrupted.connect(_on_streaming_interrupted)
	story_ai.request_error_occurred.connect(_on_request_error_occurred)

	# 初始化上下文加载器
	context_loader = preload("res://scripts/story/story_context_loader.gd").new()
	add_child(context_loader)
	context_loader.set_story_dialog_panel(self)

func _on_ai_reply_ready(_text: String):
	"""AI回复就绪"""
	print("StoryAI回复就绪")

func _on_ai_text_chunk_ready(text_chunk: String):
	"""处理文本块就绪信号，流式显示"""
	# 累积文本
	accumulated_streaming_text += text_chunk

	# 如果这是第一个文本块，创建气泡
	if current_streaming_bubble == null:
		current_streaming_bubble = _create_streaming_bubble()
		if current_streaming_bubble == null:
			print("无法创建流式输出气泡")
			return

	# 更新气泡文本
	_update_streaming_bubble_text(accumulated_streaming_text)

func _on_streaming_completed():
	"""流式响应完成"""
	print("StoryAI流式回复完成")

	# 将完成的流式消息添加到消息列表
	if accumulated_streaming_text != "":
		messages.append({"type": "ai", "text": accumulated_streaming_text})

		# 添加到显示历史
		if story_ai:
			story_ai.add_to_display_history("assistant", accumulated_streaming_text)

		# 记录到保存管理器
		if save_manager:
			save_manager.add_current_node_message("ai", accumulated_streaming_text)

		# 记录到AI上下文
		if save_manager:
			save_manager.add_ai_context_message("assistant", accumulated_streaming_text)

	# 清理流式输出状态
	current_streaming_bubble = null
	accumulated_streaming_text = ""

	# 启用输入控件
	_enable_input_after_ai_response()

func _on_streaming_interrupted(error_message: String, partial_content: String):
	"""处理流式响应中断"""
	print("StoryAI流式响应中断: ", error_message)

	# 使用系统气泡显示错误信息
	var error_line = "出现错误：" + error_message
	_add_system_message(error_line)

	# 如果有部分内容，将其作为AI消息添加到对话中
	if not partial_content.strip_edges().is_empty():
		_add_ai_message(partial_content)

		# 将部分内容加入上下文历史（虽然不完整）
		if story_ai:
			story_ai.add_to_display_history("assistant", partial_content)

		# 记录到AI上下文
		if save_manager:
			save_manager.add_ai_context_message("assistant", partial_content)

	# 添加错误信息到显示历史
	if story_ai:
		story_ai.add_to_display_history("system", error_line)

	# 清理流式输出状态
	current_streaming_bubble = null
	accumulated_streaming_text = ""

	# 启用输入控件
	_enable_input_after_ai_response()

func _on_request_error_occurred(error_message: String):
	"""处理请求级别错误（撤回用户输入）"""
	print("StoryAI请求错误: ", error_message)

	# 撤回用户输入：将最后一条用户消息放回输入框
	var last_user_message = _get_last_user_message()
	if not last_user_message.is_empty():
		message_input.text = last_user_message
		_update_send_button_style()

		# 移除最后一条用户消息（因为还没有AI响应）
		_remove_last_messages(1)

	# 使用系统气泡显示错误信息
	var error_line = "出现错误：" + error_message
	_add_system_message(error_line)

	# 从StoryAI的显示历史中移除最后一条用户消息
	if story_ai:
		story_ai.remove_last_user_from_display_history()
		story_ai.add_to_display_history("system", error_line)

	# 清理流式输出状态
	current_streaming_bubble = null
	accumulated_streaming_text = ""

	# 启用输入控件
	_enable_input_after_ai_response()

func _on_ai_error_occurred(error_message: String):
	"""处理通用AI错误（保持兼容性）"""
	print("StoryAI通用错误: ", error_message)
	var error_line = "出现错误：" + error_message
	_add_system_message(error_line)

	# 添加到显示历史
	if story_ai:
		story_ai.add_to_display_history("system", error_line)

func _send_message_to_ai(message_text: String):
	"""发送消息到StoryAI"""
	if not story_ai:
		print("StoryAI未初始化")
		return

	# 禁用输入控件
	_disable_input_during_ai_response()

	# 构建故事上下文
	var story_context = _build_story_context()

	# 添加到显示历史
	var user_name = _get_user_name()
	var user_message_line = "<%s> %s" % [user_name, message_text]
	story_ai.add_to_display_history("user", user_message_line)

	# 记录到AI上下文
	if save_manager:
		save_manager.add_ai_context_message("user", user_message_line)

	# 发送给AI
	story_ai.request_reply(message_text, story_context)

func _build_story_context() -> Dictionary:
	"""构建故事上下文"""
	# 直接返回完整的故事数据，让AI系统自己处理
	return {
		"story_data": story_data,           # 完整的故事JSON数据
		"current_node_id": dialog_node_id,  # 使用对话节点ID（修复：创建存档点时应在对话节点下创建）
		"story_id": current_story_id,       # 故事ID
		"experienced_nodes": _get_experienced_nodes()  # 缓存的经历节点
	}

func _get_user_name() -> String:
	"""获取用户名"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		return save_mgr.get_user_name()
	return "我"

func _get_character_name() -> String:
	"""获取角色名称"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		return save_mgr.get_character_name()
	return "角色"

func _create_streaming_bubble() -> Control:
	"""创建流式输出气泡"""
	var _should_scroll = _is_near_bottom()

	# 创建消息项（初始为空文本）
	var message_item = _create_message_item("", "ai")
	if message_item == null:
		return null

	message_container.add_child(message_item)

	# 调整气泡大小
	call_deferred("_adjust_bubble_size", message_item)

	return message_item

func _update_streaming_bubble_text(text: String):
	"""更新流式气泡的文本"""
	if current_streaming_bubble == null:
		return

	# 通过set_message方法更新文本
	if current_streaming_bubble.has_method("set_message"):
		current_streaming_bubble.set_message(text, "ai")

func _precompute_experienced_nodes():
	"""预计算并缓存已经经历的节点（包含当前节点）"""
	if story_data.is_empty() or current_node_id.is_empty():
		return

	var experienced_nodes = []
	var nodes = story_data.get("nodes", {})
	var root_node = story_data.get("root_node", "")

	# 首先包含当前节点
	if nodes.has(current_node_id):
		var current_node = nodes[current_node_id]
		experienced_nodes.append({
			"node_id": current_node_id,  # 可以添加ID用于标识
			"display_text": current_node.get("display_text", "")
		})

	# 从当前节点开始往上遍历父节点（使用UI显示的当前节点）
	var current_id = current_node_id
	var visited = {}  # 防止循环引用

	while current_id != root_node and not visited.has(current_id):
		visited[current_id] = true

		# 查找父节点
		var parent_id = _find_parent_node(nodes, current_id)
		if parent_id == "":
			break

		# 添加父节点到经历列表
		if nodes.has(parent_id):
			var parent_node = nodes[parent_id]
			experienced_nodes.append({
				"node_id": parent_id,  # 可以添加ID用于标识
				"display_text": parent_node.get("display_text", "")
			})

		current_id = parent_id

	# 反转数组，使根节点附近的节点在前
	experienced_nodes.reverse()

	# 更新缓存
	cached_experienced_nodes = experienced_nodes

func _find_parent_node(nodes: Dictionary, child_node_id: String) -> String:
	"""查找指定节点的父节点"""
	for node_id in nodes:
		var node = nodes[node_id]
		var child_nodes = node.get("child_nodes", [])
		if child_node_id in child_nodes:
			return node_id
	return ""

func _get_experienced_nodes() -> Array:
	"""获取缓存的经历节点"""
	return cached_experienced_nodes.duplicate()

func _clear_experienced_nodes_cache():
	"""清空经历节点缓存"""
	cached_experienced_nodes.clear()

func _get_last_user_message() -> String:
	"""获取最后一条用户消息"""
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].type == "user":
			return messages[i].text
	return ""

func _remove_last_messages(count: int):
	"""移除最后几条消息"""
	if count <= 0 or messages.size() == 0:
		return

	var messages_to_remove = min(count, messages.size())
	var start_index = messages.size() - messages_to_remove

	# 从消息容器中移除对应的UI元素
	for i in range(start_index, messages.size()):
		var child_index = i
		if child_index < message_container.get_child_count():
			var child = message_container.get_child(child_index)
			child.queue_free()

	# 从消息数组中移除
	messages.resize(start_index)

func _initialize_save_manager():
	"""初始化保存管理器"""
	save_manager = preload("res://scripts/story/story_dialog_save_manager.gd").new()
	add_child(save_manager)
	save_manager.set_story_dialog_panel(self)

func _update_checkpoint_button_pulse():
	"""更新创建存档点按钮的脉冲效果"""
	if not save_manager or not create_checkpoint_button:
		return

	if save_manager.should_show_checkpoint_pulse():
		_start_checkpoint_pulse_animation()
	else:
		_stop_checkpoint_pulse_animation()

func _start_checkpoint_pulse_animation():
	"""启动存档点按钮的脉冲动画"""
	if checkpoint_pulse_tween:
		checkpoint_pulse_tween.kill()

	checkpoint_pulse_tween = create_tween()
	checkpoint_pulse_tween.set_loops()  # 无限循环

	# 脉冲动画：荧光效果，从弱到强再回到弱
	checkpoint_pulse_tween.tween_property(
		create_checkpoint_button,
		"modulate",
		Color(2.0, 2.0, 1.5, 1.0),  # 明亮的蓝色荧光
		0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	checkpoint_pulse_tween.tween_property(
		create_checkpoint_button,
		"modulate",
		Color(1.0, 1.0, 1.0, 1.0),  # 回到正常颜色
		0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_checkpoint_pulse_animation():
	"""停止存档点按钮的脉冲动画"""
	if checkpoint_pulse_tween:
		checkpoint_pulse_tween.kill()
		checkpoint_pulse_tween = null

	# 恢复原始缩放
	if create_checkpoint_button:
		create_checkpoint_button.scale = Vector2(1.0, 1.0)
