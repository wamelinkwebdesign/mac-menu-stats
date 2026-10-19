import SwiftUI
import MenuStatsCore

struct StatsPanel: View {
    @ObservedObject var store: StatsStore
    let openActivityMonitor: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Menu Stats")
                        .font(.headline)
                    Text("This Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
                .accessibilityLabel("Refresh now")
            }

            Divider()

            MetricRow(
                name: "CPU", symbol: "cpu", value: StatsFormat.percent(store.snapshot?.cpuPercent),
                detail: "Across all \(ProcessInfo.processInfo.activeProcessorCount) logical cores",
                progress: store.snapshot?.cpuPercent,
                help: "The percentage of total CPU time spent working since the previous sample."
            )

            MetricRow(
                name: "Memory", symbol: "memorychip", value: StatsFormat.percent(store.snapshot?.memory?.percentUsed),
                detail: memoryDetail,
                progress: store.snapshot?.memory?.percentUsed,
                help: "Estimated memory used by apps, wired memory, and compressed memory. Reclaimable file cache is excluded."
            )

            MetricRow(
                name: "Disk space", symbol: "internaldrive", value: diskValue,
                detail: diskDetail,
                progress: store.snapshot?.disk.map { 100 - $0.percentUsed },
                help: "Free space on the startup data volume. The bar shows the share still free; purgeable space is excluded."
            )

            if let errors = store.snapshot?.errors, !errors.isEmpty {
                Label(errors.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Some readings are unavailable: \(errors.joined(separator: "; "))")
            }

            Divider()

            AppUsageView(store: store)

            Divider()

            HStack {
                Text("Update every")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Update every", selection: $store.refreshInterval) {
                    Text("1 sec").tag(1)
                    Text("2 sec").tag(2)
                    Text("5 sec").tag(5)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 175)
            }

            HStack {
                Button("Activity Monitor", action: openActivityMonitor)
                Spacer()
                Button("Quit Menu Stats", action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .controlSize(.small)
            .font(.system(size: 11))
        }
        .padding(20)
        .frame(width: 440)
    }

    private var memoryDetail: String {
        guard let memory = store.snapshot?.memory else { return waitingText }
        return "\(StatsFormat.memoryBytes(memory.usedBytes)) of \(StatsFormat.memoryBytes(memory.totalBytes)) used"
    }

    private var diskValue: String {
        guard let disk = store.snapshot?.disk else { return "..." }
        return "\(StatsFormat.bytes(disk.freeBytes)) free"
    }

    private var diskDetail: String {
        guard let disk = store.snapshot?.disk else { return waitingText }
        return "Startup disk · \(StatsFormat.bytes(disk.totalBytes)) total"
    }

    private var waitingText: String {
        store.snapshot == nil ? "Taking the first reading..." : "Reading unavailable"
    }
}

private struct MetricRow: View {
    let name: String
    let symbol: String
    let value: String
    let detail: String
    let progress: Double?
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(name, systemImage: symbol)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            if let progress {
                ProgressView(value: min(100, max(0, progress)), total: 100)
                    .accessibilityLabel(name == "Disk space" ? "Disk space free" : "\(name) used")
            } else {
                Text("Waiting for reading...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(help)
        .accessibilityElement(children: .combine)
    }
}
