# Android UI 自动查看工具 (Android UI Automatic Viewer)

这个工具提供了一种简单的方式来捕获Android设备的UI界面，并在浏览器中以交互式方式查看和分析UI结构。

This tool provides a simple way to capture Android device UI interfaces and view and analyze UI structures interactively in a browser.

![Android UI Viewer Screenshot](resources/Screenshot%202025-02-26%20at%2014.53.45.png)

## 功能特点 (Features)

- 自动捕获Android设备屏幕截图
- 自动获取UI层次结构（XML格式）
- 生成交互式HTML查看器，支持：
  - 树形展示UI结构
  - 元素属性详细查看
  - 在截图上高亮显示选中元素
  - 搜索UI元素
  - 查看原始XML内容
  - 多语言支持（英文/中文）
- 完善的中文和日文字符支持
- 自动处理XML编码问题
- 支持多种设备连接方式

## 环境要求 (Requirements)

- macOS或Linux系统（Windows系统可能需要额外配置）
- 已安装ADB（Android Debug Bridge）
- 已启用USB调试的Android设备

## 环境配置 (Environment Setup)

### 1. 安装Android SDK (Install Android SDK)

如果您还没有安装Android SDK，可以通过以下方式安装：

#### macOS（使用Homebrew）:

```bash
brew install android-platform-tools
```

#### Linux:

```bash
sudo apt-get install android-tools-adb
```

或者从Android官网下载Android SDK，然后设置环境变量：

```bash
export ANDROID_SDK_ROOT=/path/to/android/sdk
export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools
```

### 2. 配置设备 (Configure Device)

1. 在Android设备上启用开发者选项：
   - 进入设置 > 关于手机
   - 点击"版本号"7次以启用开发者选项
   - 返回设置，进入新出现的"开发者选项"
   - 启用"USB调试"

2. 连接设备并授权：
   - 使用USB线连接设备到电脑
   - 在设备上确认USB调试授权提示

3. 验证设备连接：
   ```bash
   adb devices
   ```
   应该能看到您的设备列表

## 使用方法 (Usage)

### 基本使用 (Basic Usage)

1. 确保脚本有执行权限：
   ```bash
   chmod +x auto_view_ui.sh
   ```

2. 运行脚本：
   ```bash
   ./auto_view_ui.sh
   ```

3. 脚本将自动：
   - 检测连接的Android设备
   - 捕获屏幕截图
   - 获取UI层次结构
   - 创建HTML查看器
   - 在默认浏览器中打开查看器

### HTML查看器使用 (HTML Viewer Usage)

HTML查看器提供以下功能：

- **语言选择**：在界面顶部选择英文或中文界面
- **树形浏览**：左侧面板显示UI元素的树形结构
- **元素详情**：点击任意元素查看其详细属性
- **元素高亮**：选中元素会在截图上高亮显示
- **搜索功能**：使用顶部搜索框查找特定元素
- **展开/折叠**：使用顶部按钮控制树形结构的展开和折叠
- **查看原始XML**：查看未处理的XML内容
- **重新加载**：刷新当前分析结果
- **再次获取UI**：提供友好的对话框，指导用户在终端中运行脚本获取新的UI数据，并提供刷新按钮查看最新结果
- **导入现有UI**：允许分别导入XML文件和截图图片，实现手动更新UI界面
  - 导入XML文件：更新UI结构树而不影响截图
  - 导入截图：更新界面截图而不影响UI结构树

## 目录结构 (Directory Structure)

```
.
├── auto_view_ui.sh    # 主脚本文件
└── resources/         # 资源文件目录
    ├── no_image.png   # 截图获取失败时的占位图
    └── Screenshot.png # 界面截图示例
```

## 故障排除 (Troubleshooting)

1. **找不到设备**：
   - 确保设备已正确连接并已授权USB调试
   - 运行`adb devices`检查设备是否被识别
   - 检查USB线是否正常工作

2. **无法获取UI结构**：
   - 某些应用可能限制UI获取，尝试不同的应用
   - 确保设备未锁屏
   - 尝试重启ADB服务：`adb kill-server && adb start-server`

3. **中文/日文字符显示问题**：
   - 脚本已内置处理多语言字符的功能
   - 如果仍有问题，检查设备和电脑的语言设置

4. **HTML查看器无法打开**：
   - 手动打开生成的HTML文件：`auto_view/[时间戳]/viewer.html`
   - 检查浏览器是否支持现代JavaScript功能

## 高级用法 (Advanced Usage)

### 自定义ADB路径 (Custom ADB Path)

如果您的ADB不在标准路径，可以修改脚本开头的环境变量设置：

```bash
export ANDROID_SDK_ROOT=/your/custom/path
```

### 集成到其他工具 (Integration with Other Tools)

您可以将此脚本集成到自动化测试流程中：

```bash
./auto_view_ui.sh && echo "UI分析完成"
```

## 改进建议 (Improvement Suggestions)

### 在当前界面中直接更新UI数据 (Update UI Data Directly in Current Interface)

已实现的改进：
1. ✅ 允许分别导入XML文件和截图图片，实现手动更新UI界面
2. ✅ 添加多语言支持（英文/中文）

未来的改进可以包括：
1. 实现在当前HTML查看器中直接更新UI数据的功能，无需刷新页面
2. 创建一个简单的本地服务器，处理UI捕获请求
3. 添加WebSocket支持，实现实时UI更新
4. 开发一个浏览器扩展，允许从浏览器直接执行脚本

## 许可 (License)

此工具仅供个人学习和开发使用。

## 贡献 (Contribution)

欢迎提交问题报告和改进建议。 