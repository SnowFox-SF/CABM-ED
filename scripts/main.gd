extends Control

@onready var background: TextureRect = $Background
@onready var sidebar = $Sidebar
@onready var character = $Background/Character
@onready var chat_dialog = $ChatDialog
@onready var action_menu = $ActionMenu
@onready var scene_menu = $SceneMenu
@onready var right_click_area = $Background/RightClickArea
@onready var debug_helper = $CharacterDebugHelper
@onready var audio_manager = $AudioManager
@onready var character_diary_viewer = $CharacterDiaryViewer if has_node("CharacterDiaryViewer") else null
@onready var music_player_panel = $MusicPlayerPanel if has_node("MusicPlayerPanel") else null

# 管理器
var scene_manager: SceneManager
var ui_layout_manager: UILayoutManager
var message_display_manager: MessageDisplayManager
var interaction_handler: InteractionHandler
var game_state_manager: GameStateManager
var costume_manager: CostumeManager

# 存储动态创建的交互元素
var dynamic_elements = {}

func _ready():
	# 检查并迁移旧日记数据
	_check_and_migrate_diary()
	
	# 延迟检查离线位置变化，确保边栏已经初始化并连接了信号
	await get_tree().process_frame
	await get_tree().process_frame
	_check_pending_offline_position_change()
	
	# 初始化管理器
	await _setup_managers()
	
	# 连接信号
	_connect_signals()
	
	# 监听窗口大小变化
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# 等待侧边栏初始化完成
	await get_tree().process_frame
	
	# 加载初始场景
	var initial_scene = scene_manager.load_initial_scene()
	var initial_weather = sidebar.current_weather_id
	var initial_time = sidebar.current_time_id
	
	# 恢复播放列表
	audio_manager.restore_bgm_playlist_sync()
	
	# 加载场景
	await scene_manager.load_scene(initial_scene, initial_weather, initial_time)
	sidebar.set_current_scene(initial_scene)
	
	# 初始化UI布局
	await get_tree().process_frame
	ui_layout_manager.update_all_layouts()
	
	# 更新可交互元素显示状态
	_update_interactive_elements_visibility()
	
	
	# 播放背景音乐
	audio_manager.play_background_music(initial_scene, initial_time, initial_weather)
	# 探索断点恢复
	if has_node("/root/SaveManager"):
		var sm_resume = get_node("/root/SaveManager")
		if not sm_resume.has_meta("open_map_on_load"):
			if sm_resume.save_data.has("explore_checkpoint") and sm_resume.save_data.explore_checkpoint.get("active", false):
				get_tree().change_scene_to_file("res://scenes/explore_scene.tscn")
				return
	# 检查是否需要打开地图
	_check_open_map_on_load()
	# 检查是否需要打开死亡页面
	_check_open_death_on_load()

func _input(event):
	# 按 F12 打开存档调试面板
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		pass
		# _show_save_debug_panel()

func _setup_managers():
	"""初始化各种管理器"""
	await get_tree().process_frame
	
	var save_mgr = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	
	# 初始化场景管理器
	scene_manager = SceneManager.new()
	scene_manager.initialize(background, character, save_mgr)
	add_child(scene_manager)
	
	# 初始化UI布局管理器
	ui_layout_manager = UILayoutManager.new()
	ui_layout_manager.initialize(scene_manager)
	
	# 创建动态交互元素
	await _create_dynamic_elements()
	
	# 设置UI引用
	_set_ui_references()
	add_child(ui_layout_manager)
	
	# 初始化消息显示管理器
	message_display_manager = MessageDisplayManager.new()
	message_display_manager.initialize(scene_manager, self)
	add_child(message_display_manager)
	
	# 初始化交互处理器
	interaction_handler = InteractionHandler.new()
	interaction_handler.initialize(scene_manager, character, chat_dialog, scene_menu, self)
	add_child(interaction_handler)
	
	# 初始化游戏状态管理器
	game_state_manager = GameStateManager.new()
	game_state_manager.set_main_scene_elements({
		"sidebar": sidebar,
		"character": character,
		"action_menu": action_menu,
		"scene_menu": scene_menu,
		"current_scene": scene_manager.current_scene
	})
	add_child(game_state_manager)
	
	# 初始化换装管理器
	costume_manager = CostumeManager.new()
	costume_manager.initialize(character, message_display_manager)
	
	# 设置换装按钮引用（如果存在）
	var costume_button = dynamic_elements.get("costume_button")
	if costume_button:
		costume_manager.set_costume_button(costume_button)
	
	add_child(costume_manager)
	
	# 注册可交互UI元素到UIManager
	if has_node("/root/UIManager"):
		var ui_mgr = get_node("/root/UIManager")
		ui_mgr.register_element(right_click_area)
		
		# 注册所有动态元素
		for element_id in dynamic_elements:
			ui_mgr.register_element(dynamic_elements[element_id])

