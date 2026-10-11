import Foundation

/// Loosely-typed JSON value. pi's wire format carries many open-ended shapes
/// (tool inputs, details, extension payloads), so most decoding goes through this.
public enum JSON: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSON].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public static func parse(_ data: Data) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: data)
    }

    public static func parse(_ string: String) -> JSON? {
        parse(Data(string.utf8))
    }

    public subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSON? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var string: String? { if case .string(let s) = self { return s } else { return nil } }
    public var double: Double? { if case .number(let n) = self { return n } else { return nil } }
    public var int: Int? { double.flatMap { $0.isFinite ? Int($0) : nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var array: [JSON]? { if case .array(let a) = self { return a } else { return nil } }
    public var object: [String: JSON]? { if case .object(let o) = self { return o } else { return nil } }
    public var isNull: Bool { if case .null = self { return true } else { return false } }

    /// Foundation-compatible object graph, for `JSONSerialization`.
    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    public func serialized(pretty: Bool = false) -> String {
        let opts: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        guard JSONSerialization.isValidJSONObject(any) || {
            switch self { case .object, .array: return false; default: return true }
        }() else { return "" }
        switch self {
        case .string(let s): return s
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        default:
            guard let data = try? JSONSerialization.data(withJSONObject: any, options: opts) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
