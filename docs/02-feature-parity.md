# 02 — 功能对照表（pi-web → Pi Native）

状态：`✅ 已实现` · `⬜ 未实现` · `➖ 不需要 / 由 sidecar 承担`。

> ✅ 表示代码已实现并随当前版本发布，**不代表每一项都做过逐项实机验证**。已在真机上走通的链路：启动与 sidecar、会话列表与聊天、设置各页与 Usage 数据、文件树、新线程页。其余按实现状态标注，发现问题请提 issue。阶段见 [04](04-roadmap.md)。
“后端”列是 pi-web 的 API/模块，Pi Native 直接复用，不重写。

## A. 会话与侧栏
| 功能 | 后端 | 原生实现 | 阶段 | 状态 |
|------|------|----------|------|------|
| 会话列表（按项目分组、相对时间、运行中/待输入指示） | `GET /api/sessions`、`/api/agent/running` | `SidebarStore` + `SidebarView` | P1 | ✅ |
| 项目分组：重命名、排序、折叠、置顶项目 | `/api/sessions/ui-state` | 同上 + 拖拽排序 | P1 | ✅ |
| 会话置顶 / 归档 / 撤销 / 取消归档 | ui-state | 右键菜单 + Toast | P1 | ✅ |
| 重命名 / 删除 / 自动命名 | `PATCH/DELETE /api/sessions/{id}`、`auto-name` | 菜单 + 内联编辑 | P1 | ✅ |
| Fork（复制当前分支为新会话） | `POST …/fork` | 菜单 | P1 | ✅ |
| 会话搜索（全文） | `/api/sessions/search` | ⌘K 命令面板 + 侧栏搜索 | P1 | ✅ |
| 子 Agent 会话树（父子） | `relation.subagent` | 侧栏折叠子行 | P2 | ✅ |
| 项目标签（彩色标签、标签过滤） | `/api/project-tags` | 侧栏标签 + 设置 | P3 | ✅ |
| 新会话：选目录 / 默认目录 / worktree | `/api/cwd/*`、`/api/default-cwd`、`/api/worktrees` | New thread 视图 + 目录选择器 | P1/P2 | ✅ |
| 导出会话 HTML | `GET …/export` | 菜单 → 保存面板 | P2 | ✅ |
| 工作区记忆（每项目上次会话/面板） | 客户端 | `WorkspaceMemory` | P2 | ✅ |

## B. 聊天
| 功能 | 后端 | 原生实现 | 阶段 | 状态 |
|------|------|----------|------|------|
| 流式文本 / 思考块（可折叠） | SSE | `StreamReducer` + `ThreadView` | P1 | ✅ |
| Markdown（GFM 表格、代码高亮、LaTeX、链接、可选中） | — | Textual | P1 | ✅ |
| 工具调用卡片：read/write/edit/bash/grep/find/ls 等 | SSE + session | `ToolCallView`（按工具专用折叠样式，Codex 风格 “Ran / Edited / Read”） | P1 | ✅ |
| bash 实时输出、exit code、截断 + 全文 | `tool_execution_update`、`/agent/{id}/bash-output` | 终端风格输出块 | P1 | ✅ |
| Edit/Write 内联 Diff、本轮改动文件汇总 | `turn-written-files`、`apply-patch` | `DiffView`、“N files changed” 卡 | P1 | ✅ |
| codemode 卡片（脚本及嵌套调用） | `codemode-view` | `CodemodeToolView` | P2 | ⬜ |
| 工具结果图片 / 附件图片 | `tool-result-images` | `ImagePreview`（灯箱） | P1 | ✅ |
| 用户消息：图片/文件引用、引用选中文本（quote） | — | 气泡 + 引用块 | P1/P2 | ✅ |
| 分支导航（同一父节点多分支切换） | `navigate_tree` | `BranchNavigator` | P2 | ✅ |
| 会话树视图（可视化、跳转、label） | `sessions/{id}` tree | `SessionTreeSheet` | P2 | ✅ |
| 向上分页 / 懒加载历史 | `…/context?before` | 滚动触顶加载 | P1 | ✅ |
| 滚动小地图（minimap） | 客户端 | 右侧细条（可选） | P3 | ⬜ |
| “回到最新”按钮、跟随输出 | 客户端 | 滚动代理 | P1 | ✅ |
| 重试横幅（auto retry）/ 压缩状态 / 错误提示 | SSE | 横幅 | P1 | ✅ |
| 上下文用量环、token/费用统计 | `state`、`session stats` | 输入栏右侧环 + 弹出 | P1 | ✅ |
| 完成提示音 / 系统通知 / Dock 角标 | — | `UNUserNotification` + `NSSound` | P1 | ✅ |
| 查看系统提示词 / 工具定义 | `state.systemPrompt`、`get_tools` | Inspector sheet | P3 | ✅ |