func _create_dynamic_elements():
	"""根据配置创建动态交互元素"""
	var interactive_elements = ui_layout_manager.get_interactive_elements()
	
	for element_id in interactive_elements:
		
		# 检查场景中是否已存在该元素
		if has_node(element_id):
			dynamic_elements[element_id] = get_node(element_id)
			print("使用场景中的 ", element_id)
		else:
			# 动态创建元素
			var element_scene = load("res://scenes/interactive_element.tscn")
			if element_scene:
				var element = element_scene.instantiate()
				element.name = element_id
				element.element_id = element_id
				add_child(element)
				dynamic_elements[element_id] = element
				print("动态创建 ", element_id)
			else:
				print("警告: 无法加载 interactive_element.tscn")

func _set_ui_references():
	"""设置UI组件引用到布局管理器"""
	var refs = {
		"sidebar": sidebar,
		"chat_dialog": chat_dialog,
		"action_menu": action_menu,
		"character_diary_viewer": character_diary_viewer
	}
	
	# 添加所有动态元素引用
	for element_id in dynamic_elements:
		refs[element_id] = dynamic_elements[element_id]
	
	ui_layout_manager.set_ui_references(refs)

func _connect_signals():
	"""连接所有信号"""
	# 事件管理器
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		event_mgr.event_completed.connect(_on_event_completed)
	
	# SaveManager
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.character_scene_changed.connect(_on_character_scene_changed)
	
	# 场景管理器
	scene_manager.scene_loaded.connect(_on_scene_loaded)
	
	# 侧边栏
	sidebar.scene_changed.connect(_on_scene_changed)
	
	# 角色
	character.character_clicked.connect(_on_character_clicked)
	character.set_background_reference(background)
	
	# 聊天对话框
	chat_dialog.chat_ended.connect(_on_chat_ended)
	
	# 选项菜单
	action_menu.action_selected.connect(_on_action_selected)
	action_menu.game_selected.connect(_on_game_selected)
	action_menu.companion_mode_selected.connect(_on_companion_mode_selected)
	
	# 场景菜单
	scene_menu.scene_selected.connect(_on_scene_menu_selected)
	scene_menu.character_called.connect(_on_character_called)
	scene_menu.map_open_requested.connect(_on_open_map_requested)
	
	# 右侧点击区域
	right_click_area.gui_input.connect(_on_right_area_input)
	
	# 角色日记
	if character_diary_viewer:
		character_diary_viewer.diary_closed.connect(_on_character_diary_closed)
	
	# 连接动态元素的信号
	_connect_dynamic_elements_signals()

