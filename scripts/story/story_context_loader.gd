extends Node
class_name StoryContextLoader

# 故事上下文加载器
# 负责加载故事上下文和历史记录

# 最大AI上下文数量
const MAX_AI_CONTEXT_COUNT: int = 20

# 依赖的面板引用
var story_dialog_panel: Control = null

# 缓存的上下文数据
var current_ai_context: Array = []  # AI上下文消息数组
var loaded_node_contexts: Dictionary = {}  # 已加载的节点上下文缓存

# 加载状态管理
var is_loading_context: bool = false  # 是否正在加载上下文
var loaded_parent_nodes: Array = []  # 已加载的父节点列表，防止重复加载
var last_scroll_position: float = 0.0  # 上次滚动位置，用于检测滚动方向

func _ready():
	"""初始化"""
	pass

func set_story_dialog_panel(panel: Control):
	"""设置故事对话面板引用"""
	story_dialog_panel = panel

func initialize_story_context() -> Array:
	"""初始化故事上下文（进入故事时调用）

	Returns:
		系统消息数组，需要显示在聊天栏中
	"""
	if not story_dialog_panel:
		push_error("故事对话面板引用未设置")
		return []

	# 清空缓存
	current_ai_context.clear()
	loaded_node_contexts.clear()

	# 加载AI上下文（不显示）
	_load_ai_context()

	# 生成系统消息（显示）
	var system_messages = _generate_enter_story_system_messages()

	return system_messages

func _load_ai_context():
	"""加载AI上下文（20条历史记录，从当前节点向上查找）"""
	if not story_dialog_panel:
		return

	var story_data = story_dialog_panel.story_data
	var nodes_data = story_dialog_panel.nodes_data
	var current_node_id = story_dialog_panel.current_node_id

	if story_data.is_empty() or nodes_data.is_empty():
		return

	# 从当前节点开始向上查找历史记录
	var context_messages: Array = []
	var current_node = current_node_id

	# 遍历节点链，直到收集够20条记录或到达根节点
	while context_messages.size() < MAX_AI_CONTEXT_COUNT and not current_node.is_empty():
		# 获取当前节点的对话记录
		var node_messages = _get_node_messages(current_node)
		if not node_messages.is_empty():
			# 将消息添加到上下文的开头（因为是从下往上遍历）
			context_messages.insert(0, node_messages)

		# 查找父节点
		current_node = _find_parent_node(current_node)

	# 扁平化消息数组
	var flattened_context: Array = []
	for node_msg_array in context_messages:
		for msg in node_msg_array:
			if flattened_context.size() >= MAX_AI_CONTEXT_COUNT:
				break
			flattened_context.append(msg)
		if flattened_context.size() >= MAX_AI_CONTEXT_COUNT:
			break

	# 更新AI上下文缓存
	current_ai_context = flattened_context

	# 应用到StoryAI
	if story_dialog_panel.story_ai:
		story_dialog_panel.story_ai.conversation_history = flattened_context.duplicate()

func _get_node_messages(node_id: String) -> Array:
	"""获取节点的对话消息

	Args:
		node_id: 节点ID

	Returns:
		消息数组，格式为[{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]
	"""
	if not story_dialog_panel or story_dialog_panel.nodes_data.is_empty():
		return []

	var node_data = story_dialog_panel.nodes_data.get(node_id, {})
	var messages = node_data.get("message", [])

	var formatted_messages: Array = []

	for msg in messages:
		var msg_type = msg.get("type", "")
		var msg_text = msg.get("text", "")

		if msg_type == "user":
			formatted_messages.append({
				"role": "user",
				"content": msg_text
			})
		elif msg_type == "ai":
			formatted_messages.append({
				"role": "assistant",
				"content": msg_text
			})
		# 忽略系统消息，不加入AI上下文

	return formatted_messages

func _find_parent_node(node_id: String) -> String:
	"""查找节点的父节点

	Args:
		node_id: 节点ID

	Returns:
		父节点ID，如果没有找到则返回空字符串
	"""
	if not story_dialog_panel or story_dialog_panel.nodes_data.is_empty():
		return ""

	# 遍历所有节点，找到包含当前节点作为子节点的节点
	for parent_id in story_dialog_panel.nodes_data.keys():
		var parent_data = story_dialog_panel.nodes_data[parent_id]
		var child_nodes = parent_data.get("child_nodes", [])

		if node_id in child_nodes:
			return parent_id

	return ""

