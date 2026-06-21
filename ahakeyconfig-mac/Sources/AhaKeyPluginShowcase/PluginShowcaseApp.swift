import AhaKeyPluginKit
import SwiftUI

@main
struct PluginShowcaseApp: App {
    @StateObject private var model = PluginShowcaseModel()

    var body: some Scene {
        WindowGroup("AhaKey Plugin Showcase") {
            PluginShowcaseView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class PluginShowcaseModel: ObservableObject {
    struct PluginSummary: Identifiable {
        let id: String
        let manifestName: String
        let version: String
        let reportedName: String
        let methods: [String]
    }

    @Published var plugins: [PluginSummary] = []
    @Published var statusJSON = "Waiting for plugin status..."
    @Published var activity: [String] = []
    @Published var isBusy = false

    private let manager = PluginManager()
    private var loadedPlugins: [PluginManager.LoadedPlugin] = []
    private var pollingTask: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        Task { await reload() }
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await refreshStatus(recordActivity: false)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        started = false
        Task { await manager.unloadAll() }
    }

    func reload() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        await manager.unloadAll()
        let count = await manager.loadAll()
        loadedPlugins = await manager.allLoaded()
        plugins = loadedPlugins.map { plugin in
            PluginSummary(
                id: plugin.manifest.id,
                manifestName: plugin.manifest.name,
                version: plugin.manifest.version,
                reportedName: plugin.initialize?.name ?? "<not reported>",
                methods: plugin.initialize?.methods ?? []
            )
        }
        appendActivity("Loaded \(count) plugin(s)")

        let failures = await manager.failures
        for failure in failures {
            appendActivity("Failed \(failure.manifestDirectory.lastPathComponent): \(failure.error)")
        }

        await refreshStatus()
    }

    func refreshStatus(recordActivity: Bool = true) async {
        guard let plugin = pluginSupporting("demo/getStatus") else {
            statusJSON = "No loaded plugin exposes demo/getStatus."
            return
        }

        do {
            let result = try await plugin.host.client.call("demo/getStatus", timeout: 4)
            statusJSON = prettyJSON(result)
            if recordActivity {
                appendActivity("Refreshed status through \(plugin.manifest.id)")
            }
        } catch {
            statusJSON = "Status request failed: \(error)"
            if recordActivity {
                appendActivity("Status request failed: \(error)")
            }
        }
    }

    func greet() async {
        guard let plugin = pluginSupporting("demo/greet") else {
            appendActivity("No loaded plugin exposes demo/greet")
            return
        }

        do {
            let result = try await plugin.host.client.call(
                "demo/greet",
                params: .object(["name": .string("AhaKey Studio")]),
                timeout: 4
            )
            appendActivity("demo/greet -> \(compactJSON(result))")
        } catch {
            appendActivity("demo/greet failed: \(error)")
        }
    }

    private func pluginSupporting(_ method: String) -> PluginManager.LoadedPlugin? {
        loadedPlugins.first { $0.initialize?.methods?.contains(method) == true }
    }

    private func appendActivity(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        activity.insert("[\(formatter.string(from: Date()))] \(message)", at: 0)
        activity = Array(activity.prefix(20))
    }

    private func prettyJSON(_ value: JSONValue) -> String {
        encodeJSON(value, prettyPrinted: true)
    }

    private func compactJSON(_ value: JSONValue) -> String {
        encodeJSON(value, prettyPrinted: false)
    }

    private func encodeJSON(_ value: JSONValue, prettyPrinted: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return "<invalid JSON>"
        }
        return text
    }
}

struct PluginShowcaseView: View {
    @EnvironmentObject private var model: PluginShowcaseModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pluginList
                statusPanel
                activityPanel
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 620)
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AhaKey Plugin Showcase")
                    .font(.title.bold())
                Text("Swift host + TypeScript plugin + AhaKey agent bridge")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Reload Plugins") {
                Task { await model.reload() }
            }
            .disabled(model.isBusy)
        }
    }

    private var pluginList: some View {
        GroupBox("Loaded Plugins") {
            VStack(alignment: .leading, spacing: 10) {
                if model.plugins.isEmpty {
                    Text("No plugins loaded. Build the TypeScript example and set AHAKEY_PLUGINS_DIR.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.plugins) { plugin in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.manifestName)
                                .font(.headline)
                            Text("\(plugin.id) v\(plugin.version)")
                                .font(.system(.body, design: .monospaced))
                            Text("Plugin reports: \(plugin.reportedName)")
                                .foregroundColor(.secondary)
                            Text("Methods: \(plugin.methods.joined(separator: ", "))")
                                .font(.system(.caption, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusPanel: some View {
        GroupBox("App-linked Demo") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The TypeScript plugin asks the Swift host for app metadata and the physical lever state. The panel refreshes every 2 seconds.")
                    .foregroundColor(.secondary)
                HStack {
                    Button("Refresh Status") {
                        Task { await model.refreshStatus() }
                    }
                    Button("Call demo/greet") {
                        Task { await model.greet() }
                    }
                }
                Text(model.statusJSON)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
            }
            .padding(8)
        }
    }

    private var activityPanel: some View {
        GroupBox("Activity") {
            VStack(alignment: .leading, spacing: 4) {
                if model.activity.isEmpty {
                    Text("No activity yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(model.activity.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