func _connect_dynamic_elements_signals():
	"""连接动态交互元素的信号"""
	for element_id in dynamic_elements:
		var element = dynamic_elements[element_id]
		
		if element_id == "character_diary_button" and element.has_signal("action_triggered"):
			element.action_triggered.connect(_on_diary_action_triggered)
		elif element_id == "cook_button" and element.has_signal("action_triggered"):
			element.action_triggered.connect(_on_cook_action_triggered)
		elif element_id == "shop_button" and element.has_signal("action_triggered"):
			element.action_triggered.connect(_on_shop_action_triggered)
		elif element_id == "farming_button" and element.has_signal("action_triggered"):
			element.action_triggered.connect(_on_farming_action_triggered)
		elif element_id == "story_mode_button" and element.has_signal("action_triggered"):
			element.action_triggered.connect(_on_story_mode_action_triggered)
		
		# 可以根据需要添加其他元素的信号连接

func _process(_delta):
	# 持续更新场景区域信息（确保 scene_manager 已初始化）
	if scene_manager:
		scene_manager.calculate_scene_rect()
	
	# 如果聊天框可见，持续更新其位置（确保 ui_layout_manager 已初始化）
	if ui_layout_manager and chat_dialog.visible:
		ui_layout_manager.update_chat_dialog_layout()

func _on_viewport_size_changed():
	"""窗口大小变化时更新UI布局"""
	ui_layout_manager.update_all_layouts()

func _on_scene_loaded(scene_id: String, weather_id: String, time_id: String):
	"""场景加载完成后的处理"""
	await get_tree().process_frame
	ui_layout_manager.update_all_layouts()
	
	# 更新可交互元素显示状态
	_update_interactive_elements_visibility()
	
	# 切换背景音乐
	audio_manager.play_background_music(scene_id, time_id, weather_id)

func _update_interactive_elements_visibility():
	"""更新所有可交互元素的显示状态"""
	if not scene_manager:
		return
	
	var current_scene = scene_manager.current_scene
	
	# 更新所有动态元素的可见性
	for element_id in dynamic_elements:
		var element = dynamic_elements[element_id]
		_update_element_visibility(element_id, element, current_scene)

func _update_element_visibility(element_id: String, element, current_scene: String):
	"""统一更新单个交互元素的显示状态"""
	if not element:
		return
	
	var should_show = false
	if has_node("/root/InteractiveElementManager"):
		var mgr = get_node("/root/InteractiveElementManager")
		should_show = mgr.should_show_in_scene(element_id, current_scene) and mgr.is_element_enabled(element_id)
	
	if should_show:
		element.enable()
	else:
		element.disable()

func _on_scene_changed(scene_id: String, weather_id: String, time_id: String):
	# 如果正在聊天，忽略场景切换请求
	if chat_dialog.visible or character.is_chatting:
		print("正在聊天，忽略场景切换请求")
		return
	
	if not scene_manager:
		print("scene_manager 未初始化，忽略场景切换")
		return
	
	var old_scene = scene_manager.current_scene
	var scene_actually_changed = (old_scene != "" and scene_id != old_scene)
	
	# 场景切换时取消待触发的聊天
	if scene_actually_changed:
		interaction_handler.cancel_pending_chat()
		interaction_handler.lock_scene_switch()
	
	var target_scene = scene_id if scene_actually_changed else old_scene
	
	if target_scene == "":
		print("场景为空，忽略此次变化")
		return
	
	# 加载场景
	await scene_manager.load_scene(target_scene, weather_id, time_id)
	
	if scene_actually_changed:
		sidebar.set_current_scene(target_scene)
	
	await get_tree().process_frame
	
	# 触发场景交互
	if scene_actually_changed:
		if scene_manager.has_character_in_scene(target_scene):
			interaction_handler.try_scene_interaction("enter_scene")
		elif scene_manager.has_character_in_scene(old_scene):
			interaction_handler.try_scene_interaction("leave_scene")

