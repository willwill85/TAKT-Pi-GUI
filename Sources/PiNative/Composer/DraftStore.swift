import Foundation

/// Per-thread composer drafts, kept across thread switches and launches.
@MainActor
final class DraftStore {
    static let shared = DraftStore()
    private var drafts: [String: String]
    private let key = "composerDrafts"
    init() { drafts = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
    func get(_ k: String) -> String { drafts[k] ?? "" }
    func set(_ k: String, _ v: String) {
        if v.isEmpty { drafts[k] = nil } else { drafts[k] = v }
        UserDefaults.standard.set(drafts, forKey: key)
    }
}

/// History of sent prompts for ↑ recall.
@MainActor
final class PromptHistory {
    static let shared = PromptHistory()
    private(set) var items: [String]
    init() { items = UserDefaults.standard.stringArray(forKey: "promptHistory") ?? [] }
    func add(_ s: String) {
        items.removeAll { $0 == s }; items.append(s)
        if items.count > 100 { items.removeFirst(items.count - 100) }
        UserDefaults.standard.set(items, forKey: "promptHistory")
    }
}
