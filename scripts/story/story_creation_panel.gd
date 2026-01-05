extends Control

# 信号
signal story_created
signal creation_cancelled

# UI节点引用
@onready var back_button: Button = $Panel/VBoxContainer/TopBar/BackButton
@onready var keyword_input: LineEdit = $Panel/VBoxContainer/Content/KeywordSection/KeywordInput
@onready var generate_button: Button = $Panel/VBoxContainer/Content/KeywordSection/GenerateButton
@onready var title_input: LineEdit = $Panel/VBoxContainer/Content/TitleSection/TitleInput
@onready var summary_input: TextEdit = $Panel/VBoxContainer/Content/SummarySection/SummaryInput
@onready var create_button: Button = $Panel/VBoxContainer/BottomBar/CreateButton

# AI生成器
var ai_generator: Node = null

func _ready():
	"""初始化"""
	# 初始化AI生成器
	_initialize_ai_generator()

	# 连接信号已在tscn文件中设置
	pass

func _initialize_ai_generator():
	"""初始化AI生成器"""
	ai_generator = preload("res://scripts/story/story_ai_generator.gd").new()
	add_child(ai_generator)
	ai_generator.set_story_creation_panel(self)

	# 连接AI生成器信号
	ai_generator.generation_started.connect(_on_generation_started)
	ai_generator.generation_completed.connect(_on_generation_completed)
	ai_generator.generation_error.connect(_on_generation_error)

func show_panel():
	"""显示面板"""
	visible = true
	# 清空输入框
	keyword_input.text = ""
	title_input.text = ""
	summary_input.text = ""

func hide_panel():
	"""隐藏面板"""
	visible = false

func _on_back_pressed():
	"""返回按钮点击"""
	creation_cancelled.emit()

func _on_generate_pressed():
	"""生成故事按钮点击"""
	var keyword = keyword_input.text.strip_edges()

	# 检查关键词是否为空
	if keyword.is_empty():
		print("关键词为空，将生成随机故事")
	else:
		print("生成故事，关键词：", keyword)

	# 使用AI生成器生成故事
	if ai_generator:
		ai_generator.generate_story_from_keywords(keyword)
	else:
		print("错误：AI生成器未初始化")
		_on_generation_error("AI生成器初始化失败")

func _on_create_pressed():
	"""创建故事按钮点击"""
	var title = title_input.text.strip_edges()
	var summary = summary_input.text.strip_edges()

	# 验证输入
	if title.is_empty():
		print("错误：故事标题不能为空")
		return

	if summary.is_empty():
		print("错误：故事简介不能为空")
		return

	# 创建故事
	if _create_story(title, summary):
		story_created.emit()
	else:
		print("创建故事失败")

func _create_story(title: String, summary: String) -> bool:
	"""创建故事文件"""
	# 确保故事目录存在
	var story_dir = DirAccess.open("user://")
	if not story_dir.dir_exists("story"):
		story_dir.make_dir("story")

	# 生成故事ID
	var story_id = _generate_story_id(title)
	if story_id.is_empty():
		return false

	# 获取当前时间戳
	var current_time = Time.get_datetime_dict_from_system()
	var timestamp = "%04d-%02d-%02dT%02d:%02d:%02d" % [
		current_time.year, current_time.month, current_time.day,
		current_time.hour, current_time.minute, current_time.second
	]

	# 创建故事数据
	var story_data = {
		"story_id": story_id,
		"story_title": title,
		"story_summary": summary,
		"root_node": "start",
		"last_played_at": timestamp,
		"nodes": {
			"start": {
				"display_text": summary,
				"child_nodes": []
			}
		}
	}

	# 保存到文件
	var file_path = "user://story/" + story_id + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		print("无法创建故事文件: ", file_path)
		return false

	var json_string = JSON.stringify(story_data, "\t")
	file.store_string(json_string)
	file.close()

	print("故事创建成功: ", story_id)
	return true

func _generate_story_id(title: String) -> String:
	"""生成故事ID（时间戳+标题哈希，带冲突检查）"""
	var timestamp = str(Time.get_unix_time_from_system())
	var title_hash = title.hash()
	var base_id = timestamp + str(title_hash).substr(0, 6)  # 取哈希前6位

	# 检查冲突，如果冲突则递增
	var story_id = base_id
	var counter = 1
	while _story_id_exists(story_id):
		story_id = base_id + str(counter)
		counter += 1
		if counter > 1000:  # 防止无限循环
			print("无法生成唯一的故事ID")
			return ""

	return story_id

func _story_id_exists(story_id: String) -> bool:
	"""检查故事ID是否已存在"""
	var file_path = "user://story/" + story_id + ".json"
	return FileAccess.file_exists(file_path)

# AI生成器信号处理

func _on_generation_started():
	"""AI生成开始"""
	print("开始生成故事...")
	# 按钮状态已在AI生成器中处理

func _on_generation_completed(title: String, summary: String):
	"""AI生成完成"""
	print("故事生成完成")
	print("标题：", title)
	print("简介：", summary)

func _on_generation_error(error_message: String):
	"""AI生成错误"""
	print("故事生成失败：", error_message)
	# 错误信息已在AI生成器中显示到UI
