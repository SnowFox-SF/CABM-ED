extends Node

# 提示词构建器 - 负责构建 AI 对话的系统提示词
# 自动加载单例

var config: Dictionary = {}

func _should_perform_kg_search() -> bool:
	"""检查是否应该进行知识图谱检索"""
	var ai_config_mgr = get_node_or_null("/root/AIConfigManager")
	if ai_config_mgr:
		var memory_config = ai_config_mgr.load_memory_config()
		return memory_config.get("enable_kg_search", true)
	return true  # 默认启用

func _ready():
	_load_config()

func _load_config():
	"""加载 AI 配置"""
	var config_path = "res://config/ai_config.json"
	if not FileAccess.file_exists(config_path):
		push_error("AI 配置文件不存在")
		return
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		config = json.data
		print("PromptBuilder: AI 配置加载成功")
	else:
		push_error("PromptBuilder: AI 配置解析失败")

func build_system_prompt(trigger_mode: String = "passive", keep_long_term_memory_placeholder: bool = false) -> String:
	"""构建系统提示词
	
	Args:
		trigger_mode: 触发模式
		keep_long_term_memory_placeholder: 是否保留长期记忆占位符（用于后续填充）
	"""
	if config.is_empty():
		push_error("PromptBuilder: 配置未加载")
		return ""
	
	var save_mgr = get_node("/root/SaveManager")
	
	# 从存档读取角色名称
	var character_name = save_mgr.get_character_name()
	
	# 从存档系统读取用户名
	var user_name = save_mgr.get_user_name()
	
	# 获取记忆上下文
	var memory_context = get_memory_context()
	
	# 获取关系上下文
	var relationship_context = get_relationship_context()
	
	# 从mood_config.json生成moods列表
	var moods = _generate_moods_list()
	
	# 获取触发上下文
	var trigger_context = _get_trigger_context(trigger_mode)
	
	# 获取好感度和交互意愿
	var affection = save_mgr.get_affection()
	var interaction_will = save_mgr.get_reply_willingness()
	
	# 转换为描述文本
	var affection_level = _convert_affection_to_text(affection)
	var interaction_level = _convert_willingness_to_text(interaction_will)
	
	# 获取当前心情的文字描述
	var current_mood = get_current_mood_name(save_mgr.get_mood())
	
	# 格式化当前时间
	var current_time = _format_current_time()
	
	# 生成场景列表
	var scenes_list = _generate_scenes_list()
	
	# 从存档系统读取用户称呼
	var user_address = save_mgr.get_user_address()
	
	# 加载角色预设配置，获取prompt字段
	var character_preset = _load_character_preset()
	var character_prompt = character_preset.get("prompt", "")
	
	# 获取回复风格
	var response_style = _get_response_style()
	
	# 准备所有占位符的替换字典
	var replacements = {
		"{character_name}": character_name,
		"{user_name}": user_name,
		"{user_address}": user_address,
		"{current_scene}": _get_scene_description(save_mgr.get_character_scene()),
		"{current_weather}": _get_weather_description(save_mgr.get_current_weather()),
		"{long_term_memory}": "{long_term_memory}" if keep_long_term_memory_placeholder else "", # 保留或清空
		"{knowledge_memory}": "{knowledge_memory}" if keep_long_term_memory_placeholder else "", # 知识图谱占位符
		"{memory_context}": memory_context,
		"{relationship_context}": relationship_context,
		"{moods}": moods,
		"{trigger_context}": trigger_context,
		"{affection_level}": affection_level,
		"{interaction_level}": interaction_level,
		"{current_mood}": current_mood,
		"{current_time}": current_time,
		"{scenes}": scenes_list,
		"{character_prompt}": character_prompt,
		"{response_style}": response_style
	}
	
	# 检查使用哪种配置方式
	var prompt = ""
	
	if config.chat_model.has("prompt_frameworks") and config.chat_model.has("prompt_fields"):
		# 使用新的框架系统
		var framework_name = config.chat_model.get("prompt_framework", "default")
		var frameworks = config.chat_model.prompt_frameworks
		var fields = config.chat_model.prompt_fields
		
		if not frameworks.has(framework_name):
			push_error("PromptBuilder: 未找到框架 '%s'，使用 default" % framework_name)
			framework_name = "default"
		
		var framework = frameworks[framework_name]
		prompt = _build_prompt_from_framework(framework, fields, replacements)
	elif config.chat_model.has("system_prompt"):
		# 兼容旧的单一字符串配置
		prompt = config.chat_model.system_prompt
		prompt = _replace_placeholders(prompt, replacements)
		
	else:
		push_error("PromptBuilder: 未找到任何提示词配置")
		return ""
	
	return prompt

