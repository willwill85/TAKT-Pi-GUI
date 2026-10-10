# 01 — 架构

## 1. 总体

```
┌──────────────────────────── Pi Native.app ─────────────────────────────┐
│  SwiftUI / AppKit                                                      │
│  ┌ PiNative (UI) ────────────────────────────────────────────────────┐ │
│  │ Sidebar · Thread · Composer · Side panels · Settings · Palette     │ │
│  └───────────────▲───────────────────────────────────────────────────┘ │
│                  │ @Observable stores                                  │
│  ┌ PiKit (无 UI) ┴───────────────────────────────────────────────────┐ │
│  │ AppModel ─ SessionStore ─ StreamReducer ─ SidebarStore ─ Settings…  │ │
│  │ APIClient (URLSession, Basic) · SSEClient · Codable models          │ │
│  │ SidecarManager (spawn/health/restart/teardown)                      │ │
│  └───────────────┬───────────────────────────────────────────────────┘ │
└──────────────────┼─────────────────────────────────────────────────────┘
        HTTP + SSE │ 127.0.0.1:<随机端口>  Authorization: Basic pi:<随机密码>
┌──────────────────▼─────────────────────────────────────────────────────┐
│ sidecar = pi-web 的 Node 服务（Next.js standalone，零改动的 app/api/**）  │
│  rpc-manager(AgentSession 进程内) · terminal-manager(node-pty) · MCP    │
│  worktree · session-reader · models · cron-supervisor · …              │
│  加载 ~/.pi/agent/settings.json 的 packages：remote-pi / pi-mcp-adapter │
│  / pi-subagents / pi-web-access / pi-lens …                            │
└────────────────────────────────────────────────────────────────────────┘
        ~/.pi/agent/sessions/*.jsonl   ~/.pi/remote/*   各项目 cwd
```

## 2. Sidecar 生命周期（`SidecarManager`）

| 步骤 | 行为 |
|------|------|
| 定位服务端 | ① `PI_NATIVE_SERVER_DIR` 环境变量 / 设置里自定义目录 ② `.app/Contents/Resources/server/`（内置 standalone + node）③ 开发回退：`~/pi_gui/pi-web-custom` 下的 `.next-native` |
| 启动 | 选空闲端口；生成 32 字节随机密码；env：`PI_WEB_PASSWORD`、`PORT`、`HOSTNAME=127.0.0.1`、`PI_WEB_DIST_DIR=.next-native`（开发模式）、继承用户 shell 的 `PATH`（让 `npx`/`node`/`git` 可用）、`NODE_ENV=production` |
| 健康检查 | 轮询 `GET /api/home`（200 即就绪），超时 30s 给出日志入口 |
| 崩溃恢复 | 进程意外退出 → 自动重启（指数退避，最多 5 次）并重新建立所有 SSE |
| 退出 | App 退出 / 崩溃时 `SIGTERM` 整个进程组；启动时清理上次遗留的孤儿（pid 文件） |
| 日志 | `~/Library/Logs/PiNative/sidecar.log`，设置页可一键打开 |
| 外部模式 | `ConnectionMode.remote(url, password)`：不启动 sidecar，直接连已有 pi-web（局域网 / Cloudflare tunnel） |

> 本机同时跑旧的 pi-web 与 Pi Native 内置 sidecar 是安全的（不同端口），但**同一个 cwd 在两边各开一个会话**时，`remote-pi` 的“每目录一个 Pi”锁会冲突。建议日常只用其一，或让 Pi Native 用外部模式连旧服务。见 [05](05-remote-pi.md)。

## 3. 协议（全部沿用 pi-web，Swift 侧是又一个客户端）

核心端点（完整表见 [02](02-feature-parity.md)）：

| 用途 | 端点 |
|------|------|
| 会话列表 | `GET /api/sessions?summary=1` → `{sessions, runningSessionIds, awaitingInputSessionIds, …}` |
| 会话内容 | `GET /api/sessions/{id}?tail=N` → `{context:{messages, entryIds, hasMore, model, thinkingLevel}, tree, stats, leafId}`；分页 `GET …/context?before=` |
| 发送/控制 | `POST /api/agent/{id}`：`prompt` `abort` `steer` `follow_up` `set_model` `set_thinking_level` `compact` `fork` `navigate_tree` `set_tools` `bash` `get_commands` `extension_ui_response` … |
| 新会话 | `POST /api/agent/new {cwd, type:"prompt"|"ensure_session", message, provider, modelId, thinkingLevel, toolNames}` → 真实 sessionId |
| 事件流 | `GET /api/agent/{id}/events`（SSE）：`connected` `agent_start` `message_start` `message_update` `message_end` `tool_execution_*` `queue_update` `auto_retry_*` `compaction_*` `extension_ui_request` `agent_settled` `prompt_done` … |
| 侧栏状态 | `GET/POST /api/sessions/ui-state`（置顶/归档/项目顺序与命名），`GET /api/agent/running`（每次轮询带 revision） |
| 模型 | `GET /api/models?cwd=` `PUT /api/models/default` `PUT /api/models/enabled` … |
| 文件/Git | `GET /api/files/{path}?type=list|read|download|preview` `GET /api/git/status|diff` |
| 终端 | `POST /api/terminal` → id；`GET /api/terminal/{id}/events`(SSE)；`POST /api/terminal/{id}` 输入/resize |
| 设置类 | `/api/mcp*` `/api/skills*` `/api/plugins*` `/api/subagents/*` `/api/cron` `/api/models-config*` `/api/auth/*` `/api/tools/settings` `/api/project-trust` `/api/provider-usage/query` |

