# TAKT Pi 输入框与命令系统优化方案

> 当前状态：原生端输入框能用但功能比 pi-web 少很多。下面是对照 pi-web、主流桌面应用（Cursor、Codex、Perplexity、Raycast 等）的差距分析和补全方案。

---

## 一、现状对照

| 功能 | pi-web | TAKT Pi Native | 差距 |
|------|--------|----------------|------|
| **斜杠命令** | 8 个内置 + 扩展/prompt/skill，懒加载 + 补全面板 | 4 个内置，无补全面板 | ❌ 缺 4 个内置、扩展命令、补全 UI |
| **@文件提及** | 模糊搜索 + 本地索引 + 服务端搜索（大仓库）+ 补全面板 | 只加载索引，无补全 UI | ❌ 缺补全面板 |
| **历史记录** | ↑/↓ 翻历史，持久化 | 无 | ❌ 完全缺失 |
| **模型选择** | 按 provider 分组，价格，快捷键，不支持图片时警告 | 按 provider 分组，价格 + 色点 | ✅ 核心功能已有 |
| **思考等级** | Dropdown | Dropdown | ✅ 已有 |
| **工具开关** | 三档 preset + 逐工具 toggle | 无 | ❌ 完全缺失 |
| **附件** | 图片粘贴/拖入，多文件，预览缩略图 | 图片粘贴/拖入，文件选择器 | ⚠️ 缺预览、多选反馈 |
| **发送模式** | 回车/⌘Return 切换，steer/followUp，流式时可发 | 固定回车，steer/followUp（Option），无切换 | ⚠️ 缺切换开关 |
| **其他** | 紧凑模式、草稿自动保存、Compact 按钮、上下文环 | Compact 菜单、上下文环、附件菜单 | ⚠️ 缺草稿自动保存、紧凑模式 |

---

## 二、优先级分级（按影响面 × 实现成本）

### P0（必做，影响日常使用）
1. **斜杠命令补全面板**：pi-web 有 8 个内置 + 扩展命令，原生只有 4 个且无补全 UI，打字体验差。
2. **@文件补全面板**：原生已加载索引但没有面板，每次要记住完整路径。
3. **历史记录（↑/↓）**：主流编辑器必备，原生完全没有，重复输入很痛苦。
4. **扩展命令加载**：`get_commands` 接口已有，原生没调，导致 skill/prompt/extension 命令全丢。

### P1（提升体验，对标主流）
5. **工具预设开关（Tools button）**：对照 Cursor/Codex 的 "Tools" 按钮，三档 preset + 逐工具开关，原生完全缺。
6. **缺失的内置命令**：`/auto-compact`、`/reload`、`/session`，web 有原生没有。
7. **草稿自动保存**：web 有，原生没有，切会话或崩溃会丢输入。
8. **发送模式切换（回车 ⇄ ⌘Return）**：web 在设置里可切，原生固定回车，习惯 ⌘Return 的用户不友好。
9. **附件预览与多选反馈**：原生贴图后看不到缩略图，拖多个文件没有"已选 N 个"提示。

### P2（锦上添花，可延后）
10. **模型不支持图片时警告**：web 有，原生没有，用户贴图后才发现模型不支持。
11. **紧凑模式**：web 可切到单行输入框，原生固定多行。
12. **补全面板的高级特性**：skill 休眠态置底、排序、分组标签。

---

## 三、实现方案

### P0-1：斜杠命令补全面板

**目标**：输入 `/` 后弹出命令列表，支持模糊搜索、键盘导航、回车补全/执行。

**设计参考**：
- **Raycast 风格**：半透明浮层，命令名左对齐，描述右侧灰色，当前项高亮背景。
- **分组**：内置（Builtin） → 扩展（Extension） → Prompt → Skill（休眠的置底灰显）。
- **交互**：
  - 输入 `/com` 过滤到 "compact"，↓/↑ 切换，回车执行。
  - 输入 `/mcp` 直接回车打开 MCP 设置（与 web 行为一致）。
  - Esc 关闭面板但保留已输入文本。

**技术**：
- 新增 `CompletionPanel.swift`（SwiftUI overlay，跟随输入框位置，监听键盘）。
- 扩展 `ComposerTextEditor`，捕获 `/` 后的文本变化，通知 `ComposerView` 打开面板。
- 异步调 `get_commands` 懒加载扩展命令（首次输入 `/` 或打开会话时）。

**工作量**：约 3-4 小时（UI + 键盘导航 + 过滤逻辑）。

---

### P0-2：@文件补全面板

**目标**：输入 `@` 后弹出文件列表，模糊搜索，支持目录/文件图标、相对路径显示。

**设计**：
- 与斜杠面板复用同一套 UI 框架（只是数据源和过滤逻辑不同）。
- 输入 `@src/app` 过滤到 `src/app.ts`、`src/app.test.ts` 等，回车插入带引号的路径。
- 大仓库（`fileIndex.truncated`）时，150ms 防抖后额外调 `/api/file-index?q=...` 服务端搜索。