func _build_prompt_from_framework(framework: Array, fields: Dictionary, replacements: Dictionary) -> String:
	"""根据框架和字段构建提示词"""
	var parts = []
	
	for item in framework:
		var field_name = item.get("field", "")
		var title = item.get("title", null)
		
		if not fields.has(field_name):
			push_warning("PromptBuilder: 字段 '%s' 不存在，跳过" % field_name)
			continue
		
		var field_content = fields[field_name]
		# 替换占位符
		field_content = _replace_placeholders(field_content, replacements)
		
		# 如果有标题，添加二级标题
		if title != null and not title.is_empty():
			parts.append("## " + title + "\n" + field_content)
		else:
			parts.append(field_content)
	
	return "\n".join(parts)

func _replace_placeholders(text: String, replacements: Dictionary) -> String:
	"""替换文本中的占位符"""
	var result = text
	for placeholder in replacements:
		result = result.replace(placeholder, replacements[placeholder])
	return result

func _generate_moods_list() -> String:
	"""从mood_config.json生成moods列表字符串"""
	var mood_config_path = "res://config/mood_config.json"
	if not FileAccess.file_exists(mood_config_path):
		# 如果配置文件不存在，使用默认值
		return "0=平静, 1=开心, 2=难过, 3=生气, 4=惊讶, 5=害怕, 6=厌恶"
	
	var file = FileAccess.open(mood_config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return "0=平静, 1=开心, 2=难过, 3=生气, 4=惊讶, 5=害怕, 6=厌恶"
	
	var mood_config = json.data
	if not mood_config.has("moods"):
		return "0=平静, 1=开心, 2=难过, 3=生气, 4=惊讶, 5=害怕, 6=厌恶"
	
	var moods_array = []
	for mood in mood_config.moods:
		moods_array.append("%d=%s" % [mood.id, mood.name])
	
	return ", ".join(moods_array)

func _generate_scenes_list() -> String:
	"""从scenes.json生成场景列表字符串"""
	var scenes_config = _load_scenes_config()
	if not scenes_config.has("scenes"):
		return "0=客厅, 1=卧室, 2=浴室, 3=书房"
	
	# 获取排序后的场景ID列表，确保顺序一致
	var scene_ids = scenes_config.scenes.keys()
	scene_ids.sort()
	
	var scenes_array = []
	var index = 0
	for scene_id in scene_ids:
		var scene_name = scenes_config.scenes[scene_id].get("name", scene_id)
		scenes_array.append("%d=%s" % [index, scene_name])
		index += 1
	
	return ", ".join(scenes_array)

func get_scene_id_by_index(index: int) -> String:
	"""根据索引获取场景ID"""
	var scenes_config = _load_scenes_config()
	if not scenes_config.has("scenes"):
		return ""
	
	# 获取排序后的场景ID列表，确保与_generate_scenes_list()顺序一致
	var scene_ids = scenes_config.scenes.keys()
	scene_ids.sort()
	
	if index >= 0 and index < scene_ids.size():
		return scene_ids[index]
	
	return ""

func _load_character_preset() -> Dictionary:
	"""加载当前服装的角色预设配置"""
	var save_mgr = get_node("/root/SaveManager")
	var costume_id = save_mgr.get_costume_id()
	
	var config_path = "res://config/character_presets/%s.json" % costume_id
	if not FileAccess.file_exists(config_path):
		print("PromptBuilder: 角色预设配置文件不存在: %s" % config_path)
		return {}
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		return json.data
	return {}

func _get_scene_description(scene_id: String) -> String:
	"""获取场景描述（从配置文件读取）"""
	var scenes_config = _load_scenes_config()
	if scenes_config.has("scenes") and scenes_config.scenes.has(scene_id):
		return scenes_config.scenes[scene_id].get("name", "未知场景")
	return "未知场景"

func _get_weather_description(weather_id: String) -> String:
	"""获取天气描述（从配置文件读取）"""
	var scenes_config = _load_scenes_config()
	
	# 从全局 weathers 配置中读取
	if scenes_config.has("weathers") and scenes_config.weathers.has(weather_id):
		return scenes_config.weathers[weather_id]
	
	# 如果找不到，返回默认值
	return "晴天"

func _load_scenes_config() -> Dictionary:
	"""加载场景配置"""
	var config_path = "res://config/scenes.json"
	if not FileAccess.file_exists(config_path):
		return {}
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		return json.data
	return {}

func _convert_affection_to_text(affection: int) -> String:
	"""将好感度数值转换为描述文本"""
	# TODO: 根据需要自定义好感度描述
	var percentage = float(affection) / 100.0
	if percentage >= 0.8:
		return "高，愿意进行亲密互动"
	elif percentage >= 0.6:
		return "高"
	elif percentage >= 0.4:
		return "中"
	elif percentage >= 0.2:
		return "低"
	else:
		return "低，有些反感"

func _convert_willingness_to_text(willingness: int) -> String:
	"""将回复意愿数值转换为描述文本"""
	var percentage = float(willingness) / 100.0
	if percentage >= 0.8:
		return "高，乐意交流"
	elif percentage >= 0.6:
		return "中，愿意交流"
	elif percentage >= 0.4:
		return "中，略显冷漠"
	elif percentage >= 0.2:
		return "中，比较冷淡"
	else:
		return "低，不想互动"

func get_current_mood_name(mood_id: String) -> String:
	"""获取当前心情的中文名称"""
	var mood_config_path = "res://config/mood_config.json"
	if not FileAccess.file_exists(mood_config_path):
		return "平静"
	
	var file = FileAccess.open(mood_config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return "平静"
	
	var mood_config = json.data
	if not mood_config.has("moods"):
		return "平静"
	
	for mood in mood_config.moods:
		if mood.name_en == mood_id:
			return mood.name
	
	return "平静"

func _format_current_time() -> String:
	"""格式化当前时间为"xx月xx日xx:xx，星期x"格式"""
	var datetime = Time.get_datetime_dict_from_system()
	
	var weekdays = ["日", "一", "二", "三", "四", "五", "六"]
	var weekday = weekdays[datetime.weekday]
	
	return "%d月%d日%02d:%02d，星期%s" % [
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		weekday
	]

func _get_trigger_context(trigger_mode: String) -> String:
	"""获取触发上下文文本"""
	
	var trigger_contexts = config.chat_model.trigger_contexts
	var context = trigger_contexts.get(trigger_mode, "你在和{user_name}聊天。")
	
	var save_mgr = get_node("/root/SaveManager")
	
	# 如果trigger_context中包含{user_name}占位符，需要替换
	if context.contains("{user_name}"):
		var user_name = save_mgr.get_user_name()
		context = context.replace("{user_name}", user_name)
	
	# 如果trigger_context中包含{current_scene}占位符，需要替换
	if context.contains("{current_scene}"):
		var current_scene = save_mgr.get_character_scene()
		var scene_name = _get_scene_description(current_scene)
		context = context.replace("{current_scene}", scene_name)
	
	# 如果trigger_context中包含{character_scene}占位符，需要替换
	if context.contains("{character_scene}"):
		var old_scene = ""
		if save_mgr.has_meta("character_old_scene"):
			old_scene = save_mgr.get_meta("character_old_scene")
			# 使用后清除，避免影响后续对话
			save_mgr.remove_meta("character_old_scene")
		else:
			# 如果没有保存旧场景，使用当前场景（兜底）
			old_scene = save_mgr.get_character_scene()
		
		var old_scene_name = _get_scene_description(old_scene)
		context = context.replace("{character_scene}", old_scene_name)
	
	return context

func get_memory_context() -> String:
	"""获取记忆上下文（仅从中期记忆）"""
	var save_mgr = get_node("/root/SaveManager")
	
	# 确保 ai_data 字段存在
	if not save_mgr.save_data.has("ai_data"):
		save_mgr.save_data.ai_data = {
			"memory": [],
			"accumulated_summary_count": 0,
			"relationship_history": []
		}
	
	var memories = save_mgr.save_data.ai_data.memory
	
	if memories.is_empty():
		return "（这是你们的第一次对话）"
	
	var context_lines = []
	for memory in memories:
		# timestamp 格式: "2024-01-15T14:30:00"
		# 提取为 "MM-DD HH:MM" 格式
		var timestamp_parts = memory.timestamp.split("T")
		if timestamp_parts.size() >= 2:
			var date_part = timestamp_parts[0] # "2024-01-15"
			var time_part = timestamp_parts[1] # "14:30:00"
			
			var date_components = date_part.split("-")
			var time_str = time_part.substr(0, 5) # "14:30"
			
			if date_components.size() >= 3:
				var month = date_components[1]
				var day = date_components[2]
				var formatted_time = "%s-%s %s" % [month, day, time_str]
				context_lines.append("[%s] %s" % [formatted_time, memory.content])
			else:
				# 如果日期格式不对，只显示时间
				context_lines.append("[%s] %s" % [time_str, memory.content])
		else:
			# 如果时间戳格式不对，直接显示内容
			context_lines.append("%s" % memory.content)
	
	return "\n".join(context_lines)

func get_relationship_context() -> String:
	"""获取关系上下文（从关系历史）"""
	var save_mgr = get_node("/root/SaveManager")
	
	# 确保字段存在
	if not save_mgr.save_data.has("ai_data"):
		save_mgr.save_data.ai_data = {
			"memory": [],
			"accumulated_summary_count": 0,
			"relationship_history": []
		}
	
	if not save_mgr.save_data.ai_data.has("relationship_history"):
		save_mgr.save_data.ai_data.relationship_history = []
	
	var relationship_history = save_mgr.save_data.ai_data.relationship_history
	
	if relationship_history.is_empty():
		return "（暂无关系信息）"
	
	# 只返回最新的关系描述
	var latest = relationship_history[-1]
	return latest.content

func get_mood_name_en(mood_id: int) -> String:
	"""根据mood ID获取英文名称"""
	var mood_config_path = "res://config/mood_config.json"
	if not FileAccess.file_exists(mood_config_path):
		return ""
	
	var file = FileAccess.open(mood_config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return ""
	
	var mood_config = json.data
	if not mood_config.has("moods"):
		return ""
	
	for mood in mood_config.moods:
		if mood.id == mood_id:
			return mood.name_en
	
	return ""


func build_offline_diary_prompt(start_time: String, end_time: String, event_count: int) -> String:
	"""构建离线日记生成提示词"""
	if config.is_empty():
		push_error("PromptBuilder: 配置未加载")
		return ""
	
	var save_mgr = get_node("/root/SaveManager")
	
	# 从存档读取角色名称
	var character_name = save_mgr.get_character_name()
	
	# 从存档系统读取用户名和称呼
	var user_name = save_mgr.get_user_name()
	var user_address = save_mgr.get_user_address()
	
	# 获取记忆上下文
	var memory_context = get_memory_context()
	
	# 准备所有占位符的替换字典
	var replacements = {
		"{character_name}": character_name,
		"{user_name}": user_name,
		"{user_address}": user_address,
		"{start_time}": start_time,
		"{end_time}": end_time,
		"{event_count}": str(event_count),
		"{memory_context}": memory_context
	}
	
	# 使用offline框架
	if config.chat_model.has("prompt_frameworks") and config.chat_model.has("prompt_fields"):
		var frameworks = config.chat_model.prompt_frameworks
		var fields = config.chat_model.prompt_fields
		
		if not frameworks.has("offline"):
			push_error("PromptBuilder: 未找到offline框架")
			return ""
		
		var framework = frameworks["offline"]
		return _build_prompt_from_framework(framework, fields, replacements)
	
	push_error("PromptBuilder: 未找到提示词配置")
	return ""


func build_system_prompt_with_long_term_memory(trigger_mode: String, user_input: String) -> String:
	"""构建包含长期记忆的系统提示词
	
	Args:
		trigger_mode: 触发模式
		user_input: 用户输入（用于检索相关记忆）
	
	Returns:
		完整的系统提示词
	"""
	# 先构建基础提示词（保留长期记忆占位符）
	var base_prompt = build_system_prompt(trigger_mode, true)
	
	# 检索长期记忆（短期/长期摘要）和知识图谱
	var long_term_memory = await _retrieve_long_term_memory(user_input)
	var knowledge_memory = _retrieve_knowledge_memory(user_input)

	# 替换占位符
	print("替换前占位符存在: long_term=%s, knowledge=%s" % [str(base_prompt.contains("{long_term_memory}")), str(base_prompt.contains("{knowledge_memory}"))])
	base_prompt = base_prompt.replace("{long_term_memory}", long_term_memory)
	base_prompt = base_prompt.replace("{knowledge_memory}", knowledge_memory)
	print("替换后占位符存在: long_term=%s, knowledge=%s" % [str(base_prompt.contains("{long_term_memory}")), str(base_prompt.contains("{knowledge_memory}"))])

	return base_prompt

func _retrieve_long_term_memory(query: String) -> String:
	"""检索长期记忆
	
	Args:
		query: 查询文本（通常是用户输入）
	
	Returns:
		格式化的长期记忆提示词
	"""
	# 首先尝试使用 MemoryManager（如果存在）
	var memory_prompt = ""
	if has_node("/root/MemoryManager"):
		var memory_mgr = get_node("/root/MemoryManager")
		# 等待记忆系统就绪
		if not memory_mgr.is_initialized:
			await memory_mgr.memory_system_ready

		# 如果查询为空，使用最近的对话上下文作为查询
		if query.strip_edges().is_empty():
			query = _get_recent_context_for_query()

		# 获取短期记忆的时间戳，用于排除
		var exclude_timestamps = _get_short_term_memory_timestamps()

		print("正在检索长期记忆（MemoryManager），查询: %s，排除最近 %d 条" % [query.substr(0, 50), exclude_timestamps.size()])
		memory_prompt = await memory_mgr.get_relevant_memory_for_chat(query, exclude_timestamps)

		if memory_prompt.is_empty():
			print("MemoryManager：未找到相关长期记忆")
		else:
			print("MemoryManager：找到长期记忆，长度: %d 字符" % memory_prompt.length())

	# 现在 _retrieve_long_term_memory 仅负责 MemoryManager 的检索，
	# 知识图谱检索已拆分到 _retrieve_knowledge_memory
	return memory_prompt


func _retrieve_knowledge_memory(query: String) -> String:
	"""检索知识图谱并返回格式化的知识记忆提示段（只包含KG部分）"""
	# 检查配置：是否应该进行知识图谱检索
	var should_perform_kg_search = _should_perform_kg_search()
	if not should_perform_kg_search:
		print("配置已禁用知识图谱检索，跳过KG检索")
		return ""

	if query.strip_edges().is_empty():
		query = _get_recent_context_for_query()

	var kg_prompt = ""

	# 提取关键词（debug 会在 keyword_extractor 中打印 tokens/keywords）
	var ke = preload("res://scripts/keyword_extractor.gd").new()
	var keywords = ke.extract_keywords(query, config.get("knowledge_memory", {}).get("query", {}).get("top_k", 6))
	print("[PromptBuilder] extracted keywords:", keywords)

	if keywords.is_empty():
		return ""

	# 查询知识图谱
	var mg = preload("res://scripts/memory_graph.gd").new()
	var top_k = config.get("knowledge_memory", {}).get("query", {}).get("top_k", 6)
	var graph_results = mg.query_by_keywords(keywords, top_k)

	if graph_results.is_empty():
		print("PromptBuilder: 知识图谱未检索到相关条目")
		return ""

	# 格式化为提示词段落
	var lines = []
	for r in graph_results:
		var t = r.get("T", "")
		var s = r.get("S", "")
		var p = r.get("P", "")
		var o = r.get("O", "")
		var i = r.get("I", 1)
		lines.append("[%s] %s %s %s (权重：%s)" % [t, s, p, o, str(i)])

	var mem_prompts = config.get("knowledge_memory", {}).get("prompts", {})
	var prefix = mem_prompts.get("memory_prefix", "")
	var suffix = mem_prompts.get("memory_suffix", "")
	kg_prompt = prefix + "\n".join(lines) + suffix

	print("PromptBuilder: 知识图谱检索到 %d 条记录" % graph_results.size())

	return kg_prompt

func _get_short_term_memory_timestamps() -> Array:
	"""获取短期记忆的时间戳列表，用于排除重复检索
	
	Returns:
		时间戳字符串数组，格式为 "YYYY-MM-DDTHH:MM:SS"
	"""
	var save_mgr = get_node("/root/SaveManager")
	
	# 确保 ai_data 字段存在
	if not save_mgr.save_data.has("ai_data"):
		return []
	
	var memories = save_mgr.save_data.ai_data.get("memory", [])
	var timestamps = []
	
	for memory in memories:
		if memory.has("timestamp"):
			timestamps.append(memory.timestamp)
	
	return timestamps

func _get_recent_context_for_query() -> String:
	"""获取最近的对话上下文用于记忆检索"""
	var save_mgr = get_node("/root/SaveManager")
	var history = save_mgr.get_conversation_history()
	
	if history.is_empty():
		return "日常对话"
	
	# 使用最近3轮对话作为上下文
	var recent_turns = []
	var start_idx = max(0, history.size() - 3)
	
	for i in range(start_idx, history.size()):
		var turn = history[i]
		recent_turns.append(turn.user + " " + turn.assistant)
	
	return " ".join(recent_turns)

func _get_response_style() -> String:
	"""获取回复风格文本"""
	# 从用户配置加载回复模式
	var response_mode = _load_response_mode()
	
	# 从ai_config.json获取对应的风格文本
	var response_styles = config.chat_model.response_style
	
	# 如果配置中不存在该模式，使用默认值
	if not response_styles.has(response_mode):
		response_mode = "verbal"
	
	return response_styles.get(response_mode, response_styles.verbal)

func _load_response_mode() -> String:
	"""从用户配置加载回复模式"""
	var config_path = "user://ai_keys.json"
	
	if not FileAccess.file_exists(config_path):
		return "verbal" # 默认为语言表达模式
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return "verbal"
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return "verbal"
	
	var user_config = json.data
	return user_config.get("response_mode", "verbal")
