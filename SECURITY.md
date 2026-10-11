# Security

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's
[private vulnerability reporting](https://github.com/willwill85/TAKT-Pi-GUI/security/advisories/new)
for this repository. Include the version, macOS version, and steps to reproduce.

## How the app handles credentials and network access

- The embedded server (the pi-web Node service) listens on **127.0.0.1 only**, on a random port.
- It is protected by HTTP Basic auth with a **random password generated at every launch**. The password is
  passed to the child process through its environment and kept in memory; it is not written to disk.
- The app reads the same files the `pi` CLI uses (`~/.pi/agent/auth.json`, `models.json`, `settings.json`, sessions).
  It does not copy them anywhere and has no telemetry or analytics of its own.
- **Balance and spend** (Settings › Usage) are fetched by the local server straight from each provider's API using the API key
  you already configured for pi. A key is only ever sent to hosts that belong to that provider (a per-provider allow-list in
  `lib/gateway-adapters.ts`); redirects are refused.
- "Remote" connection mode sends your password to the pi-web URL you enter. Prefer HTTPS or a private network (e.g. Tailscale).
- Upgrading pi runs `pi update self` on your machine, after you click the button. Nothing is upgraded automatically.

## Supported versions

Only the latest release is supported.
