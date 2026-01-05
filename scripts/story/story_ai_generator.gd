extends Node

# AI故事生成器
# 负责根据关键词生成故事标题和简介

# 信号
signal generation_started()
signal generation_completed(title: String, summary: String)
signal generation_error(error_message: String)

# 依赖节点引用
var story_creation_panel: Control = null
var ai_http_client: Node = null

# AI配置相关
var config_loader: Node
var api_key: String = ""
var config: Dictionary = {}

# 生成状态
var is_generating: bool = false
var current_title: String = ""
var current_summary: String = ""
var full_response_content: String = ""  # 累积的完整响应内容

# 确认机制
var confirm_timer: Timer = null
var is_confirm_mode: bool = false

func _ready():
	"""初始化AI生成器"""
	_initialize_ai_config()
	_initialize_http_client()
	_initialize_confirm_timer()

func _initialize_ai_config():
	"""初始化AI配置"""
	# 初始化配置加载器（参考story_dialog_save_manager.gd）
	config_loader = preload("res://scripts/ai_chat/ai_config_loader.gd").new()
	add_child(config_loader)
	config_loader.load_all()

	# 获取配置和API密钥
	api_key = config_loader.api_key
	config = config_loader.config

func _initialize_http_client():
	"""初始化HTTP客户端"""
	ai_http_client = preload("res://scripts/ai_chat/ai_http_client.gd").new()
	add_child(ai_http_client)

	# 连接流式响应信号
	ai_http_client.stream_chunk_received.connect(_on_stream_chunk_received)
	ai_http_client.stream_completed.connect(_on_stream_completed)
	ai_http_client.stream_error.connect(_on_stream_error)

func _initialize_confirm_timer():
	"""初始化确认计时器"""
	confirm_timer = Timer.new()
	add_child(confirm_timer)
	confirm_timer.wait_time = 3.0
	confirm_timer.one_shot = true
	confirm_timer.timeout.connect(_on_confirm_timeout)

func set_story_creation_panel(panel: Control):
	"""设置故事创建面板引用"""
	story_creation_panel = panel

func generate_story_from_keywords(keywords: String):
	"""根据关键词生成故事"""
	if is_generating:
		push_warning("AI生成正在进行中，请等待完成")
		return

	# 检查输入框是否有内容
	var has_content = _has_input_content()

	if has_content and not is_confirm_mode:
		# 进入确认模式
		is_confirm_mode = true
		_update_generate_button_state(false, "清空并生成")
		confirm_timer.start()
		return

	# 退出确认模式（如果在确认模式中）
	if is_confirm_mode:
		is_confirm_mode = false
		confirm_timer.stop()

	if api_key.is_empty() or not config.has("summary_model"):
		var error_msg = "AI配置不完整，请检查配置"
		_handle_generation_error(error_msg)
		return

	# 清空当前内容
	_clear_input_fields()

	# 设置生成状态
	is_generating = true
	current_title = ""
	current_summary = ""
	full_response_content = ""

	# 更新按钮状态
	_update_generate_button_state(true, "生成中...")

	# 发送生成信号
	generation_started.emit()

	# 调用AI生成API
	_call_story_generation_api(keywords)

func _clear_input_fields():
	"""清空输入框"""
	if story_creation_panel:
		story_creation_panel.title_input.text = ""
		story_creation_panel.summary_input.text = ""

func _has_input_content() -> bool:
	"""检查输入框是否有内容"""
	if not story_creation_panel:
		return false

	var title_text = story_creation_panel.title_input.text.strip_edges() if story_creation_panel.title_input else ""
	var summary_text = story_creation_panel.summary_input.text.strip_edges() if story_creation_panel.summary_input else ""

	return not title_text.is_empty() or not summary_text.is_empty()

