<p align="center"><img src="docs/logo.png" width="112" alt="TAKT Pi GUI"></p>

<h1 align="center">TAKT Pi GUI</h1>

<p align="center">A native macOS app for the <a href="https://github.com/earendil-works/pi">pi</a> coding agent.<br>
SwiftUI, no web view. Codex-style layout. Works with <code>remote-pi</code>.</p>

---

TAKT Pi GUI gives pi a proper Mac front end. Your sessions, models, skills, MCP servers and extensions are the ones you
already use with the `pi` CLI and [pi-web](https://github.com/agegr/pi-web) — the app just replaces the browser tab.

## Features

**Chat**
- Streaming replies with collapsible reasoning, tool-call cards (read / edit / bash / grep …), inline diffs, image preview
- Composer with model and thinking-level pickers, queueing and steering, attachments (drag & drop), `@file` mentions, slash commands
- Branching: fork a thread, browse the conversation tree, view the system prompt and tool definitions
- **Generate Title** for any thread (menu), with progress and result shown as a toast

**Workspace**
- Sidebar with projects, pinned and archived threads, **colored tags** with a tag filter bar, search (⌘K)
- **Files explorer under the thread list** (like pi-web): git status letters, "contains changes" dots, a *N changed +x −y* block that opens the diff, `@mention`, reveal, download
- Right panel: Review (git diff), file viewer (code / Markdown / images / PDF / CSV), integrated terminal
- Projects: new-thread screen with project and worktree pickers, project settings (tags, structure, worktrees, trust)

**Models, balance and spend**
- Model picker shows each model's price (USD / 1M tokens) with a **price-tier color dot** (green → red, relative to the models you can pick)
- **Balance and spend for every connected provider** — last 24 hours and last 30 days — taken from the provider's own API, never estimated
  (details below). Open it from the chart button at the bottom of the sidebar or Settings › Usage

**Settings**
- General, Tags, Usage, Models (login / OAuth), Skills, Agents, Plugins, MCP, Tools, Connection, About
- Global tag library lives in Settings › Tags; project assignment is in the project menu

**Pi updates**
- Checks npm for a newer pi at launch and every 6 hours. When one exists, an **Upgrade** pill replaces the Remote Pi
  indicator at the bottom-left; click it to run `pi update self`. Nothing upgrades without your click.

**remote-pi**
- Sessions run in the same server process that loads your `remote-pi` extension, so phone pairing, `/remote-pi`, the agent mesh and
  cron/daemon keep working. The sidebar footer shows whether the remote-pi supervisor is running.

## Balance and spend

| Provider | Balance | 24 h | 30 d | Verified against a live account |
|----------|---------|------|------|------|
| InferHub | ✅ | ✅ rolling 24 h | ✅ rolling 30 d | yes |
| Surplus Intelligence | ✅ | ⚠️ UTC calendar day | ✅ rolling 30 d | yes |
| Sub2API-style gateways (e.g. vanyospace) | ✅ | ⚠️ today's cost | ⚠️ sum of the daily list if offered, else lifetime total | yes |
| OpenRouter | key limit remaining | ⚠️ UTC day | ⚠️ calendar month | no (follows the documented key endpoint) |
| DeepSeek, Moonshot, MiniMax, Vercel AI Gateway | balance | – | – | no |
| OpenAI Codex, Kimi for Coding, OpenCode Go, MiniMax plans | quota windows (% used) | – | – | no |

A ⚠️ cell means the provider does not offer that exact window, so the app shows the window it *does* report and labels it
(“today (UTC)”, “this month”, “all time”). Totals that include such a figure carry a **≈**. Different currencies are never added together.
A provider with credentials but no known usage API is listed as “connected, no balance API” rather than guessed at.

Rows marked "no" use the server's official-provider code, which is unit-tested against recorded payloads but has not been run against a real account by the maintainer — reports welcome. Adding a gateway means adding one adapter (`lib/gateway-adapters.ts` in the server); see [CONTRIBUTING.md](CONTRIBUTING.md).

## Install

There are no signed releases yet; build from source.

**Requirements:** macOS 15 or later, Xcode 16+ (Swift 6), Node 22.19+, and the `pi` CLI configured (`pi` on your `PATH`, models logged in).

```sh
git clone https://github.com/willwill85/TAKT-Pi-GUI.git
git clone https://github.com/willwill85/pi-web.git pi-web-custom     # the server; keep it next to this repo
cd pi-web-custom && npm install && PI_WEB_DIST_DIR=.next-native npx next build --webpack
cd ../TAKT-Pi-GUI && scripts/build-app.sh && open dist/PiNative.app
```

The app is ad-hoc signed, so the first launch needs *right-click → Open*.

### Connection modes
- **Embedded (default):** the app starts the server on `127.0.0.1` with a random port and a fresh password each launch.
- **Remote:** point it at an existing pi-web (`URL` + password), e.g. a server you reach over Tailscale.
  Don't open the same working directory in two clients at once — remote-pi locks a directory per process.

## How it works

```
 SwiftUI app (PiNative) ── HTTP + SSE ──▶ pi-web server (Node) ──▶ pi SDK / AgentSession, extensions, MCP
        ▲                                         │
   PiKit (state, reducer)                  ~/.pi/agent  (sessions, models, auth, settings)
```

The agent runtime is not reimplemented: the app is another client of pi-web's API, which keeps it compatible with extensions
(they are Node code). See [docs/01-architecture.md](docs/01-architecture.md).

## Privacy

No telemetry. The only network calls the app itself triggers go to npm (pi version check) and, for Usage, to the providers
you have already connected. See [SECURITY.md](SECURITY.md).

## Status

Early (0.x). Daily-usable for chat, files, review, terminal and settings; expect rough edges. Known gaps and the plan:
[docs/04-roadmap.md](docs/04-roadmap.md). What changed: [CHANGELOG](docs/CHANGELOG.md).

## Documentation

[Overview](docs/00-overview.md) · [Architecture](docs/01-architecture.md) · [Feature parity with pi-web](docs/02-feature-parity.md) ·
[UI spec](docs/03-ui-spec-codex.md) · [Roadmap](docs/04-roadmap.md) · [remote-pi](docs/05-remote-pi.md)

## Credits and license

MIT — see [LICENSE](LICENSE). Built on [pi-web](https://github.com/agegr/pi-web) by agegr, and on
[Textual](https://github.com/gonzalezreal/textual), [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) and
[Highlightr](https://github.com/raspu/Highlightr). Design references and full notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Not affiliated with OpenAI; "Codex-style" describes the layout only.
