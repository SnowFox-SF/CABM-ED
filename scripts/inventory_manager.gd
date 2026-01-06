extends Node

# 背包管理器 - 自动加载单例
# 管理玩家背包和仓库数据

const INVENTORY_SIZE = 30  # 背包格子数量
const WAREHOUSE_SIZE=80
const COOK_PREP_SIZE = 20  # 烹饪准备栏格子数量

var inventory_container: StorageContainer
var warehouse_container: StorageContainer
var cook_prep_container: StorageContainer  # 烹饪准备栏

var items_config: Dictionary = {}  # 物品配置
var unique_items: Array = []  # 唯一物品列表

func _ready():
	var sm = get_node_or_null("/root/SaveManager")
	if sm and not sm.is_resources_ready():
		return
	_load_items_config()
	_load_unique_items()
	_initialize_storage()

func _load_items_config():
	"""加载物品配置"""
	var config_path = "res://config/items.json"
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		print("警告: 物品配置文件不存在")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var data = json.data
		if data.has("items"):
			items_config = data.items

func _load_unique_items():
	"""加载唯一物品列表"""
	var config_path = "res://config/unique_items.json"
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		print("警告: 唯一物品配置文件不存在")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var data = json.data
		if data.has("unique_items"):
			unique_items = data.unique_items
			print("已加载唯一物品列表: ", unique_items)

func _manage_unique_items():
	"""管理唯一物品：只删除多余的唯一物品（保护机制）
	注意：不再自动添加缺失的唯一物品，添加逻辑已移至地图每日刷新"""
	if unique_items.is_empty():
		return
	
	print("开始检查重复的唯一物品...")
	
	# 统计每个唯一物品的数量和位置
	var item_counts = {}
	var item_locations = {}  # {item_id: [{container: String, index: int, is_weapon_slot: bool}]}
	
	for item_id in unique_items:
		item_counts[item_id] = 0
		item_locations[item_id] = []
	
	# 扫描所有容器中的唯一物品
	_scan_container_for_unique_items(inventory_container, "player", item_counts, item_locations)
	
	# 扫描雪狐背包
	if SaveManager and SaveManager.save_data.has("snow_fox_inventory"):
		var snow_fox_data = SaveManager.save_data.snow_fox_inventory
		_scan_storage_data_for_unique_items(snow_fox_data, "snow_fox", item_counts, item_locations)
	
	# 扫描仓库
	_scan_container_for_unique_items(warehouse_container, "warehouse", item_counts, item_locations)
	
	# 扫描烹饪准备栏
	_scan_container_for_unique_items(cook_prep_container, "cook_prep", item_counts, item_locations)
	
	# 只处理重复的唯一物品（删除多余的）
	for item_id in unique_items:
		var count = item_counts[item_id]
		
		if count > 1:
			# 有多个，删除多余的（保留第一个）
			print("唯一物品 ", item_id, " 有 ", count, " 个，删除多余的")
			var locations = item_locations[item_id]
			
			# 按优先级保留：玩家背包 > 雪狐背包 > 仓库
			locations.sort_custom(_sort_locations_by_priority)
			
			# 删除除第一个外的所有
			for i in range(1, locations.size()):
				var loc = locations[i]
				print("删除重复的唯一物品 ", item_id, " 在 ", loc.container, " 位置 ", loc.index)
				_remove_item_at_location(loc)
	
	print("唯一物品检查完成")

func _check_item_exists_anywhere(item_id: String) -> bool:
	"""检查物品是否存在于任何容器中"""
	# 检查玩家背包
	if inventory_container.has_item(item_id):
		return true
	
	# 检查仓库
	if warehouse_container.has_item(item_id):
		return true
	
	# 检查雪狐背包
	if SaveManager and SaveManager.save_data.has("snow_fox_inventory"):
		var snow_fox_data = SaveManager.save_data.snow_fox_inventory
		if _check_storage_data_has_item(snow_fox_data, item_id):
			return true
	
	return false

func _check_storage_data_has_item(storage_data, item_id: String) -> bool:
	"""检查存储数据中是否有指定物品"""
	if storage_data is Array:
		for item in storage_data:
			if item != null and item.has("item_id") and item.item_id == item_id:
				return true
	elif storage_data is Dictionary:
		# 检查武器栏
		if storage_data.has("weapon_slot") and not storage_data.weapon_slot.is_empty():
			if storage_data.weapon_slot.item_id == item_id:
				return true
		
		# 检查普通格子
		if storage_data.has("storage"):
			for item in storage_data.storage:
				if item != null and item.has("item_id") and item.item_id == item_id:
					return true
	return false

