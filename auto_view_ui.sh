#!/bin/bash

# Auto View UI - 全自动UI捕获和查看工具
# 此脚本自动捕获Android设备UI并在浏览器中展示

# 设置环境变量
# export PATH=$PATH:$(pwd)/platform-tools
# export PATH=$PATH:/Users/linlide/Documents/workspace/android_sdk/platform-tools

# 使用标准的Android SDK环境变量
if [ -n "$ANDROID_SDK_ROOT" ]; then
  export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools
elif [ -n "$ANDROID_HOME" ]; then
  export PATH=$PATH:$ANDROID_HOME/platform-tools
else
  echo "警告: 未找到ANDROID_SDK_ROOT或ANDROID_HOME环境变量，尝试使用默认路径"
  # 尝试常见的默认路径
  if [ -d "$HOME/Library/Android/sdk" ]; then
    export PATH=$PATH:$HOME/Library/Android/sdk/platform-tools
  elif [ -d "$HOME/Android/Sdk" ]; then
    export PATH=$PATH:$HOME/Android/Sdk/platform-tools
  fi
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 恢复颜色

# 创建输出目录
OUTPUT_DIR="$(pwd)/auto_view"
mkdir -p "$OUTPUT_DIR"

# 获取时间戳
TIMESTAMP=$(date +"%Y%m%d_%H%M%S_%N" | cut -c1-19)
SESSION_DIR="$OUTPUT_DIR/$TIMESTAMP"
mkdir -p "$SESSION_DIR"

# 检查设备连接
check_device() {
  echo -e "${BLUE}正在检查设备连接...${NC}"
  DEVICES=$(adb devices | grep -v "List" | grep -v "^$" | wc -l)
  
  if [ "$DEVICES" -eq "0" ]; then
    echo -e "${YELLOW}警告: 没有设备连接，将使用测试模式${NC}"
    TEST_MODE=true
    return 0
  elif [ "$DEVICES" -gt "1" ]; then
    echo -e "${YELLOW}警告: 发现多个设备连接${NC}"
    adb devices
    echo -e "${YELLOW}注意：将使用第一个设备${NC}"
  fi
  
  TEST_MODE=false
  DEVICE_ID=$(adb devices | grep -v "List" | grep -v "^$" | head -n 1 | awk '{print $1}')
  echo -e "${GREEN}使用设备: $DEVICE_ID${NC}"
}

# 确保XML文件使用UTF-8编码
ensure_utf8_encoding() {
  local xml_file="$1"
  
  if [ -f "$xml_file" ]; then
    # 检查文件编码
    local encoding
    encoding=$(file -I "$xml_file" | grep -o "charset=.*" | cut -d= -f2)
    
    # 如果不是UTF-8，尝试转换
    if [ "$encoding" != "utf-8" ] && [ "$encoding" != "utf8" ] && [ "$encoding" != "us-ascii" ]; then
      echo "检测到非UTF-8编码 ($encoding)，尝试转换..."
      # 创建备份
      cp "$xml_file" "${xml_file}.bak"
      # 使用iconv转换编码
      iconv -f "$encoding" -t UTF-8 "${xml_file}.bak" > "$xml_file" 2>/dev/null || {
        # 如果iconv失败，尝试使用通用方法
        cat "${xml_file}.bak" | tr -cd '[:print:]\n\r\t' > "$xml_file"
      }
    fi
    
    # 检查并修复XML文件的编码声明
    if ! grep -q "encoding=\"UTF-8\"" "$xml_file" && ! grep -q "encoding='UTF-8'" "$xml_file"; then
      # 如果没有指定UTF-8编码，添加或替换编码声明
      sed -i.bak 's/<?xml version="1.0"?>/<?xml version="1.0" encoding="UTF-8"?>/' "$xml_file"
      sed -i.bak 's/<?xml version='\''1.0'\''?>/<?xml version='\''1.0'\'' encoding='\''UTF-8'\''?>/' "$xml_file"
      # 如果文件没有XML声明，添加一个
      if ! grep -q "<?xml" "$xml_file"; then
        sed -i.bak '1s/^/<?xml version="1.0" encoding="UTF-8"?>\n/' "$xml_file"
      fi
    fi
    
    # 清理备份文件
    rm -f "${xml_file}.bak"
  fi
}

# 修复XML内容中的特殊字符
fix_xml_content() {
  local xml_file="$1"
  
  if [ -f "$xml_file" ]; then
    # 创建临时文件
    local temp_file="${xml_file}.tmp"
    
    # 修复常见的XML问题
    cat "$xml_file" | 
      # 替换非法XML字符
      sed 's/&#0;/ /g' |
      # 确保所有标签正确关闭
      sed 's/&/\&amp;/g; s/&amp;amp;/\&amp;/g; s/&amp;lt;/\&lt;/g; s/&amp;gt;/\&gt;/g;' |
      # 修复可能的编码问题
      iconv -f UTF-8 -t UTF-8//IGNORE > "$temp_file" 2>/dev/null || cat "$xml_file" > "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$xml_file"
    
    # 确保文件使用UTF-8编码
    local charset=$(file -I "$xml_file" | grep -o "charset=.*" | cut -d= -f2)
    if [ "$charset" != "utf-8" ] && [ "$charset" != "utf8" ] && [ "$charset" != "us-ascii" ]; then
      echo "检测到非UTF-8编码 ($charset)，尝试转换..."
      iconv -f "$charset" -t UTF-8 "$xml_file" > "${xml_file}.utf8" 2>/dev/null && mv "${xml_file}.utf8" "$xml_file"
    fi
  fi
}

# 捕获屏幕截图和UI布局
capture_ui() {
  echo -e "${BLUE}正在捕获屏幕截图和UI布局...${NC}"
  
  # 检查是否已经有捕获进程在运行
  if [ -f "$SESSION_DIR/.capture_lock" ]; then
    echo -e "${YELLOW}已有捕获进程正在运行，请等待完成或删除锁文件: $SESSION_DIR/.capture_lock${NC}"
    return 1
  fi
  
  # 创建锁文件
  touch "$SESSION_DIR/.capture_lock"
  
  echo -e "${BLUE}正在捕获屏幕截图和UI布局...${NC}"
  
  # 检查设备连接
  DEVICE_ID=$(adb devices | grep -v "List" | grep -v "^$" | head -n 1 | awk '{print $1}')
  if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}错误: 没有设备连接${NC}"
    rm -f "$SESSION_DIR/.capture_lock"
    return 1
  fi
  
  # 截图
  echo "正在截取屏幕..."
  adb shell screencap -p /sdcard/screen_$TIMESTAMP.png
  if ! adb pull /sdcard/screen_$TIMESTAMP.png "$SESSION_DIR/screen.png"; then
    echo -e "${RED}截图拉取失败，尝试备用方案...${NC}"
    adb exec-out screencap -p > "$SESSION_DIR/screen.png"
  fi
  adb shell rm /sdcard/screen_$TIMESTAMP.png 2>/dev/null
  
  # UI布局 - 改进捕获和处理方式
  echo "正在转储UI层次结构..."
  # 方法1: 直接使用exec-out获取XML内容
  adb exec-out uiautomator dump /dev/stdout | grep -v "UI hierchary dumped to" > "$SESSION_DIR/ui_structure.xml"
  
  # 检查文件是否存在和有效
  if [ ! -f "$SESSION_DIR/ui_structure.xml" ] || [ ! -s "$SESSION_DIR/ui_structure.xml" ] || ! grep -q "<hierarchy" "$SESSION_DIR/ui_structure.xml"; then
    echo -e "${YELLOW}方法1失败，尝试方法2...${NC}"
    # 方法2: 使用常规方式
    adb shell uiautomator dump /sdcard/window_dump_$TIMESTAMP.xml
    adb pull /sdcard/window_dump_$TIMESTAMP.xml "$SESSION_DIR/ui_structure.xml"
    adb shell rm /sdcard/window_dump_$TIMESTAMP.xml 2>/dev/null
  fi
  
  # 再次检查并尝试修复XML
  if [ ! -f "$SESSION_DIR/ui_structure.xml" ] || [ ! -s "$SESSION_DIR/ui_structure.xml" ] || ! grep -q "<hierarchy" "$SESSION_DIR/ui_structure.xml"; then
    echo -e "${RED}警告: UI结构获取失败，尝试备用方案...${NC}"
    # 备用方案 - 尝试通过sed过滤非XML内容
    adb shell uiautomator dump /sdcard/window_dump_$TIMESTAMP.xml
    adb pull /sdcard/window_dump_$TIMESTAMP.xml "$SESSION_DIR/raw_dump.xml"
    cat "$SESSION_DIR/raw_dump.xml" | sed -n '/<\?xml/,$p' > "$SESSION_DIR/ui_structure.xml"
    adb shell rm /sdcard/window_dump_$TIMESTAMP.xml 2>/dev/null
  fi
  
  # 检查文件是否存在
  if [ ! -f "$SESSION_DIR/screen.png" ]; then
    echo -e "${RED}警告: 截图获取失败${NC}"
    cp "$(pwd)/resources/no_image.png" "$SESSION_DIR/screen.png" 2>/dev/null || echo "<?xml version='1.0'?><svg xmlns='http://www.w3.org/2000/svg' width='300' height='500'><rect width='100%' height='100%' fill='#eee'/><text x='50%' y='50%' font-family='Arial' font-size='20' text-anchor='middle' fill='#999'>截图获取失败</text></svg>" > "$SESSION_DIR/screen.png"
  fi
  
  # 最终检查与生成空XML
  if [ ! -f "$SESSION_DIR/ui_structure.xml" ] || [ ! -s "$SESSION_DIR/ui_structure.xml" ] || ! grep -q "<hierarchy" "$SESSION_DIR/ui_structure.xml"; then
    echo -e "${RED}警告: 所有UI结构获取方法都失败，创建空结构...${NC}"
    echo "<?xml version='1.0' encoding='UTF-8'?><hierarchy rotation='0'><node bounds='[0,0][0,0]' package='无法获取UI数据' /></hierarchy>" > "$SESSION_DIR/ui_structure.xml"
  else
    # 尝试修复常见XML问题
    echo -e "${GREEN}UI结构获取成功，进行格式修复...${NC}"
    # 确保文件有XML头
    if ! grep -q "<?xml" "$SESSION_DIR/ui_structure.xml"; then
      sed -i.bak '1s/^/<?xml version="1.0" encoding="UTF-8"?>\n/' "$SESSION_DIR/ui_structure.xml"
      rm -f "$SESSION_DIR/ui_structure.xml.bak"
    fi
    
    # 确保XML使用UTF-8编码
    ensure_utf8_encoding "$SESSION_DIR/ui_structure.xml"
    
    # 修复XML内容
    fix_xml_content "$SESSION_DIR/ui_structure.xml"
  fi
  
  # 删除锁文件
  rm -f "$SESSION_DIR/.capture_lock"
  
  return 0
}

