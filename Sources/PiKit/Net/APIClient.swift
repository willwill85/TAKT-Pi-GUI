import Foundation

public struct APIError: Error, LocalizedError, Sendable {
    public var message: String
    public var status: Int
    public var code: String?
    public var accepted: Bool?
    public var errorDescription: String? { message }
    /// The server definitively refused the prompt (nothing was started).
    public var isPromptRejected: Bool { code == "prompt_rejected" && accepted == false }
}

/// Where to reach a pi-web compatible server and how to authenticate.
public struct Endpoint: Sendable, Equatable {
    public var baseURL: URL
    public var password: String?
    public init(baseURL: URL, password: String?) { self.baseURL = baseURL; self.password = password }
    public var authorization: String? {
        guard let password, !password.isEmpty else { return nil }
        return "Basic " + Data("pi:\(password)".utf8).base64EncodedString()
    }
}

public final class APIClient: @unchecked Sendable {
    public let endpoint: Endpoint
    private let session: URLSession
    private let streamSession: URLSession

    public init(endpoint: Endpoint) {
        self.endpoint = endpoint
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.httpMaximumConnectionsPerHost = 16
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
        let s = URLSessionConfiguration.ephemeral
        s.timeoutIntervalForRequest = 3600
        s.timeoutIntervalForResource = 24 * 3600
        s.httpMaximumConnectionsPerHost = 16
        s.requestCachePolicy = .reloadIgnoringLocalCacheData
        streamSession = URLSession(configuration: s)
    }

    public func url(_ path: String, query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false)!
        comps.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return comps.url!
    }

    func makeRequest(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil, contentType: String? = "application/json") -> URLRequest {
        var r = URLRequest(url: url(path, query: query))
        r.httpMethod = method
        if let a = endpoint.authorization { r.setValue(a, forHTTPHeaderField: "Authorization") }
        if let body { r.httpBody = body; if let contentType { r.setValue(contentType, forHTTPHeaderField: "Content-Type") } }
        return r
    }

    @discardableResult
    public func raw(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil, contentType: String? = "application/json") async throws -> Data {
        let req = makeRequest(method, path, query: query, body: body, contentType: contentType)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            let j = JSON.parse(data)
            let msg = j?["error"]?.string ?? String(data: data.prefix(300), encoding: .utf8) ?? "HTTP \(status)"
            throw APIError(message: msg, status: status, code: j?["code"]?.string, accepted: j?["accepted"]?.bool)
        }
        return data
    }

    public func get(_ path: String, query: [String: String] = [:]) async throws -> JSON {
        let d = try await raw("GET", path, query: query)
        return JSON.parse(d) ?? .null
    }

    public func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> JSON {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let d = try await raw(method, path, query: query, body: data)
        return JSON.parse(d) ?? .null
    }

    public func post(_ path: String, query: [String: String] = [:], body: [String: Any] = [:]) async throws -> JSON {
        try await send("POST", path, query: query, body: body)
    }

    /// `POST /api/agent/{id}` — returns the `data` payload.
    @discardableResult
    public func command(_ sessionId: String, _ cmd: [String: Any]) async throws -> JSON {
        let r = try await post("/api/agent/\(sessionId)", body: cmd)
        return r["data"] ?? .null
    }

    /// Server-sent events. Each `data:` line is one JSON event.
    public func events(_ path: String, query: [String: String] = [:]) -> AsyncThrowingStream<JSON, Error> {
        var req = makeRequest("GET", path, query: query)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 3600
        let session = streamSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        throw APIError(message: "Event stream failed (HTTP \(status))", status: status)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        var payload = line.dropFirst(5)
                        if payload.first == " " { payload = payload.dropFirst() }
                        if let j = JSON.parse(String(payload)) { continuation.yield(j) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? self
    }
}
