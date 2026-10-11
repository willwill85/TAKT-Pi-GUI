import Foundation

/// One spend figure as reported by a provider. `window` says what period it really covers.
public struct SpendFigure: Hashable, Sendable {
    public enum Window: String, Sendable { case h24 = "24h", today, d30 = "30d", month, total }
    public var amount: Double
    public var window: Window
    /// Short label that never passes a calendar-day figure off as a rolling 24 hours.
    public func label(wanted: Window) -> String {
        switch window {
        case .h24: return "24h"
        case .d30: return "30d"
        case .today: return "today (UTC)"
        case .month: return "this month"
        case .total: return "all time"
        }
    }
}

public struct AccountUsageEntry: Identifiable, Hashable, Sendable {
    public var id: String { providerId }
    public var providerId: String
    public var providerName: String
    public var failed: Bool
    public var currency: String
    public var balance: Double?
    public var spend24h: SpendFigure?
    public var spend30d: SpendFigure?
    public var quotas: [Quota]
    public var message: String?

    public struct Quota: Hashable, Sendable { public var label: String; public var usedPercent: Double }
}

public struct AccountUsage: Sendable {
    public var capturedAt: Date
    public var entries: [AccountUsageEntry]
    public var unsupported: [String]
    public init(capturedAt: Date = .distantPast, entries: [AccountUsageEntry] = [], unsupported: [String] = []) {
        self.capturedAt = capturedAt; self.entries = entries; self.unsupported = unsupported
    }

    public struct Total: Hashable, Sendable { public var currency: String; public var amount: Double; public var exact: Bool }

    /// Sums per currency; different currencies are never added together.
    public func total(_ key: KeyPath<AccountUsageEntry, SpendFigure?>) -> [Total] {
        let exactWindow: SpendFigure.Window = key == \AccountUsageEntry.spend24h ? .h24 : .d30
        var sums: [String: Total] = [:]
        for e in entries where !e.failed {
            guard let f = e[keyPath: key] else { continue }
            var t = sums[e.currency] ?? Total(currency: e.currency, amount: 0, exact: true)
            t.amount += f.amount; t.exact = t.exact && f.window == exactWindow
            sums[e.currency] = t
        }
        return sums.values.sorted { $0.currency < $1.currency }
    }

    public init(json d: JSON) {
        capturedAt = Date(timeIntervalSince1970: (d["capturedAt"]?.double ?? 0) / 1000)
        unsupported = (d["unsupported"]?.array ?? []).compactMap(\.string)
        func figure(_ j: JSON?) -> SpendFigure? {
            guard let j, let a = j["amount"]?.double, let w = j["window"]?.string else { return nil }
            let window: SpendFigure.Window = w == "24h" ? .h24 : w == "30d" ? .d30 : (SpendFigure.Window(rawValue: w) ?? .total)
            return SpendFigure(amount: a, window: window)
        }
        entries = (d["entries"]?.array ?? []).compactMap { j in
            guard let id = j["providerId"]?.string else { return nil }
            return AccountUsageEntry(
                providerId: id, providerName: j["providerName"]?.string ?? id,
                failed: j["status"]?.string != "ready", currency: j["currency"]?.string ?? "USD",
                balance: j["balance"]?.double, spend24h: figure(j["spend24h"]), spend30d: figure(j["spend30d"]),
                quotas: (j["quotas"]?.array ?? []).compactMap { q in
                    guard let l = q["label"]?.string, let p = q["usedPercent"]?.double else { return nil }
                    return .init(label: l, usedPercent: p)
                },
                message: j["message"]?.string)
        }
    }
}

public enum Money {
    public static func format(_ amount: Double?, currency: String = "USD") -> String {
        guard let amount else { return "—" }
        let symbol = ["USD": "$", "CNY": "¥", "EUR": "€"][currency] ?? currency + " "
        return symbol + String(format: abs(amount) >= 100 ? "%.0f" : "%.2f", amount)
    }
}

/// USD per million tokens, from the provider catalog or the gateway's own model listing.
public struct ModelPrice: Hashable, Sendable {
    public var input: Double
    public var output: Double
    /// A single comparable figure: a typical turn reads far more than it writes, so weight input 3 : output 1.
    public var blended: Double { (input * 3 + output) / 4 }
}

/// Price tiers are relative to the models the user can actually pick, so the colors stay meaningful
/// whatever providers are configured. Tier 0 = cheapest quarter … 3 = most expensive quarter.
public struct PriceTiers: Sendable {
    public private(set) var prices: [String: ModelPrice]
    private var cuts: [Double] = []
    public init(prices: [String: ModelPrice] = [:], among keys: [String] = []) {
        self.prices = prices
        let values = keys.compactMap { prices[$0]?.blended }.sorted()
        if values.count >= 4 {
            cuts = [0.25, 0.5, 0.75].map { values[min(values.count - 1, Int(Double(values.count) * $0))] }
        }
    }
    public func tier(_ key: String) -> Int? {
        guard let p = prices[key] else { return nil }
        guard !cuts.isEmpty else { return nil }
        return cuts.filter { p.blended >= $0 }.count
    }
    public func price(_ key: String) -> ModelPrice? { prices[key] }
}