func _sort_locations_by_priority(a, b):
	"""按容器优先级排序位置"""
	var priority_order = {
		"player": 0,      # 最高优先级
		"snow_fox": 1,    # 中等优先级  
		"warehouse": 2    # 最低优先级
	}
	
	var a_priority = priority_order.get(a.container, 999)
	var b_priority = priority_order.get(b.container, 999)
	
	return a_priority < b_priority

func _scan_container_for_unique_items(container: StorageContainer, container_name: String, item_counts: Dictionary, item_locations: Dictionary):
	"""扫描容器中的唯一物品"""
	# 扫描武器栏
	if container.has_weapon_slot and not container.weapon_slot.is_empty():
		var item_id = container.weapon_slot.item_id
		if item_id in unique_items:
			item_counts[item_id] += 1
			item_locations[item_id].append({
				"container": container_name,
				"index": -1,  # -1 表示武器栏
				"is_weapon_slot": true,
				"container_ref": container
			})
	
	# 扫描普通格子
	for i in range(container.storage.size()):
		var item = container.storage[i]
		if item != null and item.item_id in unique_items:
			item_counts[item.item_id] += 1
			item_locations[item.item_id].append({
				"container": container_name,
				"index": i,
				"is_weapon_slot": false,
				"container_ref": container
			})

func _scan_storage_data_for_unique_items(storage_data, container_name: String, item_counts: Dictionary, item_locations: Dictionary):
	"""扫描存储数据中的唯一物品（用于雪狐背包等）"""
	# 兼容新旧格式
	var storage_array = []
	var weapon_slot_data = {}
	
	if storage_data is Array:
		storage_array = storage_data
	elif storage_data is Dictionary:
		storage_array = storage_data.get("storage", [])
		weapon_slot_data = storage_data.get("weapon_slot", {})
	
	# 扫描武器栏
	if not weapon_slot_data.is_empty() and weapon_slot_data.has("item_id"):
		var item_id = weapon_slot_data.item_id
		if item_id in unique_items:
			item_counts[item_id] += 1
			item_locations[item_id].append({
				"container": container_name,
				"index": -1,
				"is_weapon_slot": true,
				"storage_data": storage_data
			})
	
	# 扫描普通格子
	for i in range(storage_array.size()):
		var item = storage_array[i]
		if item != null and item.has("item_id") and item.item_id in unique_items:
			item_counts[item.item_id] += 1
			item_locations[item.item_id].append({
				"container": container_name,
				"index": i,
				"is_weapon_slot": false,
				"storage_data": storage_data
			})

func _remove_item_at_location(location: Dictionary):
	"""删除指定位置的物品"""
	if location.has("container_ref"):
		# 直接引用容器
		var container = location.container_ref
		if location.is_weapon_slot:
			container.weapon_slot = {}
		else:
			container.storage[location.index] = null
		container.storage_changed.emit()
	elif location.has("storage_data"):
		# 存储数据（雪狐背包）
		var storage_data = location.storage_data
		if storage_data is Dictionary:
			if location.is_weapon_slot:
				storage_data.weapon_slot = {}
			else:
				if storage_data.has("storage"):
					storage_data.storage[location.index] = null
		elif storage_data is Array:
			storage_data[location.index] = null

func _initialize_storage():
	"""初始化存储空间"""
	# 玩家背包和雪狐背包有武器栏
	inventory_container = StorageContainer.new(INVENTORY_SIZE, items_config, true)
	# 仓库物品
	warehouse_container = StorageContainer.new(WAREHOUSE_SIZE, items_config, false)
	# 烹饪准备栏（无武器栏）
	cook_prep_container = StorageContainer.new(COOK_PREP_SIZE, items_config, false)

func get_item_config(item_id: String) -> Dictionary:
	"""获取物品配置"""
	return items_config.get(item_id, {})

func add_item_to_inventory(item_id: String, count: int = 1) -> bool:
	"""添加物品到背包"""
	return inventory_container.add_item(item_id, count)

func add_item_to_warehouse(item_id: String, count: int = 1) -> bool:
	"""添加物品到仓库"""
	return warehouse_container.add_item(item_id, count)

func get_storage_data() -> Dictionary:
	"""获取存储数据用于保存"""
	return {
		"inventory": inventory_container.get_data(),
		"warehouse": warehouse_container.get_data(),
		"cook_prep": cook_prep_container.get_data()
	}

func load_storage_data(data: Dictionary):
	"""从保存数据加载"""
	if data.has("inventory"):
		inventory_container.load_data(data.inventory)
	if data.has("warehouse"):
		warehouse_container.load_data(data.warehouse)
	if data.has("cook_prep"):
		cook_prep_container.load_data(data.cook_prep)
	
	# 加载后检查并管理唯一物品
	_manage_unique_items()
