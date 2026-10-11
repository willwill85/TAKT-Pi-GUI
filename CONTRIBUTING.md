# Contributing

Thanks for helping. This is a native macOS client; the agent runtime is the unmodified pi-web server.

## Layout

| Path | What lives there |
|------|------------------|
| `Sources/PiKit` | UI-free library: models, HTTP/SSE client, stream reducer, session/sidebar/workspace state. Unit-tested. |
| `Sources/PiNative` | The SwiftUI/AppKit app. |
| `Sources/PiBrand` | Logo drawn in code (single source for the app icon and the in-app mark). |
| `Sources/IconGen` | Renders `scripts/AppIcon.iconset`. |
| `docs/` | Architecture and design notes. |

The server is a separate repository, [willwill85/pi-web](https://github.com/willwill85/pi-web) (a fork of [pi-web](https://github.com/agegr/pi-web) with tags, usage, pi-update and a few other endpoints). This app talks to it over the
documented HTTP + SSE API, so most features need no server change; when one does (e.g. `/api/account-usage`), the change
lands there first.

## Build and test

```sh
swift build
swift test            # PiKit unit tests
scripts/build-app.sh debug && open dist/PiNative.app
```

Requires macOS 15+, Xcode 16+ / Swift 6 toolchain, and Node 22.19+ for the server.

## Guidelines

- Keep `PiKit` free of SwiftUI so it stays testable. New state logic gets a test.
- Match the existing look: neutral surfaces, the orange accent only for small marks (cursor, send button, unread dot, upgrade
  hint). Do not tint large areas.
- Money and usage figures must come from a provider API. Never estimate, and label the real window
  (a provider's "today" is not a rolling 24 hours).
- Static regexes must use ICU syntax (`\x{4e00}`, not `\u{4e00}`) and must not crash the app on a bad pattern.
- Do not run `next build` against a directory that `npm run dev` is using; build with `PI_WEB_DIST_DIR=.next-native`.
- One logical change per PR. Describe what you verified on a real machine.

## Reporting bugs

Include macOS version, app version (Settings › About), and the tail of `~/Library/Logs/PiNative/sidecar.log`.
For a crash, attach the report from `~/Library/Logs/DiagnosticReports/PiNative-*.ips`.
