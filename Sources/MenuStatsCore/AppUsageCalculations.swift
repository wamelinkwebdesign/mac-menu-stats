import Foundation

/// Each counter and interval uses Mach ticks, so timebase conversion cancels.
struct ProcessUsageSample: Sendable {
    let pid: Int32
    let startTicks: UInt64
    let userTicks: UInt64
    let systemTicks: UInt64
    let sampledTicks: UInt64
    let memoryBytes: UInt64
    let executablePath: String
    let name: String

    func cpuPercent(since previous: ProcessUsageSample, processorCount: Int) -> Double? {
        guard pid == previous.pid,
              startTicks == previous.startTicks,
              executablePath == previous.executablePath,
              sampledTicks > previous.sampledTicks,
              userTicks >= previous.userTicks,
              systemTicks >= previous.systemTicks,
              processorCount > 0 else { return nil }
        // Convert each delta separately to avoid integer overflow while summing.
        let busy = Double(userTicks - previous.userTicks) + Double(systemTicks - previous.systemTicks)
        let capacity = Double(sampledTicks - previous.sampledTicks) * Double(processorCount)
        return min(100, max(0, busy / capacity * 100))
    }
}

struct AppUsageInterval: Sendable {
    private var previous: [Int32: ProcessUsageSample] = [:]
    var previousProcessCount: Int { previous.count }

    mutating func reset() { previous.removeAll(keepingCapacity: false) }

    mutating func record(
        _ processes: [ProcessUsageSample],
        processorCount: Int,
        namesByBundlePath: [String: String],
        sampledAt: Date = Date(),
        unavailableProcessCount: Int = 0
    ) -> AppUsageSnapshot {
        var current: [Int32: ProcessUsageSample] = [:]
        var groups: [String: UsageGroup] = [:]

        for process in processes where current[process.pid] == nil {
            current[process.pid] = process
            let bundlePath = AppUsageGrouping.bundlePath(for: process.executablePath)
            let fallbackName = process.name.isEmpty ? "Process \(process.pid)" : process.name
            let id = AppUsageGrouping.groupID(
                executablePath: process.executablePath, bundlePath: bundlePath,
                pid: process.pid, startTicks: process.startTicks
            )
            let name = bundlePath.map { namesByBundlePath[$0] ?? AppUsageGrouping.bundleName(for: $0) }
                ?? fallbackName
            let cpu = previous[process.pid].flatMap {
                process.cpuPercent(since: $0, processorCount: processorCount)
            }
            var group = groups[id] ?? UsageGroup(id: id, name: name, bundlePath: bundlePath)
            group.processCount += 1
            let (memorySum, overflow) = group.memoryBytes.addingReportingOverflow(process.memoryBytes)
            group.memoryBytes = overflow ? UInt64.max : memorySum
            if let cpu { group.cpuPercent = min(100, (group.cpuPercent ?? 0) + cpu) }
            groups[id] = group
        }

        // Retain only this interval's processes, including new identities.
        previous = current
        let apps = groups.values.map(\.reading).sorted { $0.id < $1.id }
        return AppUsageSnapshot(
            apps: apps,
            sampledAt: sampledAt,
            isWarmingUp: !apps.isEmpty && apps.allSatisfy { $0.cpuPercent == nil },
            unavailableProcessCount: unavailableProcessCount
        )
    }
}

enum AppUsageGrouping {
    static func bundlePath(for executablePath: String) -> String? {
        guard executablePath.hasPrefix("/") else { return nil }
        let components = (executablePath as NSString).pathComponents
        for (index, component) in components.enumerated() {
            // Choose the outer app so nested browser helpers aggregate together.
            if component.lowercased().hasSuffix(".app"),
               index + 2 < components.count, components[index + 1] == "Contents" {
                return NSString.path(withComponents: Array(components.prefix(index + 1)))
            }
        }
        return nil
    }

    static func bundleName(for bundlePath: String) -> String {
        URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
    }

    static func groupID(executablePath: String, bundlePath: String?, pid: Int32, startTicks: UInt64) -> String {
        if let bundlePath { return "app:\(bundlePath)" }
        // Do not guess ownership from a parent shell or launchd. Standalone
        // processes remain visible and identical executable paths aggregate.
        // A name alone cannot establish identity when the path is unavailable.
        return executablePath.isEmpty ? "process-id:\(pid):\(startTicks)" : "process:\(executablePath)"
    }
}

private struct UsageGroup {
    let id: String
    let name: String
    let bundlePath: String?
    var processCount = 0
    var cpuPercent: Double?
    var memoryBytes: UInt64 = 0

    var reading: AppUsageReading {
        AppUsageReading(
            id: id, name: name, bundlePath: bundlePath, processCount: processCount,
            cpuPercent: cpuPercent, memoryBytes: memoryBytes, isApplication: bundlePath != nil
        )
    }
}
