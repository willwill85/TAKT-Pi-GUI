# 05 — pi remote 兼容

**结论：天然兼容。** Pi Native 的会话全部运行在 sidecar（pi-web 的 Node 服务）里，`AgentSession` 通过 SDK 的 `createAgentSessionFromServices()` 创建，**与 pi CLI 完全一样地加载 `~/.pi/agent/settings.json` 的 `packages`**——其中就有 `npm:remote-pi`。因此手机端 Remote Pi、`/remote-pi` 命令、本地 agent mesh 都与在终端里跑 pi 时一样。

## 依赖的事实（本机已核对）
- `~/.pi/agent/settings.json` → `packages: ["npm:remote-pi", "npm:pi-mcp-adapter", "npm:pi-subagents", "npm:pi-web-access", "npm:pi-lens"]`
- `~/.pi/remote/` 存在 `supervisor.sock`、`daemons.json`、`cron.json`、`sessions/`、`locks/`；`remote-pi/dist/bin/supervisord.js` 常驻。
- 扩展向 UI 发的 `extension_ui_request`（`setStatus`/`setWidget`/`notify`/`select`/`confirm`…）pi-web 已完整转发——Pi Native 必须**完整实现**这些方法（见 02 的 D 节），这是兼容 remote-pi 的关键。

## 需要在原生侧做的事
1. **扩展 UI 全量支持**（P1）：remote-pi 用 `setStatus` 显示连接/配对状态，用对话框做配对确认；`select/confirm/input/editor` 弹窗、`notify` Toast、状态条与小部件都要实现。
2. **斜杠命令补全**（P1）：`get_commands` 返回的 `/remote-pi` 等扩展命令原样出现在补全里并可执行。
3. **Remote Pi 状态点**（P1）：侧栏底部显示：supervisor 是否在线（读 `~/.pi/remote/supervisor.sock` 存在性+连通）、当前会话 `remote-pi` 状态条文本。点击 → 在当前会话输入 `/remote-pi`。
4. **cwd 锁提示**（P1）：remote-pi 每目录一个 Pi（`~/.pi/remote/locks/<roomId>.sock`）。若新建会话时检测到该目录已被另一个 Pi 进程占用，提示“该目录已有 Pi 实例（可能是终端或 pi-web）”，并提供“仍然继续”。
5. **自动注入会话与手机同步**：手机端发来的消息会进入同一 `AgentSession`，SSE 照常推送 → 原生界面实时显示（无需额外工作；用 `agent_start` 事件触发运行态即可）。
6. **Cron / daemon**：`~/.pi/remote/cron.json(l)` 与 pi-web 的 `/api/cron` 已打通，Settings › Automations 直接用 `/api/cron`（P3）。
7. **Mesh 工具**：`list_peers`/`agent_send` 是 LLM 工具，工具卡片按通用样式渲染；`agent_send` 的参数（to/body）做专用摘要行（P2）。

## 不兼容风险与处理
| 场景 | 处理 |
|------|------|
| 同时运行旧 pi-web 与 Pi Native，在同一目录各开会话 | 锁冲突提示（上 4）；推荐二选一或外部模式 |
| sidecar 退出时 remote-pi 断线 | 退出前正常关闭会话（`SIGTERM` 触发 SDK dispose）；supervisor 不受影响 |
| remote-pi 升级协议 | 不涉及：协议在扩展与 relay 之间，与 UI 无关 |

## 验收
- 在 Pi Native 中新建会话 → 状态条出现 remote-pi 状态 → 用手机 Remote Pi 配对并发消息 → 原生界面实时出现该消息与助手回复 → 手机端能看到回复。
- `/remote-pi` 出现在 `/` 补全并可执行。
- 与终端 `pi` 同时存在时，锁冲突提示正确。
