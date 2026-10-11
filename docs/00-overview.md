# Pi Native — 总览

> 把 pi-web（Next.js 网页版）的**全部当前功能**做成一个跑在 Mac 上的**原生 App**：不用浏览器、不嵌网页，界面对标 **Codex 桌面版**，并完整兼容 **pi remote**（`remote-pi` 扩展）。

## 1. 目标 / 非目标

**目标**
1. 功能与 pi-web 当前版本（[willwill85/pi-web](https://github.com/willwill85/pi-web)，基于上游 v0.11.1，pi SDK 1.1.0）等价：会话、聊天、工具卡片、模型、文件、Git、终端、子 Agent、设置（Models/Skills/Agents/Plugins/MCP/Cron/Tags…）。
2. **原生**：SwiftUI + AppKit，无 WebView 渲染主界面（Markdown / 终端 / Diff / 文件预览全部原生控件）。
3. **视觉与交互对标 Codex 桌面版**（见 [03-ui-spec-codex.md](03-ui-spec-codex.md)）。
4. **兼容 pi remote**：手机端 Remote Pi、`/remote-pi` 命令、本地 agent mesh（`list_peers`/`agent_send`）、cron/daemon 都照常工作（见 [05-remote-pi.md](05-remote-pi.md)）。
5. 与现有 pi 数据完全共用：`~/.pi/agent/sessions`、`settings.json`、`models.json`、`auth.json`、`~/.pi/remote`，装了 Pi Native 不破坏 CLI / pi-web。

**非目标**
- 不重写 pi agent 运行时（继续用 `@earendil-works/pi-coding-agent` SDK）。
- 不做 iOS / Windows / Linux（只有 macOS 15+，Apple Silicon 优先）。
- 不新增 pi-web 没有的 agent 能力；先做到对等，再谈超越。

## 2. 关键决策（及理由）

| # | 决策 | 理由 |
|---|------|------|
| D1 | **UI 全部原生 Swift，后端复用 pi-web 的 Node 服务作为 sidecar** | pi-web 的 ~70k 行里，UI 约占一半，**后端（`lib/` + `app/api/**`，约 35k 行）才是 pi 的核心价值**：`AgentSession` 进程内托管、扩展加载、MCP host、OAuth、模型目录、session 索引、worktree、terminal(node-pty)、cron、子 Agent。这些用 Swift 重写既无必要，也会与 `remote-pi` 等扩展不兼容（扩展是 Node 代码，必须跑在 Node 里）。 |
| D2 | 原生 App 与 sidecar 之间走 **pi-web 现有的 HTTP + SSE 协议**，零后端改动 | 协议已被 web / PWA / 手机端验证；Swift 端只是又一个客户端。只给 `next.config.ts` 加了可选 `PI_WEB_DIST_DIR`，避免污染 `npm run dev` 的 `.next`。 |
| D3 | sidecar 由 App 启动、**随机端口 + 每次启动随机密码（HTTP Basic）**，仅监听 127.0.0.1 | 复用 `proxy.ts` 现成的 `PI_WEB_PASSWORD` 鉴权；原生 `URLSession` 不带 `Origin`，天然通过 `request-security`。零安全回归。 |
| D4 | 支持第二种连接模式：**连接已有 pi-web / 远程 pi-web（URL+密码）** | 让 App 也能当 Mac 上的“瘦客户端”连另一台机器；也避免本机同时跑两份服务抢同一 cwd 的 remote-pi 锁。 |
| D5 | 不 fork 任何现成 App 做底座，但**大量复用开源组件**（见 §3） | Kiln/Perch/Codexeption 等的数据层是“每轮拉起 CLI 子进程”或绑死 Codex/ACP 协议，与 pi 的“常驻 AgentSession + 分支树 + 扩展 UI”不匹配；强改的成本高于自写。它们的 **UI 零件与交互思路**可参考。 |
| D6 | Swift Package（`PiKit` 库 + `PiNative` 可执行）+ 脚本打包 `.app`，不依赖 Xcode 工程 | CLI 可构建/测试/CI；`PiKit` 里的协议层/状态机有单元测试。 |

## 3. 开源复用清单

| 用途 | 选用 | 许可 | 说明 |
|------|------|------|------|
| Markdown 渲染（含表格、代码块高亮、LaTeX、可选中文本） | [gonzalezreal/textual](https://github.com/gonzalezreal/textual) | MIT | 取代 pi-web 的 react-markdown + KaTeX + syntax-highlighter；SwiftUI `Text` 管线，原生选中复制。 |
| 终端 | [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | 取代 xterm.js；PTY 仍由 sidecar 的 `terminal-manager`(node-pty) 提供，SwiftTerm 只做渲染与输入。 |
| 代码高亮（文件预览/Diff） | [raspu/Highlightr](https://github.com/raspu/Highlightr) | MIT | highlight.js via JavaScriptCore，无 WebView。 |
| Markdown AST（需要自定义块时） | [swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown) | Apache-2.0 | Textual 内部亦可替换解析器。 |
| 设计/交互参考 | [raya-ac/kiln](https://github.com/raya-ac/kiln)（MIT）、[chenweigao/perch](https://github.com/chenweigao/perch)（MIT）、[MarlonJD/codexeption](https://github.com/MarlonJD/codexeption)（MIT）、[dishant0406/kaji](https://github.com/dishant0406/kaji)（MIT） | MIT | 参考其侧栏分组、工具调用折叠分组（Kiln 借鉴 T3 Code）、@文件选择器、Composer 布局、右侧面板；**代码若直接搬运，保留版权声明并记入 `THIRD_PARTY_NOTICES.md`**。 |
| 仅参考架构（不复制代码） | [851-labs/codevisor](https://github.com/851-labs/codevisor)（**AGPL-3.0**，已支持 Pi）、[sst/opencode](https://github.com/sst/opencode) 桌面端（sidecar + 随机密码 Basic 认证 + 同一套 HTTP/SSE 协议，与本方案 D2/D3 同构） | AGPL / MIT | AGPL 代码不引入。opencode 的 sidecar 生命周期（选端口、随机密码、健康检查、退出清理）可借鉴思路。 |
| 后续可选 | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) 自动更新 | MIT | P4。 |

参考仓库放在本仓库同级的 `refs/` 目录（kiln、perch、kaji、codexeption、codevisor、textual），**不进入本仓库构建**。

## 4. 目录结构

```
pi-native/
  Package.swift
  docs/                     ← 本文档集
  Sources/
    PiKit/                  ← 与 UI 无关的库（可单测）
      Models/               ← JSON 模型：Session/Message/ContentBlock/ToolResult/Model/…
      Net/                  ← APIClient(HTTP+Basic)、SSE 解析、AgentEventStream
      Server/               ← SidecarManager（启动/探活/重启/退出清理）、ConnectionMode
      State/                ← 流式消息 reducer、SessionStore、SidebarStore（对应 hooks/useAgentSession、lib/session-tree）
    PiNative/               ← SwiftUI App
      App/                  ← @main、窗口、菜单、命令面板、快捷键
      Theme/                ← Codex 风格色板/字体/间距 token
      Sidebar/ Chat/ Composer/ Panels/ Settings/ Components/
  Tests/PiKitTests/
  scripts/                  ← build-app.sh（打包 .app）、build-server.sh（构建并内置 sidecar）
```

## 5. 文档索引
- [01-architecture.md](01-architecture.md) — sidecar、协议、状态机、数据流
- [02-feature-parity.md](02-feature-parity.md) — pi-web 功能 → 原生实现对照表（含状态）
- [03-ui-spec-codex.md](03-ui-spec-codex.md) — Codex 风格 UI 规范
- [04-roadmap.md](04-roadmap.md) — 分阶段计划与验收标准
- [05-remote-pi.md](05-remote-pi.md) — pi remote 兼容方案
