# Pi Native 功能对照与优化方案

## 一、模型选择器 (Model Picker)

### 现状
**原生端 (`ComposerView.swift` L143-176)**:
- 基础 Menu，按 provider 分组
- 显示模型名称、价格（`$X.X in · $Y.Y out / 1M tokens`）、价格色点（绿到红）
- 无搜索、无过滤、无收藏/默认标记

**网页端 (`ModelSelector.tsx`, 337 行)**:
- 支持搜索过滤 (`filterModelOptions`)
- 分组显示（provider 分隔线）
- 星标标记默认模型
- 字段模式 (field) 和按钮模式 (button)

### 差距
1. **无搜索**: 模型多时（20+ 个）难找
2. **无默认星标**: 不知道哪个是新会话的默认模型
3. **UX 粗糙**: 原生 Menu 没有 hover 高亮、滚动体验差

### 建议
**P1 (必要)**:
- 搜索框：支持按名称、provider 过滤
- 星标：当前默认模型加 ⭐️，右键菜单"设为默认"

**P2 (改善)**:
- 自定义弹出面板代替 SwiftUI Menu，支持键盘导航、平滑滚动
- "仅显示已启用"开关（settings 里禁用的模型灰色或隐藏）

---

## 二、斜杠命令 (`/` commands)

### 现状
**原生端 (`ComposerView.swift` L271-283)**:
- 4 个内置命令：`/compact`, `/clone`, `/copy`, `/name <name>`
- **无补全面板、无提示、无扩展命令**

**网页端 (`ChatInput.tsx` + `useAgentSession.ts`)**:
- 8 个内置命令：`/compact`, `/auto-compact`, `/reload`, `/name`, `/session`, `/mcp`, `/copy`, `/clone`
- 补全面板：输入 `/` 自动弹出，显示所有命令、描述、来源（builtin/extension/prompt/skill）
- 支持扩展命令 (`SlashCommandInfo[]`)、prompt 模板、skill 命令
- 模糊搜索、排序（优先精确匹配 > 前缀 > 包含）
- 单 Enter 确认精确命令，Tab/Enter 补全

### 差距
1. **无补全 UI**: 用户不知道有哪些命令、怎么用
2. **缺命令**: 没有 `/reload`, `/auto-compact`, `/session`, `/mcp`
3. **无扩展性**: 不支持 extension/skill/prompt 命令

### 建议
**P1 (必要)**:
- 补全面板：`CompletionPanel` SwiftUI view，监听输入框 `/` 触发
- 补全逻辑：
  ```swift
  struct SlashCommand { let name: String; let description: String; let source: String }
  var builtinCommands = [
    SlashCommand(name: "compact", description: "Compress context", source: "builtin"),
    SlashCommand(name: "clone", description: "Fork this thread", source: "builtin"),
    SlashCommand(name: "copy", description: "Copy last assistant reply", source: "builtin"),
    SlashCommand(name: "name", description: "Rename session: /name <name>", source: "builtin"),
    SlashCommand(name: "reload", description: "Reload session resources", source: "builtin"),
    SlashCommand(name: "auto-compact", description: "Toggle auto-compaction", source: "builtin"),
  ]
  ```
- 搜索：输入 `/re` 过滤到 `reload`
- 键盘：↑↓ 选择，Enter 执行/补全，Esc 关闭

**P2 (扩展)**:
- 从服务端加载扩展命令：`GET /api/commands` → `[{name, description, source}]`
- Skill 命令集成（如果后端支持）
- Prompt 模板命令

---

## 三、@ 文件提及 (File Mention)

### 现状
**原生端**:
- 有 `fileIndex` 加载 (`GET /api/file-index`)
- **但没有补全 UI**，用户无法通过 `@` 触发

**网页端 (`ChatInput.tsx` L1090-1280)**:
- 输入 `@` 自动弹出文件补全面板
- 本地过滤 + 服务端搜索（repo 超大时）
- 模糊匹配、路径高亮
- 支持 `@folder/` 补全子路径

### 差距
1. **完全缺失 @ 补全 UI**
2. fileIndex 已加载但未使用

### 建议
**P1 (必要)**:
- `@` 补全面板：复用 slash 补全的 UI 框架
- 触发逻辑：检测光标前最后一个 `@`，提取查询（如 `@src/ap` → query=`src/ap`）
- 匹配：
  ```swift
  func filterFiles(_ query: String, index: [String]) -> [String] {
    index.filter { $0.localizedCaseInsensitiveContains(query) || $0.hasPrefix(query) }
         .sorted { pathScore($0, query) < pathScore($1, query) }
         .prefix(20)
  }
  ```
