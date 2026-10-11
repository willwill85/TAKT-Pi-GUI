import SwiftUI
import PiKit

/// Model price as a small colored dot + "$in / $out per 1M tokens" text.
struct PriceDot: View {
    let key: String
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.priceTiers.tier(key) {
            Circle().fill(Theme.priceColor(t)).frame(width: 7, height: 7)
        }
    }
}

func priceText(_ p: ModelPrice) -> String {
    func f(_ v: Double) -> String { v >= 10 ? String(format: "%.0f", v) : v >= 1 ? String(format: "%.1f", v) : String(format: "%.2f", v) }
    return "$\(f(p.input)) in · $\(f(p.output)) out / 1M tokens"
}

struct UsageTotalCard: View {
    let title: String
    let totals: [AccountUsage.Total]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
            if totals.isEmpty { Text("—").font(.system(size: 20, weight: .semibold)).foregroundStyle(.tertiary) }
            ForEach(totals, id: \.currency) { t in
                HStack(spacing: 4) {
                    Text(Money.format(t.amount, currency: t.currency)).font(.system(size: 20, weight: .semibold, design: .monospaced))
                    if !t.exact { Text("≈").foregroundStyle(.tertiary).help("Some providers report a window that is not exactly 24h / 30d") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.surface))
    }
}

struct UsageEntryRow: View {
    let e: AccountUsageEntry
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.providerName).font(.system(size: compact ? 12.5 : 13.5, weight: .semibold))
                Spacer()
                if !e.failed, let b = e.balance {
                    Text(Money.format(b, currency: e.currency)).font(.system(size: compact ? 13 : 15, weight: .medium, design: .monospaced))
                    Text("balance").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            if e.failed {
                Text("Query failed: \(e.message ?? "unknown error")").font(.system(size: 11.5)).foregroundStyle(Theme.removed)
            } else {
                HStack(spacing: 16) {
                    Text("\(e.spend24h?.label(wanted: .h24) ?? "24h"): \(Money.format(e.spend24h?.amount, currency: e.currency))")
                    Text("\(e.spend30d?.label(wanted: .d30) ?? "30d"): \(Money.format(e.spend30d?.amount, currency: e.currency))")
                }.font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                ForEach(e.quotas, id: \.label) { q in
                    HStack(spacing: 8) {
                        Text(q.label).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(q.usedPercent > 85 ? Theme.removed : Color.primary.opacity(0.55)).frame(width: g.size.width * min(1, q.usedPercent / 100))
                            }
                        }.frame(height: 5)
                        Text("\(Int(q.usedPercent.rounded()))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Settings › Usage.
struct UsageSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let u = model.accountUsage
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Usage & Spend").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(model.accountUsageLoading ? "Refreshing…" : "Refresh") { Task { await model.refreshAccountUsage(force: true) } }
                    .disabled(model.accountUsageLoading)
            }
            Text("Balances and spend come from each provider's own API; nothing is estimated. \u{201C}today\u{201D} is the provider's UTC calendar day, not a rolling 24 hours.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                UsageTotalCard(title: "Last 24 hours", totals: u.total(\.spend24h))
                UsageTotalCard(title: "Last 30 days", totals: u.total(\.spend30d))
            }
            if u.entries.isEmpty && !model.accountUsageLoading { Text("No provider with a usage API is connected.").foregroundStyle(.secondary) }
            VStack(spacing: 0) {
                ForEach(u.entries) { e in
                    UsageEntryRow(e: e).padding(.horizontal, 14).padding(.vertical, 10)
                    if e.id != u.entries.last?.id { Divider().opacity(0.7) }
                }
            }.background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.surface))
            if !u.unsupported.isEmpty {
                Text("Connected, but no balance API is known for: \(u.unsupported.joined(separator: ", "))")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .task { await model.refreshAccountUsage() }
    }
}

/// Compact balance / spend popover opened from the sidebar footer.
struct UsagePopover: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let u = model.accountUsage
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                UsageTotalCard(title: "24 hours", totals: u.total(\.spend24h))
                UsageTotalCard(title: "30 days", totals: u.total(\.spend30d))
            }
            ForEach(u.entries) { e in
                Divider().opacity(0.6)
                UsageEntryRow(e: e, compact: true)
            }
            if u.entries.isEmpty { Text(model.accountUsageLoading ? "Loading…" : "No usage data").foregroundStyle(.secondary).font(.system(size: 12)) }
            HStack {
                Button("Refresh") { Task { await model.refreshAccountUsage(force: true) } }.controlSize(.small).disabled(model.accountUsageLoading)
                Spacer()
                SettingsLink { Text("Details…") }.controlSize(.small)
            }
        }
        .padding(14).frame(width: 340)
        .task { await model.refreshAccountUsage() }
    }
}
