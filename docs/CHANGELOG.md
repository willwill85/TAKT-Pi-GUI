
## 未发布 · 设置与标签拆分、logo、图片预览

- 设置窗口改为全局页：General / Models / Skills / Agents / Plugins / MCP / Tools / Connection / About。项目级内容（标签归属、项目结构、信任、worktree）移到项目设置 sheet。
- 全局标签库与设置分离：侧栏标签筛选条的「＋ 管理」打开标签库弹窗（网页端同步改动，见 pi-web-custom 提交）。
- 新建会话页增加项目 / worktree 选择条。
- 会话顶栏增加分支、文件/Review/终端入口、会话树与 system prompt 弹窗。
- 聊天图片预览（内联图、附件、本地路径）与 logo（`scripts/AppIcon.icns`，`docs/logo.png`）。
- 已知未验证：屏幕锁定期间无法截图，视觉与 Codex 的对照仍待完成。

## Unreleased

### Added
- **Usage**: balance and 24 h / 30 d spend per provider, straight from each provider's API (InferHub, Surplus Intelligence, Sub2API-style gateways, and the official providers pi-web already knew). Settings › Usage, plus a compact popover from the chart button in the sidebar footer. Windows a provider cannot give exactly are labelled ("today (UTC)", "this month", "all time") and totals that include them carry ≈.
- **Model prices** in the model picker, with a green → red price-tier dot relative to the models you can pick.
- **Pi updates**: checks at launch and every 6 h; an Upgrade pill takes the place of the Remote Pi indicator at the bottom-left; click to run `pi update self`.
- **Generate Title** now shows progress and the resulting title, and cannot be started twice for one thread.
- **Files explorer** under the thread list by default (like pi-web): git status letters, changed-directory dots, a *N changed +x −y* block that opens the diff, `@mention`, reveal in Finder, download.
- Settings › **Tags** (global tag library) alongside the sidebar tag filter.
- Open-source housekeeping: LICENSE (MIT), SECURITY.md, CONTRIBUTING.md, rewritten README.

### Fixed
- Launch crash: a static regex used `\u{4e00}` (not ICU syntax); now `\x{4e00}`, and static regexes no longer abort the app.
- The new-thread header drew a large solid orange square instead of the logo's cursor block; the mark is now a single Canvas drawing and menus use a neutral tint.
- Orange text where it did not belong (project name, links, selected states); the accent is now limited to small marks.

### Known gaps
Scroll minimap, tool presets, voice input, the `custom` terminal UI for extensions, a codemode-specific card, and a bundled Node server with auto-update. See [04-roadmap](04-roadmap.md).

## 未发布 · 设置与标签拆分、logo、图片预览

- 设置窗口改为全局页：General / Models / Skills / Agents / Plugins / MCP / Tools / Connection / About。项目级内容（标签归属、项目结构、信任、worktree）移到项目设置 sheet。
- 全局标签库与设置分离：侧栏标签筛选条的「＋ 管理」打开标签库弹窗（网页端同步改动，见 pi-web-custom 提交）。
- 新建会话页增加项目 / worktree 选择条。
- 会话顶栏增加分支、文件/Review/终端入口、会话树与 system prompt 弹窗。
- 聊天图片预览（内联图、附件、本地路径）与 logo（`scripts/AppIcon.icns`，`docs/logo.png`）。
- 已知未验证：屏幕锁定期间无法截图，视觉与 Codex 的对照仍待完成。

## Unreleased
- Fix launch crash: ICU regex used `\u{…}`; now `\x{…}`.
- Files explorer: git status letters, changed-directory dots, Changes block (N changed +x −y) opening the diff in Review, @mention / download / reveal in context menu.
- Settings › Tags page restored (global tag create / rename / recolor / delete), shared with the sidebar sheet.
- Pi version: checked at launch and every 6 h; Settings › General › Pi shows Check Now / Upgrade (`pi update self`); New Thread header shows the upgrade hint.
- Theme: brand orange accent via `.tint`, amber for warnings (no raw system blue / orange fills).
