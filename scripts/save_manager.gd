extends Node

# 保存管理器 - 自动加载单例
# 负责游戏数据的保存和加载

const SAVE_DIR = "user://saves/"
const SAVE_FILE_PREFIX = "save_slot_"
const SAVE_FILE_EXT = ".json"

var current_slot: int = 1
var save_data: Dictionary = {}
var auto_save_timer: Timer
var is_auto_save_enabled: bool = true
var auto_save_interval: float = 300.0 # 默认5分钟
var enable_instant_save: bool = true # 启用即时保存
var is_initial_setup_completed: bool = false # 初始设置是否完成
var capture_checkpoint_on_save: bool = false
const REQUIRED_RES_VERSION: String = "CABM-ED_RES_v1-20251208-1"
var initialized: bool = false

signal save_completed(slot: int)
signal load_completed(slot: int)
signal save_failed(slot: int, error: String)
signal load_failed(slot: int, error: String)
signal affection_changed(new_value: int)
signal willingness_changed(new_value: int)
signal mood_changed(new_value: String)
signal energy_changed(new_value: int)
signal character_scene_changed(new_scene: String)

func _ready():
	if not is_resources_ready():
		print("资源未准备，跳过所有初始化")
		is_initial_setup_completed = false
		initialized = false
		return
	_initialize_after_resources_ready()

func _initialize_after_resources_ready():
	if initialized:
		return
	_ensure_save_directory()
	
	# 加载保存模板
	_load_template()
	
	# 设置自动保存定时器
	_setup_auto_save_timer()
	
	# 检查是否存在存档
	var has_save = _has_save_file()
	
	# 如果存在存档，则加载并标记初始设置已完成
	if has_save:
		load_game(current_slot)
		is_initial_setup_completed = true
	else:
		# 首次启动，不加载存档，等待初始设置完成
		print("首次启动，等待初始设置完成")
		is_initial_setup_completed = false
	initialized = true

func is_resources_ready() -> bool:
	return true #已经弃用资源分离，不检查资源
	# var dir = DirAccess.open("user://")
	# if dir == null:
	# 	return false
	# if not dir.dir_exists("resources"):
	# 	return false
	# var version_path = "user://resources/version.txt"
	# if not FileAccess.file_exists(version_path):
	# 	return false
	# var f = FileAccess.open(version_path, FileAccess.READ)
	# if f == null:
	# 	return false
	# var content = f.get_as_text().strip_edges()
	# f.close()
	# return content == REQUIRED_RES_VERSION

func get_required_resource_version() -> String:
	return REQUIRED_RES_VERSION

func _has_save_file() -> bool:
	"""检查存档文件是否存在"""
	var save_path = SAVE_DIR + SAVE_FILE_PREFIX + str(current_slot) + SAVE_FILE_EXT
	return FileAccess.file_exists(save_path)

func _notification(what):
	"""捕获窗口关闭事件"""
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not is_resources_ready() or not initialized:
			return
		# 只有在初始设置完成后才允许自动保存
		if not is_initial_setup_completed:
			print("初始设置未完成，跳过自动保存")
			get_tree().quit()
			return
		print("检测到窗口关闭，正在保存游戏...")
		capture_checkpoint_on_save = true
		save_game(current_slot)
		capture_checkpoint_on_save = false
		# 等待保存完成后再退出
		get_tree().quit()

func _ensure_save_directory():
	"""确保保存目录存在"""
	var dir = DirAccess.open("user://")
	if dir == null:
		print("错误: 无法访问 user:// 目录")
		return
	
	print("user:// 路径: ", OS.get_user_data_dir())
	
	if not dir.dir_exists("saves"):
		var err = dir.make_dir("saves")
		if err != OK:
			print("错误: 无法创建 saves 目录，错误码: ", err)
		else:
			print("成功创建 saves 目录")

