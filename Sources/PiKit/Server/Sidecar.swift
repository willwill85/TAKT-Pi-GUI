import Foundation
import Darwin
import Observation

public enum ConnectionMode: Equatable, Sendable {
    /// Start the bundled / local pi-web server as a child process.
    case embedded
    /// Connect to an already-running pi-web (LAN, tunnel, other Mac).
    case remote(url: URL, password: String?)
}

public enum SidecarState: Equatable, Sendable {
    case idle
    case starting(String)
    case ready(Endpoint)
    case failed(String)
}

/// Starts and supervises the pi-web Node server this app talks to.
@MainActor
@Observable
public final class SidecarManager {
    public private(set) var state: SidecarState = .idle
    public private(set) var serverDirectory: URL?
    public let logURL: URL

    private var process: Process?
    private var restarts = 0
    private var stopping = false
    private let password: String

    public init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PiNative")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent("sidecar.log")
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        password = Data(bytes).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    // MARK: Locating things

    public struct ServerLocation {
        public var directory: URL
        public var node: URL
        /// `server.js` (standalone) or Next CLI.
        public var useStandalone: Bool
        public var distDir: String?
    }

    public static func locateServer(override: String? = nil) -> ServerLocation? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let o = override ?? ProcessInfo.processInfo.environment["PI_NATIVE_SERVER_DIR"], !o.isEmpty {
            candidates.append(URL(fileURLWithPath: (o as NSString).expandingTildeInPath))
        }
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("server")) }
        candidates.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("pi_gui/pi-web-custom"))
        for dir in candidates {
            // Bundled standalone build.
            let standalone = dir.appendingPathComponent("server.js")
            if fm.fileExists(atPath: standalone.path), let node = locateNode(bundledIn: dir) {
                return ServerLocation(directory: dir, node: node, useStandalone: true, distDir: nil)
            }
            // Source checkout built into .next-native.
            let next = dir.appendingPathComponent("node_modules/next/dist/bin/next")
            let dist = dir.appendingPathComponent(".next-native/BUILD_ID")
            if fm.fileExists(atPath: next.path), fm.fileExists(atPath: dist.path), let node = locateNode(bundledIn: nil) {
                return ServerLocation(directory: dir, node: node, useStandalone: false, distDir: ".next-native")
            }
        }
        return nil
    }

    static func locateNode(bundledIn dir: URL?) -> URL? {
        let fm = FileManager.default
        if let dir {
            let b = dir.appendingPathComponent("node")
            if fm.isExecutableFile(atPath: b.path) { return b }
        }
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        paths += ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.volta/bin", NSHomeDirectory() + "/.nvm/current/bin"]
        for p in paths {
            let c = URL(fileURLWithPath: p).appendingPathComponent("node")
            if fm.isExecutableFile(atPath: c.path) { return c }
        }
        return nil
    }

    static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return got == 0 ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }

    /// PATH of the user's login shell, so `npx`, `git`, `node` resolve like in Terminal.
    static func loginShellPath() -> String {
        let base = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                    NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/.bun/bin", NSHomeDirectory() + "/.cargo/bin"]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "printf %s \"$PATH\""]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let deadline = Date().addingTimeInterval(4)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if p.isRunning { p.terminate(); return base.joined(separator: ":") }
            let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let last = s.split(separator: "\n").last.map(String.init) ?? ""
            if last.contains("/") { return last + ":" + base.joined(separator: ":") }
        } catch {}
        return base.joined(separator: ":")
    }

    // MARK: Lifecycle

    public func start(mode: ConnectionMode, serverOverride: String? = nil) {
        stopping = false
        switch mode {
        case .remote(let url, let pw):
            state = .starting("Connecting…")
            let ep = Endpoint(baseURL: url, password: pw)
            Task { [weak self] in
                if await Self.healthy(ep) { self?.state = .ready(ep) }
                else { self?.state = .failed("Cannot reach \(url.absoluteString)") }
            }
        case .embedded:
            guard let loc = Self.locateServer(override: serverOverride) else {
                state = .failed("Pi Web server not found. Build it with `PI_WEB_DIST_DIR=.next-native npx next build --webpack` in pi-web-custom, or set PI_NATIVE_SERVER_DIR.")
                return
            }
            serverDirectory = loc.directory
            launch(loc)
        }
    }

    private func launch(_ loc: ServerLocation) {
        state = .starting("Starting Pi server…")
        guard let port = Self.freePort() else { state = .failed("No free local port"); return }
        killStaleSidecar()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        let nodeArgs: [String] = loc.useStandalone
            ? [loc.node.path, "server.js"]
            : [loc.node.path, "node_modules/next/dist/bin/next", "start", "-H", "127.0.0.1", "-p", String(port)]
        // Watchdog: if this app dies, take the server down with it.
        let script = "PARENT=$1; shift; \"$@\" & CHILD=$!; (while kill -0 $PARENT 2>/dev/null; do sleep 2; done; kill $CHILD 2>/dev/null) & wait $CHILD"
        proc.arguments = ["-c", script, "sh", String(getpid())] + nodeArgs
        proc.currentDirectoryURL = loc.directory

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.loginShellPath()
        env["PI_WEB_PASSWORD"] = password
        env["PORT"] = String(port)
        env["HOSTNAME"] = "127.0.0.1"
        env["NODE_ENV"] = "production"
        env["NEXT_TELEMETRY_DISABLED"] = "1"
        if let d = loc.distDir { env["PI_WEB_DIST_DIR"] = d }
        proc.environment = env

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: logURL) {
            proc.standardOutput = h; proc.standardError = h
        }
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in self?.processExited(p, loc: loc) }
        }
        do { try proc.run() } catch {
            state = .failed("Could not launch node: \(error.localizedDescription)"); return
        }
        process = proc
        writePid(proc.processIdentifier)

        let ep = Endpoint(baseURL: URL(string: "http://127.0.0.1:\(port)")!, password: password)
        Task { [weak self] in
            for _ in 0..<150 {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !self.stopping, self.process === proc, proc.isRunning else { return }
                if await Self.healthy(ep) {
                    self.restarts = 0
                    self.state = .ready(ep)
                    return
                }
            }
            self?.state = .failed("The Pi server did not become ready in 30s. See \(self?.logURL.path ?? "log").")
        }
    }

    private func processExited(_ p: Process, loc: ServerLocation) {
        guard process === p else { return }
        process = nil
        if stopping { return }
        if restarts < 5 {
            restarts += 1
            state = .starting("Restarting Pi server (\(restarts))…")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(restarts)))
                guard let self, !self.stopping else { return }
                self.launch(loc)
            }
        } else {
            state = .failed("The Pi server keeps crashing. See \(logURL.path).")
        }
    }

    public func stop() {
        stopping = true
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        try? FileManager.default.removeItem(at: pidURL)
    }

    public func restart(mode: ConnectionMode, serverOverride: String? = nil) {
        stop()
        restarts = 0
        start(mode: mode, serverOverride: serverOverride)
    }

    static func healthy(_ ep: Endpoint) async -> Bool {
        var req = URLRequest(url: ep.baseURL.appendingPathComponent("api/home"))
        req.timeoutInterval = 2
        if let a = ep.authorization { req.setValue(a, forHTTPHeaderField: "Authorization") }
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: Stale process cleanup

    private var pidURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PiNative")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sidecar.pid")
    }
    private func writePid(_ pid: Int32) { try? String(pid).write(to: pidURL, atomically: true, encoding: .utf8) }
    private func killStaleSidecar() {
        guard let s = try? String(contentsOf: pidURL, encoding: .utf8), let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        if pid > 1, kill(pid, 0) == 0 { kill(pid, SIGTERM) }
        try? FileManager.default.removeItem(at: pidURL)
    }
}
