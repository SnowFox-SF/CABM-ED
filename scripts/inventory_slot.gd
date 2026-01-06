extends Panel

# 物品格子组件

signal slot_clicked(slot_index: int, storage_type: String)
signal slot_double_clicked(slot_index: int, storage_type: String)
signal slot_right_clicked(slot_index: int, storage_type: String)
signal slot_shift_clicked(slot_index: int, storage_type: String)
signal drag_started(slot_index: int, storage_type: String)
signal drag_ended(slot_index: int, storage_type: String)

@onready var icon_texture = $Icon
@onready var count_label = $CountLabel

var slot_index: int = 0
var storage_type: String = ""  # "player", "other", "inventory", "warehouse" 等
var item_data: Dictionary = {}  # {item_id: String, count: int}
var is_selected: bool = false

# 拖拽相关
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 5.0  # 拖拽阈值（像素）

# 双击检测
var last_click_time: float = 0.0
const DOUBLE_CLICK_TIME: float = 0.3  # 双击时间窗口（秒）

func _ready():
	gui_input.connect(_on_gui_input)
	update_display()

func setup(index: int, type: String):
	"""初始化格子"""
	slot_index = index
	storage_type = type

func set_item(data):
	"""设置物品数据"""
	item_data = data if data != null else {}
	update_display()

func update_display():
	"""更新显示"""
	if not is_node_ready():
		return
	
	if item_data.is_empty():
		# 空格子
		icon_texture.texture = null
		count_label.text = ""
		modulate = Color.WHITE
	else:
		# 有物品 - 尝试从InventoryManager获取配置
		var item_config: Dictionary = {}
		if InventoryManager:
			item_config = InventoryManager.get_item_config(item_data.item_id)
		
		if item_config.has("icon"):
			var icon_path = "res://assets/images/items/" + item_config.icon
			icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if ResourceLoader.exists(icon_path):
				icon_texture.texture = load(icon_path)
			else:
				icon_texture.texture = load("res://assets/images/error.png")
		else:
			icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_texture.texture = load("res://assets/images/error.png")
		
		# 显示数量（确保是整数）
		var count = int(item_data.count)
		if count > 1:
			count_label.text = str(count)
		else:
			count_label.text = ""
		
		modulate = Color.WHITE
	
	# 更新选中状态
	if is_selected:
		modulate = Color(1.5, 1.5, 0.8)  # 高亮
	else:
		modulate = Color.WHITE

func set_selected(selected: bool):
	"""设置选中状态"""
	is_selected = selected
	update_display()

func _on_gui_input(event: InputEvent):
	"""处理输入"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 鼠标按下
				drag_start_position = event.position
				is_dragging = false

				# 检测Shift+左键快速转移
				if Input.is_key_pressed(KEY_SHIFT):
					slot_shift_clicked.emit(slot_index, storage_type)
					return

				# 检测双击
				var current_time = Time.get_ticks_msec() / 1000.0
				if current_time - last_click_time < DOUBLE_CLICK_TIME and is_selected:
					# 双击事件
					slot_double_clicked.emit(slot_index, storage_type)
					last_click_time = 0.0  # 重置，避免三击被识别为双击
				else:
					last_click_time = current_time
			else:
				# 鼠标释放
				if is_dragging:
					drag_ended.emit(slot_index, storage_type)
					is_dragging = false
				else:
					# 单击事件
					slot_clicked.emit(slot_index, storage_type)

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# 右键点击
			slot_right_clicked.emit(slot_index, storage_type)

	elif event is InputEventMouseMotion:
		# 检测拖拽开始
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and not is_dragging:
			var drag_distance = event.position.distance_to(drag_start_position)
			if drag_distance > DRAG_THRESHOLD and not item_data.is_empty():
				is_dragging = true
				drag_started.emit(slot_index, storage_type)
