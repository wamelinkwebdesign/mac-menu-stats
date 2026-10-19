import Combine
import Foundation
import MenuStatsCore

private actor SamplingService {
    private var sampler = SystemSampler()

    func sample() -> SystemSnapshot {
        sampler.sample()
    }
}

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published var refreshInterval: Int {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            start()
        }
    }

    private let service = SamplingService()
    private var pollingTask: Task<Void, Never>?
    private var refreshing = false

    init() {
        let saved = UserDefaults.standard.integer(forKey: "refreshInterval")
        refreshInterval = [1, 2, 5].contains(saved) ? saved : 2
    }

    func start() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
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
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let sample = await service.sample()
        if !Task.isCancelled { snapshot = sample }
        refreshing = false
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
