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
@onready var tree_view: Control = $Panel/VBoxContainer/HSplitContainer/TreeViewPanel/VBoxContainer/TreeViewContainer/TreeView

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

signal story_mode_closed

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	plus_button.pressed.connect(_on_plus_button_pressed)
	start_from_button.pressed.connect(_on_start_from_pressed)

	# 连接树状图信号
	tree_view.node_selected.connect(_on_tree_node_selected)
	tree_view.node_deselected.connect(_on_tree_node_deselected)

	_create_tween()
	_load_stories()
	_refresh_story_list()



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

	# 使用TreeView的方法清除选中状态
	tree_view.clear_selection()

	# 停止当前的视图动画
	if view_tween and view_tween.is_valid():
		view_tween.kill()
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
	tree_view.reset_view()

	_refresh_story_list()  # 刷新故事列表显示
	_render_story_tree()

func _render_story_tree():
	"""渲染故事树状图"""
	if not current_story_id or not stories_data.has(current_story_id):
		return

	var story_data = stories_data[current_story_id]
	if not story_data.has("nodes") or not story_data.has("root_node"):
		return

	# 使用通用树状图组件渲染
	tree_view.render_tree(story_data.root_node, story_data.nodes)



func _on_tree_node_selected(node_id: String):
	"""树状图节点选中"""
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

	# TreeView 会自动平滑移动到选中节点

	print("节点被选中: ", node_id)

func _on_tree_node_deselected():
	"""树状图节点取消选中"""
	selected_node_id = ""
	start_from_button.visible = false
	node_text_label.text = ""
	node_text_label.visible = false

	print("节点被取消选中")

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
		# 重置树状图视图（缩放和位置）
		tree_view.reset_view()

		_render_story_tree()

		# 如果之前有选中的节点，尝试重新选中它
		if not last_selected_node_id.is_empty():
			tree_view.select_node(last_selected_node_id)

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
