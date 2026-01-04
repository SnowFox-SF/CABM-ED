extends Node

# 故事对话保存管理器
# 处理对话的保存与加载功能

# 上下文数组
var ai_context_messages: Array = []  # 发送给AI的上下文消息
var current_node_messages: Array = []  # 当前节点的对话记录

# 依赖的节点引用
var story_dialog_panel: Control = null

# 总结API相关
var config_loader: Node
var api_key: String = ""
var config: Dictionary = {}
var http_request: HTTPRequest

# 唯一ID生成器
var node_id_counter: int = 0

# 存档状态标记
var has_saved_checkpoint: bool = false

# 返回按钮状态管理
var back_button_confirm_mode: bool = false  # 是否处于确认退出模式
var back_button_timer: Timer = null  # 恢复按钮状态的定时器

func _ready():
	"""初始化管理器"""
	_initialize_summary_api()
	_initialize_back_button_timer()

func _initialize_summary_api():
	"""初始化总结API"""
	# 初始化配置加载器
	config_loader = preload("res://scripts/ai_chat/ai_config_loader.gd").new()
	add_child(config_loader)
	config_loader.load_all()

	# 获取配置和API密钥
	api_key = config_loader.api_key
	config = config_loader.config

	# 创建HTTP请求节点
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func _initialize_back_button_timer():
	"""初始化返回按钮定时器"""
	back_button_timer = Timer.new()
	back_button_timer.one_shot = true
	back_button_timer.timeout.connect(_reset_back_button)
	add_child(back_button_timer)

func set_story_dialog_panel(panel: Control):
	"""设置故事对话面板引用"""
	story_dialog_panel = panel

func add_ai_context_message(role: String, content: String):
	"""添加AI上下文消息"""
	ai_context_messages.append({
		"role": role,
		"content": content
	})

func add_current_node_message(type: String, text: String):
	"""添加当前节点消息"""
	current_node_messages.append({
		"type": type,
		"text": text,
		"timestamp": Time.get_unix_time_from_system()
	})

func clear_current_node_messages():
	"""清空当前节点消息"""
	current_node_messages.clear()

func get_current_node_messages() -> Array:
	"""获取当前节点消息"""
	return current_node_messages.duplicate()

func _generate_unique_node_id() -> String:
	"""生成唯一的节点ID"""
	node_id_counter += 1
	var timestamp = Time.get_unix_time_from_system()
	return "node_%d_%d" % [timestamp, node_id_counter]

func _flatten_current_node_messages() -> String:
	"""将当前节点的对话消息扁平化为文本格式"""
	var flattened = []

	for msg in current_node_messages:
		var type = msg.get("type", "")
		var text = msg.get("text", "")

		if type == "user":
			flattened.append("用户: " + text)
		elif type == "ai":
			flattened.append("AI: " + text)
		elif type == "system":
			flattened.append("系统: " + text)

	return "\n".join(flattened)

func create_checkpoint() -> Dictionary:
	"""创建存档点"""
	if not story_dialog_panel:
		push_error("故事对话面板引用未设置")
		return {"success": false, "summary": ""}

	if api_key.is_empty() or not config.has("summary_model"):
		push_error("总结API配置不完整")
		return {"success": false, "summary": ""}

	if current_node_messages.is_empty():
		push_error("当前节点没有对话内容")
		return {"success": false, "summary": ""}

	# 获取用户名和角色名
	var user_name = story_dialog_panel._get_user_name()
	var character_name = story_dialog_panel._get_character_name()

	# 调用故事总结API
	var summary_text = await _call_story_summary_api(user_name, character_name)

	if summary_text.is_empty():
		push_error("获取总结失败")
		return {"success": false, "summary": ""}

	# 创建新节点
	var success = _create_new_story_node(summary_text)
	if not success:
		push_error("创建新节点失败")
		return {"success": false, "summary": ""}

	# 清空当前节点消息，为新节点做准备
	clear_current_node_messages()

	# 标记已创建存档点
	has_saved_checkpoint = true

	return {"success": true, "summary": summary_text}