鉴权：每个请求 `Authorization: Basic base64("pi:"+password)`。不发送 `Origin`/`Sec-Fetch-*`，满足 `lib/request-security.ts`。SSE 用 `URLSession.bytes(for:)` 逐行解析（`data: {json}\n\n`）。

## 4. 客户端状态机（对应 `hooks/useAgentSession.ts`、`lib/streaming-message.ts`）

每个打开的会话一个 `SessionStore`（`@Observable`，`@MainActor`）：

```
state: messages[Message]  streaming: StreamingMessage?  phase: Phase?
       isRunning  queued{steering,followUp}  retry?  compaction?
       extensionDialogs[]  statuses[]  widgets[]  contextUsage  model  thinkingLevel
```

事件 → 状态（与 Web 版逐条对齐，已核对源码）：

| 事件 | 动作 |
|------|------|
| `connected` | 清流式态；`isStreaming:true` 则进入运行态；按 `pendingExtensionUiIds` 保留未决对话框 |
| `agent_start` | `isRunning=true`，phase=`waiting_model`，`streaming=nil` |
| `message_start`(assistant) | `streaming = message`（snapshot） |
| `message_update` | 对 `assistantMessageEvent` 应用 delta：`text_*` `thinking_*` `toolcall_start/delta/end`（`rawInput` 累积，`toolcall_end` 落定 `input`）。**`*_start` 必须重置块**（避免首个 delta 重复渲染——Web 版同款坑） |
| `message_end` | user：与乐观气泡去重；其余：追加到 `messages`；清流式态 |
| `tool_execution_start/update/end` | 维护 `phase.running_tools`；`bash`/`codemode` 的 `partialResult` 作为实时输出；`parentToolCallId` 非空的嵌套调用忽略 |
| `agent_end` | 结束流式；**重新 `GET /api/sessions/{id}` 与 `GET /api/agent/{id}`** 对账（模型、上下文用量、队列、扩展状态） |
| `agent_settled` / `prompt_done` | 收尾；`aborted:true` 不响铃、不通知；延迟关闭 SSE（idle grace） |
| `queue_update` | 更新 steering / follow-up 队列 |
| `auto_retry_*` / `compaction_*` | 横幅 / 状态 |
| `extension_ui_request` | `select/confirm/input/editor` 入队弹窗；`notify` 提示；`setStatus/setWidget/setTitle/set_editor_text/custom` 更新对应区域；`extension_ui_closed` 出队 |

`PiKit` 里的 `StreamReducer` 是纯函数（`(State, Event) -> State`），配 `Tests/PiKitTests` 用 `~/.pi/agent/sessions` 抽样和合成事件做回放测试。

## 5. UI 层结构

- **窗口**：单窗口 `NavigationSplitView` 风格自绘（隐藏标题栏文字、`NSVisualEffectView.sidebar` 毛玻璃侧栏、统一工具栏）；支持多窗口（⌘N 新窗口 = 新 `AppModel` 视图态，共享同一 sidecar）。
- **导航态**：`AppModel` 持有 `selection`（会话 id / 新会话草稿）、右侧面板开关与宽度、侧栏宽度；按 cwd 记忆工作区（对应 `lib/workspace-memory.ts`）。
- **渲染性能**：消息列表用 `LazyVStack` + 稳定 id；流式块只刷新最后一条；Markdown 用 Textual，对**历史消息缓存解析结果**；超长工具输出分段折叠；`tail=50` 起步、向上滚动再分页（`hasMore`/`before`）。
- **不使用 WebView**：Mermaid 图首期以“源码块 + 复制”呈现（P3 再评估原生渲染）；KaTeX 数学公式由 Textual 的 SwiftUIMath 原生渲染。

## 6. 持久化与偏好

- 业务数据全部由 sidecar 读写 `~/.pi/agent/*`（与 CLI / pi-web 共用）。
- 纯客户端偏好（窗口/面板尺寸、字体、侧栏分组展开、草稿、声音开关）：`UserDefaults` + `~/Library/Application Support/PiNative/`。草稿按会话 key 存（对应 `lib/draft-store.ts`）。

## 7. 安全

- 仅监听回环；随机密码仅在内存与子进程环境中；不写盘。
- 文件访问沿用 sidecar 的 allowed-roots 校验（`lib/file-access.ts`）。
- 项目信任（`project-trust`）弹窗沿用；未信任项目不加载项目扩展。
- 外部模式使用 Keychain 存密码。

## 8. 测试策略

- `PiKitTests`：SSE 解析、reducer 回放、模型解码（对真实会话文件抽样）、SidecarManager 的端口/就绪逻辑。
- 端到端冒烟（脚本）：启动 sidecar → 建会话 → 发 prompt（用 stub 模型或真实模型）→ 断言事件序列 → 对账。
- UI：用 peekaboo 截图对照 Codex 规范做目视验收（见 [04](04-roadmap.md) 验收清单）。