# 创建一体化HTML查看器
create_html_viewer() {
  echo -e "${BLUE}正在创建一体化查看器...${NC}"
  
  HTML_FILE="$SESSION_DIR/viewer.html"
  
  # 保存原始XML文件以便调试
  cp "$SESSION_DIR/ui_structure.xml" "$SESSION_DIR/original_ui_structure.xml"
  
  # 确保XML文件使用UTF-8编码
  ensure_utf8_encoding "$SESSION_DIR/ui_structure.xml"
  
  echo "正在处理XML内容..."
  
  # 使用base64编码避免转义问题
  if [ -f "$SESSION_DIR/ui_structure.xml" ]; then
    # 确保XML文件使用UTF-8编码
    ensure_utf8_encoding "$SESSION_DIR/ui_structure.xml"
    
    # 再次修复XML内容
    fix_xml_content "$SESSION_DIR/ui_structure.xml"
    
    # 使用cat命令将内容传递给base64，避免文件路径问题
    XML_BASE64=$(cat "$SESSION_DIR/ui_structure.xml" | base64)
    if [ $? -ne 0 ]; then
      echo -e "${RED}base64编码失败，尝试备用方法...${NC}"
      # 备用方法：直接读取文件内容
      XML_CONTENT=$(cat "$SESSION_DIR/ui_structure.xml")
      # 对特殊字符进行转义
      XML_CONTENT="${XML_CONTENT//\\/\\\\}"
      XML_CONTENT="${XML_CONTENT//\"/\\\"}"
      XML_CONTENT="${XML_CONTENT//\$/\\\$}"
      XML_CONTENT="${XML_CONTENT//\`/\\\`}"
    fi
  else
    echo -e "${RED}错误：找不到XML文件${NC}"
    XML_BASE64=""
    XML_CONTENT="<?xml version='1.0' encoding='UTF-8'?><hierarchy><node text='XML文件不存在'/></hierarchy>"
  fi
  
  # 创建HTML文件
  cat > "$HTML_FILE" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Android UI 自动查看器 - $TIMESTAMP</title>
    <style>
        html, body {
            height: 100%;
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", "Noto Sans CJK SC", "Noto Sans CJK JP", "Microsoft YaHei", "Microsoft JhengHei", sans-serif;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", "Noto Sans CJK SC", "Noto Sans CJK JP", "Microsoft YaHei", "Microsoft JhengHei", sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f5f5f5;
            display: flex;
            flex-direction: column;
            height: 100vh;
            overflow: hidden;
        }
        .header {
            background-color: #0066cc;
            color: white;
            padding: 10px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            z-index: 10;
        }
        .header-left {
            display: flex;
            flex-direction: column;
        }
        .header-right {
            display: flex;
            align-items: center;
        }
        .language-selector {
            padding: 6px 10px;
            border-radius: 4px;
            border: 1px solid #fff;
            background-color: rgba(255, 255, 255, 0.2);
            color: white;
            font-size: 0.9rem;
            cursor: pointer;
            outline: none;
        }
        .language-selector option {
            background-color: #fff;
            color: #333;
        }
        .header h1 {
            margin: 0;
            font-size: 1.5rem;
        }
        .header .info {
            font-size: 0.9rem;
        }
        .main-content {
            display: flex;
            flex: 1;
            overflow: hidden;
            position: relative;
        }
        .screenshot-panel {
            width: 30%;
            padding: 10px;
            overflow: auto;
            border-right: 1px solid #ddd;
            display: flex;
            flex-direction: column;
            background-color: white;
            position: relative;
            height: 100%;
            box-sizing: border-box;
        }
        .h-resizer {
            width: 8px;
            background-color: #f0f0f0;
            cursor: col-resize;
            position: absolute;
            top: 0;
            right: 0;
            bottom: 0;
            border-left: 1px solid #ddd;
            border-right: 1px solid #ddd;
            z-index: 10;
        }
        .v-resizer {
            height: 8px;
            background-color: #f0f0f0;
            cursor: row-resize;
            width: 100%;
            border-top: 1px solid #ddd;
            border-bottom: 1px solid #ddd;
            z-index: 10;
            position: relative;
        }
        .v-resizer:hover {
            background-color: #ddd;
        }
        .v-resizer:after {
            content: "";
            position: absolute;
            left: 50%;
            top: 50%;
            transform: translate(-50%, -50%);
            width: 30px;
            height: 2px;
            background-color: #999;
            border-radius: 1px;
        }
        .screenshot-container {
            text-align: center;
            margin-bottom: 10px;
            height: calc(100% - 40px);
            overflow: auto;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 5px;
        }
        .screenshot {
            max-width: 100%;
            max-height: 100%;
            border: 1px solid #ddd;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            object-fit: contain;
            display: block;
            margin: 0 auto;
        }
        .right-panel {
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
            box-sizing: border-box;
        }
        .controls {
            padding: 10px;
            background-color: #f0f8ff;
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            border-bottom: 1px solid #ddd;
            z-index: 5;
        }
        button {
            padding: 8px 15px;
            background-color: #0066cc;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            margin-right: 10px;
            margin-bottom: 5px;
        }
        button:hover {
            background-color: #0055aa;
        }
        input[type="text"] {
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            margin-right: 10px;
            flex-grow: 1;
            min-width: 150px;
            margin-bottom: 5px;
        }
        .content-container {
            flex: 1;
            overflow: hidden;
            display: flex;
            flex-direction: column;
            position: relative;
            height: calc(100% - 50px); /* 减去controls的高度 */
        }
        .tree-view {
            flex: 2;
            padding: 15px;
            background-color: white;
            overflow: auto;
            height: 65%;
            min-height: 100px;
            box-sizing: border-box;
        }
        .node-detail {
            padding: 10px;
            background-color: #f9f9f9;
            border-top: 1px solid #ddd;
            overflow: auto;
            flex: 1;
            height: 35%;
            min-height: 150px; /* 增加最小高度 */
            display: block;
            box-sizing: border-box;
            padding-bottom: 20px; /* 添加底部内边距确保内容不会紧贴底部 */
            position: relative; /* 为滚动按钮定位 */
        }
        .scroll-controls {
            position: absolute;
            right: 10px;
            bottom: 10px;
            display: flex;
            gap: 5px;
        }
        .scroll-btn {
            width: 30px;
            height: 30px;
            border-radius: 50%;
            background-color: rgba(0, 102, 204, 0.7);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            font-size: 18px;
            border: none;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
        }
        .scroll-btn:hover {
            background-color: rgba(0, 102, 204, 0.9);
        }
        .node-detail h3 {
            margin-top: 0;
            color: #0066cc;
        }
        .tree-node {
            margin-left: 20px;
        }
        .node-content {
            padding: 3px 5px;
            cursor: pointer;
            border-radius: 3px;
            margin: 2px 0;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            max-width: 100%;
            word-break: break-all;
        }
        .node-content:hover {
            background-color: #f0f0f0;
        }
        .node-content.selected {
            background-color: #e3f2fd;
            border: 1px solid #2196F3;
        }
        .node-content.search-result {
            background-color: #fff9c4;
            border: 1px solid #ffc107;
        }
        .node-name {
            color: #0D47A1;
            font-weight: bold;
        }
        .attr-name {
            color: #1976D2;
        }
        .attr-value {
            color: #D32F2F;
            word-break: break-all;
        }
        .children {
            margin-left: 20px;
            border-left: 1px dashed #ccc;
            padding-left: 5px;
        }
        .collapsed > .children {
            display: none;
        }
        .node-expander {
            display: inline-block;
            width: 16px;
            text-align: center;
            cursor: pointer;
            color: #666;
            margin-right: 4px;
            transition: transform 0.2s;
        }
        .collapsed > .node-content > .node-expander {
            transform: rotate(-90deg);
        }
        .node-detail {
            flex: 1;
            padding: 10px;
            overflow: auto;
            background-color: white;
            position: relative;
            box-sizing: border-box;
            padding-bottom: 20px;
        }
        .properties-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            table-layout: fixed;
        }
        .properties-table th, .properties-table td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
            word-break: break-word;
        }
        .properties-table th {
            width: 30%;
            background-color: #f5f5f5;
            font-weight: bold;
        }
        .properties-table td {
            width: 70%;
        }
        .status-indicator {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 10px;
            font-size: 0.8rem;
            margin-left: 10px;
        }
        .status-success {
            background-color: #d4edda;
            color: #155724;
        }
        .status-warning {
            background-color: #fff3cd;
            color: #856404;
        }
        .status-error {
            background-color: #f8d7da;
            color: #721c24;
        }
        .error-container {
            padding: 15px;
            margin: 20px;
            background-color: #f8d7da;
            border: 1px solid #f5c6cb;
            border-radius: 4px;
            color: #721c24;
        }
        .error-actions {
            margin-top: 15px;
        }
        .raw-xml {
            width: 100%;
            height: 300px;
            font-family: monospace;
            margin-top: 10px;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        .highlight-bounds {
            position: absolute;
            border: 2px solid #ff5722;
            background-color: rgba(255, 87, 34, 0.3);
            pointer-events: none;
            z-index: 100;
            box-shadow: 0 0 5px rgba(255, 87, 34, 0.5);
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            <h1>Android UI Automatic Viewer <span class="status-indicator status-success" data-i18n="auto-capture">Auto Capture</span></h1>
            <div class="info" data-i18n-params="capture-time">Capture Time: $TIMESTAMP</div>
        </div>
        <div class="header-right">
            <select id="languageSelector" class="language-selector">
                <option value="en">English</option>
                <option value="zh">中文</option>
            </select>
        </div>
    </div>
    
    <div class="main-content">
        <div class="screenshot-panel">
            <h2 data-i18n="device-screenshot">Device Screenshot</h2>
            <div class="screenshot-container">
                <img src="screen.png" class="screenshot" id="deviceScreenshot" alt="Device Screenshot" />
            </div>
            <div class="h-resizer" id="horizontalResizer"></div>
        </div>
        
        <div class="right-panel">
            <div class="controls">
                <button id="expandAll" data-i18n="expand-all">Expand All</button>
                <button id="collapseAll" data-i18n="collapse-all">Collapse All</button>
                <input type="text" id="searchInput" data-i18n-placeholder="search-text" placeholder="Search text..." />
                <button id="searchBtn" data-i18n="search">Search</button>
                <button id="showRawXml" data-i18n="view-raw-xml">View Raw XML</button>
                <button id="reloadXml" data-i18n="reload">Reload</button>
                <button id="recaptureUI" data-i18n="recapture-ui">Recapture UI</button>
                <button id="importUI" data-i18n="import-ui">Import UI</button>
            </div>
            
            <div class="content-container">
                <div id="treeView" class="tree-view">
                    <!-- XML树结构将在这里渲染 -->
                </div>
                <div class="v-resizer" id="verticalResizer"></div>
                <div id="nodeDetail" class="node-detail">
                    <h3 data-i18n="element-details">Element Details</h3>
                    <table class="properties-table" id="nodeProperties">
                    </table>
                </div>
            </div>
        </div>
    </div>

    <script>
        document.addEventListener('DOMContentLoaded', function() {
            // 语言配置
            const i18n = {
                'en': {
                    'auto-capture': 'Auto Capture',
                    'capture-time': 'Capture Time: $TIMESTAMP',
                    'device-screenshot': 'Device Screenshot',
                    'expand-all': 'Expand All',
                    'collapse-all': 'Collapse All',
                    'search-text': 'Search text...',
                    'search': 'Search',
                    'view-raw-xml': 'View Raw XML',
                    'reload': 'Reload',
                    'recapture-ui': 'Recapture UI',
                    'import-ui': 'Import UI',
                    'element-details': 'Element Details',
                    'no-attributes': 'This node has no attributes',
                    'raw-xml-content': 'Raw XML Content',
                    'back-to-tree': 'Back to Tree View',
                    'xml-parse-error': 'XML Parse Error',
                    'original-xml-content': 'Original XML Content:',
                    'try-fix-xml': 'Try to Fix XML',
                    'import-ui-title': 'Import Existing UI',
                    'import-ui-desc': 'Please select the type of file to import:',
                    'import-xml-file': 'Import XML File',
                    'import-screenshot': 'Import Screenshot',
                    'cancel': 'Cancel',
                    'xml-import-success': 'XML structure has been successfully imported!',
                    'image-import-success': 'Screenshot has been successfully imported!',
                    'read-file-error': 'Error reading file, please try again.',
                    'xml-import-error': 'XML Import Error',
                    'fix-and-import': 'Try to Fix and Import',
                    'back': 'Back',
                    'get-new-ui-data': 'Get New UI Data',
                    'run-command': 'Please run the following command in the terminal to get new UI data:',
                    'refresh-page': 'Refresh Page',
                    'close': 'Close',
                    'no-match-found': 'No match found: ',
                    'confirm-recapture': 'Are you sure you want to recapture the current UI structure?',
                    'after-command-instruction': 'After execution, click the "Refresh Page" button below to view the latest results.',
                    'xml-fetch-error': 'Failed to fetch XML content:',
                    'xml-parse-error-console': 'Error parsing XML:',
                    'decode-text-error': 'Error decoding text:',
                    'parse-node-attr-error': 'Error parsing node attributes:',
                    'show-node-details-error': 'Error showing node details:',
                    'screenshot-zero-dim': 'Screenshot dimensions are zero',
                    'highlight-bounds-error': 'Error highlighting bounds:',
                    'search-error': 'Error during search:',
                    'process-xml-error': 'Error processing XML file:'
                },
                'zh': {
                    'auto-capture': '自动捕获',
                    'capture-time': '捕获时间: $TIMESTAMP',
                    'device-screenshot': '设备截图',
                    'expand-all': '全部展开',
                    'collapse-all': '全部折叠',
                    'search-text': '搜索文本...',
                    'search': '搜索',
                    'view-raw-xml': '查看原始XML',
                    'reload': '重新加载XML',
                    'recapture-ui': '再次获取界面UI',
                    'import-ui': '导入现有UI',
                    'element-details': '元素详情',
                    'no-attributes': '该节点没有属性',
                    'raw-xml-content': '原始XML内容',
                    'back-to-tree': '返回树视图',
                    'xml-parse-error': 'XML解析错误',
                    'original-xml-content': '原始XML内容:',
                    'try-fix-xml': '尝试修复XML',
                    'import-ui-title': '导入现有UI',
                    'import-ui-desc': '请选择要导入的文件类型：',
                    'import-xml-file': '导入XML文件',
                    'import-screenshot': '导入截图',
                    'cancel': '取消',
                    'xml-import-success': 'XML结构已成功导入！',
                    'image-import-success': '截图已成功导入！',
                    'read-file-error': '读取文件时出错，请重试。',
                    'xml-import-error': 'XML导入错误',
                    'fix-and-import': '尝试修复并导入',
                    'back': '返回',
                    'get-new-ui-data': '获取新的UI数据',
                    'run-command': '请在终端中执行以下命令来获取新的UI数据：',
                    'refresh-page': '刷新页面',
                    'close': '关闭',
                    'no-match-found': '未找到匹配项: ',
                    'confirm-recapture': '确定要重新获取当前界面的UI结构吗？',
                    'after-command-instruction': '执行完成后，点击下方的"刷新页面"按钮查看最新结果。',
                    'xml-fetch-error': 'XML内容获取失败:',
                    'xml-parse-error-console': '解析XML时出错:',
                    'decode-text-error': '解码文本时出错:',
                    'parse-node-attr-error': '解析节点属性时出错:',
                    'show-node-details-error': '显示节点详情时出错:',
                    'screenshot-zero-dim': '截图尺寸为零',
                    'highlight-bounds-error': '高亮边界时出错:',
                    'search-error': '搜索时出错:',
                    'process-xml-error': '处理XML文件时出错:'
                }
            };
            
            // 当前语言
            let currentLang = 'en';
            
            // 应用语言
            function applyLanguage(lang) {
                currentLang = lang;
                
                // 保存语言选择到本地存储
                localStorage.setItem('uiViewerLanguage', lang);
                
                // 更新所有带有data-i18n属性的元素
                document.querySelectorAll('[data-i18n]').forEach(el => {
                    const key = el.getAttribute('data-i18n');
                    if (i18n[lang][key]) {
                        el.textContent = i18n[lang][key];
                    }
                });
                
                // 更新所有带有data-i18n-placeholder属性的元素
                document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
                    const key = el.getAttribute('data-i18n-placeholder');
                    if (i18n[lang][key]) {
                        el.placeholder = i18n[lang][key];
                    }
                });
                
                // 更新带有data-i18n-params属性的元素
                document.querySelectorAll('[data-i18n-params]').forEach(el => {
                    const key = el.getAttribute('data-i18n-params');
                    if (i18n[lang][key]) {
                        let text = i18n[lang][key];
                        // 替换参数
                        if (key === 'capture-time') {
                            text = text.replace('$TIMESTAMP', '$TIMESTAMP');
                        }
                        el.textContent = text;
                    }
                });
            }
            
            // 语言选择器事件
            const languageSelector = document.getElementById('languageSelector');
            languageSelector.addEventListener('change', function() {
                applyLanguage(this.value);
            });
            
            // 从本地存储加载语言设置
            const savedLang = localStorage.getItem('uiViewerLanguage');
            if (savedLang && i18n[savedLang]) {
                currentLang = savedLang;
                languageSelector.value = savedLang;
            }
            
            // 初始应用语言
            applyLanguage(currentLang);
            
            const treeView = document.getElementById('treeView');
            const expandAllBtn = document.getElementById('expandAll');
            const collapseAllBtn = document.getElementById('collapseAll');
            const searchInput = document.getElementById('searchInput');
            const searchBtn = document.getElementById('searchBtn');
            const nodeDetail = document.getElementById('nodeDetail');
            const nodeProperties = document.getElementById('nodeProperties');
            const deviceScreenshot = document.getElementById('deviceScreenshot');
            const showRawXmlBtn = document.getElementById('showRawXml');
            const reloadXmlBtn = document.getElementById('reloadXml');
            const recaptureUIBtn = document.getElementById('recaptureUI');
            const importUIBtn = document.getElementById('importUI');
            const horizontalResizer = document.getElementById('horizontalResizer');
            const verticalResizer = document.getElementById('verticalResizer');
            const screenshotPanel = document.querySelector('.screenshot-panel');
            const rightPanel = document.querySelector('.right-panel');
            const contentContainer = document.querySelector('.content-container');
            
            // 初始化面板高度
            treeView.style.height = '60%'; // 减少树视图高度，给详情面板更多空间
            treeView.style.flex = 'none';
            nodeDetail.style.height = '40%'; // 增加详情面板高度
            nodeDetail.style.flex = 'none';
            
            // 初始化截图面板宽度
            screenshotPanel.style.width = '30%';
            
            // 调整截图显示，确保完整显示而不需要滚动
            deviceScreenshot.addEventListener('load', function() {
                // 获取截图容器和图片尺寸
                const container = document.querySelector('.screenshot-container');
                const containerHeight = container.clientHeight;
                const containerWidth = container.clientWidth;
                const imgNaturalWidth = this.naturalWidth;
                const imgNaturalHeight = this.naturalHeight;
                
                // 计算适合容器的图片尺寸
                const containerRatio = containerWidth / containerHeight;
                const imageRatio = imgNaturalWidth / imgNaturalHeight;
                
                if (imageRatio > containerRatio) {
                    // 图片更宽，以宽度为基准
                    this.style.width = '95%';
                    this.style.height = 'auto';
                } else {
                    // 图片更高，以高度为基准
                    this.style.height = '95%';
                    this.style.width = 'auto';
                }
                
                // 确保图片完全可见
                container.scrollTop = 0;
                
                // 更新高亮元素位置
                const selectedNode = document.querySelector('.node-content.selected');
                if (selectedNode) {
                    setTimeout(() => {
                        highlightElementBounds(selectedNode);
                    }, 100);
                }
            });
            
            // 获取XML内容
            let xmlString = '';
            
            try {
                // 尝试使用base64解码（如果有base64编码的内容）
                const xmlBase64 = "${XML_BASE64}";
                if (xmlBase64 && xmlBase64.trim() !== "") {
                    xmlString = atob(xmlBase64);
                    
                    // 检查并修复可能的编码问题
                    if (!xmlString.includes('<hierarchy')) {
                        console.warn('检测到可能的编码问题，尝试修复...');
                        // 尝试修复常见的编码问题
                        xmlString = xmlString.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ' ');
                    }
                    
                    // 尝试修复UTF-8编码问题
                    try {
                        // 检查是否有UTF-8编码的字节序列
                        if (/[\u00e0-\u00ef][\u0080-\u00bf]/.test(xmlString)) {
                            console.warn('检测到可能的UTF-8编码问题，尝试修复...');
                            // 将字符串转换为UTF-8字节数组
                            const bytes = [];
                            for (let i = 0; i < xmlString.length; i++) {
                                const code = xmlString.charCodeAt(i);
                                bytes.push(code);
                            }
                            // 使用TextDecoder解码
                            const decoder = new TextDecoder('utf-8');
                            const decoded = decoder.decode(new Uint8Array(bytes));
                            if (decoded && decoded.length > 0 && decoded.includes('<hierarchy')) {
                                xmlString = decoded;
                            }
                        }
                    } catch (e) {
                        console.warn('TextDecoder处理失败，继续使用原始文本', e);
                    }
                } else {
                    // 如果没有base64编码，使用直接嵌入的XML内容
                    xmlString = \`${XML_CONTENT}\`;
                }
            } catch (e) {
                console.error('XML内容获取失败:', e);
                treeView.innerHTML = '<div class="error-container"><h3>XML解析错误</h3><p>内容获取失败: ' + e.message + '</p></div>';
                return;
            }
            
            let highlightElement = null;
            
            // 显示原始XML
            showRawXmlBtn.addEventListener('click', function() {
                // 清空树视图
                treeView.innerHTML = '';
                
                // 创建文本区域显示原始XML
                const container = document.createElement('div');
                container.className = 'error-container';
                container.innerHTML = '<h3>' + i18n[currentLang]['raw-xml-content'] + '</h3>';
                
                const textarea = document.createElement('textarea');
                textarea.className = 'raw-xml';
                textarea.value = xmlString;
                textarea.readOnly = true;
                
                const actions = document.createElement('div');
                actions.className = 'error-actions';
                actions.innerHTML = '<button id="backToTree">' + i18n[currentLang]['back-to-tree'] + '</button>';
                
                container.appendChild(textarea);
                container.appendChild(actions);
                treeView.appendChild(container);
                
                document.getElementById('backToTree').addEventListener('click', function() {
                    parseAndRenderXML();
                });
            });
            
            // 重新加载XML
            reloadXmlBtn.addEventListener('click', function() {
                window.location.reload();
            });
            
            function parseAndRenderXML() {
                const parser = new DOMParser();
                let xmlDoc;
                
                try {
                    // 预处理XML字符串，修复常见编码问题
                    let processedXmlString = xmlString;
                    
                    // 检查XML内容是否为空
                    if (!processedXmlString || !processedXmlString.trim()) {
                        throw new Error('XML内容为空');
                    }
                    
                    // 移除BOM标记
                    processedXmlString = processedXmlString.replace(/^\uFEFF/, '');
                    
                    // 确保XML声明包含UTF-8编码
                    if (!processedXmlString.includes('encoding="UTF-8"') && !processedXmlString.includes("encoding='UTF-8'")) {
                        processedXmlString = processedXmlString.replace(/<\?xml[^>]*\?>/, '<?xml version="1.0" encoding="UTF-8"?>');
                        if (!processedXmlString.includes('<?xml')) {
                            processedXmlString = '<?xml version="1.0" encoding="UTF-8"?>\n' + processedXmlString;
                        }
                    }
                    
                    // 处理可能的编码问题
                    processedXmlString = processedXmlString.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ' ');
                    
                    // 检查是否有根元素
                    if (!processedXmlString.match(/<[a-zA-Z0-9_:-]+[^>]*>/)) {
                        throw new Error('无法找到有效的XML标签');
                    }
                    
                    // 确保XML字符串是UTF-8编码
                    xmlDoc = parser.parseFromString(processedXmlString, 'text/xml');
                    
                    // 检查是否有解析错误
                    const parseError = xmlDoc.getElementsByTagName('parsererror');
                    if (parseError.length > 0) {
                        const errorMsg = parseError[0].textContent || '未知解析错误';
                        throw new Error('XML解析错误: ' + errorMsg);
                    }
                    
                    // 检查根元素
                    if (!xmlDoc.documentElement) {
                        throw new Error('XML文档没有根元素');
                    }
                    
                    treeView.innerHTML = '';
                    renderNode(xmlDoc.documentElement, treeView);
                    
                    // 默认展开第一级
                    const rootNodes = treeView.querySelectorAll('.tree-node');
                    rootNodes.forEach(node => {
                        if (node.parentElement === treeView) {
                            node.classList.remove('collapsed');
                        } else {
                            node.classList.add('collapsed');
                        }
                    });
                } catch (error) {
                    console.error('解析XML时出错:', error);
                    
                    // 清空树视图
                    treeView.innerHTML = '';
                    
                    // 创建错误消息
                    const errorContainer = document.createElement('div');
                    errorContainer.className = 'error-container';
                    
                    const errorTitle = document.createElement('h3');
                    errorTitle.textContent = i18n[currentLang]['xml-parse-error'];
                    
                    const errorMessage = document.createElement('p');
                    errorMessage.textContent = error.message;
                    
                    const rawXmlTitle = document.createElement('h4');
                    rawXmlTitle.textContent = i18n[currentLang]['original-xml-content'];
                    
                    const rawXml = document.createElement('textarea');
                    rawXml.className = 'raw-xml';
                    rawXml.value = xmlString;
                    rawXml.readOnly = true;
                    
                    const fixButton = document.createElement('button');
                    fixButton.textContent = i18n[currentLang]['try-fix-xml'];
                    fixButton.style.marginTop = '10px';
                    fixButton.style.marginRight = '10px';
                    fixButton.onclick = function() {
                        try {
                            // 尝试更强力的修复
                            let fixedContent = xmlString;
                            
                            // 确保有XML声明
                            if (!fixedContent.includes('<?xml')) {
                                fixedContent = '<?xml version="1.0" encoding="UTF-8"?>\n' + fixedContent;
                            }
                            
                            // 如果没有根元素，添加一个
                            if (!fixedContent.match(/<[a-zA-Z0-9_:-]+[^>]*>/)) {
                                fixedContent = fixedContent + '\n<hierarchy></hierarchy>';
                            }
                            
                            // 如果有内容但没有被标签包围，添加根标签
                            if (!fixedContent.match(/<[a-zA-Z0-9_:-]+[^>]*>[\s\S]*<\/[a-zA-Z0-9_:-]+>/)) {
                                const textContent = fixedContent.replace(/^<\?xml[^>]*>\s*/, '');
                                fixedContent = '<?xml version="1.0" encoding="UTF-8"?>\n<hierarchy>' + textContent + '</hierarchy>';
                            }
                            
                            // 更新XML内容
                            xmlString = fixedContent;
                            
                            // 重新解析和渲染XML
                            parseAndRenderXML();
                        } catch (e) {
                            alert('修复失败: ' + e.message);
                        }
                    };
                    
                    errorContainer.appendChild(errorTitle);
                    errorContainer.appendChild(errorMessage);
                    errorContainer.appendChild(rawXmlTitle);
                    errorContainer.appendChild(rawXml);
                    errorContainer.appendChild(fixButton);
                    
                    treeView.appendChild(errorContainer);
                }
            }
            
            function renderNode(node, container) {
                if (!node) return;
                
                const nodeDiv = document.createElement('div');
                nodeDiv.className = 'tree-node collapsed';
                
                const nodeContent = document.createElement('div');
                nodeContent.className = 'node-content';
                
                // 获取所有属性
                const attributes = {};
                if (node.attributes) {
                    for (let i = 0; i < node.attributes.length; i++) {
                        const attr = node.attributes[i];
                        attributes[attr.name] = attr.value;
                    }
                }
                
                // 存储所有属性为JSON字符串
                nodeContent.dataset.allAttributes = JSON.stringify(attributes);
                
                // 存储bounds属性，用于高亮显示
                if (attributes['bounds']) {
                    nodeContent.dataset.bounds = attributes['bounds'];
                }
                
                // 添加展开/折叠图标
                const hasChildren = node.hasChildNodes();
                if (hasChildren) {
                    const expander = document.createElement('span');
                    expander.className = 'node-expander';
                    expander.textContent = '▼';
                    nodeContent.appendChild(expander);
                } else {
                    // 为没有子节点的元素添加空白，保持缩进一致
                    const spacer = document.createElement('span');
                    spacer.className = 'node-expander';
                    spacer.textContent = ' ';
                    spacer.style.visibility = 'hidden';
                    nodeContent.appendChild(spacer);
                }
                
                // 显示节点名称和主要属性
                const nodeNameSpan = document.createElement('span');
                nodeNameSpan.className = 'node-name';
                nodeNameSpan.textContent = node.nodeName;
                nodeContent.appendChild(nodeNameSpan);
                
                // 添加主要属性到显示文本
                const importantAttrs = [];
                if (attributes['text'] && attributes['text'].trim() !== '') {
                    // 解码文本内容以正确显示中文和日文
                    const decodedText = decodeEntities(attributes['text']);
                    importantAttrs.push('text="' + decodedText + '"');
                }
                if (attributes['resource-id']) {
                    importantAttrs.push('id="' + attributes['resource-id'] + '"');
                }
                if (attributes['class']) {
                    importantAttrs.push('class="' + attributes['class'] + '"');
                }
                if (attributes['package']) {
                    importantAttrs.push('package="' + attributes['package'] + '"');
                }
                if (attributes['content-desc'] && attributes['content-desc'].trim() !== '') {
                    // 解码内容描述以正确显示中文和日文
                    const decodedDesc = decodeEntities(attributes['content-desc']);
                    importantAttrs.push('desc="' + decodedDesc + '"');
                }
                
                if (importantAttrs.length > 0) {
                    const attrsSpan = document.createElement('span');
                    attrsSpan.textContent = ' [' + importantAttrs.join(', ') + ']';
                    nodeContent.appendChild(attrsSpan);
                }
                
                // 添加点击事件
                nodeContent.addEventListener('click', function(e) {
                    e.stopPropagation();
                    
                    // 切换折叠状态
                    const parentNode = this.parentElement;
                    parentNode.classList.toggle('collapsed');
                    
                    // 显示节点详情
                    showNodeDetails(this);
                    
                    // 高亮元素边界
                    highlightElementBounds(this);
                });
                
                nodeDiv.appendChild(nodeContent);
                
                // 处理子节点
                if (hasChildren) {
                    const childrenContainer = document.createElement('div');
                    childrenContainer.className = 'children';
                    
                    for (let i = 0; i < node.childNodes.length; i++) {
                        const childNode = node.childNodes[i];
                        if (childNode.nodeType === 1) { // 元素节点
                            renderNode(childNode, childrenContainer);
                        }
                    }
                    
                    nodeDiv.appendChild(childrenContainer);
                }
                
                container.appendChild(nodeDiv);
            }
            
            // 解码HTML实体
            function decodeEntities(text) {
                if (!text) return '';
                try {
                    // 处理常见的编码问题
                    let decodedText = text;
                    
                    // 处理Unicode转义序列 \uXXXX
                    decodedText = decodedText.replace(/\\u([0-9a-fA-F]{4})/g, function(match, hex) {
                        return String.fromCharCode(parseInt(hex, 16));
                    });
                    
                    // 处理HTML实体编码
                    decodedText = decodedText.replace(/&#(\d+);/g, function(match, dec) {
                        return String.fromCharCode(parseInt(dec, 10));
                    });
                    
                    // 处理十六进制HTML实体
                    decodedText = decodedText.replace(/&#x([0-9a-fA-F]+);/g, function(match, hex) {
                        return String.fromCharCode(parseInt(hex, 16));
                    });
                    
                    // 处理常见的特殊字符替换
                    const specialChars = {
                        '&lt;': '<',
                        '&gt;': '>',
                        '&amp;': '&',
                        '&quot;': '"',
                        '&apos;': "'",
                        '&nbsp;': ' '
                    };
                    
                    for (const [entity, char] of Object.entries(specialChars)) {
                        decodedText = decodedText.replace(new RegExp(entity, 'g'), char);
                    }
                    
                    // 使用TextDecoder进一步处理可能的UTF-8编码问题
                    try {
                        // 检查是否有UTF-8编码的字节序列
                        if (/[\u00e0-\u00ef][\u0080-\u00bf]/.test(decodedText)) {
                            // 将字符串转换为UTF-8字节数组
                            const bytes = [];
                            for (let i = 0; i < decodedText.length; i++) {
                                const code = decodedText.charCodeAt(i);
                                if (code < 0x80) {
                                    bytes.push(code);
                                } else if (code < 0x800) {
                                    bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
                                } else {
                                    bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
                                }
                            }
                            // 使用TextDecoder解码
                            const decoder = new TextDecoder('utf-8');
                            const decoded = decoder.decode(new Uint8Array(bytes));
                            if (decoded && decoded.length > 0) {
                                decodedText = decoded;
                            }
                        }
                    } catch (e) {
                        console.warn('TextDecoder处理失败，继续使用原始文本', e);
                    }
                    
                    // 创建一个临时元素来解码HTML实体
                    const textarea = document.createElement('textarea');
                    textarea.innerHTML = decodedText;
                    decodedText = textarea.value;
                    
                    return decodedText;
                } catch (e) {
                    console.error(i18n[currentLang]['decode-text-error'], e);
                    return text; // 如果解码失败，返回原始文本
                }
            }
            
            // 显示节点详细信息
            function showNodeDetails(nodeContent) {
                try {
                    // 移除之前选中的节点样式
                    document.querySelectorAll('.node-content.selected').forEach(el => {
                        el.classList.remove('selected');
                    });
                    
                    // 添加选中样式到当前节点
                    nodeContent.classList.add('selected');
                    
                    // 获取节点属性
                    let allAttributes;
                    try {
                        allAttributes = JSON.parse(nodeContent.dataset.allAttributes || '{}');
                    } catch (e) {
                        console.error('解析节点属性时出错:', e);
                        allAttributes = {};
                    }
                    
                    // 清空属性表
                    nodeProperties.innerHTML = '';
                    
                    // 如果没有属性，显示提示信息
                    if (Object.keys(allAttributes).length === 0) {
                        const row = document.createElement('tr');
                        const cell = document.createElement('td');
                        cell.colSpan = 2;
                        cell.textContent = i18n[currentLang]['no-attributes'];
                        cell.style.textAlign = 'center';
                        cell.style.fontStyle = 'italic';
                        row.appendChild(cell);
                        nodeProperties.appendChild(row);
                    } else {
                        // 填充属性表
                        for (const [key, value] of Object.entries(allAttributes)) {
                            const row = document.createElement('tr');
                            
                            const keyCell = document.createElement('th');
                            keyCell.textContent = key;
                            row.appendChild(keyCell);
                            
                            const valueCell = document.createElement('td');
                            // 解码HTML实体，确保中文和日文正确显示
                            valueCell.textContent = decodeEntities(value || '');
                            row.appendChild(valueCell);
                            
                            nodeProperties.appendChild(row);
                        }
                    }
                    
                    // 确保详情面板滚动到顶部，以便查看所有内容
                    nodeDetail.scrollTop = 0;
                    
                    // 添加滚动控制按钮
                    let scrollControls = nodeDetail.querySelector('.scroll-controls');
                    if (!scrollControls) {
                        scrollControls = document.createElement('div');
                        scrollControls.className = 'scroll-controls';
                        
                        const scrollTopBtn = document.createElement('button');
                        scrollTopBtn.className = 'scroll-btn';
                        scrollTopBtn.innerHTML = '↑';
                        scrollTopBtn.title = '滚动到顶部';
                        scrollTopBtn.onclick = function() {
                            nodeDetail.scrollTop = 0;
                        };
                        
                        const scrollBottomBtn = document.createElement('button');
                        scrollBottomBtn.className = 'scroll-btn bottom-btn';
                        scrollBottomBtn.innerHTML = '↓';
                        scrollBottomBtn.title = '滚动到底部';
                        scrollBottomBtn.onclick = function() {
                            nodeDetail.scrollTop = nodeDetail.scrollHeight;
                        };
                        
                        scrollControls.appendChild(scrollTopBtn);
                        scrollControls.appendChild(scrollBottomBtn);
                        nodeDetail.appendChild(scrollControls);
                    }
                    
                    // 高亮元素边界
                    if (allAttributes.bounds) {
                        highlightElementBounds(nodeContent);
                    }
                } catch (e) {
                    console.error(i18n[currentLang]['show-node-details-error'], e);
                    nodeProperties.innerHTML = '<tr><td colspan="2" class="error">' + i18n[currentLang]['show-node-details-error'] + ' ' + e.message + '</td></tr>';
                }
            }
            
            // 高亮元素在截图上的边界
            function highlightElementBounds(nodeContent) {
                // 清除之前的高亮
                if (highlightElement) {
                    highlightElement.remove();
                    highlightElement = null;
                }
                
                // 从dataset中获取bounds
                const allAttributes = JSON.parse(nodeContent.dataset.allAttributes || '{}');
                const boundsStr = nodeContent.dataset.bounds || allAttributes.bounds;
                if (!boundsStr) return;
                
                try {
                    // 解析bounds字符串，格式为[left,top][right,bottom]
                    const matches = boundsStr.match(/\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]/);
                    if (!matches || matches.length !== 5) return;
                    
                    const left = parseInt(matches[1]);
                    const top = parseInt(matches[2]);
                    const right = parseInt(matches[3]);
                    const bottom = parseInt(matches[4]);
                    
                    // 获取截图的尺寸和位置
                    const img = deviceScreenshot;
                    const imgRect = img.getBoundingClientRect();
                    const imgWidth = img.naturalWidth || 1080; // 默认宽度，防止为0
                    const imgHeight = img.naturalHeight || 1920; // 默认高度，防止为0
                    
                    if (imgWidth === 0 || imgHeight === 0) {
                        console.error(i18n[currentLang]['screenshot-zero-dim']);
                        return;
                    }
                    
                    // 计算高亮元素的位置和大小
                    const scaleX = imgRect.width / imgWidth;
                    const scaleY = imgRect.height / imgHeight;
                    
                    const highlightLeft = left * scaleX + imgRect.left;
                    const highlightTop = top * scaleY + imgRect.top;
                    const highlightWidth = (right - left) * scaleX;
                    const highlightHeight = (bottom - top) * scaleY;
                    
                    // 创建高亮元素
                    highlightElement = document.createElement('div');
                    highlightElement.className = 'highlight-bounds';
                    highlightElement.style.left = highlightLeft + 'px';
                    highlightElement.style.top = highlightTop + 'px';
                    highlightElement.style.width = highlightWidth + 'px';
                    highlightElement.style.height = highlightHeight + 'px';
                    
                    document.body.appendChild(highlightElement);
                } catch (error) {
                    console.error(i18n[currentLang]['highlight-bounds-error'], error);
                }
            }
            
            // 实现可调整大小的面板
            let isResizingHorizontal = false;
            let isResizingVertical = false;
            
            // 水平调整器（左右调整）
            horizontalResizer.addEventListener('mousedown', function(e) {
                e.preventDefault();
                isResizingHorizontal = true;
                document.addEventListener('mousemove', resizeHorizontal);
                document.addEventListener('mouseup', stopResizeHorizontal);
            });
            
            function resizeHorizontal(e) {
                if (!isResizingHorizontal) return;
                
                const containerWidth = document.querySelector('.main-content').offsetWidth;
                const newWidth = (e.clientX / containerWidth * 100);
                
                // 限制最小宽度
                if (newWidth > 20 && newWidth < 80) {
                    screenshotPanel.style.width = newWidth + '%';
                    // 不需要设置rightPanel的宽度，它会自动填充剩余空间
                }
                
                // 更新高亮元素位置
                const selectedNode = document.querySelector('.node-content.selected');
                if (selectedNode) {
                    setTimeout(() => {
                        highlightElementBounds(selectedNode);
                    }, 10);
                }
            }
            
            function stopResizeHorizontal() {
                isResizingHorizontal = false;
                document.removeEventListener('mousemove', resizeHorizontal);
                document.removeEventListener('mouseup', stopResizeHorizontal);
            }
            
            // 垂直调整器（上下调整）
            verticalResizer.addEventListener('mousedown', function(e) {
                e.preventDefault();
                isResizingVertical = true;
                document.body.style.cursor = 'row-resize';
                document.addEventListener('mousemove', resizeVertical);
                document.addEventListener('mouseup', stopResizeVertical);
            });
            
            function resizeVertical(e) {
                if (!isResizingVertical) return;
                
                const container = document.querySelector('.content-container');
                const containerRect = container.getBoundingClientRect();
                const containerHeight = containerRect.height;
                const relativeY = e.clientY - containerRect.top;
                const percentage = (relativeY / containerHeight * 100);
                
                // 限制最小高度
                if (percentage > 30 && percentage < 85) {
                    const treeHeight = percentage + '%';
                    const detailHeight = (100 - percentage - 1) + '%';
                    
                    treeView.style.height = treeHeight;
                    treeView.style.flex = 'none';
                    treeView.style.maxHeight = 'none';
                    
                    nodeDetail.style.height = detailHeight;
                    nodeDetail.style.flex = 'none';
                    nodeDetail.style.maxHeight = 'none';
                    
                    // 强制重新计算布局
                    contentContainer.style.display = 'none';
                    contentContainer.offsetHeight; // 触发重排
                    contentContainer.style.display = 'flex';
                    
                    // 更新高亮元素位置
                    const selectedNode = document.querySelector('.node-content.selected');
                    if (selectedNode) {
                        setTimeout(() => {
                            highlightElementBounds(selectedNode);
                        }, 10);
                    }
                }
            }
            
            function stopResizeVertical() {
                isResizingVertical = false;
                document.body.style.cursor = '';
                document.removeEventListener('mousemove', resizeVertical);
                document.removeEventListener('mouseup', stopResizeVertical);
            }
            
            // 确保图片加载完成后更新高亮
            deviceScreenshot.addEventListener('load', function() {
                const selectedNode = document.querySelector('.node-content.selected');
                if (selectedNode) {
                    setTimeout(() => {
                        highlightElementBounds(selectedNode);
                    }, 100);
                }
            });
            
            // 更新高亮位置（在窗口大小改变时）
            window.addEventListener('resize', function() {
                const selectedNode = document.querySelector('.node-content.selected');
                if (selectedNode) {
                    setTimeout(() => {
                        highlightElementBounds(selectedNode);
                    }, 100);
                }
            });
            
            // 渲染XML
            parseAndRenderXML();
            
            // 确保按钮点击事件正常工作
            expandAllBtn.onclick = function() {
                document.querySelectorAll('.tree-node').forEach(node => {
                    node.classList.remove('collapsed');
                });
            };
            
            collapseAllBtn.onclick = function() {
                document.querySelectorAll('.tree-node').forEach(node => {
                    node.classList.add('collapsed');
                });
                // 保持根节点展开
                const rootNodes = treeView.querySelectorAll(':scope > .tree-node');
                rootNodes.forEach(node => {
                    node.classList.remove('collapsed');
                });
            };
            
            // 搜索功能
            searchBtn.addEventListener('click', function() {
                performSearch();
            });
            
            searchInput.addEventListener('keypress', function(e) {
                if (e.key === 'Enter') {
                    performSearch();
                }
            });
            
            function performSearch() {
                const searchText = searchInput.value.trim();
                if (!searchText) return;
                
                // 清除之前的搜索结果
                document.querySelectorAll('.search-result').forEach(el => {
                    el.classList.remove('search-result');
                });
                
                // 搜索节点
                let found = false;
                document.querySelectorAll('.node-content').forEach(node => {
                    try {
                        // 获取节点文本和属性
                        const nodeText = node.textContent.toLowerCase();
                        const nodeAttrs = JSON.parse(node.dataset.allAttributes || '{}');
                        
                        // 检查节点文本
                        if (nodeText.includes(searchText.toLowerCase())) {
                            highlightSearchResult(node);
                            found = true;
                            return;
                        }
                        
                        // 检查节点属性
                        for (const [key, value] of Object.entries(nodeAttrs)) {
                            if (value && value.toLowerCase().includes(searchText.toLowerCase())) {
                                highlightSearchResult(node);
                                found = true;
                                return;
                            }
                        }
                    } catch (e) {
                        console.error(i18n[currentLang]['search-error'], e);
                    }
                });
                
                if (!found) {
                    alert(i18n[currentLang]['no-match-found'] + searchText);
                }
            }
            
            function highlightSearchResult(node) {
                // 添加高亮类
                node.classList.add('search-result');
                
                // 展开所有父节点
                let parent = node.parentElement;
                while (parent) {
                    if (parent.classList.contains('tree-node')) {
                        parent.classList.remove('collapsed');
                    }
                    parent = parent.parentElement;
                }
                
                // 滚动到可见区域
                node.scrollIntoView({ behavior: 'smooth', block: 'center' });
                
                // 显示节点详情
                showNodeDetails(node);
            }
            
            // 再次获取界面UI
            recaptureUIBtn.addEventListener('click', function() {
                if (confirm(i18n[currentLang]['confirm-recapture'])) {
                    // 获取当前工作目录（基于当前HTML文件的路径）
                    const currentPath = window.location.pathname;
                    const workspacePath = currentPath.substring(0, currentPath.indexOf('/auto_view/'));
                    
                    // 创建一个模态对话框
                    const modal = document.createElement('div');
                    modal.style.position = 'fixed';
                    modal.style.top = '0';
                    modal.style.left = '0';
                    modal.style.width = '100%';
                    modal.style.height = '100%';
                    modal.style.backgroundColor = 'rgba(0, 0, 0, 0.7)';
                    modal.style.zIndex = '9999';
                    modal.style.display = 'flex';
                    modal.style.justifyContent = 'center';
                    modal.style.alignItems = 'center';
                    
                    // 创建对话框内容
                    const modalContent = document.createElement('div');
                    modalContent.style.backgroundColor = 'white';
                    modalContent.style.padding = '20px';
                    modalContent.style.borderRadius = '10px';
                    modalContent.style.maxWidth = '500px';
                    modalContent.style.width = '80%';
                    modalContent.style.boxShadow = '0 4px 8px rgba(0, 0, 0, 0.2)';
                    
                    // 添加标题
                    const title = document.createElement('h3');
                    title.textContent = i18n[currentLang]['get-new-ui-data'];
                    title.style.marginTop = '0';
                    title.style.color = '#0066cc';
                    
                    // 添加说明
                    const description = document.createElement('p');
                    description.innerHTML = i18n[currentLang]['run-command'] + '<br><br>' +
                        '<div style="background-color: #f5f5f5; padding: 10px; border-radius: 5px; font-family: monospace;">' +
                        'cd ' + workspacePath + '<br>' +
                        './auto_view_ui.sh' +
                        '</div><br>' +
                        i18n[currentLang]['after-command-instruction'];
                    
                    // 添加按钮容器
                    const buttonContainer = document.createElement('div');
                    buttonContainer.style.display = 'flex';
                    buttonContainer.style.justifyContent = 'flex-end';
                    buttonContainer.style.marginTop = '20px';
                    
                    // 添加关闭按钮
                    const closeButton = document.createElement('button');
                    closeButton.textContent = i18n[currentLang]['close'];
                    closeButton.style.padding = '8px 15px';
                    closeButton.style.marginRight = '10px';
                    closeButton.style.backgroundColor = '#f0f0f0';
                    closeButton.style.border = 'none';
                    closeButton.style.borderRadius = '4px';
                    closeButton.style.cursor = 'pointer';
                    closeButton.onclick = function() {
                        document.body.removeChild(modal);
                    };
                    
                    // 添加刷新按钮
                    const refreshButton = document.createElement('button');
                    refreshButton.textContent = i18n[currentLang]['refresh-page'];
                    refreshButton.style.padding = '8px 15px';
                    refreshButton.style.backgroundColor = '#0066cc';
                    refreshButton.style.color = 'white';
                    refreshButton.style.border = 'none';
                    refreshButton.style.borderRadius = '4px';
                    refreshButton.style.cursor = 'pointer';
                    refreshButton.onclick = function() {
                        window.location.reload();
                    };
                    
                    // 组装对话框
                    buttonContainer.appendChild(closeButton);
                    buttonContainer.appendChild(refreshButton);
                    modalContent.appendChild(title);
                    modalContent.appendChild(description);
                    modalContent.appendChild(buttonContainer);
                    modal.appendChild(modalContent);
                    
                    // 显示对话框
                    document.body.appendChild(modal);
                }
            });
            
            // 导入现有UI
            importUIBtn.addEventListener('click', function() {
                // 创建模态对话框
                const modal = document.createElement('div');
                modal.style.position = 'fixed';
                modal.style.top = '0';
                modal.style.left = '0';
                modal.style.width = '100%';
                modal.style.height = '100%';
                modal.style.backgroundColor = 'rgba(0, 0, 0, 0.7)';
                modal.style.zIndex = '9999';
                modal.style.display = 'flex';
                modal.style.justifyContent = 'center';
                modal.style.alignItems = 'center';
                
                // 创建对话框内容
                const modalContent = document.createElement('div');
                modalContent.style.backgroundColor = 'white';
                modalContent.style.padding = '20px';
                modalContent.style.borderRadius = '10px';
                modalContent.style.maxWidth = '500px';
                modalContent.style.width = '80%';
                modalContent.style.boxShadow = '0 4px 8px rgba(0, 0, 0, 0.2)';
                
                // 添加标题
                const title = document.createElement('h3');
                title.textContent = i18n[currentLang]['import-ui-title'];
                title.style.marginTop = '0';
                title.style.color = '#0066cc';
                
                // 添加说明
                const description = document.createElement('p');
                description.textContent = i18n[currentLang]['import-ui-desc'];
                
                // 添加按钮容器
                const buttonContainer = document.createElement('div');
                buttonContainer.style.display = 'flex';
                buttonContainer.style.flexDirection = 'column';
                buttonContainer.style.gap = '15px';
                buttonContainer.style.marginTop = '20px';
                
                // 导入XML按钮
                const importXmlButton = document.createElement('button');
                importXmlButton.textContent = i18n[currentLang]['import-xml-file'];
                importXmlButton.style.padding = '10px 15px';
                importXmlButton.style.backgroundColor = '#0066cc';
                importXmlButton.style.color = 'white';
                importXmlButton.style.border = 'none';
                importXmlButton.style.borderRadius = '4px';
                importXmlButton.style.cursor = 'pointer';
                importXmlButton.onclick = function() {
                    importXmlFile();
                    document.body.removeChild(modal);
                };
                
                // 导入图片按钮
                const importImageButton = document.createElement('button');
                importImageButton.textContent = i18n[currentLang]['import-screenshot'];
                importImageButton.style.padding = '10px 15px';
                importImageButton.style.backgroundColor = '#0066cc';
                importImageButton.style.color = 'white';
                importImageButton.style.border = 'none';
                importImageButton.style.borderRadius = '4px';
                importImageButton.style.cursor = 'pointer';
                importImageButton.onclick = function() {
                    importImageFile();
                    document.body.removeChild(modal);
                };
                
                // 取消按钮
                const cancelButton = document.createElement('button');
                cancelButton.textContent = i18n[currentLang]['cancel'];
                cancelButton.style.padding = '10px 15px';
                cancelButton.style.backgroundColor = '#f0f0f0';
                cancelButton.style.border = 'none';
                cancelButton.style.borderRadius = '4px';
                cancelButton.style.cursor = 'pointer';
                cancelButton.onclick = function() {
                    document.body.removeChild(modal);
                };
                
                // 组装对话框
                buttonContainer.appendChild(importXmlButton);
                buttonContainer.appendChild(importImageButton);
                buttonContainer.appendChild(cancelButton);
                modalContent.appendChild(title);
                modalContent.appendChild(description);
                modalContent.appendChild(buttonContainer);
                modal.appendChild(modalContent);
                
                // 显示对话框
                document.body.appendChild(modal);
            });
            
            // 导入XML文件
            function importXmlFile() {
                // 创建文件输入元素
                const fileInput = document.createElement('input');
                fileInput.type = 'file';
                fileInput.accept = '.xml';
                fileInput.style.display = 'none';
                document.body.appendChild(fileInput);
                
                // 触发文件选择对话框
                fileInput.click();
                
                // 处理文件选择
                fileInput.addEventListener('change', function() {
                    const file = this.files[0];
                    if (!file) {
                        document.body.removeChild(fileInput);
                        return;
                    }
                    
                    const reader = new FileReader();
                    reader.onload = function(e) {
                        try {
                            // 获取文件内容
                            let xmlContent = e.target.result;
                            
                            // 预处理XML内容
                            xmlContent = preprocessXmlContent(xmlContent);
                            
                            // 验证XML内容
                            if (!xmlContent || !xmlContent.trim()) {
                                throw new Error('XML文件为空');
                            }
                            
                            // 检查是否包含XML声明
                            if (!xmlContent.includes('<?xml')) {
                                xmlContent = '<?xml version="1.0" encoding="UTF-8"?>\n' + xmlContent;
                            }
                            
                            // 检查是否包含根元素
                            if (!xmlContent.includes('<hierarchy')) {
                                // 如果没有hierarchy标签，尝试查找任何XML标签
                                const tagMatch = xmlContent.match(/<([a-zA-Z0-9_:-]+)[^>]*>/);
                                if (!tagMatch) {
                                    throw new Error('无法找到有效的XML标签');
                                }
                                
                                // 使用找到的第一个标签作为根元素
                                const rootTag = tagMatch[1];
                                console.log('使用 ' + rootTag + ' 作为根元素');
                            }
                            
                            // 更新XML内容
                            xmlString = xmlContent;
                            
                            // 重新解析和渲染XML
                            parseAndRenderXML();
                            
                            // 显示成功消息
                            alert(i18n[currentLang]['xml-import-success']);
                        } catch (error) {
                            console.error(i18n[currentLang]['process-xml-error'], error);
                            alert(i18n[currentLang]['xml-import-error'] + ': ' + error.message);
                            
                            // 显示错误信息和原始内容
                            showImportError(e.target.result, error.message);
                        }
                    };
                    
                    reader.onerror = function() {
                        alert(i18n[currentLang]['read-file-error']);
                    };
                    
                    reader.readAsText(file);
                    document.body.removeChild(fileInput);
                });
            }
            
            // 预处理XML内容
            function preprocessXmlContent(content) {
                if (!content) return content;
                
                // 移除BOM标记
                content = content.replace(/^\uFEFF/, '');
                
                // 移除前导空白
                content = content.trim();
                
                // 移除XML注释
                content = content.replace(/<!--[\s\S]*?-->/g, '');
                
                // 移除非打印字符
                content = content.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ' ');
                
                // 确保XML声明包含UTF-8编码
                if (content.includes('<?xml')) {
                    if (!content.includes('encoding="UTF-8"') && !content.includes("encoding='UTF-8'")) {
                        content = content.replace(/<\?xml[^>]*\?>/, '<?xml version="1.0" encoding="UTF-8"?>');
                    }
                } else {
                    content = '<?xml version="1.0" encoding="UTF-8"?>\n' + content;
                }
                
                return content;
            }
            
            // 显示导入错误
            function showImportError(content, errorMessage) {
                // 清空树视图
                treeView.innerHTML = '';
                
                // 创建错误消息
                const errorContainer = document.createElement('div');
                errorContainer.className = 'error-container';
                
                const errorTitle = document.createElement('h3');
                errorTitle.textContent = i18n[currentLang]['xml-import-error'];
                
                const errorMsg = document.createElement('p');
                errorMsg.textContent = errorMessage;
                
                const rawXmlTitle = document.createElement('h4');
                rawXmlTitle.textContent = i18n[currentLang]['original-xml-content'];
                
                const rawXml = document.createElement('textarea');
                rawXml.className = 'raw-xml';
                rawXml.value = content;
                rawXml.readOnly = true;
                
                const fixButton = document.createElement('button');
                fixButton.textContent = i18n[currentLang]['fix-and-import'];
                fixButton.style.marginTop = '10px';
                fixButton.style.marginRight = '10px';
                fixButton.onclick = function() {
                    try {
                        // 尝试更强力的修复
                        let fixedContent = content;
                        
                        // 确保有XML声明
                        if (!fixedContent.includes('<?xml')) {
                            fixedContent = '<?xml version="1.0" encoding="UTF-8"?>\n' + fixedContent;
                        }
                        
                        // 如果没有根元素，添加一个
                        if (!fixedContent.match(/<[a-zA-Z0-9_:-]+[^>]*>/)) {
                            fixedContent = fixedContent + '\n<hierarchy></hierarchy>';
                        }
                        
                        // 如果有内容但没有被标签包围，添加根标签
                        if (!fixedContent.match(/<[a-zA-Z0-9_:-]+[^>]*>[\s\S]*<\/[a-zA-Z0-9_:-]+>/)) {
                            const textContent = fixedContent.replace(/^<\?xml[^>]*>\s*/, '');
                            fixedContent = '<?xml version="1.0" encoding="UTF-8"?>\n<hierarchy>' + textContent + '</hierarchy>';
                        }
                        
                        // 更新XML内容
                        xmlString = fixedContent;
                        
                        // 重新解析和渲染XML
                        parseAndRenderXML();
                    } catch (e) {
                        alert(i18n[currentLang]['fix-failed'] + ': ' + e.message);
                    }
                };
                
                const backButton = document.createElement('button');
                backButton.textContent = i18n[currentLang]['back'];
                backButton.style.marginTop = '10px';
                backButton.onclick = function() {
                    parseAndRenderXML();
                };
                
                errorContainer.appendChild(errorTitle);
                errorContainer.appendChild(errorMsg);
                errorContainer.appendChild(rawXmlTitle);
                errorContainer.appendChild(rawXml);
                errorContainer.appendChild(fixButton);
                errorContainer.appendChild(backButton);
                
                treeView.appendChild(errorContainer);
            }
            
            // 导入图片文件
            function importImageFile() {
                // 创建文件输入元素
                const fileInput = document.createElement('input');
                fileInput.type = 'file';
                fileInput.accept = 'image/*';
                fileInput.style.display = 'none';
                document.body.appendChild(fileInput);
                
                // 触发文件选择对话框
                fileInput.click();
                
                // 处理文件选择
                fileInput.addEventListener('change', function() {
                    const file = this.files[0];
                    if (!file) {
                        document.body.removeChild(fileInput);
                        return;
                    }
                    
                    const reader = new FileReader();
                    reader.onload = function(e) {
                        // 更新截图
                        const screenshot = document.getElementById('deviceScreenshot');
                        screenshot.src = e.target.result;
                        
                        // 显示成功消息
                        alert(i18n[currentLang]['image-import-success']);
                        
                        // 更新高亮元素位置
                        const selectedNode = document.querySelector('.node-content.selected');
                        if (selectedNode) {
                            setTimeout(() => {
                                highlightElementBounds(selectedNode);
                            }, 100);
                        }
                    };
                    
                    reader.onerror = function() {
                        alert(i18n[currentLang]['read-file-error']);
                    };
                    
                    reader.readAsDataURL(file);
                    document.body.removeChild(fileInput);
                });
            }
        });
    </script>
</body>
</html>
EOF

  echo -e "${GREEN}一体化查看器已创建: $HTML_FILE${NC}"
}

# 主函数
main() {
  echo "===== Android UI 自动查看器 ====="
  echo "正在启动自动捕获和分析流程..."
  
  # 检查是否已经有相同时间戳的会话在运行
  if [ -d "$SESSION_DIR" ] && [ -f "$SESSION_DIR/.capture_lock" ]; then
    echo -e "${YELLOW}检测到相同时间戳的会话已在运行，正在打开已有结果...${NC}"
    # 直接打开已有的HTML查看器
    if [ -f "$SESSION_DIR/viewer.html" ]; then
      if [ "$(uname)" == "Darwin" ]; then
        open "$SESSION_DIR/viewer.html"
      elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        if [ -n "$(command -v xdg-open)" ]; then
          xdg-open "$SESSION_DIR/viewer.html"
        fi
      fi
      echo -e "${GREEN}已打开现有查看器: $SESSION_DIR/viewer.html${NC}"
      exit 0
    fi
  fi
  
  # 检查设备连接
  check_device
  
  # 捕获UI和截图
  capture_ui
  
  # 创建HTML查看器
  create_html_viewer
  
  # 自动打开HTML查看器
  echo -e "${BLUE}正在打开一体化查看器...${NC}"
  if [ "$(uname)" == "Darwin" ]; then
    open "$SESSION_DIR/viewer.html"
  elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    if [ -n "$(command -v xdg-open)" ]; then
      xdg-open "$SESSION_DIR/viewer.html"
    fi
  fi
  
  echo ""
  echo -e "${GREEN}完成!${NC}"
  echo -e "UI分析结果已保存到 ${BLUE}$SESSION_DIR${NC}"
  echo -e "您可以随时在浏览器中重新打开 ${BLUE}$SESSION_DIR/viewer.html${NC} 查看分析结果"
}

# 执行主函数
main 