import Foundation

/// One local headless browser, driven by `scripts/browser-server.mjs` (Playwright's Chromium).
/// The user's Chrome is never involved. Frames arrive as JPEG bytes over SSE.
@MainActor
@Observable
public final class BrowserSession {
    public private(set) var image: Data?
    public private(set) var url = ""
    public private(set) var title = ""
    public private(set) var status = "Starting…"
    public private(set) var log: [String] = []

    private var process: Process?
    private var port: Int?
    private var events: Task<Void, Never>?
    private var starting = false

    public init() {}

    public var pageURL: URL? { URL(string: url) }

    public func start() {
        guard process == nil, !starting else { return }
        starting = true
        guard let script = Self.scriptURL() else { status = "Browser server script not found"; starting = false; return }
        guard let node = Self.nodeURL() else { status = "node not found"; starting = false; return }
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = node
        proc.arguments = [script.path]
        proc.environment = ProcessInfo.processInfo.environment.merging(["PINATIVE_BROWSER_PORT": "0"]) { _, new in new }
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { status = error.localizedDescription; starting = false; return }
        process = proc
        let handle = pipe.fileHandleForReading
        // availableData blocks until the process closes the pipe, so it must not run on the main actor.
        Task.detached { [weak self] in
            let data = handle.availableData
            let port = String(data: data, encoding: .utf8).flatMap { line -> Int? in
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                return obj["port"] as? Int
            }
            await MainActor.run {
                guard let self else { return }
                guard let port else { self.status = "Browser failed to start"; self.starting = false; return }
                self.port = port
                self.starting = false
                self.status = "Ready"
                self.listen(port: port)
            }
        }
    }

    public func stop() {
        events?.cancel(); events = nil
        process?.terminate(); process = nil
        port = nil
    }

    public func go(_ raw: String) { act(["op": "goto", "url": raw]) }
    public func back() { act(["op": "back"]) }
    public func forward() { act(["op": "forward"]) }
    public func reload() { act(["op": "reload"]) }
    public func click(x: Double, y: Double) { act(["op": "click", "x": x, "y": y]) }
    public func type(_ text: String) { act(["op": "type", "text": text]) }
    public func key(_ key: String) { act(["op": "key", "key": key]) }
    public func scroll(dy: Double) { act(["op": "scroll", "dy": dy]) }

    private func act(_ body: [String: Any]) {
        if process == nil { start() }
        guard let port else { return }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/act")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        Task { _ = try? await URLSession.shared.data(for: req) }
    }

    private func listen(port: Int) {
        events?.cancel()
        events = Task { [weak self] in
            while !Task.isCancelled {
                var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/frame")!)
                req.timeoutInterval = 8
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run { self?.apply("frame", obj) }
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func apply(_ event: String, _ obj: [String: Any]) {
        switch event {
        case "frame":
            if let b64 = obj["image"] as? String { image = Data(base64Encoded: b64) }
            url = obj["url"] as? String ?? url
            title = obj["title"] as? String ?? title
            status = title.isEmpty ? url : title
        case "nav":
            url = obj["url"] as? String ?? url
        case "log":
            if let text = obj["text"] as? String { log.append(text); if log.count > 50 { log.removeFirst() } }
        case "error":
            status = obj["message"] as? String ?? "Error"
        default: break
        }
    }

    private static func scriptURL() -> URL? {
        let fm = FileManager.default
        var candidates = [URL(fileURLWithPath: #filePath).deletingLastPathComponent()]
        candidates.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("pi_gui/pi-native/scripts/browser-server.mjs"))
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("browser-server.mjs")
        if let bundled { candidates.insert(bundled, at: 0) }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    private static func nodeURL() -> URL? {
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