func _update_generate_button_state(disabled: bool, text: String = ""):
	"""更新生成按钮状态"""
	print("_update_generate_button_state 被调用: disabled=", disabled, ", text='", text, "'")
	if story_creation_panel and story_creation_panel.generate_button:
		print("更新按钮状态: disabled=", disabled, ", text='", text, "'")
		story_creation_panel.generate_button.disabled = disabled
		if not text.is_empty():
			story_creation_panel.generate_button.text = text
	else:
		print("警告：story_creation_panel 或 generate_button 为 null")

func _call_story_generation_api(keywords: String):
	"""调用故事生成API"""
	var story_config = config.summary_model
	var model = story_config.model
	var base_url = story_config.base_url

	if model.is_empty() or base_url.is_empty():
		var error_msg = "故事生成模型配置不完整"
		_handle_generation_error(error_msg)
		return

	# 构建系统提示词
	var system_prompt = _build_story_generation_system_prompt()

	# 构建用户提示词
	var user_prompt = _build_story_generation_user_prompt(keywords)

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}
	]

	var url = base_url + "/chat/completions"
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]

	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": 512,
		"temperature": 0.8,
		"top_p": 0.9,
		"enable_thinking": false,
		"stream": true  # 启用流式响应
	}

	var json_body = JSON.stringify(body)

	# 启动流式请求
	ai_http_client.start_stream_request(url, headers, json_body)

func _build_story_generation_system_prompt() -> String:
	"""构建故事生成系统提示词"""
	# 获取角色信息
	var save_mgr = get_node("/root/SaveManager")
	var character_name = save_mgr.get_character_name()
	var user_name = save_mgr.get_user_name()

	var prompt = """你是一个故事生成助手。请根据用户提供的关键词，创作一个引人入胜的故事开头，不超过50字。
人物信息：两个主角名字是“{character_name}”和“{user_name}”。
要求：第一行是标题，然后用一个空行分隔，后面是开头正文内容。禁止使用markdown。参考格式：
故事标题

这是故事的开头，根据关键词创作。
"""
	prompt = prompt.format({
		"character_name": character_name,
		"user_name": user_name
	})

	return prompt

func _build_story_generation_user_prompt(keywords: String) -> String:
	"""构建故事生成用户提示词"""
	var prompt = "请根据以下关键词创作故事："

	if not keywords.strip_edges().is_empty():
		prompt += "\n关键词：" + keywords
	else:
		prompt += "\n（无特定关键词，请自由创作）"

	return prompt

func _on_stream_chunk_received(data: String):
	"""处理流式数据块"""
	if not is_generating:
		print("收到数据块但is_generating为false，忽略: " + data.substr(0, 100) + "...")
		return

	# 解析流式数据
	var parsed_data = _parse_stream_data(data)
	if parsed_data.is_empty():
		return

	# 累积完整响应内容
	full_response_content += parsed_data
	print("累积响应内容长度: ", full_response_content.length())

	# 解析标题和简介
	_parse_and_display_content(full_response_content)

func _parse_stream_data(data: String) -> String:
	"""解析流式响应数据"""
	# 处理SSE格式的数据
	if data.begins_with("data: "):
		var json_str = data.substr(6).strip_edges()
		if json_str == "[DONE]":
			print("收到[DONE]标记，流式响应结束")
			# 直接标记生成完成，不等待_http_client的信号
			_finalize_generation()
			return ""

		var json = JSON.new()
		if json.parse(json_str) == OK:
			var response_data = json.data
			if response_data.has("choices") and response_data.choices.size() > 0:
				var choice = response_data.choices[0]

				# 检查是否是结束chunk（包含finish_reason）
				if choice.has("finish_reason") and choice.finish_reason == "stop":
					print("收到finish_reason=stop，流式响应结束")
					_finalize_generation()
					return ""

				# 处理正常的内容delta
				if choice.has("delta") and choice.delta.has("content"):
					var content = choice.delta.content
					return content

	print("无法解析的数据: " + data)
	return ""