func _create_new_story_node(summary_text: String) -> bool:
	"""创建新的故事节点"""
	if not story_dialog_panel:
		return false

	# 获取故事数据
	var story_data = story_dialog_panel.story_data
	var nodes_data = story_dialog_panel.nodes_data
	var current_node_id = story_dialog_panel.current_node_id

	if story_data.is_empty() or nodes_data.is_empty():
		push_error("故事数据未加载")
		return false

	# 生成新节点ID
	var new_node_id = _generate_unique_node_id()

	# 创建新节点数据
	var new_node_data = {
		"display_text": summary_text,
		"child_nodes": [],
		"message": current_node_messages.duplicate()  # 保存完整对话记录
	}

	# 添加新节点到节点数据中
	nodes_data[new_node_id] = new_node_data

	# 将新节点添加到当前节点的子节点列表中
	var current_node_data = nodes_data.get(current_node_id, {})
	var child_nodes = current_node_data.get("child_nodes", [])

	# 查找并替换临时节点（如果存在）
	var temp_node_replaced = false
	for i in range(child_nodes.size()):
		var child_id = child_nodes[i]
		if nodes_data.has(child_id):
			var child_data = nodes_data[child_id]
			if child_data.get("display_text", "") == "……":
				# 替换临时节点为新节点
				child_nodes[i] = new_node_id
				nodes_data.erase(child_id)  # 删除临时节点
				temp_node_replaced = true
				break

	# 如果没有找到临时节点，直接添加新节点
	if not temp_node_replaced:
		child_nodes.append(new_node_id)

	nodes_data[current_node_id]["child_nodes"] = child_nodes

	# 更新故事数据
	story_dialog_panel.nodes_data = nodes_data
	story_dialog_panel.current_node_id = new_node_id

	# 重新计算经历节点缓存
	story_dialog_panel._precompute_experienced_nodes()

	# 重新渲染树状图（会自动创建新的临时节点）
	story_dialog_panel._initialize_tree_view()

	# 保存修改后的故事数据到硬盘
	_save_story_data_to_disk()

	return true

func _save_story_data_to_disk() -> bool:
	"""将修改后的故事数据保存到硬盘"""
	if not story_dialog_panel:
		push_error("故事对话面板引用未设置")
		return false

	var story_data = story_dialog_panel.story_data
	if story_data.is_empty():
		push_error("故事数据为空")
		return false

	# 构造文件路径
	var story_id = story_data.get("story_id", "")
	if story_id.is_empty():
		push_error("故事ID为空")
		return false

	var file_path = "user://story/" + story_id + ".json"

	# 将故事数据转换为JSON字符串
	var json_string = JSON.stringify(story_data, "\t", false)
	if json_string.is_empty():
		push_error("JSON序列化失败")
		return false

	# 保存到文件
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("无法打开文件进行写入: " + file_path)
		return false

	file.store_string(json_string)
	file.close()

	print("故事数据已保存到: " + file_path)
	return true

func has_checkpoint_saved() -> bool:
	"""获取是否有存档过的标记"""
	return has_saved_checkpoint

func reset_checkpoint_flag():
	"""重置存档标记"""
	has_saved_checkpoint = false

func _call_story_summary_api(user_name: String, character_name: String) -> String:
	"""调用故事对话总结API

	Args:
		user_name: 用户名
		character_name: 角色名

	Returns:
		总结文本，如果失败则返回空字符串
	"""
	var summary_config = config.summary_model
	var model = summary_config.model
	var base_url = summary_config.base_url

	if model.is_empty() or base_url.is_empty():
		push_error("故事总结模型配置不完整")
		return ""

	# 构建故事上下文
	var story_context = _build_story_summary_context(user_name, character_name)

	# 构建系统提示词
	var system_prompt = _build_story_summary_system_prompt(story_context)

	# 构建用户提示词（对话消息）
	var user_prompt = _build_story_summary_user_prompt(user_name, character_name)

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}
	]

	var url = base_url + "/chat/completions"
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]

	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": 1024,
		"temperature": 0.5,
		"top_p": 0.7,
		"enable_thinking": false,
		"stream": false
	}

	var json_body = JSON.stringify(body)

	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("故事总结请求失败: " + str(error))
		return ""

	# 等待响应
	var result = await http_request.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		push_error("故事总结请求失败: " + str(result[0]))
		return ""

	var response_code = result[1]
	var response_body = result[3]

	if response_code != 200:
		var error_text = response_body.get_string_from_utf8()
		push_error("故事总结API错误 (%d): %s" % [response_code, error_text])
		return ""

	var response_text = response_body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(response_text) != OK:
		push_error("故事总结响应解析失败: " + response_text)
		return ""

	var response_data = json.data
	var summary = ""

	if response_data.has("choices") and response_data.choices.size() > 0:
		var choice = response_data.choices[0]
		if choice.has("message") and choice.message.has("content"):
			summary = choice.message.content.strip_edges()

	return summary

