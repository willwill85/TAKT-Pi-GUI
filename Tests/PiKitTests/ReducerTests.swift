import XCTest
@testable import PiKit

final class ReducerTests: XCTestCase {
    func j(_ s: String) -> JSON { JSON.parse(s)! }

    func testTextStreamingDoesNotDuplicateFirstDelta() {
        var st = StreamingState()
        st = StreamReducer.reduce(st, .start)
        // snapshot already contains first chunk (shared partial)
        st = StreamReducer.reduce(st, .snapshot(Message(json: j(#"{"role":"assistant","content":[{"type":"text","text":"Hel"}]}"#))))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"text_start","contentIndex":0}"#)))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"text_delta","contentIndex":0,"delta":"Hel"}"#)))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"text_delta","contentIndex":0,"delta":"lo"}"#)))
        XCTAssertEqual(st.message?.text, "Hello")
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"text_end","contentIndex":0,"content":"Hello!"}"#)))
        XCTAssertEqual(st.message?.text, "Hello!")
    }

    func testToolCallStreaming() {
        var st = StreamReducer.reduce(StreamingState(), .snapshot(Message(json: j(#"{"role":"assistant","content":[]}"#))))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"toolcall_start","contentIndex":0,"id":"c1","toolName":"bash"}"#)))
        st = StreamReducer.reduce(st, .delta(j(##"{"type":"toolcall_delta","contentIndex":0,"delta":"{\"command\":\"ls"}"##)))
        guard case .toolCall(let c)? = st.message?.blocks.first else { return XCTFail() }
        XCTAssertEqual(c.name, "bash")
        XCTAssertEqual(PartialJSON.parse(c.rawInput ?? "")?["command"]?.string, "ls")
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"toolcall_end","contentIndex":0,"toolCall":{"id":"c1","name":"bash","arguments":{"command":"ls -la"}}}"#)))
        guard case .toolCall(let d)? = st.message?.blocks.first else { return XCTFail() }
        XCTAssertEqual(d.input["command"]?.string, "ls -la")
    }

    func testThinkingGap() {
        var st = StreamReducer.reduce(StreamingState(), .snapshot(Message(json: j(#"{"role":"assistant","content":[]}"#))))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"thinking_start","contentIndex":0}"#)))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"thinking_delta","contentIndex":0,"delta":"hm"}"#)))
        st = StreamReducer.reduce(st, .delta(j(#"{"type":"text_start","contentIndex":1}"#)))
        XCTAssertEqual(st.message?.blocks.count, 2)
    }

    func testMessageParsingBothToolCallShapes() {
        let a = Message(json: j(#"{"role":"assistant","content":[{"type":"toolCall","id":"x","name":"read","arguments":{"path":"a"}}]}"#))
        let b = Message(json: j(#"{"role":"assistant","content":[{"type":"toolCall","toolCallId":"x","toolName":"read","input":{"path":"a"}}]}"#))
        XCTAssertEqual(a.toolCalls.first, b.toolCalls.first)
    }

    func testPartialJSON() {
        XCTAssertEqual(PartialJSON.parse(#"{"path":"/a/b","content":"he"#)?["path"]?.string, "/a/b")
        XCTAssertEqual(PartialJSON.parse(#"{"a":1,"b""#)?["a"]?.int, 1)
        XCTAssertNil(PartialJSON.parse(""))
    }

    func testSidebarGrouping() {
        func s(_ id: String, _ key: String, _ mod: Double, rel: String? = nil) -> SessionInfo {
            var o: [String: Any] = ["id": id, "cwd": key, "projectRoot": key, "projectKey": key, "path": id, "created": "2026-01-01T00:00:00.000Z",
                                    "modified": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: mod)), "messageCount": 1, "firstMessage": id]
            if let rel { o["relation"] = ["kind": "subagent", "parentSessionId": rel] }
            return SessionInfo(json: JSON.parse(try! JSONSerialization.data(withJSONObject: o))!)!
        }
        var ui = SessionUiState()
        ui.pinnedAt["a"] = 5
        ui.archivedAt["d"] = 1
        let m = SidebarModel.build(sessions: [s("a", "/p1", 100), s("b", "/p2", 300), s("c", "/p1", 200), s("d", "/p2", 50), s("e", "/p1", 10, rel: "c")], ui: ui, running: [])
        XCTAssertEqual(m.pinnedFamilies.map(\.id), ["a"])
        XCTAssertEqual(m.archived.map(\.id), ["d"])
        XCTAssertEqual(m.projects.map(\.key), ["/p2", "/p1"]) // newest project first when unordered
        XCTAssertEqual(m.projects[1].families.first?.children.map(\.id), ["e"])
    }
}
