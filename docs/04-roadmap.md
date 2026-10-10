# 04 — 路线图

原则：**每个阶段结束都是可运行、可日用的版本**；先打通纵向（sidecar→协议→一条完整对话），再横向铺功能。

| 阶段 | 目标 | 交付 | 验收 |
|------|------|------|------|
| **P0 地基** | 工程、sidecar、协议、窗口壳 | Swift Package；`SidecarManager`；`APIClient`+`SSE`；毛玻璃侧栏+主区壳；`build-app.sh` 出 `.app` | 双击 App → 自动起 sidecar → 侧栏显示真实会话列表 |
| **P1 核心对话（MVP）** | 能完整替代 pi-web 的日常聊天 | 侧栏（分组/置顶/归档/重命名/删除/Fork/搜索）；对话渲染（Markdown/思考/工具卡片/Diff/bash 输出/图片）；流式；Composer（模型/思考档/发送/停止/插话/队列/附件/@文件/斜杠命令/草稿）；扩展对话框与状态条；上下文用量；通知与提示音；General 设置 | 新建会话→发 prompt→流式输出+工具调用→结束对账；与 pi-web 打开同一会话内容一致；`/remote-pi` 命令可用 |
| **P2 工作区** | 右侧面板与高级会话能力 | 文件树/多标签文件查看（代码/MD/图/PDF/CSV）；Git Review+Diff；SwiftTerm 终端；子 Agent 查看器；分支导航+会话树；worktree；工具预设；`!bash`；路径链接；codemode 卡片；导出 | 在面板里浏览/预览/Review 本轮改动；终端可用；分支切换正确 |
| **P3 设置全集** | 与 pi-web 设置对等 | Models/登录(OAuth)/Skills/Agents/Plugins/MCP/Cron/Tags/Structure/Tools/用量；系统提示词与工具定义；项目信任；minimap | 设置页每项都能读写并与 pi-web 行为一致 |
| **P4 打包与打磨** | 可分发 | 内置 node+standalone sidecar；Sparkle 更新；图标；本地化(zh/en/…)；命令面板；性能（长会话）；无障碍；崩溃/日志 | 干净的 Mac 上拖入 Applications 即用（不依赖仓库路径） |

## P0 任务清单
1. `Package.swift`（PiKit + PiNative + 依赖：Textual、SwiftTerm、Highlightr）
2. `SidecarManager`、`ConnectionMode`、日志
3. `APIClient`（JSON、Basic、错误统一为 `AgentCommandError` 语义）、`SSEClient`
4. `Codable` 模型：Session/Message/ContentBlock/Usage/Model
5. 窗口壳：隐藏标题栏、`VisualEffectView` 侧栏、分栏拖拽
6. `scripts/build-app.sh`（Info.plist、图标、ad-hoc 签名）

## P1 任务清单（按依赖顺序）
1. `StreamReducer` + 单测 → `SessionStore`
2. `SidebarStore`（列表+ui-state 合并、轮询 running、分组/排序规则对齐 `lib/session-tree.ts`）
3. 对话视图：用户/助手/思考/工具/结果配对/Diff/bash/图片
4. Composer：文本框（NSTextView 包装，处理 IME 与 ↩/⇧↩）、模型&思考菜单、发送/停止/插话/队列
5. 新会话流程：目录选择 → `agent/new` → 切换到真实 id
6. 补全：`/` `@`；附件上传
7. 扩展 UI 队列；状态条/小部件
8. 通知/提示音；General 设置

## 风险与对策
| 风险 | 对策 |
|------|------|
| 长会话渲染卡顿 | tail 分页、行级缓存、Markdown 结果缓存、`LazyVStack` 稳定 id；必要时降级为 `NSTableView` 包装 |
| Textual 流式重排抖动 | 流式阶段只渲染最后一块；历史块冻结；必要时流式阶段先用纯文本+定时刷新 |
| sidecar 体积（node_modules 835MB） | standalone 追踪裁剪 + 去 source map；node-pty 仅保留 darwin-arm64 预编译 |
| 与旧 pi-web 同 cwd 锁冲突 | 外部模式；设置里提示；启动时检测 30141 端口上的 pi-web 并提示 |
| Mermaid/docx 预览无原生方案 | P2/P3 再定：源码块降级；docx 用 `NSAttributedString(docFormat)`/QuickLook |
| Codex 视觉只能凭记忆 | 落地后实机截图校准，记录于 03 文档 |

## 进度日志
见 [CHANGELOG.md](../CHANGELOG.md)。