**技术**：
- 复用 `CompletionPanel`，传入 `fileIndex` 数据源。
- `ComposerView` 已有 `fileIndex` 和 `loadFileIndex()`，补上补全面板即可。

**工作量**：约 2 小时（复用斜杠面板 UI，只改数据源和插入逻辑）。

---

### P0-3：历史记录（↑/↓）

**目标**：↑ 翻上一条，↓ 翻下一条，支持持久化。

**设计**：
- 与 web 对齐：每次发送后记录到 `~/Library/Application Support/PiNative/prompt-history.json`（最多 100 条）。
- ↑ 从最新开始往前翻，↓ 往后翻，到头时回到空输入。
- 翻历史时不影响草稿（草稿暂存当前输入，退出历史模式时恢复）。

**技术**：
- 新增 `PromptHistory.swift`（单例，读写 JSON，与 web 的 `localStorage` 逻辑一致）。
- `ComposerTextEditor` 捕获 ↑/↓ 键（当输入框在首行/末行时），调 `ComposerView` 的 `historyUp/Down`。
- `ComposerView` 维护 `historyIndex: Int?`、`draftBeforeHistory: String?`。

**工作量**：约 1.5 小时。

---

### P0-4：扩展命令加载（`get_commands`）

**目标**：调 `/api/agent/command` 的 `get_commands`，加载 extension/prompt/skill 命令。

**技术**：
- `SessionStore` 新增 `commands: [SlashCommand]`、`func loadCommands() async`。
- 打开会话时异步调一次，结果存 `commands`。
- `ComposerView` 读 `store.commands`，合并内置命令后传给补全面板。

**数据结构**（对照 web 的 `SlashCommandInfo`）：
```swift
struct SlashCommand: Identifiable, Codable {
    let name: String
    let description: String?
    let source: Source // extension | prompt | skill
    let sourceInfo: SourceInfo?
    enum Source: String, Codable { case builtin, extension, prompt, skill }
    struct SourceInfo: Codable {
        let path: String?
        let source: String?
        let scope: String? // user | project | temporary
    }
}
```

**工作量**：约 1 小时。

---

### P1-5：工具预设开关（Tools button）

**目标**：输入框右侧加一个 "Tools" 按钮（扳手图标），点击弹出菜单：
- 三档 preset：Read-only / Default / Full（单选）
- 下方列出所有工具，逐个 toggle（checkbox）
- 底部"恢复默认"按钮

**参考**：Cursor 的 Tools 按钮、Codex 的 "Context" 按钮。

**技术**：
- 新增 `ToolsMenu.swift`（Menu + Popover，读 `/api/tools` 获取工具列表）。
- 修改工具状态后调 `set_tools` 命令（与 web 一致）。
- 按钮放在思考等级菜单右侧、上下文环左侧。

**工作量**：约 2 小时。

---

### P1-6：缺失的内置命令

| 命令 | 作用 | 实现 |
|------|------|------|
| `/auto-compact` | 切换自动压缩开关 | 调 `set_auto_compaction` 命令 |
| `/reload` | 重新加载会话（刷新） | 调 `SessionStore.reload()` |
| `/session` | 复制当前会话 ID | 复制到剪贴板 + Toast |

**工作量**：约 30 分钟。

---

### P1-7：草稿自动保存

**目标**：切会话时保存当前输入，切回时恢复。

**技术**：
- `ComposerView` 在 `text` 或 `attachments` 变化时，`onChange` 存到 `UserDefaults["draft_\(sessionId)"]`（JSON）。
- 打开会话时读取并恢复。
- 发送后清空草稿。

**工作量**：约 30 分钟。

---

### P1-8：发送模式切换

**目标**：设置里加"回车发送 / ⌘Return 发送"开关，影响输入框行为。

**技术**：
- `@AppStorage("enterToSend") var enterToSend: Bool = true`（默认回车发送）。
- `ComposerTextEditor` 根据此值决定回车是发送还是换行。
- Settings › General 加一个 Picker。

**工作量**：约 20 分钟（设置里已有此开关，只需在输入框里生效）。

---

### P1-9：附件预览与多选反馈

**目标**：
- 贴图后在输入框下方显示缩略图（可删除）。
- 拖多个文件后显示"已选 3 个文件"，点击展开列表。

**技术**：
- `ComposerView` 新增 `AttachmentsPreview`（HStack of 缩略图，右上角 X 删除）。
- 文件附件显示图标 + 文件名，图片附件显示缩略图。

**工作量**：约 1 小时。

---

### P2-10：模型不支持图片时警告

**目标**：贴图后，如果当前模型不支持图片输入，输入框上方显示黄色横幅："此模型不支持图片输入"。

**技术**：
- `ModelCatalog` 新增 `func supportsImages(_ ref: ModelRef) -> Bool`（读 `input` 字段）。
- `ComposerView` 在 `attachments` 非空且 `!supportsImages` 时显示警告。

**工作量**：约 20 分钟。

