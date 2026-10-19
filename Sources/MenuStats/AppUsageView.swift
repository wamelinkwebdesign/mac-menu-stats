import SwiftUI
import MenuStatsCore
import MenuStatsAppControl

struct AppUsageView: View {
    @ObservedObject var store: StatsStore
    @State private var sortBy: SortOrder = .cpu
    @State private var pendingQuit: AppQuitTarget?

    private enum SortOrder: String, CaseIterable {
        case cpu = "CPU"
        case memory = "Memory"
    }

    private var rankedApps: [AppUsageReading] {
        guard let usage = store.appUsage else { return [] }
        return sortBy == .cpu ? usage.topCPUApps() : usage.topMemoryApps()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top apps")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Rank apps by", selection: $sortBy) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                .disabled(pendingQuit != nil)
                .help("Show the five apps using the most CPU or memory")
            }

            HStack {
                Text("App")
                Spacer()
                Text("CPU").frame(width: 56, alignment: .trailing)
                Text("Memory").frame(width: 74, alignment: .trailing)
                Color.clear.frame(width: 42, height: 1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            VStack(spacing: 7) {
                if let target = pendingQuit {
                    quitConfirmation(target)
                } else if let error = store.appUsage?.error {
                    message(error, symbol: "exclamationmark.triangle")
                } else if store.appUsage == nil {
                    message("Reading running apps...", symbol: "app.dashed")
                } else if sortBy == .cpu && store.appUsage?.isWarmingUp == true {
                    message("Measuring CPU usage...", symbol: "cpu")
                } else if rankedApps.isEmpty {
                    message("No app readings are available.", symbol: "app.dashed")
                } else {
                    ForEach(rankedApps, id: \.id) { app in
                        appRow(app)
                    }
                }
            }
            .frame(height: 133, alignment: .top)

            Text(coverageNote)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help("CPU is a percentage of total capacity across all cores. App helpers are grouped when their owning app can be identified. Memory is the physical footprint reported by macOS, including compressed memory.")

            if let feedback = store.quitFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: store.panelIsVisible) { visible in
            if !visible { pendingQuit = nil }
        }
    }

    private func quitConfirmation(_ target: AppQuitTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quit \(target.name)?")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            Text(target.instanceCount > 1
                ? "All \(target.instanceCount) selected instances will be asked to quit. The app may ask you to save your work."
                : "The app will be asked to quit normally and may ask you to save your work.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { pendingQuit = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel quit")
                Button("Quit", role: .destructive) {
                    pendingQuit = nil
                    store.requestQuit(target)
                }
                .accessibilityLabel("Confirm quit \(target.name)")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 133, alignment: .center)
    }

    private var coverageNote: String {
        let partial = (store.appUsage?.unavailableProcessCount ?? 0) > 0
        return partial
            ? "CPU across all cores. Some protected or exited processes are unavailable."
            : "CPU across all cores. Includes app helpers and background processes."
    }

    private func appRow(_ app: AppUsageReading) -> some View {
        let target = store.quitTarget(for: app)
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if let icon = store.icon(for: app) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: app.isApplication ? "app" : "gearshape")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(StatsFormat.appCPU(app.cpuPercent))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
                Text(StatsFormat.appMemory(app.memoryBytes))
                    .monospacedDigit()
                    .frame(width: 74, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(app.name), CPU \(StatsFormat.appCPU(app.cpuPercent)), memory \(StatsFormat.appMemory(app.memoryBytes)), \(app.processCount) processes")
            .help("\(app.name) · \(app.processCount) \(app.processCount == 1 ? "process" : "processes")")

            Button("Quit") { pendingQuit = target }
                .controlSize(.mini)
                .fixedSize()
                .frame(width: 42)
                .disabled(target == nil)
                .help(target == nil
                    ? "Only running desktop apps can be quit here. Use the bottom Quit button to close Menu Stats."
                    : "Ask \(app.name) to quit normally")
                .accessibilityLabel("Quit \(app.name)")
        }
        .font(.system(size: 12))
        .frame(height: 21)
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
