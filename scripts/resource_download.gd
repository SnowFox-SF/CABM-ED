extends Control

@onready var progress_bar: ProgressBar = $Panel/VBox/ProgressBar
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var hint_label: Label = $Panel/VBox/HintLabel
@onready var download_button: Button = $Panel/VBox/Buttons/DownloadButton
@onready var import_button: Button = $Panel/VBox/Buttons/ImportButton

var http_request: HTTPRequest
var current_url_index: int = 0
var download_urls: Array = [
	"https://github.com/xhc2008/CABM-ED/releases/download/resources/resouces-v1-20251208-1.zip?mirror=tuna",
	"https://github.com/xhc2008/CABM-ED/releases/download/resources/resouces-v1-20251208-1.zip",
]
var required_version: String = "CABM-ED_RES_v1-20251208-1"

# 添加下载统计变量
var download_start_time: int = 0
var last_downloaded_bytes: int = 0
var last_update_time: int = 0

func _ready():
	if has_node("/root/SaveManager"):
		required_version = get_node("/root/SaveManager").get_required_resource_version()
	_ensure_resources_dir()
	_set_ui_enabled(true)
	_show_hint()
	download_button.pressed.connect(_on_download_pressed)
	import_button.pressed.connect(_on_import_pressed)

func _show_hint():
	hint_label.text = "需要安装资源包才能开始游戏。可选择在线下载或手动导入压缩包。完成后需要重启游戏。"

func _set_ui_enabled(enabled: bool):
	download_button.disabled = not enabled
	import_button.disabled = not enabled

func _on_download_pressed():
	_set_ui_enabled(false)
	# 修复：将进度条初始值设为0
	progress_bar.value = 0
	status_label.text = "开始下载资源..."
	current_url_index = 0
	_start_next_download()

func _start_next_download():
	if current_url_index >= download_urls.size():
		status_label.text = "所有下载源失败，请尝试手动导入"
		_set_ui_enabled(true)
		return
	
	var url = download_urls[current_url_index]
	status_label.text = "尝试下载: " + url.get_file()
	if http_request:
		http_request.queue_free()
	
	# 重置下载统计
	download_start_time = Time.get_ticks_msec()
	last_downloaded_bytes = 0
	last_update_time = download_start_time
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	# 连接进度信号
	http_request.request_completed.connect(_on_request_completed)
	http_request.download_file = "user://resources/_download.zip"
	
	var err = http_request.request(url)
	if err != OK:
		status_label.text = "发送请求失败，切换下一源"
		current_url_index += 1
		_start_next_download()
		return
	
	# 开始进度更新循环
	_update_progress_loop()

func _update_progress_loop():
	while http_request and http_request.is_inside_tree() and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_update_progress()
		await get_tree().create_timer(0.1).timeout

func _update_progress():
	if not http_request or not http_request.is_inside_tree():
		return
	
	var downloaded = http_request.get_downloaded_bytes()
	var total = http_request.get_body_size()
	
	# 计算下载速度
	var current_time = Time.get_ticks_msec()
	var time_diff = max(current_time - last_update_time, 1) / 1000.0  # 转换为秒
	var bytes_diff = downloaded - last_downloaded_bytes
	var speed_kbps = 0.0
	var eta_seconds = -1  # ETA初始值
	
	if time_diff > 0 and bytes_diff > 0:
		speed_kbps = (bytes_diff / time_diff) / 1024.0
		# 计算ETA（预估剩余时间）
		if total > 0 and speed_kbps > 0:
			var remaining_bytes = total - downloaded
			var remaining_kb = remaining_bytes / 1024.0
			eta_seconds = int(remaining_kb / speed_kbps)
	
	# 更新下载统计
	last_downloaded_bytes = downloaded
	last_update_time = current_time
	
	# 更新进度条
	if total > 0:
		var pct = float(downloaded) / float(total) * 100.0
		progress_bar.value = clamp(pct, 0.0, 100.0)
		
		# 格式化显示大小和速度
		var downloaded_mb = downloaded / (1024.0 * 1024.0)
		var total_mb = total / (1024.0 * 1024.0)
		var speed_str = "%.1f KB/s" % speed_kbps
		var size_str = "%.1f/%.1f MB" % [downloaded_mb, total_mb]
		
		# 更新状态标签，显示下载大小、速度和ETA
		if eta_seconds >= 0:
			var eta_str = _format_eta(eta_seconds)
			status_label.text = "下载中: %s - %s (ETA: %s)" % [size_str, speed_str, eta_str]
		else:
			status_label.text = "下载中: %s - %s" % [size_str, speed_str]
	else:
		# 如果服务器没有提供总大小，只显示已下载大小和速度
		var downloaded_mb = downloaded / (1024.0 * 1024.0)
		var speed_str = "%.1f KB/s" % speed_kbps
		status_label.text = "下载中: %.1f MB - %s" % [downloaded_mb, speed_str]
		# 修复：不使用固定值，而是根据下载情况动态显示
		if downloaded > 0:
			# 如果已经开始下载但没有总大小，显示一个缓慢增长的进度
			progress_bar.value = min(float(downloaded) / (10 * 1024 * 1024) * 100.0, 90.0)  # 假设最大10MB
		else:
			progress_bar.value = 0