## C. 输入框
| 功能 | 后端 | 原生实现 | 阶段 | 状态 |
|------|------|----------|------|------|
| 发送 / 停止 / 运行中 steer（插话）/ follow-up 队列 / 清队列 | `prompt/abort/steer/follow_up/clear_queue` | `ComposerView` | P1 | ✅ |
| 模型选择（按 provider 分组、搜索、已启用过滤） | `/api/models` | 弹出菜单 | P1 | ✅ |
| 思考等级（按模型支持的档位） | `thinkingLevels` | 弹出菜单 | P1 | ✅ |
| 工具预设（None/Read-only/Default/Full）与逐工具开关 | `get_tools/set_tools` | 弹出面板 | P2 | ⬜ |
| 斜杠命令（内置 + 扩展 + skills + prompt 模板） | `get_commands` | 弹出补全 | P1 | ✅ |
| `@` 文件提及（模糊搜索） | `/api/file-index` | 弹出补全 | P1 | ✅ |
| 附件：粘贴/拖入图片、文件上传 | `/api/files?type=upload` | 拖放 + ⌘V + 选择器 | P1 | ✅ |
| `!cmd` / `!!cmd` 直接执行 bash | `bash`、`abort_bash` | 同 Web 语法 | P2 | ✅ |
| 草稿持久化、历史回溯（↑） | 客户端 | `DraftStore` | P1 | ✅ |
| 回车发送/⌘回车发送 切换 | 客户端 | 设置 | P1 | ✅ |
| 手动 /compact、自动压缩开关 | `compact`、`set_auto_compaction` | 菜单 | P1 | ✅ |
| 语音输入 | — | 系统听写（可选） | P3 | ⬜ |

## D. 扩展交互（保证 pi 扩展与 TUI 行为一致）
| 功能 | 原生实现 | 阶段 | 状态 |
|------|----------|------|------|
| `select / confirm / input / editor` 对话框队列 | 模态 sheet（FIFO） | P1 | ✅ |
| `notify`、`setStatus`（状态栏）、`setWidget`（编辑器上/下）、`setTitle`、`set_editor_text` | 状态条 / 小部件区 | P1 | ✅ |
| `custom` 终端 UI（`custom-ui-terminal`） | SwiftTerm 面板渲染 | P2 | ⬜ |
| 扩展错误提示 | Toast | P1 | ✅ |

## E. 右侧工作区面板
| 功能 | 后端 | 原生实现 | 阶段 | 状态 |
|------|------|----------|------|------|
| 文件树（忽略 .gitignore、隐藏项、符号链接目录） | `/api/files?type=list`、`file-tree-visibility` | `FileTreeView` (OutlineGroup) | P2 | ✅ |
| 文件查看：代码高亮、Markdown 预览、图片、PDF（PDFKit）、CSV/TSV 表格、docx | `type=read/preview` | `FileViewerView` 多标签 | P2 | ✅ |
| 文件编辑 / 保存 | `PUT`（若支持）/ 按 Web 现状 | 只读优先，P3 评估编辑 | P3 | ✅ |
| 文件监听刷新 | `type=watch` SSE | 自动刷新 | P2 | ✅ |
| 打开方式：Finder / 默认应用 / 终端 | `open-in-explorer` | 本地直接 `NSWorkspace` | P2 | ✅ |
| Git 变更列表 + 单文件 Diff（Review 面板） | `/api/git/status|diff` | `ReviewPanel`（Codex 同款） | P2 | ✅ |
| 终端（多标签、持久） | `/api/terminal*` | SwiftTerm | P2 | ✅ |
| 子 Agent 只读查看器 | `…/context` 轮询 | `SubagentViewer` | P2 | ✅ |
| Worktree 创建/切换/删除 | `/api/worktrees` | 分支 chip 菜单 | P2 | ✅ |
| 项目结构分析视图 | `/api/project-structure` | 设置页子页 | P3 | ✅ |
| 聊天里路径可点击（相对/绝对/行号/文件夹） | `file-links` | 链接拦截 → 右侧面板 | P2 | ✅ |

