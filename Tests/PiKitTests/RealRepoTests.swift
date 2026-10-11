import XCTest
@testable import PiKit

/// Runs against a real repository when `PINATIVE_REAL_REPO` is set (skipped otherwise).
@MainActor
final class RealRepoTests: XCTestCase {
    func testOpeningLargeRepoStaysFast() throws {
        guard let repo = ProcessInfo.processInfo.environment["PINATIVE_REAL_REPO"] else { throw XCTSkip("no repo given") }
        let out = Process(); out.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        out.arguments = ["-C", repo, "status", "--porcelain", "-uall"]
        let pipe = Pipe(); out.standardOutput = pipe; try out.run(); out.waitUntilExit()
        let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
        var s = GitStatus(); s.isRepo = true; s.root = repo
        s.files = lines.map { GitChange(path: String($0.dropFirst(3)), status: "modified", code: String($0.prefix(2))) }
        let ws = WorkspaceModel(); ws.setCwd(repo)
        let t0 = Date(); ws.testSetGit(s); let dt = Date().timeIntervalSince(t0)
        print("REAL files=\(s.files.count) dirs=\(ws.changedDirectoryPaths.count) index_ms=\(Int(dt * 1000))")
        XCTAssertLessThan(dt, 0.5)
    }
}
