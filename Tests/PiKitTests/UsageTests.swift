import XCTest
@testable import PiKit

final class UsageTests: XCTestCase {
    func testPriceTiersAreRelativeQuartiles() {
        let prices = Dictionary(uniqueKeysWithValues: (1...8).map { ("p:m\($0)", ModelPrice(input: Double($0), output: Double($0))) })
        let tiers = PriceTiers(prices: prices, among: Array(prices.keys))
        XCTAssertEqual(tiers.tier("p:m1"), 0)
        XCTAssertEqual(tiers.tier("p:m8"), 3)
        XCTAssertNil(tiers.tier("p:unknown"), "no price → no color, never a guess")
    }

    func testTooFewModelsGiveNoTiers() {
        let prices = ["a:x": ModelPrice(input: 1, output: 1), "a:y": ModelPrice(input: 9, output: 9)]
        XCTAssertNil(PriceTiers(prices: prices, among: Array(prices.keys)).tier("a:x"))
    }

    func testTotalsNeverMixCurrenciesAndFlagInexactWindows() throws {
        let json = try JSONDecoder().decode(JSON.self, from: Data("""
        {"capturedAt": 1, "unsupported": [], "entries": [
          {"providerId":"a","providerName":"A","status":"ready","currency":"USD","spend24h":{"amount":1.5,"window":"24h"},"spend30d":{"amount":10,"window":"30d"}},
          {"providerId":"b","providerName":"B","status":"ready","currency":"USD","spend24h":{"amount":0.5,"window":"today"},"spend30d":{"amount":2,"window":"30d"}},
          {"providerId":"c","providerName":"C","status":"ready","currency":"CNY","spend24h":{"amount":7,"window":"24h"}},
          {"providerId":"d","providerName":"D","status":"query-failed","message":"HTTP 401"}
        ]}
        """.utf8))
        let usage = AccountUsage(json: json)
        let day = usage.total(\.spend24h)
        XCTAssertEqual(day.map(\.currency), ["CNY", "USD"])
        XCTAssertEqual(day.first { $0.currency == "USD" }?.amount, 2.0)
        XCTAssertEqual(day.first { $0.currency == "USD" }?.exact, false, "a calendar-day figure makes the sum approximate")
        XCTAssertEqual(day.first { $0.currency == "CNY" }?.exact, true)
        XCTAssertEqual(usage.total(\.spend30d).first { $0.currency == "USD" }?.amount, 12)
        XCTAssertTrue(usage.entries.last!.failed)
    }

    func testMoneyFormat() {
        XCTAssertEqual(Money.format(2.639289), "$2.64")
        XCTAssertEqual(Money.format(1234.5, currency: "CNY"), "¥1234")
        XCTAssertEqual(Money.format(nil), "—")
    }
}

final class SidebarFoldTests: XCTestCase {
    func testTagFilterNeverChangesFolding() {
        let open: Set<String> = ["a"]
        for filtered in [false, true] {
            XCTAssertTrue(isProjectExpanded(key: "a", expanded: open, tagFilterActive: filtered))
            XCTAssertFalse(isProjectExpanded(key: "b", expanded: open, tagFilterActive: filtered),
                           "a collapsed project must stay collapsed while a tag is selected")
        }
    }
}

@MainActor
final class WorkspaceGitIndexTests: XCTestCase {
    func testIndexIsBuiltOncePerGitChangeAndHandlesLargeSets() throws {
        let ws = WorkspaceModel()
        ws.setCwd("/p")
        XCTAssertTrue(ws.changedDirectoryPaths.isEmpty)
        // Not reachable through the network here, so exercise the pure path-walking the same way refreshGit does.
        var s = GitStatus(); s.isRepo = true; s.root = "/p"
        s.files = (0..<20_000).map { GitChange(path: "a/b\($0 % 50)/c/f\($0).txt", status: "modified", code: " M") }
        let t0 = Date()
        ws.testSetGit(s)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0, "indexing 20k changes must be fast")
        XCTAssertEqual(ws.gitStatusByAbsolutePath.count, 20_000)
        XCTAssertTrue(ws.changedDirectoryPaths.contains("/p/a"))
        XCTAssertTrue(ws.changedDirectoryPaths.contains("/p/a/b7/c"))
        XCTAssertEqual(ws.changedDirectoryPaths.count, 1 + 50 * 2)
    }
}

final class SyncDecisionTests: XCTestCase {
    func testFirstSightRecordsWithoutReloading() {
        XCTAssertEqual(SyncDecision.decide(known: nil, current: "r1"), .recordOnly)
    }
    func testSameRevisionDoesNothing() {
        XCTAssertEqual(SyncDecision.decide(known: "r1", current: "r1"), .none)
    }
    func testChangedRevisionReloads() {
        // A turn written from another window changes the revision; the open thread must pick it up.
        XCTAssertEqual(SyncDecision.decide(known: "r1", current: "r2"), .reload)
    }
}