func _on_scene_menu_selected(scene_id: String):
	# 如果正在聊天，忽略场景切换请求
	if chat_dialog.visible or character.is_chatting:
		print("正在聊天，忽略场景切换请求")
		return
	
	if not scene_manager:
		print("scene_manager 未初始化，忽略场景切换")
		return
	
	var old_scene = scene_manager.current_scene
	
	# 场景切换时取消待触发的聊天
	if old_scene != scene_id:
		interaction_handler.cancel_pending_chat()
		interaction_handler.lock_scene_switch()
	
	# 切换到选中的场景
	await scene_manager.load_scene(scene_id, scene_manager.current_weather, scene_manager.current_time)
	sidebar.set_current_scene(scene_id)
	
	await get_tree().process_frame
	
	# 触发场景交互
	if scene_manager.has_character_in_scene(scene_id):
		interaction_handler.try_scene_interaction("enter_scene")
	elif scene_manager.has_character_in_scene(old_scene):
		interaction_handler.try_scene_interaction("leave_scene")

func _on_character_clicked(char_position: Vector2, char_size: Vector2):
	# 尝试交互
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		var result = event_mgr.on_character_clicked()
		if not result.success:
			if result.message != "":
				message_display_manager.show_failure_message(result.message)
			return
	
	if not scene_manager:
		print("scene_manager 未初始化，无法显示菜单")
		return
	
	# 显示选项菜单
	var scene_rect = scene_manager.scene_rect
	var scene_char_pos = scene_rect.position + char_position
	
	var menu_pos = Vector2(
		scene_char_pos.x + char_size.x + 10,
		scene_char_pos.y
	)
	
	var scene_right = scene_rect.position.x + scene_rect.size.x
	var scene_bottom = scene_rect.position.y + scene_rect.size.y
	
	if menu_pos.x + action_menu.custom_minimum_size.x > scene_right:
		menu_pos.x = scene_char_pos.x - action_menu.custom_minimum_size.x - 10
	
	if menu_pos.y + action_menu.size.y > scene_bottom:
		menu_pos.y = scene_bottom - action_menu.size.y - 10
	
	menu_pos.x = max(menu_pos.x, scene_rect.position.x + 10)
	menu_pos.y = max(menu_pos.y, scene_rect.position.y + 10)
	
	action_menu.show_menu(menu_pos, scene_manager.current_scene)

func _on_shop_action_triggered(_action: String):
	"""处理商店入口动作，打开商店面板"""
	# 如果已经存在则显示
	if has_node("ShopPanel"):
		var panel = get_node("ShopPanel")
		if panel.has_method("open_shop"):
			panel.open_shop()
		else:
			panel.visible = true
		return

	# 尝试加载并实例化商店界面
	var shop_scene_path = "res://scenes/shop/shop_panel.tscn"
	if not ResourceLoader.exists(shop_scene_path):
		if message_display_manager:
			message_display_manager.show_failure_message("商店界面未找到: " + shop_scene_path)
		else:
			print("警告: 商店界面未找到: ", shop_scene_path)
		return

	var shop_scene = load(shop_scene_path)
	if shop_scene:
		var shop_panel = shop_scene.instantiate()
		shop_panel.name = "ShopPanel"
		add_child(shop_panel)
		
		# 确保 UI 布局更新
		await get_tree().process_frame
		
		# 打开商店
		if shop_panel.has_method("open_shop"):
			shop_panel.open_shop()
		else:
			shop_panel.visible = true
	else:
		if message_display_manager:
			message_display_manager.show_failure_message("无法实例化商店界面")
		else:
			print("无法实例化商店界面")

func _on_farming_action_triggered(_action: String):
	if has_node("FarmingPanel"):
		var panel = get_node("FarmingPanel")
		if panel.has_method("open_farming"):
			panel.open_farming()
		else:
			panel.visible = true
		return

	var farming_scene_path = "res://scenes/farming/farming_panel.tscn"
	if not ResourceLoader.exists(farming_scene_path):
		if message_display_manager:
			message_display_manager.show_failure_message("菜园界面未找到: " + farming_scene_path)
		else:
			print("警告: 菜园界面未找到: ", farming_scene_path)
		return

	var farming_scene = load(farming_scene_path)
	if farming_scene:
		var farming_panel = farming_scene.instantiate()
		farming_panel.name = "FarmingPanel"
		add_child(farming_panel)
		await get_tree().process_frame
		if farming_panel.has_method("open_farming"):
			farming_panel.open_farming()
		else:
			farming_panel.visible = true
	else:
		if message_display_manager:
			message_display_manager.show_failure_message("无法实例化菜园界面")
		else:
			print("无法实例化菜园界面")

