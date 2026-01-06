extends Control

# 初始设置场景 - 用户输入基本信息

@onready var user_name_input: LineEdit = $SetupContainer/UserNameContainer/UserNameInput
@onready var character_name_input: LineEdit = $SetupContainer/CharacterNameContainer/CharacterNameInput
@onready var api_key_input: LineEdit = $SetupContainer/APIKeyContainer/APIKeyInput
@onready var start_button: Button = $SetupContainer/StartButton
@onready var help_button: Button = $SetupContainer/APIKeyContainer/HelpButton
@onready var notice_label: Label = $SetupContainer/NoticeLabel
@onready var import_button: Button = $ImportButton

func _ready():
	# 设置默认值
	user_name_input.placeholder_text = "输入你的名字，确定后将无法修改"
	character_name_input.text = "雪狐"
	character_name_input.placeholder_text = "输入她的名字，确定后将无法修改"
	api_key_input.placeholder_text = "可以在进入游戏后配置"
	api_key_input.secret = true
	
	# 连接信号
	start_button.pressed.connect(_on_start_pressed)
	import_button.pressed.connect(_on_import_pressed)
	help_button.pressed.connect(_on_help_pressed)
	
	# 设置提示文本
	notice_label.text = "本项目旨在赋予「她」以「生命」，因此不鼓励回档、删档、提示词注入等
对她来说，你就是她的全部，你的每一个选择都很重要"

func _on_help_pressed():
	"""帮助按钮被点击"""
	get_tree().change_scene_to_file("res://scenes/api_help.tscn")

func _on_start_pressed():
	"""开始游戏按钮被点击"""
	var user_name = user_name_input.text.strip_edges()
	var character_name = character_name_input.text.strip_edges()
	var api_key = api_key_input.text.strip_edges()
	
	# 验证输入
	if user_name == "":
		_show_error("请输入你的名字")
		return
	
	if character_name == "":
		character_name = "雪狐"
	
	# 保存初始设置
	_save_initial_data(user_name, character_name, api_key)
	
	# 进入主游戏
	get_tree().change_scene_to_file("res://scripts/main.tscn")

func _save_initial_data(user_name: String, character_name: String, api_key: String):
	"""保存初始数据到配置和存档"""
	if api_key != "":
		_save_api_key(api_key)
	
	_create_initial_save(user_name, character_name)