func _parse_and_display_content(content: String):
	"""解析并显示内容"""
	var lines = content.split("\n", false)

	# 找到第一行非空行作为标题
	var title_line = ""
	var summary_start_index = -1

	# 遍历所有行，找到标题和空行分隔符
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if not line.is_empty():
			if title_line.is_empty():
				# 找到第一行非空内容，作为标题
				title_line = line
				# 继续查找空行分隔符
				for j in range(i + 1, lines.size()):
					if lines[j].strip_edges().is_empty():
						summary_start_index = j + 1
						break
				break

	# 如果没找到空行分隔符，检查是否有足够的内容行
	if summary_start_index == -1 and lines.size() > 1:
		summary_start_index = 1

	# 收集简介内容
	var summary_lines = []
	if summary_start_index >= 0 and summary_start_index < lines.size():
		for i in range(summary_start_index, lines.size()):
			var line = lines[i]
			# 只添加非空行到简介，如果是空行则停止（避免添加多余的空行）
			if line.strip_edges().is_empty() and summary_lines.size() > 0:
				break
			summary_lines.append(line)

	# 处理标题
	var processed_title = _process_title(title_line)

	# 处理简介
	var processed_summary = "\n".join(summary_lines).strip_edges()

	# 更新当前内容
	current_title = processed_title
	current_summary = processed_summary

	# 显示到UI
	_display_content(processed_title, processed_summary)

func _process_title(raw_title: String) -> String:
	"""处理标题格式"""
	var title = raw_title.strip_edges()

	# 去除markdown标题标记
	if title.begins_with("#"):
		title = title.substr(1).strip_edges()
		# 处理多级标题
		while title.begins_with("#"):
			title = title.substr(1).strip_edges()

	# 去除书名号
	title = title.replace("《", "").replace("》", "")

	return title

func _display_content(title: String, summary: String):
	"""显示内容到UI"""
	if not story_creation_panel:
		return

	if story_creation_panel.title_input:
		story_creation_panel.title_input.text = title

	if story_creation_panel.summary_input:
		story_creation_panel.summary_input.text = summary

func _finalize_generation():
	"""最终化生成过程（统一处理完成逻辑）"""
	print("进入_finalize_generation函数，is_generating = ", is_generating)

	# 如果已经完成，防止重复调用
	if not is_generating:
		print("is_generating为false，跳过重复的完成处理")
		return

	# 标记为已完成，防止重复调用
	is_generating = false
	print("设置is_generating = false")

	# 停止流式传输（如果还在进行中）
	if ai_http_client:
		ai_http_client.stop_streaming()

	# 调试：打印完整响应
	print("=== AI生成完成 ===")
	print("完整响应内容:")
	print("---")
	print(full_response_content)
	print("---")
	print("解析结果:")
	print("标题: '" + current_title + "'")
	print("简介: '" + current_summary + "'")
	print("==================")

	# 恢复按钮状态
	_update_generate_button_state(false, "生成故事")

	# 发送完成信号
	generation_completed.emit(current_title, current_summary)

func _on_stream_completed():
	"""流式响应完成（由HTTP客户端调用）"""
	print("HTTP客户端报告流式响应完成，调用_finalize_generation")
	_finalize_generation()

func _on_stream_error(error_message: String):
	"""流式响应错误"""
	_handle_generation_error(error_message)

func _handle_generation_error(error_message: String):
	"""处理生成错误"""
	is_generating = false
	full_response_content = ""  # 清空响应内容

	# 恢复按钮状态
	_update_generate_button_state(false, "生成故事")

	# 将错误信息显示到简介框
	if story_creation_panel and story_creation_panel.summary_input:
		story_creation_panel.summary_input.text = "生成失败：\n" + error_message

	# 发送错误信号
	generation_error.emit(error_message)

func stop_generation():
	"""停止生成过程"""
	if is_generating:
		is_generating = false
		full_response_content = ""  # 清空响应内容
		ai_http_client.stop_streaming()
		_update_generate_button_state(false, "生成故事")

func _on_confirm_timeout():
	"""确认计时器超时"""
	is_confirm_mode = false
	_update_generate_button_state(false, "生成故事")