---

### P2-11：紧凑模式

**目标**：设置里加"紧凑输入框"开关，单行输入（类似搜索框），适合小屏。

**技术**：
- `@AppStorage("compactComposer") var compact: Bool = false`。
- `ComposerTextEditor` 根据 `compact` 设置 `NSTextView` 的 `maxNumberOfLines = 1`。

**工作量**：约 30 分钟。

---

### P2-12：补全面板高级特性

- **Skill 休眠态置底灰显**：读 `/api/skills` 的 `dormancy` 字段，休眠的技能排到最后且灰显。
- **排序**：内置 → 扩展 → Prompt → Skill（活跃）→ Skill（休眠）。
- **分组标签**：面板里用 Section 标题（"Builtin"、"Extensions"、"Skills"）。

**工作量**：约 1 小时。

---

## 四、时间估算

| 阶段 | 任务 | 工时 |
|------|------|------|
| **P0** | 斜杠补全面板 + @文件补全 + 历史记录 + 扩展命令加载 | 7.5 小时 |
| **P1** | 工具开关 + 缺失命令 + 草稿 + 发送模式 + 附件预览 | 4.5 小时 |
| **P2** | 图片警告 + 紧凑模式 + 高级特性 | 1.5 小时 |
| **总计** | — | **13.5 小时**（约 2 个工作日） |

---

## 五、其他发现的问题

### 5.1 模型编辑器（Settings › Models）

**现状**：只能在列表里看模型，不能编辑 `models.json`、不能添加自定义模型。

**对比 web**：
- 可以新增模型（填 provider/modelId/name）。
- 可以编辑现有模型（改名字、调顺序）。
- 可以删除模型。
- 可以测试模型（发一条 "Hello" 看是否能连通）。

**补全方案**：
- Settings › Models 页右上角加 "＋ 添加模型" 按钮。
- 列表项支持右键菜单：编辑 / 删除 / 测试 / 移到顶部。
- 新增 `ModelEditorSheet`（表单：provider / modelId / name / enabled）。
- 保存后调 `/api/models` POST 写入 `models.json`。

**工作量**：约 3 小时。

---

### 5.2 其他主流功能缺失

| 功能 | pi-web | TAKT Pi | 主流应用（Cursor/Codex） | 建议 |
|------|--------|---------|---------------------------|------|
| **多轮对话分支可视化** | 有（树形导航） | 有（SessionTreeSheet） | Cursor 有树形图 | ✅ 已有 |
| **代码高亮主题切换** | 无 | 无 | Cursor 可选主题 | 🔵 可做，优先级低 |
| **语音输入** | 无 | 无 | macOS 系统听写 | 🔵 P3，调 `NSSpeechRecognizer` |
| **会话导出（Markdown/PDF）** | 有（HTML） | 有（HTML） | Cursor 可导出 MD | ✅ 已有 |
| **全局快捷键唤醒** | 无 | 无 | Raycast 风格 | 🔵 P3，注册全局热键 |
| **多窗口支持** | 无（单标签页） | 支持 | VS Code 风格 | ✅ 原生已支持 |
| **@mention 不同类型**（@file / @folder / @codebase） | 只有 @file | 只有 @file | Cursor 有 @codebase | 🔵 P3，需服务端支持 |

---

## 六、推荐实施路径

```
第 1 天上午（4h）：P0-1 斜杠补全 + P0-2 @文件补全
第 1 天下午（4h）：P0-3 历史记录 + P0-4 扩展命令 + P1-6 缺失命令
第 2 天上午（3h）：P1-5 工具开关 + P1-7 草稿 + P1-8 发送模式
第 2 天下午（2.5h）：P1-9 附件预览 + P2 项（图片警告/紧凑模式/高级特性）
额外时间（3h）：模型编辑器（如果需要）
```

**验收标准**：
1. 输入 `/` 弹出补全面板，支持扩展命令，键盘导航流畅。
2. 输入 `@` 弹出文件列表，模糊搜索准确，回车插入路径。
3. ↑/↓ 翻历史，持久化到下次启动。
4. 工具按钮能切 preset 和逐工具开关。
5. 贴图后有缩略图，切会话后草稿恢复。

---

## 七、额外建议

1. **快捷键一致性**：对照 web 的快捷键（⌘K 搜索、⌘N 新会话、⌘. 停止），原生已有大部分，补全剩余的。
2. **性能优化**：补全面板打开时不要阻塞主线程，扩展命令加载异步化。
3. **可访问性**：补全面板支持 VoiceOver，键盘导航不依赖鼠标。
4. **测试覆盖**：补全逻辑（过滤、排序、插入）写单元测试，避免回归。

---

**总结**：当前输入框"能用但不好用"，P0 项（补全面板、历史记录、扩展命令）是最大痛点，优先做完这 4 项就能日常使用。P1 项提升专业感，P2 项锦上添花。全部做完约 13.5 小时 + 模型编辑器 3 小时 = **16.5 小时**（2-3 个工作日）。