# 格式化ETA为易读格式
func _format_eta(seconds: int) -> String:
	if seconds < 60:
		return "%d秒" % seconds
	elif seconds < 3600:
		var minutes = seconds / 60
		var remaining_seconds = seconds % 60
		if remaining_seconds > 0:
			return "%d分%d秒" % [minutes, remaining_seconds]
		else:
			return "%d分钟" % minutes
	else:
		var hours = seconds / 3600
		var minutes = (seconds % 3600) / 60
		if minutes > 0:
			return "%d小时%d分" % [hours, minutes]
		else:
			return "%d小时" % hours

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	if result != OK or response_code < 200 or response_code >= 300:
		status_label.text = "下载失败 (" + str(response_code) + ")，尝试下一源"
		current_url_index += 1
		_start_next_download()
		return
	status_label.text = "下载完成，开始解压"
	_extract_zip_and_finalize("user://resources/_download.zip")

func _on_import_pressed():
	if OS.get_name() == "Android":
		var perm_helper = load("res://scripts/android_permissions.gd").new()
		add_child(perm_helper)
		
		var has_permission = await perm_helper.request_storage_permission()
		perm_helper.queue_free()
		
		if not has_permission:
			return
	_set_ui_enabled(false)
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.add_filter("*.zip", "资源包")
	fd.file_selected.connect(_on_import_file_selected)
	# 连接取消信号
	fd.canceled.connect(_on_import_canceled)
	get_tree().root.add_child(fd)
	fd.popup_centered(Vector2i(800, 600))

# 添加取消导入的回调函数
func _on_import_canceled():
	_set_ui_enabled(true)
	status_label.text = "取消导入，等待操作"

func _on_import_file_selected(path: String):
	status_label.text = "选择文件: " + path.get_file() + "，检查版本..."
	# 先检查压缩包版本
	var version_check_result = 	_check_zip_version(path)
	if version_check_result:
		status_label.text = "版本检查通过，开始解压..."
		_extract_zip_and_finalize(path)
	else:
		_set_ui_enabled(true)
		status_label.text = "版本不匹配或缺少版本信息，请下载正确版本"

# 检查压缩包版本
func _check_zip_version(zip_path: String) -> bool:
	progress_bar.value = 10
	status_label.text = "正在检查资源包版本..."
	
	var zip = ZIPReader.new()
	var err = zip.open(zip_path)
	if err != OK:
		status_label.text = "无法打开ZIP文件"
		return false
	
	var files = zip.get_files()
	var found_version = false
	var zip_version = ""
	
	# 查找压缩包中的version.txt文件
	for file_path in files:
		if file_path.ends_with("version.txt"):
			# 读取版本文件内容
			var content = zip.read_file(file_path)
			if content.size() > 0:
				zip_version = content.get_string_from_utf8().strip_edges()
				found_version = true
				break
	
	zip.close()
	
	progress_bar.value = 20
	
	if not found_version:
		status_label.text = "资源包缺少版本信息"
		return false
	
	if required_version.is_empty():
		# 如果没有指定必需版本，接受任何版本
		status_label.text = "资源包版本: " + zip_version
		return true
	
	# 检查版本是否匹配
	if zip_version == required_version:
		status_label.text = "资源包版本匹配: " + zip_version
		return true
	else:
		status_label.text = "版本不匹配，需要: " + required_version + "，当前: " + zip_version
		return false

func _extract_zip_and_finalize(zip_path: String):
	progress_bar.value = 30
	var ok = _extract_resources_zip(zip_path)
	if not ok:
		status_label.text = "解压失败，请重试或更换文件"
		_set_ui_enabled(true)
		return
	
	# 不再创建version文件，因为资源包已经包含
	status_label.text = "资源安装完成！请重启游戏以生效。"
	progress_bar.value = 100
	
	# 创建重启提示对话框
	_show_restart_dialog()

func _show_restart_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "安装完成"
	dialog.dialog_text = "资源包已成功安装！\n需要重启游戏才能生效。"
	dialog.confirmed.connect(func(): get_tree().quit())
	dialog.canceled.connect(func(): get_tree().quit())
	
	# 修改确定按钮文本
	dialog.ok_button_text = "确定并退出"
	
	get_tree().root.add_child(dialog)
	dialog.popup_centered(Vector2i(400, 200))

func _ensure_resources_dir():
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("resources"):
		dir.make_dir("resources")

func _extract_resources_zip(import_path: String) -> bool:
	status_label.text = "正在解压文件..."
	progress_bar.value = 50
	
	var zip = ZIPReader.new()
	var err = zip.open(import_path)
	if err != OK:
		status_label.text = "无法打开ZIP文件"
		return false
	
	var files = zip.get_files()
	var strip_prefix := ""
	# 检测是否有顶层 resources/ 目录
	for fp in files:
		if fp.begins_with("resources/"):
			strip_prefix = "resources/"
			break
	
	var total_files = files.size()
	var processed_files = 0
	
	for file_path in files:
		var content = zip.read_file(file_path)
		if content.size() == 0 and not file_path.ends_with("/"):
			continue
		if file_path.ends_with("/"):
			continue
		
		var rel_path = file_path
		if not strip_prefix.is_empty() and rel_path.begins_with(strip_prefix):
			rel_path = rel_path.substr(strip_prefix.length())
		
		# 跳过version.txt文件，不再覆盖它
		if rel_path == "version.txt":
			processed_files += 1
			continue
		
		var base_path = ProjectSettings.globalize_path("user://resources")
		var full_path = base_path + "/" + rel_path
		var dir_path = full_path.get_base_dir()
		
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		
		var f = FileAccess.open(full_path, FileAccess.WRITE)
		if f:
			f.store_buffer(content)
			f.close()
		else:
			status_label.text = "写入文件失败: " + full_path.get_file()
			zip.close()
			return false
		
		processed_files += 1
		# 更新解压进度
		if total_files > 0:
			var progress = float(processed_files) / float(total_files) * 50 + 50
			progress_bar.value = progress
	
	zip.close()
	return true