func _on_action_selected(action: String):
	if action == "chat":
		if has_node("/root/EventManager"):
			var event_mgr = get_node("/root/EventManager")
			var result = event_mgr.on_user_start_chat()
			if result.success:
				var chat_mode = result.message if result.message != "" else "passive"
				character.start_chat()
				chat_dialog.show_dialog(chat_mode)
				if has_node("/root/UIManager"):
					get_node("/root/UIManager").disable_all()
			else:
				if result.message != "":
					message_display_manager.show_failure_message(result.message)
		else:
			character.start_chat()
			chat_dialog.show_dialog("passive")
			if has_node("/root/UIManager"):
				get_node("/root/UIManager").disable_all()

func _on_companion_mode_selected():
	"""处理陪伴模式选择"""
	print("进入陪伴模式")
	
	# 验证当前场景是否为书房
	if scene_manager.current_scene != "studyroom":
		if message_display_manager:
			message_display_manager.show_failure_message("只能在书房进入陪伴模式")
		return
	
	# 保存当前游戏状态
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.save_game(save_mgr.current_slot)
	
	# 切换到陪伴模式场景
	get_tree().change_scene_to_file("res://scenes/companion_mode.tscn")

func _on_game_selected(game_type: String):
	print("游戏选择信号接收: ", game_type)
	if game_type == "gomoku":
		_start_gomoku_game()
	elif game_type == "xiangqi":
		_start_xiangqi_game()

func _on_chat_ended():
	await character.end_chat()
	if has_node("/root/UIManager"):
		get_node("/root/UIManager").enable_all()

func _start_gomoku_game():
	print("开始加载五子棋游戏")
	var gomoku_scene = load("res://scenes/gomoku_game.tscn")
	if gomoku_scene:
		print("五子棋场景加载成功")
		var gomoku = gomoku_scene.instantiate()
		gomoku.game_ended.connect(_on_gomoku_ended)
		
		game_state_manager.hide_main_scene()
		
		add_child(gomoku)
		gomoku.z_index = 100
		print("五子棋游戏已添加到场景树")
	else:
		print("错误：无法加载五子棋场景")

func _on_gomoku_ended():
	for child in get_children():
		if child.name == "GomokuGame":
			child.queue_free()
	
	game_state_manager.show_main_scene()
	
	# 等待背景完全加载后再更新角色状态
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 确保背景纹理已加载
	if background.texture:
		ui_layout_manager.update_all_layouts()
		# 重新加载角色（此时背景已准备好）
		character.load_character_for_scene(scene_manager.current_scene)
	else:
		print("警告: 背景纹理未加载，等待加载...")
		await get_tree().process_frame
		await get_tree().process_frame
		ui_layout_manager.update_all_layouts()
		character.load_character_for_scene(scene_manager.current_scene)

func _start_xiangqi_game():
	print("开始加载中国象棋游戏")
	var xiangqi_scene = load("res://scenes/xiangqi_game.tscn")
	if xiangqi_scene:
		print("中国象棋场景加载成功")
		var xiangqi = xiangqi_scene.instantiate()
		xiangqi.game_ended.connect(_on_xiangqi_ended)
		
		game_state_manager.hide_main_scene()
		
		add_child(xiangqi)
		xiangqi.z_index = 100
		print("中国象棋游戏已添加到场景树")
	else:
		print("错误：无法加载中国象棋场景")

