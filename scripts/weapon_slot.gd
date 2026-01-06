extends Panel

# 武器槽位组件

signal slot_clicked(storage_type: String)
signal slot_double_clicked(storage_type: String)
signal drag_started(storage_type: String)
signal drag_ended(storage_type: String)

@onready var icon_texture = $Icon
@onready var count_label = $CountLabel
@onready var label = $Label

var storage_type: String = ""  # "player", "other" 等
var item_data: Dictionary = {}  # {item_id: String, count: int}
var is_selected: bool = false

# 拖拽相关
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 5.0

# 双击检测
var last_click_time: float = 0.0
const DOUBLE_CLICK_TIME: float = 0.3

func _ready():
	gui_input.connect(_on_gui_input)
	update_display()

func setup(type: String):
	"""初始化武器槽"""
	storage_type = type

func set_item(data):
	"""设置物品数据"""
	item_data = data if data != null and not data.is_empty() else {}
	update_display()

func update_display():
	"""更新显示"""
	if not is_node_ready():
		return
	
	if item_data.is_empty():
		# 空槽位
		icon_texture.texture = null
		count_label.text = ""
		modulate = Color.WHITE
	else:
		# 有武器
		var item_config: Dictionary = {}
		if InventoryManager:
			item_config = InventoryManager.get_item_config(item_data.item_id)
		
		if item_config.has("icon"):
			var icon_path = "res://assets/images/items/" + item_config.icon
			if ResourceLoader.exists(icon_path):
				icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				icon_texture.texture = load(icon_path)
			else:
				icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				icon_texture.texture = load("res://assets/images/error.png")
		else:
			icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_texture.texture = load("res://assets/images/error.png")
		
		# 显示弹药信息（如果是远程武器）
		if item_config.get("subtype") == "远程":
			var current_ammo = item_data.get("ammo", 0)
			var magazine_size = item_config.get("magazine_size", 30)
			count_label.text = str(int(current_ammo)) + "/" + str(int(magazine_size))
		else:
			count_label.text = ""
		modulate = Color.WHITE
	
	# 更新选中状态
	if is_selected:
		modulate = Color(1.5, 1.5, 0.8)
	else:
		modulate = Color.WHITE

func set_selected(selected: bool):
	"""设置选中状态"""
	is_selected = selected
	update_display()

func _on_gui_input(event: InputEvent):
	"""处理输入"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_start_position = event.position
			is_dragging = false
			
			# 检测双击
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_click_time < DOUBLE_CLICK_TIME:
				slot_double_clicked.emit(storage_type)
				last_click_time = 0.0
			else:
				last_click_time = current_time
		else:
			# 鼠标释放
			if is_dragging:
				drag_ended.emit(storage_type)
				is_dragging = false
			else:
				slot_clicked.emit(storage_type)
	
	elif event is InputEventMouseMotion:
		# 检测拖拽开始
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and not is_dragging:
			var drag_distance = event.position.distance_to(drag_start_position)
			if drag_distance > DRAG_THRESHOLD and not item_data.is_empty():
				is_dragging = true
				drag_started.emit(storage_type)
