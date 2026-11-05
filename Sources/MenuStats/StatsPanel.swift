import SwiftUI
import MenuStatsCore

struct StatsPanel: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var updates: UpdateController
    let checkForUpdates: () -> Void
    let openActivityMonitor: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Menu Stats")
                        .font(.headline)
                    Text("This Mac · \(updates.version)")
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
                Menu {
                    Button("Check for Updates…", action: checkForUpdates)
                        .disabled(!updates.isAvailable || !updates.canCheckForUpdates)
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .disabled(!updates.isAvailable)
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Update settings")
                .accessibilityLabel("Update settings")
            }

            if let version = updates.availableUpdateVersion {
                Button(action: checkForUpdates) {
                    Label("Menu Stats \(version) is available", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.small)
                .disabled(!updates.canCheckForUpdates)
                .help("Review and install the update")
            }

            if let error = updates.initializationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            MetricRow(
                name: "CPU", symbol: "cpu", value: StatsFormat.percent(store.snapshot?.cpuPercent),
                detail: "Across all \(ProcessInfo.processInfo.activeProcessorCount) logical cores",
                progress: store.snapshot?.cpuPercent,
                trend: store.cpuHistory.values,
                help: "The percentage of total CPU time spent working since the previous sample. \(historyHelp)"
            )

            MetricRow(
                name: "Memory", symbol: "memorychip", value: StatsFormat.percent(store.snapshot?.memory?.percentUsed),
                detail: memoryDetail,
                secondaryDetail: memoryPressureDetail,
                progress: store.snapshot?.memory?.percentUsed,
                progressTint: pressureTint,
                trend: store.memoryHistory.values,
                help: "Estimated memory used by apps, wired memory, and compressed memory. Reclaimable file cache is excluded. Memory pressure is the level macOS reports, also shown in Activity Monitor. Swap is space on disk used when memory runs short. \(historyHelp)"
            )

            MetricRow(
                name: "Disk space", symbol: "internaldrive", value: diskValue,
                detail: diskDetail,
                progress: store.snapshot?.disk.map { 100 - $0.percentUsed },
                help: "Free space on the startup data volume. The bar shows the share still free; purgeable space is excluded."
            )

            MetricRow(
                name: "Network", symbol: "network", value: networkValue,
                detail: networkDetail,
                showsProgress: false,
                help: "Data received and sent per second since the previous sample, across Wi-Fi and Ethernet interfaces. VPN tunnels and bridges are excluded so traffic is not counted twice."
            )

            if case .installed(let battery) = store.snapshot?.battery {
                MetricRow(
                    name: "Battery", symbol: batterySymbol(battery), value: StatsFormat.percent(battery.chargePercent),
                    detail: batteryDetail(battery),
                    secondaryDetail: batteryHealthDetail(battery),
                    progress: battery.chargePercent,
                    help: "Charge level and power state from macOS. Health compares the current full-charge capacity with the design capacity and is an estimate. Temperature is the battery sensor reading."
                )
            }

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

    private var memoryPressureDetail: String {
        let pressure = store.snapshot?.memoryPressure.map { "Pressure \(StatsFormat.pressure($0))" }
            ?? "Pressure unavailable"
        guard let swap = store.snapshot?.swap else { return "\(pressure) · Swap unavailable" }
        if swap.totalBytes == 0 { return "\(pressure) · No swap in use" }
        return "\(pressure) · Swap \(StatsFormat.memoryBytes(swap.usedBytes)) of \(StatsFormat.memoryBytes(swap.totalBytes))"
    }

    private var pressureTint: Color? {
        switch store.snapshot?.memoryPressure {
        case .warning: return .yellow
        case .critical: return .red
        case .normal, nil: return nil
        }
    }

    private var historyHelp: String {
        "The graph shows the last \(StatsFormat.historySpan(samples: StatsStore.historyLength, interval: store.refreshInterval))."
    }

    private var networkValue: String {
        guard let network = store.snapshot?.network else { return "..." }
        return "↓ \(StatsFormat.rate(network.receivedBytesPerSecond))   ↑ \(StatsFormat.rate(network.sentBytesPerSecond))"
    }

    private var networkDetail: String {
        guard let network = store.snapshot?.network else {
            let failed = store.snapshot?.errors.contains { $0.hasPrefix("Network:") } == true
            return failed ? "Reading unavailable" : "Measuring since the previous reading..."
        }
        return network.interfaceCount == 0 ? "No Wi-Fi or Ethernet interfaces found" : "Received and sent over Wi-Fi and Ethernet"
    }

    private func batterySymbol(_ battery: BatteryReading) -> String {
        if battery.isCharging == true { return "battery.100.bolt" }
        guard let charge = battery.chargePercent else { return "battery.100" }
        switch charge {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryDetail(_ battery: BatteryReading) -> String {
        switch (battery.isCharging, battery.isOnPower) {
        case (true, _): return "Charging"
        case (_, true): return "On power adapter, not charging"
        case (_, false): return "On battery"
        default: return "Power state unavailable"
        }
    }

    private func batteryHealthDetail(_ battery: BatteryReading) -> String {
        var parts: [String] = []
        if let condition = battery.condition { parts.append(condition) }
        parts.append(battery.healthPercent.map { String(format: "Health %.0f%%", $0) } ?? "Health unavailable")
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        if let temperature = battery.temperatureCelsius {
            parts.append(String(format: "%.1f °C", temperature))
        }
        return parts.joined(separator: " · ")
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
    var secondaryDetail: String? = nil
    var progress: Double? = nil
    var progressTint: Color? = nil
    var trend: [Double?]? = nil
    var showsProgress = true
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(name, systemImage: symbol)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let trend {
                    Sparkline(values: trend, capacity: StatsStore.historyLength)
                        .frame(width: 84, height: 16)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            if showsProgress {
                if let progress {
                    ProgressView(value: min(100, max(0, progress)), total: 100)
                        .tint(progressTint)
                        .accessibilityLabel(name == "Disk space" ? "Disk space free" : "\(name) used")
                } else {
                    Text("Waiting for reading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let secondaryDetail {
                Text(secondaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

/// A 0 to 100 percent line graph. Missing samples leave gaps.
private struct Sparkline: View {
    let values: [Double?]
    let capacity: Int

    var body: some View {
        GeometryReader { geometry in
            let path = line(in: geometry.size)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.08))
                path.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func line(in size: CGSize) -> Path {
        var path = Path()
        guard capacity > 1 else { return path }
        let step = size.width / CGFloat(capacity - 1)
        // Newest sample sits at the right edge.
        let start = capacity - values.count
        var drawing = false
        for (offset, value) in values.enumerated() {
            guard let value else {
                drawing = false
                continue
            }
            let point = CGPoint(
                x: CGFloat(start + offset) * step,
                y: size.height - CGFloat(min(100, max(0, value)) / 100) * (size.height - 2) - 1
            )
            if drawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                drawing = true
            }
        }
        return path
    }
}