func _generate_enter_story_system_messages() -> Array:
	"""生成进入故事时的系统消息

	Returns:
		系统消息数组
	"""
	var system_messages: Array = []

	if not story_dialog_panel:
		return system_messages

	var nodes_data = story_dialog_panel.nodes_data
	var current_node_id = story_dialog_panel.current_node_id

	# 获取当前节点的简介（作为"上一个节点"的简介）
	var current_node_data = nodes_data.get(current_node_id, {})
	var current_node_summary = current_node_data.get("display_text", current_node_id)

	# 检查当前节点是否为根节点（没有父节点），如果是则不加"↑"
	var is_root_node = _find_parent_node(current_node_id).is_empty()
	var system_message = current_node_summary if is_root_node else "↑\n" + current_node_summary

	system_messages.append(system_message)

	return system_messages

func load_previous_node_context() -> Dictionary:
	"""加载上一节点的完整对话记录（用于顶部翻页）

	Returns:
		包含消息数组和新的当前节点ID的字典
		{
			"messages": Array,  # 消息数组，包含对话记录
			"new_current_node_id": String  # 新的当前节点ID
		}
	"""
	var result = {
		"messages": [],
		"new_current_node_id": ""
	}

	if not story_dialog_panel or is_loading_context:
		return result

	# 设置加载状态
	is_loading_context = true

	# 当前节点就是"上一个节点"，需要加载其消息
	var current_node_id = story_dialog_panel.current_node_id
	var parent_node_id = _find_parent_node(current_node_id)

	if parent_node_id.is_empty():
		# 没有父节点，无法加载更多上下文
		is_loading_context = false
		return result

	# 检查是否已经加载过当前节点
	if current_node_id in loaded_parent_nodes:
		# 已经加载过，不重复加载
		is_loading_context = false
		return result

	var context_messages: Array = []

	# 获取当前节点的对话记录（"上一个节点"的消息气泡）
	var current_messages = story_dialog_panel.nodes_data.get(current_node_id, {}).get("message", [])

	# 倒序添加当前节点的消息（从最早的消息开始）
	for i in range(current_messages.size() - 1, -1, -1):
		context_messages.append(current_messages[i])

	# 获取父节点（"上上个节点"）的简介作为系统消息
	# 根节点的display_text也需要被显示
	var parent_node_data = story_dialog_panel.nodes_data.get(parent_node_id, {})
	var parent_summary = parent_node_data.get("display_text", parent_node_id)

	# 检查父节点是否为根节点（没有父节点），如果是则不加"↑"
	var is_root_node = _find_parent_node(parent_node_id).is_empty()
	var system_message = parent_summary if is_root_node else "↑\n" + parent_summary

	context_messages.append({
		"type": "system",
		"text": system_message
	})

	# 缓存已加载的上下文
	loaded_node_contexts[current_node_id] = context_messages.duplicate()

	# 记录已加载的节点
	loaded_parent_nodes.append(current_node_id)

	# 重置加载状态
	is_loading_context = false

	result["messages"] = context_messages
	result["new_current_node_id"] = parent_node_id

	return result

func get_ai_context() -> Array:
	"""获取当前AI上下文

	Returns:
		AI上下文消息数组
	"""
	return current_ai_context.duplicate()

func can_load_previous_context(current_node_id: String) -> bool:
	"""检查是否可以加载上一节点的上下文

	Args:
		current_node_id: 当前节点ID

	Returns:
		是否可以加载上一章节
	"""
	if not story_dialog_panel:
		return false

	# 查找父节点（"上上个节点"）
	var parent_node_id = _find_parent_node(current_node_id)

	# 检查是否有父节点且当前节点未被加载过
	return not parent_node_id.is_empty() and not (current_node_id in loaded_parent_nodes)

func clear_cache():
	"""清空缓存"""
	current_ai_context.clear()
	loaded_node_contexts.clear()
	loaded_parent_nodes.clear()
	is_loading_context = false
	last_scroll_position = 0.0