func _on_xiangqi_ended():
	for child in get_children():
		if child.name == "XiangqiGame":
			child.queue_free()
	
	game_state_manager.show_main_scene()
	
	# 等待背景完全加载后再更新角色状态
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 确保背景纹理已加载
	if background.texture:
		ui_layout_manager.update_all_layouts()
		# 重新加载角色（此时背景已准备好）
		character.load_character_for_scene(scene_manager.current_scene)
	else:
		print("警告: 背景纹理未加载，等待加载...")
		await get_tree().process_frame
		await get_tree().process_frame
		ui_layout_manager.update_all_layouts()
		character.load_character_for_scene(scene_manager.current_scene)

func _on_open_map_requested():
	var map_scene = load("res://scenes/map/map_view.tscn")
	if map_scene:
		var origin := ""
		if has_node("/root/SaveManager"):
			var sm = get_node("/root/SaveManager")
			if sm.has_meta("map_origin"):
				origin = sm.get_meta("map_origin")
		var map_view = map_scene.instantiate()
		add_child(map_view)
		game_state_manager.hide_main_scene()
		map_view.on_go_selected = func(scene_id: String):
			await scene_manager.load_scene(scene_id, scene_manager.current_weather, scene_manager.current_time)
			sidebar.set_current_scene(scene_id)
			# 地图切换仅预览，不移动角色
			map_view.queue_free()
			game_state_manager.show_main_scene()
			if has_node("/root/SaveManager"):
				var sm2 = get_node("/root/SaveManager")
				if sm2.save_data.has("explore_checkpoint"):
					sm2.save_data.erase("explore_checkpoint")
				sm2.save_game(sm2.current_slot)
				if sm2.has_meta("map_origin"):
					sm2.remove_meta("map_origin")
		map_view.map_closed.connect(func():
			map_view.queue_free()
			if has_node("/root/SaveManager"):
				var sm3 = get_node("/root/SaveManager")
				if sm3.has_meta("map_origin"):
					sm3.remove_meta("map_origin")
			game_state_manager.show_main_scene())

func _check_open_map_on_load():
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		if sm.has_meta("open_map_on_load"):
			sm.remove_meta("open_map_on_load")
			await get_tree().process_frame
			_on_open_map_requested()

func _check_open_death_on_load():
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		if sm.has_meta("open_death_on_load"):
			var death_scene = load("res://scenes/death_view.tscn")
			if death_scene:
				var view = death_scene.instantiate()
				add_child(view)
				game_state_manager.hide_main_scene()
				view.death_view_closed.connect(func():
					game_state_manager.show_main_scene()
				)

func _on_cook_action_triggered(action: String):
	"""烹饪按钮动作触发"""
	if action == "start_cook":
		_start_cook_game()

func _start_cook_game():
	"""开始烹饪游戏"""
	print("开始加载烹饪游戏")
	var cook_scene = load("res://scenes/cook_game.tscn")
	if cook_scene:
		print("烹饪场景加载成功")
		var cook = cook_scene.instantiate()
		cook.game_ended.connect(_on_cook_ended)
		
		game_state_manager.hide_main_scene()
		
		add_child(cook)
		cook.z_index = 100
		cook.show_cook_ui()
		print("烹饪游戏已添加到场景树")
	else:
		print("错误：无法加载烹饪场景")

func _on_cook_ended():
	"""烹饪游戏结束"""
	for child in get_children():
		if child.name == "CookGame":
			child.queue_free()
	
	game_state_manager.show_main_scene()
	
	# 等待背景完全加载后再更新角色状态
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 确保背景纹理已加载
	if background.texture:
		ui_layout_manager.update_all_layouts()
		# 重新加载角色（此时背景已准备好）
		character.load_character_for_scene(scene_manager.current_scene)
	else:
		print("警告: 背景纹理未加载，等待加载...")
		await get_tree().process_frame
		await get_tree().process_frame
		ui_layout_manager.update_all_layouts()
		character.load_character_for_scene(scene_manager.current_scene)