func _load_template():
	"""从模板加载默认数据结构"""
	var template_path = "res://config/save_data_template.json"
	if not FileAccess.file_exists(template_path):
		print("警告: 保存模板不存在")
		return
	
	var file = FileAccess.open(template_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var template = json.data
		# 提取slot_1作为默认数据结构
		if template.has("save_slots") and template.save_slots.has("slot_1"):
			save_data = template.save_slots.slot_1.duplicate(true)
		
		# 加载设置
		if template.has("settings"):
			var settings = template.settings
			is_auto_save_enabled = settings.get("auto_save", true)
			auto_save_interval = settings.get("auto_save_interval", 300.0)
			enable_instant_save = settings.get("instant_save", true)
	
	# 确保BGM配置存在
	if not save_data.has("bgm_config"):
		save_data.bgm_config = {}
	
	# 延迟加载背包数据
	call_deferred("_load_inventory_data")

func _setup_auto_save_timer():
	"""设置自动保存定时器"""
	auto_save_timer = Timer.new()
	auto_save_timer.wait_time = auto_save_interval
	auto_save_timer.one_shot = false
	auto_save_timer.timeout.connect(_on_auto_save_timeout)
	add_child(auto_save_timer)
	
	if is_auto_save_enabled:
		auto_save_timer.start()

func _on_auto_save_timeout():
	"""自动保存触发"""
	# 只有在初始设置完成后才允许自动保存
	if is_initial_setup_completed:
		save_game(current_slot)
		print("自动保存完成")

func save_game(slot: int = 1, update_last_played_at: bool = true) -> bool:
	"""保存游戏数据
	
	参数:
		slot: 存档槽位
	
	注意：
		- last_saved_at: 每次保存时更新
		- last_played_at: 每次保存时更新（记录退出时间，用于离线时间计算）
		- last_refresh_date: 只在每日刷新时更新（用于判断是否需要刷新）
	"""
	print("保存游戏到槽位 ", slot, "；更新时间戳: ", update_last_played_at)
	var save_path = SAVE_DIR + SAVE_FILE_PREFIX + str(slot) + SAVE_FILE_EXT
	
	# 保存背包数据
	if has_node("/root/InventoryManager"):
		save_data.inventory_data = get_node("/root/InventoryManager").get_storage_data()
	# 保存探索场地状态（宝箱、掉落物）
	var cur_scene = get_tree().current_scene
	if cur_scene and cur_scene.has_method("get_field_state_data"):
		var field_data = cur_scene.get_field_state_data()
		if field_data.has("chest_system_data"):
			save_data.chest_system_data = field_data.chest_system_data
		if field_data.has("drop_system_data"):
			save_data.drop_system_data = field_data.drop_system_data
		if field_data.has("enemy_system_data"):
			save_data.enemy_system_data = field_data.enemy_system_data
	# 更新探索断点
	if capture_checkpoint_on_save and cur_scene and cur_scene.has_method("get_checkpoint_data"):
		var cp = cur_scene.get_checkpoint_data()
		save_data.explore_checkpoint = cp
		print("更新探索断点")
	
	# 更新时间戳
	var now = Time.get_datetime_string_from_system()
	var now_unix = Time.get_unix_time_from_system()
	save_data.timestamp.last_saved_at = now
	if update_last_played_at:
		save_data.timestamp.last_played_at = now
		save_data.timestamp.last_played_at_unix = now_unix
	
	# 转换为JSON
	var json_string = JSON.stringify(save_data, "\t")
	
	# 写入文件
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		var err = FileAccess.get_open_error()
		var error = "无法创建保存文件: " + save_path + " (错误码: " + str(err) + ")"
		print(error)
		print("完整路径: ", ProjectSettings.globalize_path(save_path))
		save_failed.emit(slot, error)
		return false
	
	file.store_string(json_string)
	file.close()
	
	# 验证文件是否真的保存成功
	if FileAccess.file_exists(save_path):
		print("游戏已保存到槽位 ", slot, " 路径: ", ProjectSettings.globalize_path(save_path))
		save_completed.emit(slot)
		return true
	else:
		var error = "文件保存后验证失败: " + save_path
		print(error)
		save_failed.emit(slot, error)
		return false

func load_game(slot: int = 1) -> bool:
	"""加载游戏数据"""
	var save_path = SAVE_DIR + SAVE_FILE_PREFIX + str(slot) + SAVE_FILE_EXT
	
	print("尝试加载存档: ", ProjectSettings.globalize_path(save_path))
	
	if not FileAccess.file_exists(save_path):
		print("存档不存在，使用默认数据: ", save_path)
		# 初始化时间戳
		var now = Time.get_datetime_string_from_system()
		var now_unix = Time.get_unix_time_from_system()
		save_data.timestamp.created_at = now
		save_data.timestamp.last_saved_at = now
		save_data.timestamp.last_played_at = now
		save_data.timestamp.last_played_at_unix = now_unix
		return false
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		var err = FileAccess.get_open_error()
		var error = "无法读取保存文件: " + save_path + " (错误码: " + str(err) + ")"
		print(error)
		load_failed.emit(slot, error)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		var error = "保存文件格式错误: " + json.get_error_message()
		print(error)
		load_failed.emit(slot, error)
		return false
	
	# 深度合并存档数据和模板数据，确保存档中的值优先
	# 这样可以防止重新安装时重置已有数据
	var loaded_data = json.data
	save_data = _deep_merge(save_data, loaded_data)
	current_slot = slot
	
	# 检查是否需要每日刷新（删除opened_chests）
	_check_daily_refresh()
	
	# 先检查离线时间变化（使用存档中的旧时间）
	# 延迟调用以确保 OfflineTimeManager 已经加载
	call_deferred("_check_offline_time")
	
	print("游戏已从槽位 ", slot, " 加载")
	load_completed.emit(slot)
	return true

func _check_daily_refresh():
	"""检查是否需要每日刷新地图（在游戏启动时调用）
	
	使用 last_refresh_date 字段来判断是否需要刷新，而不是 last_played_at
	这样即使玩家跨越0点保存退出，下次启动时仍能正确刷新
	"""
	# 确保 last_refresh_date 字段存在
	if not save_data.has("timestamp"):
		save_data.timestamp = {}
	
	var now_str = Time.get_datetime_string_from_system()
	var today = now_str.split("T")[0] if "T" in now_str else now_str.split(" ")[0]
	
	if not save_data.timestamp.has("last_refresh_date"):
		# 首次运行，使用当前日期
		save_data.timestamp.last_refresh_date = today
		print("首次运行，初始化刷新日期: ", today)
		return
	
	var last_refresh_date = save_data.timestamp.last_refresh_date
	
	print("上次刷新日期: ", last_refresh_date, ", 当前日期: ", today)
	
	# 如果日期不同，刷新地图
	if last_refresh_date != today:
		print("检测到日期变化，刷新地图")
		_perform_daily_refresh(today)

func _perform_daily_refresh(new_date: String):
	"""执行每日刷新操作
	
	参数:
		new_date: 新的日期字符串（YYYY-MM-DD）
	"""
	# 1. 删除opened_chests（刷新宝箱）
	if save_data.has("chest_system_data") and save_data.chest_system_data.has("opened_chests"):
		save_data.chest_system_data.opened_chests = {}
		print("已删除opened_chests，地图已刷新")
	# 删除掉落物（刷新地图）
	if save_data.has("drop_system_data") and save_data.drop_system_data.has("drops_by_scene"):
		save_data.drop_system_data.drops_by_scene = {}
		print("已删除drop_system_data，掉落物已刷新")
	# 删除shop_system_data（刷新商店）
	if save_data.has("shop_system_data"):
		save_data.shop_system_data = {}
		print("已删除shop_system_data，商店已刷新")
	# 删除enemy_system_data（刷新敌人）
	if save_data.has("enemy_system_data"):
		save_data.enemy_system_data = {}
		print("已删除enemy_system_data，敌人已刷新")
	
	# 2. 更新刷新日期
	save_data.timestamp.last_refresh_date = new_date
	print("已更新刷新日期: ", new_date)
	
	# 3. 检查并添加缺失的唯一物品到仓库
	# 延迟调用以确保 InventoryManager 已加载
	call_deferred("_add_missing_unique_items_on_daily_refresh")
	
	# 4. 保存刷新后的数据
	call_deferred("save_game", current_slot, false)

# === 角色数据访问方法 ===

func get_character_scene() -> String:
	"""获取角色当前所在场景"""
	return save_data.character_data.get("current_scene", "")

func set_character_scene(scene_id: String):
	"""设置角色当前所在场景"""
	save_data.character_data.current_scene = scene_id
	character_scene_changed.emit(scene_id)
	_auto_save()

func get_current_weather() -> String:
	"""获取当前天气"""
	return save_data.character_data.get("current_weather", "sunny")

func set_current_weather(weather_id: String):
	"""设置当前天气"""
	save_data.character_data.current_weather = weather_id
	_auto_save()

func get_current_time() -> String:
	"""获取当前时间段"""
	return save_data.character_data.get("current_time", "day")

func set_current_time(time_id: String):
	"""设置当前时间段"""
	save_data.character_data.current_time = time_id
	_auto_save()

func get_character_preset() -> Dictionary:
	"""获取角色当前预设动作"""
	return save_data.character_data.get("current_preset", {})

func set_character_preset(preset: Dictionary):
	"""设置角色当前预设动作"""
	save_data.character_data.current_preset = preset.duplicate(true)
	_auto_save()

func get_costume_id() -> String:
	"""获取当前服装ID"""
	return save_data.character_data.get("costume_id", "default")

func set_costume_id(costume_id: String):
	"""设置当前服装ID"""
	save_data.character_data.costume_id = costume_id
	_auto_save()

func get_affection() -> int:
	return save_data.character_data.get("affection", 0)

func set_affection(value: int):
	save_data.character_data.affection = value
	affection_changed.emit(value)
	_auto_save()

func get_reply_willingness() -> int:
	return save_data.character_data.get("reply_willingness", 100)

func set_reply_willingness(value: int):
	save_data.character_data.reply_willingness = clamp(value, 0, 100)
	willingness_changed.emit(value)
	_auto_save()

func get_mood() -> String:
	return save_data.character_data.get("mood", "平静")

func set_mood(value: String):
	save_data.character_data.mood = value
	mood_changed.emit(value)
	_auto_save()

func get_energy() -> int:
	return save_data.character_data.get("energy", 100)

func set_energy(value: int):
	save_data.character_data.energy = clamp(value, 0, 100)
	energy_changed.emit(value)
	_auto_save()

func get_trust_level() -> int:
	return save_data.character_data.get("trust_level", 0)

func set_trust_level(value: int):
	save_data.character_data.trust_level = value
	_auto_save()

# === 统计数据方法 ===

func increment_messages_sent():
	save_data.statistics.total_messages_sent += 1
	_auto_save()

func increment_messages_received():
	save_data.statistics.total_messages_received += 1
	_auto_save()

func update_favorite_scene(scene_id: String):
	save_data.statistics.favorite_scene = scene_id
	_auto_save()

func update_most_used_action(action: String):
	save_data.statistics.most_used_action = action
	_auto_save()

# === 用户数据方法 ===

func get_user_name() -> String:
	return save_data.user_data.get("user_name", "未设置")

func set_user_name(user_name: String):
	save_data.user_data.user_name = user_name
	_auto_save()

func get_user_address() -> String:
	return save_data.user_data.get("user_address", "你")

func set_user_address(user_address: String):
	save_data.user_data.user_address = user_address
	_auto_save()

func get_character_name() -> String:
	"""获取角色名称"""
	return save_data.get("character_name", "雪狐")

func set_character_name(character_name: String):
	"""设置角色名称"""
	save_data.character_name = character_name
	_auto_save()

func increment_chat_count():
	save_data.user_data.total_chat_count += 1
	_auto_save()

func add_play_time(seconds: float):
	save_data.user_data.total_play_time += seconds
	_auto_save()

# === BGM配置方法 ===

func get_bgm_config() -> Dictionary:
	"""获取BGM配置"""
	return save_data.get("bgm_config", {})

func set_bgm_config(config: Dictionary):
	"""设置BGM配置"""
	save_data.bgm_config = config.duplicate(true)
	_auto_save()

# === 内部方法 ===

func _check_offline_time():
	"""检查离线时间（延迟调用）
	
	注意：离线时间计算使用存档中的 last_played_at（上次退出时间）
	计算完成后不需要立即更新 last_played_at，它会在下次保存时自动更新
	"""
	if has_node("/root/OfflineTimeManager"):
		get_node("/root/OfflineTimeManager").check_and_apply_offline_changes()

func _auto_save():
	"""数据变更时自动保存"""
	# 只有在初始设置完成后才允许自动保存
	if enable_instant_save and is_initial_setup_completed:
		save_game(current_slot)

func _add_missing_unique_items_on_daily_refresh():
	"""每日刷新时添加缺失的唯一物品到仓库"""
	if not has_node("/root/InventoryManager"):
		print("[SaveManager] InventoryManager 未找到，无法添加缺失的唯一物品")
		return
	
	var inventory_mgr = get_node("/root/InventoryManager")
	print("[SaveManager] 开始检查缺失的唯一物品...")
	
	# 获取唯一物品列表
	var unique_items = inventory_mgr.unique_items
	if unique_items.is_empty():
		return
	
	# 统计每个唯一物品的数量
	var item_counts = {}
	var item_locations = {}  # 需要初始化完整的字典结构
	for item_id in unique_items:
		item_counts[item_id] = 0
		item_locations[item_id] = []
	
	# 扫描所有容器
	inventory_mgr._scan_container_for_unique_items(inventory_mgr.inventory_container, "player", item_counts, item_locations)
	inventory_mgr._scan_container_for_unique_items(inventory_mgr.warehouse_container, "warehouse", item_counts, item_locations)
	
	# 扫描雪狐背包
	if save_data.has("snow_fox_inventory"):
		var snow_fox_data = save_data.snow_fox_inventory
		inventory_mgr._scan_storage_data_for_unique_items(snow_fox_data, "snow_fox", item_counts, item_locations)
	
	# 添加缺失的唯一物品到仓库
	for item_id in unique_items:
		if item_counts[item_id] == 0:
			print("[SaveManager] 唯一物品 ", item_id, " 缺失（可能在地图箱子中），添加到仓库")
			inventory_mgr.add_item_to_warehouse(item_id, 1)
	
	# 保存更新后的数据
	save_game(current_slot, false)
	print("[SaveManager] 唯一物品检查完成")

func _deep_merge(base: Dictionary, overlay: Dictionary) -> Dictionary:
	"""深度合并两个字典，overlay的值会覆盖base的值
	
	参数:
		base: 基础字典（模板数据）
		overlay: 覆盖字典（存档数据）
	返回:
		合并后的字典
	"""
	var result = base.duplicate(true)
	
	for key in overlay:
		if overlay[key] is Dictionary and result.has(key) and result[key] is Dictionary:
			# 递归合并嵌套字典
			result[key] = _deep_merge(result[key], overlay[key])
		else:
			# 直接覆盖值（存档数据优先）
			result[key] = overlay[key]
	
	return result

# === 背包数据方法 ===

func _load_inventory_data():
	"""加载背包数据到InventoryManager"""
	print("[SaveManager] 开始加载背包数据...")
	
	if not has_node("/root/InventoryManager"):
		print("[SaveManager] InventoryManager 未找到，延迟重试...")
		await get_tree().create_timer(0.1).timeout
		if not has_node("/root/InventoryManager"):
			print("[SaveManager] 错误: InventoryManager 仍未加载")
			return
	
	var inventory_mgr = get_node("/root/InventoryManager")
	print("[SaveManager] InventoryManager 已找到")
	
	# 检查是否需要初始化仓库物品
	# 只有当所有容器都为空时才需要初始化
	var needs_init = _should_initialize_items()
	print("[SaveManager] 是否需要初始化: ", needs_init)
	
	if save_data.has("inventory_data"):
		print("[SaveManager] 加载现有背包数据...")
		inventory_mgr.load_storage_data(save_data.inventory_data)
	
	# 首次进入或旧版本更新时，添加初始物品到仓库
	if needs_init:
		print("[SaveManager] 开始添加初始物品...")
		_add_initial_items_to_warehouse()
		# 标记已初始化，避免重复添加
		save_data.has_initialized_items = true
		save_inventory_data()
	
	# 初始化雪狐背包（如果不存在）
	if not save_data.has("snow_fox_inventory"):
		save_data.snow_fox_inventory = {
			"storage": [],
			"weapon_slot": {}
		}
		save_data.snow_fox_inventory.storage.resize(12)
		for i in range(12):
			save_data.snow_fox_inventory.storage[i] = null
		print("[SaveManager] 初始化雪狐背包")
	else:
		# 确保storage数组大小正确（但不清空已有数据）
		if not save_data.snow_fox_inventory.has("storage"):
			save_data.snow_fox_inventory.storage = []
		
		var current_size = save_data.snow_fox_inventory.storage.size()
		if current_size < 12:
			# 只扩展不足的部分
			save_data.snow_fox_inventory.storage.resize(12)
			for i in range(current_size, 12):
				save_data.snow_fox_inventory.storage[i] = null
		
		# 确保weapon_slot存在
		if not save_data.snow_fox_inventory.has("weapon_slot"):
			save_data.snow_fox_inventory.weapon_slot = {}
		
		print("[SaveManager] 雪狐背包已存在，保留数据")

func _should_initialize_items() -> bool:
	"""检查是否需要初始化物品（所有容器都为空）"""
	# 如果已经初始化过，直接返回false
	if save_data.get("has_initialized_items", false):
		print("[SaveManager] 已经初始化过物品，跳过")
		return false
	
	# 1. 检查 inventory_data 字段是否存在
	if not save_data.has("inventory_data"):
		print("[SaveManager] inventory_data 字段不存在，需要初始化")
		return true
	
	var inv_data = save_data.inventory_data
	
	# 2. 检查玩家背包是否为空
	var player_inventory_empty = true
	if inv_data.has("inventory"):
		var player_data = inv_data.inventory
		# 检查武器栏
		if player_data.has("weapon_slot") and not player_data.weapon_slot.is_empty():
			player_inventory_empty = false
			print("[SaveManager] 玩家背包武器栏有物品")
		# 检查普通格子
		elif player_data.has("storage"):
			for item in player_data.storage:
				if item != null:
					player_inventory_empty = false
					print("[SaveManager] 玩家背包有物品")
					break
	
	# 3. 检查仓库是否为空
	var warehouse_empty = true
	if inv_data.has("warehouse") and inv_data.warehouse.has("storage"):
		for item in inv_data.warehouse.storage:
			if item != null:
				warehouse_empty = false
				print("[SaveManager] 仓库有物品")
				break
	
	# 4. 检查雪狐背包是否为空
	var snow_fox_empty = true
	if save_data.has("snow_fox_inventory"):
		var snow_fox_data = save_data.snow_fox_inventory
		# 检查武器栏
		if snow_fox_data.has("weapon_slot") and not snow_fox_data.weapon_slot.is_empty():
			snow_fox_empty = false
			print("[SaveManager] 雪狐背包武器栏有物品")
		# 检查普通格子
		elif snow_fox_data.has("storage"):
			for item in snow_fox_data.storage:
				if item != null:
					snow_fox_empty = false
					print("[SaveManager] 雪狐背包有物品")
					break
	
	print("[SaveManager] 容器状态 - 玩家背包: ", "空" if player_inventory_empty else "有物品", 
		  ", 仓库: ", "空" if warehouse_empty else "有物品",
		  ", 雪狐背包: ", "空" if snow_fox_empty else "有物品")
	
	# 只有当所有容器都为空时才需要初始化
	var should_init = player_inventory_empty and warehouse_empty and snow_fox_empty
	print("[SaveManager] 所有容器都为空: ", should_init)
	
	return should_init

func save_inventory_data():
	"""保存背包数据"""
	if has_node("/root/InventoryManager"):
		save_data.inventory_data = get_node("/root/InventoryManager").get_storage_data()
		_auto_save()

func get_inventory_data() -> Dictionary:
	"""获取背包数据"""
	return save_data.get("inventory_data", {"inventory": [], "warehouse": []})

func _add_initial_items_to_warehouse():
	"""添加初始物品到仓库"""
	print("[SaveManager] _add_initial_items_to_warehouse 被调用")
	
	if not has_node("/root/InventoryManager"):
		print("[SaveManager] 错误: InventoryManager 未找到")
		return
	
	var inventory_mgr = get_node("/root/InventoryManager")
	print("[SaveManager] InventoryManager 已获取")
	
	# 定义初始物品列表 [物品ID, 数量]
	var initial_items = [
		["CMR-951", 1],
		["5.8mm_ammo", 64],
		["VSS-SF", 1],
		["9mm_ammo", 64],
		["UMP45", 1],
		[".45_ammo", 64],
	]
	
	print("[SaveManager] 准备添加 ", initial_items.size(), " 种初始物品")
	
	# 添加物品到仓库
	for item_data in initial_items:
		var item_id = item_data[0]
		var count = item_data[1]
		print("[SaveManager] 尝试添加: ", item_id, " x", count)
		var success = inventory_mgr.add_item_to_warehouse(item_id, count)
		if success:
			print("[SaveManager] ✓ 已添加初始物品到仓库: ", item_id, " x", count)
		else:
			print("[SaveManager] ✗ 警告: 无法添加初始物品: ", item_id)
	
	print("[SaveManager] ✓ 初始物品已添加到仓库")
