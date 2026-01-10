extends Panel

signal action_selected(action: String)
signal game_selected(game_type: String)
signal companion_mode_selected()

@onready var vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var chat_button: Button = $MarginContainer/VBoxContainer/ChatButton
@onready var companion_button: Button = $MarginContainer/VBoxContainer/CompanionButton if has_node("MarginContainer/VBoxContainer/CompanionButton") else null
@onready var game_button: Button = $MarginContainer/VBoxContainer/GameButton
@onready var game_submenu: Panel = $GameSubmenu
@onready var gomoku_button: Button = $GameSubmenu/MarginContainer/VBoxContainer/GomokuButton
@onready var chinese_chess_button: Button = $GameSubmenu/MarginContainer/VBoxContainer/ChineseChessButton

const ANIMATION_DURATION = 0.2

var current_scene: String = ""

func _ready():
	visible = false
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	
	# 连接按钮信号
	if chat_button:
		chat_button.pressed.connect(_on_chat_button_pressed)
		print("聊天按钮信号已连接")
	else:
		print("警告：聊天按钮未找到")
	
	if companion_button:
		companion_button.pressed.connect(_on_companion_button_pressed)
		print("陪伴模式按钮信号已连接")
	else:
		print("警告：陪伴模式按钮未找到")
		
	if game_button:
		game_button.pressed.connect(_on_game_button_pressed)
		print("游戏按钮信号已连接")
	else:
		print("警告：游戏按钮未找到")
		
	if gomoku_button:
		gomoku_button.pressed.connect(_on_gomoku_button_pressed)
		print("五子棋按钮信号已连接")
	else:
		print("警告：五子棋按钮未找到")
	
	if chinese_chess_button:
		chinese_chess_button.pressed.connect(_on_chinese_chess_button_pressed)
		print("中国象棋按钮信号已连接")
	else:
		print("警告：中国象棋按钮未找到")
	
	# 初始隐藏游戏子菜单
	if game_submenu:
		game_submenu.visible = false
		print("游戏子菜单已初始化")
	else:
		print("警告：游戏子菜单未找到")

func _input(event):
	# 如果菜单不可见，不处理
	if not visible:
		return
	
	# 只处理鼠标左键按下事件
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	
	# 获取全局鼠标位置
	var mouse_pos = get_viewport().get_mouse_position()
	
	# 检查是否点击在主菜单内
	var main_rect = get_global_rect()
	var in_main_menu = main_rect.has_point(mouse_pos)
	
	# 检查是否点击在子菜单内
	var in_submenu = false
	if game_submenu and game_submenu.visible:
		var submenu_rect = game_submenu.get_global_rect()
		in_submenu = submenu_rect.has_point(mouse_pos)
	
	# 只有点击在菜单和子菜单外才隐藏
	if not in_main_menu and not in_submenu:
		hide_menu()
		get_viewport().set_input_as_handled()

func show_menu(at_position: Vector2, scene_id: String = ""):
	# 设置菜单位置（在角色旁边）
	position = at_position
	current_scene = scene_id
	
	# 根据场景显示/隐藏按钮
	if game_button:
		game_button.visible = (scene_id == "livingroom")
	
	# 只在书房场景显示陪伴模式按钮
	if companion_button:
		companion_button.visible = (scene_id == "studyroom")
	
	# 隐藏子菜单
	if game_submenu:
		game_submenu.visible = false
	
	visible = true
	pivot_offset = size / 2.0
	
	# 展开动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, ANIMATION_DURATION)
	tween.tween_property(self, "scale", Vector2.ONE, ANIMATION_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_menu():
	# 隐藏子菜单
	if game_submenu:
		game_submenu.visible = false
	
	pivot_offset = size / 2.0
	
	# 收起动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, ANIMATION_DURATION)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), ANIMATION_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	await tween.finished
	visible = false

func _on_chat_button_pressed():
	action_selected.emit("chat")
	hide_menu()

func _on_companion_button_pressed():
	print("陪伴模式按钮被点击")
	companion_mode_selected.emit()
	hide_menu()

func _on_game_button_pressed():
	print("游戏按钮被点击")
	# 显示游戏子菜单
	if game_submenu:
		game_submenu.position = Vector2(size.x + 10, 0)
		game_submenu.visible = true
		print("子菜单已显示")

func _on_gomoku_button_pressed():
	print("五子棋按钮被点击")
	game_selected.emit("gomoku")
	hide_menu()

func _on_chinese_chess_button_pressed():
	print("中国象棋按钮被点击")
	game_selected.emit("xiangqi")
	hide_menu()