func _on_character_scene_changed(new_scene: String):
	"""角色场景变化时的处理"""
	print("角色场景变化: ", new_scene)
	
	var is_first_init = false
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		if save_mgr.has_meta("is_first_scene_init"):
			is_first_init = true
			save_mgr.remove_meta("is_first_scene_init")
	
	if is_first_init:
		print("首次初始化场景，不显示字幕")
		character.load_character_for_scene(scene_manager.current_scene)
		return
	
	var show_notification = true
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		if save_mgr.has_meta("show_move_notification"):
			show_notification = save_mgr.get_meta("show_move_notification")
			save_mgr.remove_meta("show_move_notification")
	
	if show_notification:
		_show_character_move_message(new_scene)
	
	# await scene_manager.load_scene(new_scene, scene_manager.current_weather, scene_manager.current_time)
	# sidebar.set_current_scene(new_scene)
	character.load_character_for_scene(scene_manager.current_scene)

func _show_character_move_message(new_scene: String):
	"""显示角色移动的提示消息"""
	var character_name = "角色"
	if has_node("/root/EventHelpers"):
		var helpers = get_node("/root/EventHelpers")
		character_name = helpers.get_character_name()
	
	var scene_name = scene_manager.get_scene_name(new_scene)
	var message = "%s去%s了" % [character_name, scene_name]
	message_display_manager.show_info_message(message)

func _on_right_area_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if chat_dialog.visible or character.is_chatting:
				print("正在聊天，忽略场景切换点击")
				return
			
			if not interaction_handler or interaction_handler.is_scene_switch_locked():
				print("场景切换锁定中，忽略点击")
				return
			
			if not scene_manager:
				print("scene_manager 未初始化，忽略点击")
				return
			
			var click_pos = event.position
			var scene_rect = scene_manager.scene_rect
			var right_threshold = scene_rect.position.x + scene_rect.size.x * 0.75
			
			if click_pos.x >= right_threshold and scene_rect.has_point(click_pos):
				_show_scene_menu(click_pos)

func _show_scene_menu(at_position: Vector2):
	scene_menu.setup_scenes(scene_manager.scenes_config, scene_manager.current_scene)
	
	await get_tree().process_frame
	
	var scene_rect = scene_manager.scene_rect
	var menu_pos = Vector2(
		at_position.x - scene_menu.size.x - 10,
		at_position.y
	)
	
	var scene_bottom = scene_rect.position.y + scene_rect.size.y
	
	menu_pos.x = max(menu_pos.x, scene_rect.position.x + 10)
	menu_pos.y = max(menu_pos.y, scene_rect.position.y + 10)
	
	if menu_pos.y + scene_menu.size.y > scene_bottom:
		menu_pos.y = scene_bottom - scene_menu.size.y - 10
	
	scene_menu.show_menu(menu_pos)

func _on_event_completed(event_name: String, result):
	"""事件完成处理"""
	if result.success:
		print("事件成功: ", event_name)
		
		if event_name == "idle_timeout":
			if result.message == "active":
				interaction_handler.trigger_active_chat()
			elif result.message == "idle_position_change":
				interaction_handler.trigger_idle_position_change()
			elif result.message == "auto_continue":
				interaction_handler.auto_continue_chat()
			elif result.message == "timeout_to_input":
				_handle_timeout_to_input()
			elif result.message == "chat_idle_timeout":
				_handle_chat_idle_timeout()
	else:
		print("事件失败: ", event_name)

func _handle_timeout_to_input():
	"""处理超时切换到输入模式"""
	interaction_handler.force_end_chat()
	
	var character_name = "角色"
	if has_node("/root/EventHelpers"):
		var helpers = get_node("/root/EventHelpers")
		character_name = helpers.get_character_name()
	
	message_display_manager.show_failure_message(character_name + "默默离开了")

func _handle_chat_idle_timeout():
	"""处理聊天空闲超时"""
	interaction_handler.force_end_chat()
	
	var character_name = "角色"
	if has_node("/root/EventHelpers"):
		var helpers = get_node("/root/EventHelpers")
		character_name = helpers.get_character_name()
	
	message_display_manager.show_failure_message(character_name + "默默离开了")
	chat_dialog._on_end_button_pressed()

