extends Node
class_name StoryAI

signal reply_ready(text: String)
signal text_chunk_ready(chunk: String)
signal streaming_completed()
signal error_occurred(error_message: String)
signal streaming_interrupted(error_message: String, partial_content: String)
signal request_error_occurred(error_message: String)

# 配置和API密钥管理
var config_loader: Node
var api_key: String = ""
var config: Dictionary = {}

# 短期上下文（对话历史）- 用于AI API上下文
var conversation_history: Array = []
var max_history_count: int = 20  # 故事模式携带20条上下文

# 显示历史（完整的消息）- 保留完整记录，但限制大小防止内存泄漏
var display_history: Array = []
const MAX_DISPLAY_HISTORY_SIZE: int = 1000  # 最大显示历史条数

# AI HTTP客户端（用于真正的流式输出）
var ai_http_client: Node

# 日志记录器
var logger: Node

func _ready():
	# 初始化配置加载器
	config_loader = preload("res://scripts/ai_chat/ai_config_loader.gd").new()
	add_child(config_loader)
	config_loader.load_all()

	# 获取配置和API密钥
	api_key = config_loader.api_key
	config = config_loader.config

	# 初始化日志记录器
	logger = preload("res://scripts/ai_chat/ai_logger.gd").new()
	add_child(logger)

	# 创建AI HTTP客户端（用于真正的流式输出）
	ai_http_client = preload("res://scripts/ai_chat/ai_http_client.gd").new()
	add_child(ai_http_client)
	ai_http_client.stream_chunk_received.connect(_on_stream_chunk_received)
	ai_http_client.stream_completed.connect(_on_stream_completed)
	ai_http_client.stream_error.connect(_on_stream_error)

func request_reply(prompt: String, story_context: Dictionary = {}):
	"""请求AI回复（异步）

	Args:
		prompt: 用户输入的提示词
		story_context: 故事上下文，包含故事相关信息
	"""
	if api_key.is_empty():
		request_error_occurred.emit("API密钥未配置")
		return

	# 异步处理请求
	_handle_request_async(prompt, story_context)

func _handle_request_async(prompt: String, story_context: Dictionary):
	"""异步处理请求"""
	# 构建系统提示词
	var story_data = story_context.get("story_data", {})
	var current_node_id = story_context.get("current_node_id", "")
	var system_prompt = _build_system_prompt(story_data, current_node_id, story_context)

	# 构建消息列表
	var messages = [{"role": "system", "content": system_prompt}]

	# 添加短期上下文（限制数量）
	var history_to_send = _get_limited_history()
	for msg in history_to_send:
		messages.append(msg)

	# 添加当前用户消息
	messages.append({"role": "user", "content": prompt})

	# 记录请求日志
	logger.log_api_request("STORY_AI_REQUEST", {"messages": messages}, JSON.stringify({"messages": messages}))

	# 调用AI API（异步）
	await _call_ai_api_async(messages, prompt)

func _build_system_prompt(story_data: Dictionary, _current_node_id: String, story_context: Dictionary) -> String:
	"""构建系统提示词

	Args:
		story_data: 完整的故事文件数据
		current_node_id: 当前节点ID
	"""

	var save_mgr = get_node("/root/SaveManager")

	# 获取基本信息
	var character_name = save_mgr.get_character_name()
	var user_name = save_mgr.get_user_name()
	var user_address = save_mgr.get_user_address()

	var prompt_parts = []

	# 1. 基础提示词（身份设定）
	var base_prompt = """##身份设定
你是人类，女，白色中短发，淡蓝色眼睛。你的名字是“{character_name}”。用户的名字是“{user_name}”
"""
	base_prompt = base_prompt.format({
		"character_name": character_name,
		"user_name": user_name,
		"user_address": user_address
	})
	prompt_parts.append(base_prompt)

	# 2. 故事简介
	var story_summary = story_data.get("story_summary", "")
	if not story_summary.is_empty():
		prompt_parts.append("## 故事简介\n" + story_summary)

	# 3. 经历的节点（从上下文获取，避免重复计算）
	var experienced_nodes = story_context.get("experienced_nodes", [])
	if not experienced_nodes.is_empty():
		var nodes_text = "## 经历的故事节点\n"
		for node in experienced_nodes:
			nodes_text += node.display_text + "\n"
		prompt_parts.append(nodes_text)

	return "\n".join(prompt_parts)


func _get_limited_history() -> Array:
	"""获取限制数量的短期上下文（超出部分不携带但不要删除）"""
	var history_to_send = []
	var start_index = max(0, conversation_history.size() - max_history_count)

	for i in range(start_index, conversation_history.size()):
		history_to_send.append({
			"role": conversation_history[i].role,
			"content": conversation_history[i].content
		})

	return history_to_send

func _call_ai_api_async(messages: Array, user_prompt: String):
	"""异步调用AI API（真正的流式输出）"""
	# 确保ai_http_client已初始化
	if ai_http_client == null:
		ai_http_client = preload("res://scripts/ai_chat/ai_http_client.gd").new()
		add_child(ai_http_client)
		ai_http_client.stream_chunk_received.connect(_on_stream_chunk_received)
		ai_http_client.stream_completed.connect(_on_stream_completed)
		ai_http_client.stream_error.connect(_on_stream_error)

	var chat_config = config.chat_model
	var url = chat_config.base_url + "/chat/completions"

	# 构建请求体
	var body = {
		"model": chat_config.model,
		"messages": messages,
		"max_tokens": int(chat_config.max_tokens),
		"temperature": float(chat_config.temperature),
		"top_p": float(chat_config.top_p),
		"stream": true,  # 流式响应
		"enable_thinking": false
	}

	var json_body = JSON.stringify(body)

	# 构建请求头
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]

	# 存储请求信息用于后续处理
	ai_http_client.set_meta("user_prompt", user_prompt)
	ai_http_client.set_meta("messages", messages)
	ai_http_client.set_meta("request_body", body)

	# 重置流式变量
	streaming_full_reply = ""
	streaming_buffer = ""

	# 启动流式请求
	ai_http_client.start_stream_request(url, headers, json_body, 30.0)

	# 等待流式响应完成
	await ai_http_client.stream_completed