## F. 设置
| 页面 | 后端 | 阶段 | 状态 |
|------|------|------|------|
| General：外观(浅/深/跟随系统)、字体、语言(zh/en/ja/ru)、提示音、回车行为、Remote Pi 状态 | 客户端 + `settings.json` | P1 | ✅ |
| Models：默认模型/思考档、启用模型开关、models.json 编辑、模型目录刷新、测试、供应商用量 | `/api/models*`、`/api/models-config*`、`/api/provider-usage` | P3 | ✅ |
| 登录：API key / OAuth（设备码、粘贴回调） | `/api/auth/*` | P3 | ✅ |
| Skills：已加载、开关、搜索安装(skills.sh)、更新检查 | `/api/skills*` | P3 | ✅ |
| Agents：内置子 Agent 开关、并发数、Profile 编辑 | `/api/subagents/*` | P3 | ✅ |
| Plugins：包插件管理、更新检查 | `/api/plugins*` | P3 | ✅ |
| MCP：服务器列表/开关/暴露/添加(粘贴导入)/测试/OAuth 登录/撤销/项目信任 | `/api/mcp*`、`/api/project-trust` | P3 | ✅ |
| 定时任务（Cron） | `/api/cron` | P3 | ✅ |
| 项目结构 / 项目标签 | `/api/project-structure`、`/api/project-tags` | P3 | ✅ |
| 工具设置（Code mode、PowerShell 开关） | `/api/tools/settings` | P3 | ✅ |
| 应用更新检查 | `/api/app-update` | P4 | ✅ |

## F2. Pi Native 新增（pi-web 没有或形态不同）
| 功能 | 后端 | 原生实现 | 状态 |
|------|------|----------|------|
| 各服务商余额 + 24 小时 / 30 天花费（以服务商 API 为准，不估算；窗口不严格时标注） | `/api/account-usage`（`lib/gateway-adapters.ts`） | 设置 › Usage、侧栏底部图表弹层 | ✅ |
| 模型价格（USD / 1M tokens）与价格档位色点 | `/api/model-prices` | 模型选择器 | ✅ |
| pi 新版本定期检查（6 小时）与一键升级 | `/api/pi-update`（`pi update self`） | 侧栏左下角 Upgrade 胶囊（占用 Remote Pi 位置）、设置 › General | ✅ |
| 文件树放在侧栏左下（默认），可切到右侧面板 | — | `SidebarFilesSection` | ✅ |
| 文件树：git 状态字母、含变更目录圆点、变更块（N changed +x −y）→ 打开 diff、@提及 / 下载 / 在 Finder 显示 | `/api/git/status` | `FilesPanel` / `ChangesSection` | ✅ |
| 生成标题（带进度与结果提示） | `POST …/auto-name` | 线程菜单、侧栏右键 | ✅ |
| 全局标签库（设置 › Tags）与侧栏标签过滤 | `/api/project-tags` | `TagsManagerContent` | ✅ |

## G. 平台级（原生独有 / 取代 Web 机制）
| 项 | 说明 | 阶段 | 状态 |
|----|------|------|------|
| Web 密码登录 / Cookie | ➖ 由 Basic 随机密码取代 | — | ➖ |
| PWA / Service Worker / Web Push | ➖ 由原生通知取代（`/api/push` 不用） | — | ➖ |
| 移动端响应式布局 | ➖ 仅桌面 | — | ➖ |
| 菜单栏、快捷键、⌘K 命令面板、多窗口、Dock 菜单、深链 `pinative://` | 原生 | P1/P4 | ✅ |
| 内置 sidecar 打包（node + standalone）与自动更新(Sparkle) | `scripts/build-server.sh` | P4 | ⬜ |
