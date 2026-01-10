extends Control

# 陪伴模式主场景脚本
# 处理陪伴模式的UI交互和场景切换

@onready var manager: CompanionModeManager = $CompanionModeManager
@onready var exit_button: Button = $ExitButton
@onready var welcome_label: Label = $WelcomeLabel

var audio_manager: Node = null
var save_manager: Node = null

func _ready():
	# 获取全局管理器引用
	if has_node("/root/SaveManager"):
		save_manager = get_node("/root/SaveManager")
	
	# 查找AudioManager（可能在主场景中）
	var main_scene = get_tree().root.get_node_or_null("Main")
	if main_scene and main_scene.has_node("AudioManager"):
		audio_manager = main_scene.get_node("AudioManager")
	
	# 连接管理器信号
	if manager:
		manager.session_started.connect(_on_session_started)
		manager.session_ended.connect(_on_session_ended)
	
	# 进入陪伴模式
	if manager:
		var success = manager.enter_companion_mode()
		if not success:
			print("无法进入陪伴模式")
			_return_to_previous_scene()
			return
	
	# 播放适合学习的背景音乐
	_play_study_music()
	
	# 显示欢迎提示
	_show_welcome_message()

func _on_session_started():
	"""会话开始时的处理"""
	print("陪伴会话已开始")

func _on_session_ended(summary: Dictionary):
	"""会话结束时的处理"""
	print("陪伴会话已结束")
	print("会话总结: ", summary)
	
	# 显示会话总结
	_show_session_summary(summary)

func _on_exit_button_pressed():
	"""退出按钮点击处理"""
	_show_exit_confirmation()

func _show_exit_confirmation():
	"""显示退出确认对话框"""
	var dialog = ConfirmationDialog.new()
	dialog.title = "退出陪伴模式"
	dialog.dialog_text = "确定要退出陪伴模式吗？\n所有数据将被保存。"
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	
	dialog.confirmed.connect(_confirm_exit)
	dialog.canceled.connect(func(): dialog.queue_free())
	
	add_child(dialog)
	dialog.popup_centered()

func _confirm_exit():
	"""确认退出"""
	if manager:
		var _summary = manager.exit_companion_mode()
		_return_to_previous_scene()

func _return_to_previous_scene():
	"""返回到之前的场景（书房）"""
	# 切换回主场景
	get_tree().change_scene_to_file("res://scripts/main.tscn")

func _play_study_music():
	"""播放适合学习的背景音乐"""
	if audio_manager and audio_manager.has_method("play_background_music"):
		# 播放书房场景的音乐
		audio_manager.play_background_music("studyroom", "day", "sunny")

func _show_welcome_message():
	"""显示欢迎提示"""
	if welcome_label:
		welcome_label.text = "欢迎进入陪伴模式\n让我陪你一起学习吧"
		
		# 3秒后淡出欢迎消息
		await get_tree().create_timer(3.0).timeout
		
		var tween = create_tween()
		tween.tween_property(welcome_label, "modulate:a", 0.0, 1.0)
		await tween.finished
		welcome_label.visible = false

func _show_session_summary(summary: Dictionary):
	"""显示会话总结"""
	var dialog = AcceptDialog.new()
	dialog.title = "会话总结"
	
	var duration_minutes = int(summary.duration / 60.0)
	var focus_minutes = int(summary.focus_duration / 60.0)
	
	var summary_text = "本次陪伴时长: %d 分钟\n" % duration_minutes
	summary_text += "专注时长: %d 分钟\n" % focus_minutes
	summary_text += "完成任务: %d 个\n" % summary.tasks_completed
	summary_text += "对话次数: %d 次" % summary.dialogue_count
	
	dialog.dialog_text = summary_text
	dialog.ok_button_text = "确定"
	
	dialog.confirmed.connect(func(): dialog.queue_free())
	
	add_child(dialog)
	dialog.popup_centered()