func _build_story_summary_context(user_name: String, character_name: String) -> Dictionary:
	"""构建故事总结上下文"""
	var context = {
		"user_name": user_name,
		"character_name": character_name,
		"story_title": "",
		"story_summary": "",
		"previous_chapter": "",
		"conversation": []
	}

	if story_dialog_panel:
		var story_data = story_dialog_panel.story_data
		if not story_data.is_empty():
			context.story_title = story_data.get("story_title", "")
			context.story_summary = story_data.get("story_summary", "")

		# 获取上一章节内容（当前节点的display_text）
		var current_node_id = story_dialog_panel.current_node_id
		var nodes_data = story_dialog_panel.nodes_data
		if nodes_data.has(current_node_id):
			context.previous_chapter = nodes_data[current_node_id].get("display_text", "")

	return context

func _build_story_summary_system_prompt(context: Dictionary) -> String:
	"""构建故事总结系统提示词"""
	var prompt = "你是一个故事总结专家。你需要用精炼的语言总结用户输入的故事对话内容。\n"
	prompt += "故事标题：《%s》\n" % context.story_title
	prompt += "简介：%s\n\n" % context.story_summary
	prompt += "上一章节：%s\n\n" % context.previous_chapter
	prompt += "总结要求：\n"
	prompt += "- 反映故事发展的主要内容\n"
	prompt += "- 不要超过50字\n"
	prompt += "- 直接给出总结内容，不要包含多余的提示"

	return prompt

func _build_story_summary_user_prompt(user_name: String, character_name: String) -> String:
	"""构建故事总结用户提示词（对话消息）"""
	var conversation_lines = []

	for msg in current_node_messages:
		var type = msg.get("type", "")
		var text = msg.get("text", "")

		if type == "user":
			conversation_lines.append("%s: %s" % [user_name, text])
		elif type == "ai":
			conversation_lines.append("%s: %s" % [character_name, text])

	return "\n".join(conversation_lines)

func should_confirm_back() -> bool:
	"""检查是否需要确认退出"""
	return not current_node_messages.is_empty()

func enter_back_confirm_mode():
	"""进入返回确认模式"""
	if not story_dialog_panel:
		return

	var back_button = story_dialog_panel.back_button
	if back_button:
		back_button.text = "有内容未存档，确认退出？"
		back_button.modulate = Color(1.0, 0.3, 0.3)  # 红色
		back_button_confirm_mode = true

		# 启动3秒定时器恢复按钮状态
		if back_button_timer:
			back_button_timer.start(3.0)

func _reset_back_button():
	"""重置返回按钮状态"""
	if not story_dialog_panel:
		return

	var back_button = story_dialog_panel.back_button
	if back_button:
		back_button.text = "返回"
		back_button.modulate = Color(1.0, 1.0, 1.0)  # 白色
		back_button_confirm_mode = false

func is_back_confirm_mode() -> bool:
	"""检查是否处于返回确认模式"""
	return back_button_confirm_mode

func should_show_checkpoint_pulse() -> bool:
	"""检查是否应该显示存档点按钮的脉冲效果"""
	return current_node_messages.size() >= 18

func _on_request_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	"""处理请求完成信号"""
	# 这个方法主要用于异步请求，但我们使用await所以这里不需要处理
	pass