var streaming_buffer: String = ""  # 流式响应缓冲区
var streaming_full_reply: String = ""  # 完整的回复内容

func _on_stream_chunk_received(chunk_text: String):
	"""处理接收到的流式数据块"""
	streaming_buffer += chunk_text

	# 处理完整的行
	var lines = streaming_buffer.split("\n", false)
	var lines_array = Array(lines)  # 转换为Array以便使用Array方法

	# 保留不完整的行（最后一行如果没有换行符）
	if lines_array.size() > 0:
		var last_line = lines_array.back()
		if not streaming_buffer.ends_with("\n"):
			streaming_buffer = last_line
			lines_array.pop_back()  # 移除不完整的行
		else:
			streaming_buffer = ""
	else:
		streaming_buffer = ""

	for line in lines_array:
		line = line.strip_edges()
		if line.is_empty():
			continue

		# 检查是否是数据行
		if line.begins_with("data: "):
			var data = line.substr(6)  # 移除"data: "前缀

			# 检查是否是结束标记
			if data == "[DONE]":
				# 流式响应完成
				_finalize_streaming_response()
				return

			# 解析JSON数据
			var json = JSON.new()
			if json.parse(data) == OK:
				var chunk_data = json.data

				# 提取内容
				if chunk_data.has("choices") and chunk_data.choices.size() > 0:
					var choice = chunk_data.choices[0]
					if choice.has("delta") and choice.delta.has("content"):
						var content = choice.delta.content
						if not content.is_empty():
							streaming_full_reply += content
							# 实时发送文本块信号
							text_chunk_ready.emit(content)

func _on_stream_completed():
	"""流式响应完成"""
	_finalize_streaming_response()

func _on_stream_error(error_message: String):
	"""流式响应错误"""
	# 根据是否收到内容来决定错误处理方式
	if streaming_full_reply.strip_edges().is_empty():
		# 没有收到任何内容，当作请求错误处理（撤回用户输入）
		request_error_occurred.emit("请求失败: " + error_message)
	else:
		# 收到部分内容，当作响应中断处理
		streaming_interrupted.emit("响应中断: " + error_message, streaming_full_reply)

func _finalize_streaming_response():
	"""完成流式响应处理"""
	if ai_http_client == null:
		request_error_occurred.emit("AI HTTP客户端未初始化")
		return

	# 处理缓冲区中剩余的数据
	if not streaming_buffer.is_empty():
		var lines = streaming_buffer.split("\n", false)
		var lines_array = Array(lines)
		for line in lines_array:
			line = line.strip_edges()
			if line.begins_with("data: "):
				var data = line.substr(6)
				if data == "[DONE]":
					break

				var json = JSON.new()
				if json.parse(data) == OK:
					var chunk_data = json.data
					if chunk_data.has("choices") and chunk_data.choices.size() > 0:
						var choice = chunk_data.choices[0]
						if choice.has("delta") and choice.delta.has("content"):
							var content = choice.delta.content
							if not content.is_empty():
								streaming_full_reply += content
								text_chunk_ready.emit(content)

	# 记录响应日志
	var messages = ai_http_client.get_meta("messages", [])
	logger.log_api_call("STORY_AI_RESPONSE", messages, streaming_full_reply)

	# 添加到AI上下文历史
	var user_prompt = ai_http_client.get_meta("user_prompt", "")
	if not user_prompt.is_empty():
		conversation_history.append({"role": "user", "content": user_prompt})
		conversation_history.append({"role": "assistant", "content": streaming_full_reply})

	# 限制AI上下文历史记录总数
	if conversation_history.size() > max_history_count * 2:
		var keep_count = max_history_count
		conversation_history = conversation_history.slice(-keep_count)

	# 发送完整回复信号
	reply_ready.emit(streaming_full_reply)
	streaming_completed.emit()

func add_to_display_history(role: String, content: String):
	"""添加到显示历史（分句后的消息记录）"""
	display_history.append({"role": role, "content": content})

	# 限制显示历史大小，防止内存泄漏
	if display_history.size() > MAX_DISPLAY_HISTORY_SIZE:
		# 保留最新的80%历史记录
		var keep_count = int(MAX_DISPLAY_HISTORY_SIZE * 0.8)
		display_history = display_history.slice(-keep_count)
		print("显示历史超出限制，已清理旧记录，当前大小: ", display_history.size())

func get_display_history() -> Array:
	"""获取显示历史"""
	return display_history.duplicate()

func clear_history():
	"""清空所有对话历史"""
	conversation_history.clear()
	display_history.clear()

func remove_last_user_from_display_history():
	"""从显示历史中移除最后一条用户消息"""
	if not display_history.is_empty() and display_history.back().role == "user":
		display_history.pop_back()

func set_story_context(_story_context: Dictionary):
	"""设置故事上下文（可用于更新提示词中的故事信息）"""
	# 这里可以存储故事上下文，用于后续的提示词构建
	pass
