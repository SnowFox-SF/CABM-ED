extends MarginContainer
## 记忆系统配置管理模块
## 处理记忆向量、语义检索、重排序和知识图谱的配置

# 记忆系统配置UI引用
@onready var save_vector_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/SaveVectorCheckBox
@onready var semantic_search_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/SemanticSearchCheckBox
@onready var rerank_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/RerankCheckBox
@onready var pre_recall_reasoning_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/PreRecallReasoningCheckBox
@onready var save_kg_checkbox: CheckBox = $ScrollContainer/VBoxContainer/KGContainer/SaveKGCheckBox
@onready var kg_search_checkbox: CheckBox = $ScrollContainer/VBoxContainer/KGContainer/KGSearchCheckBox
@onready var enable_forgetting_checkbox: CheckBox = $ScrollContainer/VBoxContainer/KGContainer/EnableForgettingCheckBox

var config_manager: Node

func _ready():
	# 连接信号
	save_vector_checkbox.toggled.connect(_on_save_vector_toggled)
	semantic_search_checkbox.toggled.connect(_on_semantic_search_toggled)
	rerank_checkbox.toggled.connect(_on_rerank_toggled)
	pre_recall_reasoning_checkbox.toggled.connect(_on_pre_recall_reasoning_toggled)
	save_kg_checkbox.toggled.connect(_on_save_kg_toggled)
	kg_search_checkbox.toggled.connect(_on_kg_search_toggled)
	enable_forgetting_checkbox.toggled.connect(_on_enable_forgetting_toggled)

func initialize(config_mgr: Node):
	"""初始化记忆系统配置管理器"""
	config_manager = config_mgr
	load_memory_config()

func _on_save_vector_toggled(enabled: bool):
	"""保存记忆向量勾选框状态改变"""
	if not enabled:
		# 父节点关闭时，子节点也关闭
		semantic_search_checkbox.button_pressed = false
		rerank_checkbox.button_pressed = false
		pre_recall_reasoning_checkbox.button_pressed = false

	# 更新子节点可用性
	semantic_search_checkbox.disabled = not enabled
	if not enabled:
		rerank_checkbox.disabled = true
		pre_recall_reasoning_checkbox.disabled = true
	else:
		rerank_checkbox.disabled = not semantic_search_checkbox.button_pressed
		pre_recall_reasoning_checkbox.disabled = not semantic_search_checkbox.button_pressed

	# 自动保存配置
	_auto_save_config()

func _on_semantic_search_toggled(enabled: bool):
	"""语义检索勾选框状态改变"""
	if not enabled:
		# 父节点关闭时，子节点也关闭
		rerank_checkbox.button_pressed = false
		pre_recall_reasoning_checkbox.button_pressed = false

	# 更新子节点可用性
	rerank_checkbox.disabled = not enabled
	pre_recall_reasoning_checkbox.disabled = not enabled

	# 自动保存配置
	_auto_save_config()

func _on_rerank_toggled(_enabled: bool):
	"""重排勾选框状态改变"""
	# 重排没有子节点，不需要特殊处理
	_auto_save_config()

func _on_pre_recall_reasoning_toggled(_enabled: bool):
	"""召回前推理勾选框状态改变"""
	# 召回前推理没有子节点，不需要特殊处理
	_auto_save_config()

func _on_save_kg_toggled(enabled: bool):
	"""保存知识图谱勾选框状态改变"""
	if not enabled:
		# 父节点关闭时，子节点也关闭
		kg_search_checkbox.button_pressed = false
		enable_forgetting_checkbox.button_pressed = false

	# 更新子节点可用性
	kg_search_checkbox.disabled = not enabled
	enable_forgetting_checkbox.disabled = not enabled

	# 自动保存配置
	_auto_save_config()

func _on_kg_search_toggled(_enabled: bool):
	"""图谱检索勾选框状态改变"""
	# 图谱检索没有子节点，不需要特殊处理
	_auto_save_config()

func _on_enable_forgetting_toggled(_enabled: bool):
	"""启用知识遗忘勾选框状态改变"""
	# 知识遗忘没有子节点，不需要特殊处理
	_auto_save_config()

func _auto_save_config():
	"""自动保存记忆系统配置"""
	var config = collect_memory_config()
	config_manager.save_memory_config(config)

func collect_memory_config() -> Dictionary:
	"""收集当前UI中的配置"""
	return {
		"save_memory_vectors": save_vector_checkbox.button_pressed,
		"enable_semantic_search": semantic_search_checkbox.button_pressed,
		"enable_reranking": rerank_checkbox.button_pressed,
		"enable_pre_recall_reasoning": pre_recall_reasoning_checkbox.button_pressed,
		"save_knowledge_graph": save_kg_checkbox.button_pressed,
		"enable_kg_search": kg_search_checkbox.button_pressed,
		"enable_knowledge_forgetting": enable_forgetting_checkbox.button_pressed
	}

func load_memory_config():
	"""加载记忆系统配置"""
	var config = config_manager.load_memory_config()

	# 设置勾选框状态
	save_vector_checkbox.button_pressed = config.get("save_memory_vectors", true)
	semantic_search_checkbox.button_pressed = config.get("enable_semantic_search", true)
	rerank_checkbox.button_pressed = config.get("enable_reranking", true)
	pre_recall_reasoning_checkbox.button_pressed = config.get("enable_pre_recall_reasoning", false)
	save_kg_checkbox.button_pressed = config.get("save_knowledge_graph", true)
	kg_search_checkbox.button_pressed = config.get("enable_kg_search", true)
	enable_forgetting_checkbox.button_pressed = config.get("enable_knowledge_forgetting", true)

	# 设置初始的禁用状态
	semantic_search_checkbox.disabled = not save_vector_checkbox.button_pressed
	rerank_checkbox.disabled = not (save_vector_checkbox.button_pressed and semantic_search_checkbox.button_pressed)
	pre_recall_reasoning_checkbox.disabled = not (save_vector_checkbox.button_pressed and semantic_search_checkbox.button_pressed)
	kg_search_checkbox.disabled = not save_kg_checkbox.button_pressed
	enable_forgetting_checkbox.disabled = not save_kg_checkbox.button_pressed
