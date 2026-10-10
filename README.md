# TAKT Pi GUI

原生 macOS（SwiftUI）版 **pi** 编码代理客户端：功能对标 [pi-web](../pi-web-custom)，界面对标 Codex 桌面版，兼容 pi remote。

- 规划与文档：[docs/00-overview.md](docs/00-overview.md)（总览）→ [01 架构](docs/01-architecture.md) → [02 功能对照](docs/02-feature-parity.md) → [03 UI 规范](docs/03-ui-spec-codex.md) → [04 路线图](docs/04-roadmap.md) → [05 pi remote](docs/05-remote-pi.md)
- 进度：[CHANGELOG.md](CHANGELOG.md)

## 构建与运行

```sh
# 1. 构建 sidecar（pi-web 服务，输出到独立 .next-native，不影响 npm run dev）
cd ../pi-web-custom && PI_WEB_DIST_DIR=.next-native npx next build --webpack
# 2. 构建并打包 App
cd ../pi-native && scripts/build-app.sh && open dist/PiNative.app
```

需要 macOS 15+、Swift 6、Node 22.19+。

## 致谢
见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