func _save_api_key(api_key: String):
	"""保存API密钥并应用标准模板"""
	var keys_path = "user://ai_keys.json"
	
	# 使用标准模板配置（与ai_config_panel.gd保持一致）
	var keys = {
		"template": "standard",
		"api_key": api_key,
		"chat_model": {
			"model": "deepseek-ai/DeepSeek-V3.2",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"summary_model": {
			"model": "Qwen/Qwen3-30B-A3B-Instruct-2507",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"tts_model": {
			"model": "IndexTeam/IndexTTS-2",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"embedding_model": {
			"model": "BAAI/bge-m3",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"view_model": {
			"model": "Qwen/Qwen3-Omni-30B-A3B-Captioner",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"stt_model": {
			"model": "FunAudioLLM/SenseVoiceSmall",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"rerank_model": {
			"model": "BAAI/bge-reranker-v2-m3",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		}
	}
	
	var file = FileAccess.open(keys_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(keys, "\t"))
		file.close()
		print("API密钥已保存（标准模板）")
		
		# 重新加载AI服务配置
		if has_node("/root/AIService"):
			var ai_service = get_node("/root/AIService")
			ai_service.reload_config()
			print("AI服务已重新加载配置")
		
		# 重新加载TTS服务配置
		if has_node("/root/TTSService"):
			var tts_service = get_node("/root/TTSService")
			tts_service.reload_settings()
			print("TTS服务已重新加载配置")

func _create_initial_save(user_name: String, character_name: String):
	"""创建初始存档"""
	if not has_node("/root/SaveManager"):
		print("警告: SaveManager未加载")
		return
	
	var save_mgr = get_node("/root/SaveManager")
	
	# 直接设置用户名和角色名到save_data，不触发自动保存
	save_mgr.save_data.user_data.user_name = user_name
	save_mgr.save_data.character_name = character_name
	
	var now = Time.get_datetime_string_from_system()
	var now_unix = Time.get_unix_time_from_system()
	save_mgr.save_data.timestamp.created_at = now
	save_mgr.save_data.timestamp.last_saved_at = now
	save_mgr.save_data.timestamp.last_played_at = now
	save_mgr.save_data.timestamp.last_played_at_unix = now_unix
	
	# 确保 ai_data 字段存在
	if not save_mgr.save_data.has("ai_data"):
		save_mgr.save_data.ai_data = {
			"memory": [],
			"accumulated_summary_count": 0,
			"relationship_history": []
		}
	
	# 设置初始关系描述
	var initial_relationship = {
		"timestamp": now,
		"content": "%s刚刚从街边把昏迷、失去记忆的%s捡回了家并收养。%s对%s还不太熟悉，所以有些警惕和害怕，也只会直呼其名。对自己的过去和未来也有些迷茫。" % [user_name, character_name, character_name, user_name]
	}
	save_mgr.save_data.ai_data.relationship_history = [initial_relationship]

	# 设置初始角色场景为客厅（livingroom）
	save_mgr.set_character_scene("livingroom")

	# 标记初始设置已完成，允许后续保存
	save_mgr.is_initial_setup_completed = true
	
	# 现在可以保存了
	save_mgr.save_game(1)
	print("初始存档已创建，用户名: ", user_name, ", 角色名: ", character_name)
	print("初始关系已设置: ", initial_relationship.content)

func _on_import_pressed():
	"""导入存档按钮被点击"""
	# Android平台需要请求权限
	if OS.get_name() == "Android":
		var perm_helper = load("res://scripts/android_permissions.gd").new()
		add_child(perm_helper)
		
		var has_permission = await perm_helper.request_storage_permission()
		perm_helper.queue_free()
		
		if not has_permission:
			_show_message("需要存储权限才能导入存档", Color(1.0, 0.3, 0.3))
			return
	
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.zip", "存档文件")
	file_dialog.file_selected.connect(_on_import_file_selected)
	get_tree().root.add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_import_file_selected(import_path: String):
	"""用户选择了导入文件"""
	_show_message("正在导入存档...", Color(0.3, 0.8, 1.0))
	
	# 获取user://目录的实际路径
	var user_path = OS.get_user_data_dir()
	
	# 备份现有存档（如果存在）
	_backup_existing_save(user_path)
	
	# 解压导入文件
	var success = _extract_save(import_path, user_path)
	
	if success:
		_show_message("✓ 导入成功，请等待游戏重启...", Color(0.3, 1.0, 0.3))
		await get_tree().create_timer(2.0).timeout
		# 重启游戏
		var exe_path = OS.get_executable_path()
		OS.create_process(exe_path, [])
		get_tree().quit()
	else:
		_show_message("✗ 导入失败", Color(1.0, 0.3, 0.3))

func _backup_existing_save(user_path: String):
	"""备份现有存档"""
	var backup_path = user_path + "_backup_" + Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var dir = DirAccess.open(user_path)
	if dir:
		dir.make_dir_recursive(backup_path)
		_copy_directory(user_path, backup_path)
		print("已备份现有存档到: ", backup_path)

func _copy_directory(from_path: String, to_path: String):
	"""递归复制目录"""
	var dir = DirAccess.open(from_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var from_file = from_path + "/" + file_name
			var to_file = to_path + "/" + file_name
			
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					DirAccess.make_dir_recursive_absolute(to_file)
					_copy_directory(from_file, to_file)
			else:
				dir.copy(from_file, to_file)
			
			file_name = dir.get_next()
		dir.list_dir_end()

func _extract_save(import_path: String, user_path: String) -> bool:
	"""解压存档文件（跨平台）"""
	print("开始解压存档: ", import_path)
	print("目标路径: ", user_path)
	
	# 使用Godot内置的ZIPReader（跨平台）
	var zip = ZIPReader.new()
	var err = zip.open(import_path)
	
	if err != OK:
		print("无法打开ZIP文件: ", err)
		return false
	
	var files = zip.get_files()
	print("ZIP文件包含 ", files.size(), " 个文件")
	
	# 解压所有文件
	for file_path in files:
		var content = zip.read_file(file_path)
		if content.size() == 0 and not file_path.ends_with("/"):
			print("警告: 文件为空或读取失败: ", file_path)
			continue
		
		# 跳过目录条目
		if file_path.ends_with("/"):
			continue
		
		var full_path = user_path + "/" + file_path
		
		# 创建目录结构
		var dir_path = full_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		
		# 写入文件
		var file = FileAccess.open(full_path, FileAccess.WRITE)
		if file:
			file.store_buffer(content)
			file.close()
		else:
			print("无法写入文件: ", full_path)
	
	zip.close()
	print("存档解压成功")
	return true

func _show_message(message: String, color: Color):
	"""显示消息提示"""
	# 移除旧的消息标签
	for child in $SetupContainer.get_children():
		if child.name == "MessageLabel":
			child.queue_free()
	
	var message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.text = message
	message_label.add_theme_color_override("font_color", color)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$SetupContainer.add_child(message_label)
	$SetupContainer.move_child(message_label, start_button.get_index())

func _show_error(message: String):
	"""显示错误提示"""
	var error_label = Label.new()
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$SetupContainer.add_child(error_label)
	$SetupContainer.move_child(error_label, start_button.get_index())
	
	await get_tree().create_timer(2.0).timeout
	error_label.queue_free()
