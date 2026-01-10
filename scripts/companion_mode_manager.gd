extends Node
class_name CompanionModeManager

# 陪伴模式核心管理器
# 负责陪伴模式的生命周期和状态管理

signal session_started()
signal session_ended(summary: Dictionary)
signal mode_changed(new_mode: String)

# 会话数据
var current_session: Dictionary = {
	"session_id": "",
	"start_time": 0,
	"end_time": 0,
	"duration": 0,
	"focus_duration": 0,
	"break_count": 0,
	"tasks_completed": 0,
	"dialogue_count": 0,
	"tools_used": []
}

# 设置
var settings: Dictionary = {
	"dialogue_frequency": "medium",  # off/low/medium/high
	"default_bgm_type": "study_music",
	"default_timer_duration": 25,  # 分钟
	"animation_style": "calm",  # calm/lively
	"power_save_timeout": 300,  # 秒
	"screen_brightness": 0.7
}

# 引用
var save_manager: Node = null
var scene_manager: Node = null
var ui_manager: Node = null

# 状态
var is_active: bool = false
var previous_scene: String = ""

func _ready():
	# 获取全局管理器引用
	if has_node("/root/SaveManager"):
		save_manager = get_node("/root/SaveManager")
	if has_node("/root/UIManager"):
		ui_manager = get_node("/root/UIManager")
	
	# 加载设置
	load_settings()

func enter_companion_mode() -> bool:
	"""进入陪伴模式"""
	# 验证只能从书房进入
	if not _can_enter_companion_mode():
		print("无法进入陪伴模式：不在书房场景")
		return false
	
	print("进入陪伴模式")
	
	# 保存当前场景
	if scene_manager:
		previous_scene = scene_manager.current_scene
	
	# 保存游戏状态
	if save_manager:
		save_manager.save_game(save_manager.current_slot)
	
	# 初始化会话
	_initialize_session()
	
	# 标记为激活状态
	is_active = true
	
	# 发送信号
	session_started.emit()
	mode_changed.emit("companion")
	
	return true

func exit_companion_mode() -> Dictionary:
	"""退出陪伴模式，返回会话总结"""
	print("退出陪伴模式")
	
	# 结束会话
	_finalize_session()
	
	# 保存所有数据
	_save_all_data()
	
	# 获取会话总结
	var summary = get_session_summary()
	
	# 标记为非激活状态
	is_active = false
	
	# 发送信号
	session_ended.emit(summary)
	mode_changed.emit("normal")
	
	return summary

func _can_enter_companion_mode() -> bool:
	"""检查是否可以进入陪伴模式（必须在书房）"""
	if not scene_manager:
		# 如果没有场景管理器，尝试从父节点获取
		var main_scene = get_tree().current_scene
		if main_scene and main_scene.has_node("SceneManager"):
			scene_manager = main_scene.get_node("SceneManager")
	
	if scene_manager:
		return scene_manager.current_scene == "studyroom"
	
	# 如果无法获取场景管理器，检查SaveManager
	if save_manager:
		return save_manager.get_character_scene() == "studyroom"
	
	return false

func _initialize_session():
	"""初始化新会话"""
	var timestamp = Time.get_unix_time_from_system()
	var datetime = Time.get_datetime_dict_from_system()
	
	current_session = {
		"session_id": "session_%d%02d%02d_%02d%02d%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		],
		"start_time": timestamp,
		"end_time": 0,
		"duration": 0,
		"focus_duration": 0,
		"break_count": 0,
		"tasks_completed": 0,
		"dialogue_count": 0,
		"tools_used": []
	}
	
	print("会话已初始化: ", current_session.session_id)

func _finalize_session():
	"""结束当前会话"""
	var timestamp = Time.get_unix_time_from_system()
	current_session.end_time = timestamp
	current_session.duration = timestamp - current_session.start_time
	
	print("会话已结束: ", current_session.session_id)
	print("总时长: ", current_session.duration, " 秒")

func get_session_summary() -> Dictionary:
	"""获取会话总结"""
	return {
		"session_id": current_session.session_id,
		"duration": current_session.duration,
		"focus_duration": current_session.focus_duration,
		"tasks_completed": current_session.tasks_completed,
		"dialogue_count": current_session.dialogue_count,
		"tools_used": current_session.tools_used.duplicate()
	}

func update_session_stat(stat_name: String, value) -> void:
	"""更新会话统计数据"""
	if current_session.has(stat_name):
		if stat_name == "tools_used" and value is String:
			# 工具使用记录为数组
			if value not in current_session.tools_used:
				current_session.tools_used.append(value)
		else:
			current_session[stat_name] = value
		print("会话统计已更新: ", stat_name, " = ", value)

func load_settings() -> void:
	"""从SaveManager加载设置"""
	if not save_manager:
		print("SaveManager未找到，使用默认设置")
		return
	
	if save_manager.save_data.has("companion_settings"):
		var saved_settings = save_manager.save_data.companion_settings
		for key in saved_settings:
			if settings.has(key):
				settings[key] = saved_settings[key]
		print("陪伴模式设置已加载")
	else:
		print("未找到保存的设置，使用默认值")

func save_settings() -> void:
	"""保存设置到SaveManager"""
	if not save_manager:
		print("SaveManager未找到，无法保存设置")
		return
	
	save_manager.save_data.companion_settings = settings.duplicate()
	save_manager.save_game(save_manager.current_slot)
	print("陪伴模式设置已保存")

func _save_all_data() -> void:
	"""保存所有陪伴模式数据"""
	if not save_manager:
		print("SaveManager未找到，无法保存数据")
		return
	
	# 保存会话历史
	if not save_manager.save_data.has("companion_sessions"):
		save_manager.save_data.companion_sessions = []
	
	save_manager.save_data.companion_sessions.append(current_session.duplicate())
	
	# 只保留最近30个会话
	if save_manager.save_data.companion_sessions.size() > 30:
		save_manager.save_data.companion_sessions = save_manager.save_data.companion_sessions.slice(-30)
	
	# 保存设置
	save_manager.save_data.companion_settings = settings.duplicate()
	
	# 执行保存
	save_manager.save_game(save_manager.current_slot)
	print("陪伴模式数据已保存")

func get_previous_scene() -> String:
	"""获取进入陪伴模式前的场景"""
	return previous_scene if previous_scene != "" else "studyroom"
