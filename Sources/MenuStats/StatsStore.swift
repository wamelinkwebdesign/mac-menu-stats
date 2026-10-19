import Combine
import AppKit
import Foundation
import MenuStatsCore
import MenuStatsAppControl

private actor SamplingService {
    private var sampler = SystemSampler()

    func sample() -> SystemSnapshot {
        sampler.sample()
    }
}

private actor AppSamplingService {
    private var sampler = AppUsageSampler()

    func sample() -> AppUsageSnapshot { sampler.sample() }
    func reset() { sampler.reset() }
}

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var appUsage: AppUsageSnapshot?
    @Published private(set) var quitFeedback: String?
    @Published private(set) var panelIsVisible = false
    @Published var refreshInterval: Int {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            start()
            if panelIsVisible { startAppPolling() }
        }
    }

    private let service = SamplingService()
    private let appService = AppSamplingService()
    private let quitController = AppQuitController()
    private var pollingTask: Task<Void, Never>?
    private var appPollingTask: Task<Void, Never>?
    private var refreshing = false
    private var refreshingApps = false
    private var appGeneration = 0
    private let appIcons = NSCache<NSString, NSImage>()

    init() {
        let saved = UserDefaults.standard.integer(forKey: "refreshInterval")
        refreshInterval = [1, 2, 5].contains(saved) ? saved : 2
        appIcons.countLimit = 32
    }

    func start() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshSystem()
                do {
                    try await Task.sleep(for: .seconds(self.refreshInterval))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        setPanelVisible(false)
    }

    func refresh() async {
        await refreshSystem()
        await refreshAppUsage()
    }

    private func refreshSystem() async {
        guard !refreshing else { return }
        refreshing = true
        let sample = await service.sample()
        if !Task.isCancelled { snapshot = sample }
        refreshing = false
    }

    func setPanelVisible(_ visible: Bool) {
        guard panelIsVisible != visible else { return }
        panelIsVisible = visible
        appGeneration += 1
        appPollingTask?.cancel()
        appPollingTask = nil
        appUsage = nil
        if visible { startAppPolling() }
    }

    private func startAppPolling() {
        appPollingTask?.cancel()
        appGeneration += 1
        appUsage = nil
        appPollingTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.appService.reset()
            var firstSample = true
            while !Task.isCancelled && self.panelIsVisible {
                await self.refreshAppUsage()
                do {
                    try await Task.sleep(for: .seconds(firstSample ? 1 : self.refreshInterval))
                } catch {
                    return
                }
                firstSample = false
            }
        }
    }

    private func refreshAppUsage() async {
        guard panelIsVisible, !refreshingApps, !Task.isCancelled else { return }
        refreshingApps = true
        let generation = appGeneration
        let sample = await appService.sample()
        if !Task.isCancelled && panelIsVisible && generation == appGeneration {
            appUsage = sample
        }
        refreshingApps = false
    }

    func icon(for app: AppUsageReading) -> NSImage? {
        guard let path = app.bundlePath else { return nil }
        if let cached = appIcons.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        appIcons.setObject(icon, forKey: path as NSString)
        return icon
    }

    func quitTarget(for app: AppUsageReading) -> AppQuitTarget? {
        quitController.prepare(app)
    }

    func requestQuit(_ target: AppQuitTarget) {
        switch quitController.requestQuit(target) {
        case .requested:
            quitFeedback = "Asked \(target.name) to quit. It may ask you to save your work."
        case .partiallyRequested:
            quitFeedback = "Some instances of \(target.name) accepted the quit request. Others did not; try their own Quit command."
        case .noLongerRunning:
            quitFeedback = "The selected instance of \(target.name) is no longer running."
        case .failed:
            quitFeedback = "Could not request that \(target.name) quit. Try its own Quit command."
        }
        Task { await refresh() }
    }
}

enum StatsFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "..." }
        return String(format: "%.0f%%", value)
    }

    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    static func memoryBytes(_ value: UInt64) -> String {
        String(format: "%.1f GiB", Double(value) / 1_073_741_824)
    }

    static func appMemory(_ value: UInt64) -> String {
        if value >= 1_073_741_824 { return memoryBytes(value) }
        return String(format: "%.0f MiB", Double(value) / 1_048_576)
    }

    static func appCPU(_ value: Double?) -> String {
        guard let value else { return "..." }
        return String(format: "%.1f%%", value)
    }

    static func menuTitle(_ snapshot: SystemSnapshot?) -> String {
        let cpu = snapshot?.cpuPercent.map { String(format: "%3.0f%%", $0) } ?? "  ..."
        let memory = snapshot?.memory.map { String(format: "%3.0f%%", $0.percentUsed) } ?? "  ..."
        let disk = snapshot?.disk.map { reading in
            let gb = Double(reading.freeBytes) / 1_000_000_000
            if gb >= 1_000 { return String(format: "%.1f TB", gb / 1_000) }
            return gb < 100 ? String(format: "%.1f GB", gb) : String(format: "%.0f GB", gb)
        } ?? "..."
        return "CPU \(cpu)   RAM \(memory)   \(disk) free"
    }
}
