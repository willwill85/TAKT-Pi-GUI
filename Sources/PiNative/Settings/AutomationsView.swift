import SwiftUI
import PiKit

@MainActor @Observable
final class AutomationsModel {
    var jobs: [CronJob] = []
    var daemons: [Daemon] = []
    var error: String?
    var logs: String?
    var busy = false
    var loaded = false

    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    func load(_ client: APIClient?) async {
        guard let client else { return }
        do {
            let d = try await client.get("/api/cron")
            jobs = (d["jobs"]?.array ?? []).compactMap { j in
                guard let id = j["id"]?.string else { return nil }
                return CronJob(id: id, daemonId: j["daemon_id"]?.string ?? "", schedule: j["schedule"]?.string ?? "", prompt: j["prompt"]?.string ?? "",
                               enabled: j["enabled"]?.bool ?? true, tz: j["tz"]?.string ?? "",
                               lastRun: j["last_run"]?.string.flatMap { Self.iso.date(from: $0) }, lastStatus: j["last_status"]?.string,
                               nextRun: j["next_run"]?.string.flatMap { Self.iso.date(from: $0) })
            }
            daemons = (d["daemons"]?.array ?? []).compactMap { j in
                guard let id = j["id"]?.string else { return nil }
                return Daemon(id: id, cwd: j["cwd"]?.string ?? "", name: j["name"]?.string ?? "", state: j["state"]?.string ?? "")
            }
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    func act(_ client: APIClient?, _ body: [String: Any]) async -> Bool {
        guard let client else { return false }
        busy = true; defer { busy = false }
        do {
            let d = try await client.post("/api/cron", body: body)
            if body["action"] as? String == "log" { logs = (d["entries"] ?? .null).serialized(pretty: true) }
            await load(client); return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct AutomationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var m = AutomationsModel()
    @State private var showForm = false
    @State private var daemonId = ""
    @State private var schedule = "0 6 * * *"
    @State private var tz = TimeZone.current.identifier
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !ui.sidebarVisible {
                    Button { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible = true } } label: { Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary) }
                        .buttonStyle(HoverButtonStyle()).padding(.leading, 74)
                }
                Spacer()
            }.frame(height: 44).background(WindowDragArea())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automations").font(.system(size: 24, weight: .semibold))
                            Text("Wake a Pi daemon on a schedule to run a prompt in a project folder. Powered by the remote-pi supervisor.").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showForm.toggle() } label: { Label("New automation", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.regular)
                    }
                    if let e = m.error { BannerPill(icon: "exclamationmark.triangle.fill", text: e, tint: Theme.warning) }
                    if showForm { form }
                    if m.jobs.isEmpty && m.loaded && m.error == nil {
                        EmptyState(icon: "clock.arrow.circlepath", title: "No automations yet", text: "Create one to run a prompt every morning, hourly, or on any cron schedule.").frame(height: 220)
                    }
                    ForEach(m.jobs) { j in jobCard(j) }
                    if let logs = m.logs {
                        VStack(alignment: .leading) {
                            HStack { Text("Log").font(.system(size: 13, weight: .semibold)); Spacer(); Button("Close") { m.logs = nil }.controlSize(.small) }
                            OutputBlock(text: logs, maxHeight: 280)
                        }.padding(14).cardSurface().hairline()
                    }
                }.frame(maxWidth: 760).padding(.horizontal, 30).padding(.bottom, 40).frame(maxWidth: .infinity)
            }
        }
        .task { await m.load(model.client); if daemonId.isEmpty { daemonId = m.daemons.first?.id ?? "" } }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Run in", selection: $daemonId) { ForEach(m.daemons) { d in Text("\(d.name.isEmpty ? SidebarModel.folderName(d.cwd) : d.name) · \(d.state)").tag(d.id) } }
            HStack {
                TextField("Cron expression", text: $schedule).textFieldStyle(.roundedBorder).font(Theme.mono(12.5))
                TextField("Time zone", text: $tz).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            Text(describeCron(schedule)).font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 110).scrollContentBackground(.hidden).padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.background))
                .overlay(alignment: .topLeading) { if prompt.isEmpty { Text("What should Pi do?").foregroundStyle(.tertiary).padding(14).allowsHitTesting(false) } }
            HStack {
                Spacer()
                Button("Cancel") { showForm = false }
                Button("Create") { Task { if await m.act(model.client, ["action": "add", "daemon_id": daemonId, "schedule": schedule, "tz": tz, "prompt": prompt]) { showForm = false; prompt = "" } } }
                    .buttonStyle(.borderedProminent).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || daemonId.isEmpty || m.busy)
            }
        }.padding(16).cardSurface().hairline()
    }

    private func jobCard(_ j: CronJob) -> some View {
        let d = m.daemons.first { $0.id == j.daemonId }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(j.enabled ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                Text(d.map { $0.name.isEmpty ? SidebarModel.folderName($0.cwd) : $0.name } ?? j.daemonId).font(.system(size: 14, weight: .semibold))
                Text(j.schedule).font(Theme.mono(12)).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                Text(describeCron(j.schedule)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(get: { j.enabled }, set: { v in Task { await m.act(model.client, ["action": "enable", "job_id": j.id, "enabled": v]) } })).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Text(j.prompt).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85)).lineLimit(3).textSelection(.enabled)
            HStack(spacing: 14) {
                if let n = j.nextRun, j.enabled { Label("Next " + n.formatted(date: .abbreviated, time: .shortened), systemImage: "clock") }
                if let l = j.lastRun { Label("Last " + l.formatted(date: .abbreviated, time: .shortened) + (j.lastStatus.map { " · \($0)" } ?? ""), systemImage: "checkmark.circle") }
                if let d { Label(shortPath(d.cwd), systemImage: "folder").lineLimit(1).truncationMode(.head) }
                Spacer()
                Button("Run now") { Task { await m.act(model.client, ["action": "run", "job_id": j.id]) } }
                Button("Log") { Task { await m.act(model.client, ["action": "log", "job_id": j.id]) } }
                Button("Delete", role: .destructive) { Task { await m.act(model.client, ["action": "remove", "job_id": j.id]) } }
            }.font(.system(size: 12)).foregroundStyle(.secondary).controlSize(.small)
        }.padding(16).cardSurface().hairline().opacity(j.enabled ? 1 : 0.65)
    }

    private func describeCron(_ s: String) -> String {
        let p = s.split(separator: " ").map(String.init)
        guard p.count == 5 else { return "5 fields: minute hour day month weekday" }
        if p[0].allSatisfy(\.isNumber), p[1].allSatisfy(\.isNumber), p[2] == "*", p[3] == "*", p[4] == "*" { return String(format: "Every day at %02d:%02d", Int(p[1])!, Int(p[0])!) }
        if p[0].hasPrefix("*/"), p[1...].allSatisfy({ $0 == "*" }) { return "Every \(p[0].dropFirst(2)) minutes" }
        if p[0].allSatisfy(\.isNumber), p[1] == "*", p[2...].allSatisfy({ $0 == "*" }) { return "Every hour at :\(p[0])" }
        if p[0].allSatisfy(\.isNumber), p[1].allSatisfy(\.isNumber), p[4] != "*" { return String(format: "At %02d:%02d on weekday %@", Int(p[1])!, Int(p[0])!, p[4]) }
        return "Custom schedule"
    }
}