func _check_pending_offline_position_change():
	"""检查并应用待处理的离线位置变化"""
	if not has_node("/root/SaveManager"):
		return
	
	var save_mgr = get_node("/root/SaveManager")
	if save_mgr.has_meta("pending_offline_position_change"):
		print("检测到待应用的离线位置变化")
		save_mgr.remove_meta("pending_offline_position_change")
		await character.apply_position_probability_silent()
		print("离线位置变化已应用")

func _on_diary_action_triggered(action: String):
	"""日记按钮动作触发"""
	if action == "diary_selected":
		if character_diary_viewer:
			# 显示日记前禁用其他UI交互
			if has_node("/root/UIManager"):
				get_node("/root/UIManager").disable_all()
			character_diary_viewer.show_diary()

func _on_story_mode_action_triggered(action: String):
	"""故事模式按钮动作触发"""
	if action == "story_mode":
		_open_story_mode()

func _open_story_mode():
	"""打开故事模式界面"""
	# 检查是否已存在故事模式面板
	var story_panel = get_node_or_null("StoryModePanel")
	if story_panel:
		story_panel.show_panel()
		return

	# 创建新的故事模式面板
	var story_mode_scene = load("res://scenes/story_mode_panel.tscn")
	if story_mode_scene:
		var panel = story_mode_scene.instantiate()
		add_child(panel)
		# 显示故事模式前禁用其他UI交互
		if has_node("/root/UIManager"):
			get_node("/root/UIManager").disable_all()
		# 连接关闭信号
		panel.story_mode_closed.connect(_on_story_mode_closed)
		panel.show_panel()

func _on_story_mode_closed():
	"""故事模式关闭事件"""
	# 重新启用UI交互
	if has_node("/root/UIManager"):
		get_node("/root/UIManager").enable_all()

func _on_character_diary_closed():
	"""角色日记查看器关闭事件"""
	print("角色日记查看器已关闭")
	# 重新启用UI交互
	if has_node("/root/UIManager"):
		get_node("/root/UIManager").enable_all()

func _check_and_migrate_diary():
	"""检查并迁移旧日记数据"""
	var migration = preload("res://scripts/diary_migration.gd").new()
	
	if migration.check_needs_migration():
		print("检测到旧的日记数据，开始自动迁移...")
		var count = migration.migrate_diary_data()
		print("日记迁移完成，共处理 %d 条记录" % count)
	else:
		print("未检测到需要迁移的旧日记数据")

func _on_character_called():
	"""呼唤角色事件"""
	print("用户呼唤角色")
	
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		var result = event_mgr.on_character_called()
		
		if result.success:
			print("呼唤成功")
			
			var character_scene = ""
			if has_node("/root/SaveManager"):
				var save_mgr = get_node("/root/SaveManager")
				character_scene = save_mgr.get_character_scene()
			
			if character_scene == scene_manager.current_scene:
				_start_called_chat(true)
			else:
				_move_character_to_current_scene()
		else:
			# 呼唤失败，显示失败消息
			if result.message != "":
				message_display_manager.show_failure_message(result.message)
	else:
		print("警告: EventManager 未找到")

func _start_called_chat(already_here: bool = false):
	"""开始被呼唤后的对话"""
	character.start_chat()
	var chat_mode = "called_here" if already_here else "called"
	chat_dialog.show_dialog(chat_mode)
	if has_node("/root/UIManager"):
		get_node("/root/UIManager").disable_all()

func _move_character_to_current_scene():
	"""将角色移动到当前场景并触发对话"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		
		var old_scene = save_mgr.get_character_scene()
		save_mgr.set_meta("character_old_scene", old_scene)
		save_mgr.set_meta("show_move_notification", false)
		
		save_mgr.set_character_scene(scene_manager.current_scene)
		
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		
		if not character.visible:
			print("警告: 角色加载后仍不可见")
		
		_start_called_chat()