- 应用：选中后替换 `@query` 为 `@完整路径`

**P2 (改善)**:
- 服务端搜索：query 长度 > 2 时调 `/api/file-index?q=...`
- 图标：文件类型图标（`.ts` / `.swift` / `.md`）

---

## 四、工具预设 (Tool Presets)

### 现状
**原生端**:
- **完全没有**: 没有 None/Read-only/Default/Full 预设选择
- 网页端有完整实现 (`ToolPresetsPanel.tsx`, `tool-presets.ts`)

### 差距
1. 用户无法快速切换工具集（如"只读模式"禁用 write/edit/bash）
2. 没有逐工具开关面板

### 建议
**P2 (改善，非必要)**:
- 预设按钮：输入框右侧加 "Tools" 按钮，弹出面板
- 4 档预设：
  - None: 全禁用
  - Read-only: 只读工具（read/list/grep）
  - Default: 常用工具
  - Full: 全部工具
- 逐工具开关：高级面板，列出所有工具 + checkbox

---

## 五、其他输入框功能

### 网页端有、原生端缺的

| 功能 | 网页端 | 原生端 | 优先级 |
|------|--------|--------|--------|
| 历史回溯（↑/↓） | ✅ 完整实现 | ✅ 有 (`historyIndex`) | - |
| 多行粘贴格式化 | ✅ Markdown 列表续写 | ⬜ 无 | P3 |
| 草稿持久化 | ✅ localStorage | ⬜ 无 | P2 |
| 拖入图片/文件 | ✅ 完整 | ✅ 有 (`onDrop`) | - |
| Shift+Enter 换行 vs Enter 发送 | ✅ 可配置 | ✅ 固定 Shift+Enter 换行 | P3 |
| `/!cmd` 直接执行 bash | ✅ 有 | ⬜ 无（需手动输入 `!cmd`） | P3 |
| 附件预览/移除 | ✅ 缩略图 + X 按钮 | ⬜ 只有文件名列表 | P2 |

---

## 六、主流桌面应用对照

### Cursor / Windsurf / Zed
1. **Command Palette (⌘K)**: Pi Native 已有
2. **Inline 补全**: 不适用（Pi 是对话式，不是 inline）
3. **多模型快速切换**: 
   - Cursor: ⌘+数字键切换常用模型
   - **建议**: 收藏夹 + 快捷键（⌘1-5 切前 5 个收藏模型）
4. **@ 符号补全**: 
   - Cursor: `@file`, `@folder`, `@code`, `@docs`, `@web`
   - Pi Native: 只需 `@file`，其他不适用
5. **Composer 多行高度自适应**: 
   - Pi Native 已有 (`TextEditor` 自动撑高)

### Claude Desktop
1. **Projects**: Pi 用 cwd 代替
2. **Artifacts 预览**: Pi Native 有文件查看器
3. **引用消息**: 网页端有 quote，原生端无（P3）

---

## 七、优先级总结

### P0（修复/完成中）
- ✅ 打开大变更项目卡死 (已修)
- ✅ 标签过滤时不能折叠 (已修)

### P1（核心缺失，影响日常使用）
1. **斜杠命令补全面板** (2-3 天)
   - UI: `CompletionPanel` SwiftUI view
   - 逻辑: 内置 6 个命令 + 模糊搜索
   - 交互: ↑↓ Enter Esc
   
2. **@ 文件补全** (1-2 天)
   - 复用斜杠补全 UI
   - 触发: `@` + query 提取
   - 匹配: 本地 fileIndex 过滤

3. **模型选择器搜索 + 星标** (1-2 天)
   - 搜索框: 过滤模型列表
   - 星标: 默认模型标记 + 右键设置

### P2（改善体验）
1. **草稿持久化** (半天)
   - 保存到 UserDefaults，按 sessionId key
   
2. **附件预览改善** (半天)
   - 图片缩略图 + 删除按钮
   
3. **自定义模型选择器** (2 天)
   - 代替原生 Menu，支持键盘、滚动优化

### P3（锦上添花）
1. 工具预设面板
2. `/!cmd` 快捷执行
3. Markdown 列表续写
4. Enter/⌘Enter 发送模式切换

---

## 八、实施建议

**第一阶段（1 周）**: P1 三项
- 斜杠补全
- @ 补全
- 模型搜索

**第二阶段（3 天）**: P2 高优先级
- 草稿持久化
- 附件预览

**第三阶段（按需）**: P3 + 自定义选择器

---

