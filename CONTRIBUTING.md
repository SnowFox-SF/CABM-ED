# 贡献代码/衍生项目

## 开始之前

### 1. 了解项目
- 请先阅读 [README.md](README.md) 了解项目理念、功能、使用方式、协议、架构等

### 2. 开发环境准备

#### Git 安装与配置
1. **下载 Git**
   - Windows: 从 [git-scm.com](https://git-scm.com/download/win) 下载
   - macOS: 使用 Homebrew `brew install git` 或从官网下载
   - Linux: 使用包管理器安装，如 `sudo apt install git` (Ubuntu/Debian)

2. **配置 Git**
   ```bash
   git config --global user.name "你的名字"
   git config --global user.email "你的邮箱"
   ```

#### 项目克隆
```bash
# 克隆项目到本地
git clone https://github.com/SnowFox-SF/CABM-ED.git
cd CABM-ED
```

#### Godot 引擎安装
- 下载 [Godot 4.5](https://godotengine.org/download/) 或更高版本
- 确保使用与项目兼容的版本

## 贡献流程

### 1. 创建 Issue（可选但推荐）
- 在 [Issues](https://github.com/SnowFox-SF/CABM-ED/issues)与[反馈表](https://docs.qq.com/sheet/DZHdYdGhIa1Z6VmZk)中查看是否已有类似问题
- 如果没有，创建一个新 Issue 描述你的想法或发现的 bug
- 明确说明：问题描述、重现步骤、预期行为、实际行为

### 2. 分支管理
```bash
# 同步主分支
git checkout main
git pull origin main

# 创建功能分支
git checkout -b feature/你的功能名称
# 或修复分支
git checkout -b fix/修复的问题描述
```

### 3. 代码规范
- **GDScript**: 遵循 Godot 官方 GDScript 风格指南
- **C++**: 使用一致的命名约定和代码格式，最好同时提交编译好的插件
- **注释**: 关键算法和复杂逻辑需要添加注释
- **提交信息**: 使用清晰、有意义的提交信息

### 4. 测试你的改动
1. 在 Godot 编辑器中测试你的功能
2. 确保没有引入新的错误
3. 在不同场景下验证功能正常

### 5. 提交更改
```bash
# 添加修改的文件
git add .

# 提交更改
git commit -m "描述你的修改内容"

# 推送到远程
git push origin 你的分支名称
```

### 6. 创建 Pull Request
1. 访问项目的 GitHub 仓库
2. 点击 "New Pull Request"
3. 选择你的分支与主分支进行比较
4. 填写 PR 描述，包括：
   - 修改内容概述
   - 解决的问题或添加的功能
   - 测试情况说明
   - 相关 Issue 编号（如果有）

## 衍生项目开发

如果你计划基于 CABM-ED 开发衍生项目，请注意：

### 许可协议
- 你可以自由使用 `./scripts/` 和 `./scenes/` 目录下的 MIT 许可代码
- 其他资源（美术、配置等）**不得用于商业**
- 衍生项目需要明确声明代码来源和授权范围

### 开发建议
1. **保持兼容**: 尽量与主项目保持兼容性（例如存档文件）
2. **明确差异**: 清楚说明你的项目与原始项目的区别
3. **遵守协议**: 严格遵守不同资源的许可协议

### 注意事项
- 未经许可不得使用项目中的角色设定、故事内容等原创元素
- 不得误导用户认为衍生项目是官方版本
- 建议在项目文档中明确标注 "基于 CABM-ED"

## 获取帮助

### 沟通渠道
- **GitHub Issues**: 功能建议、bug 报告
- **QQ群**: 236025099

### 联系开发者
在提交重要改动前，建议先开发者沟通，确保你的贡献方向与项目规划一致。

---

感谢你为 CABM-ED 项目做出的贡献！每一次贡献都让这个项目更加完善，让"她"的世界更加丰富。