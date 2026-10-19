import CProcessStats
import Darwin
import Foundation

/// Call on a background executor only while the panel is visible. Reset when
/// reopening so the first CPU interval does not average across the closed panel.
public struct AppUsageSampler: Sendable {
    private var interval = AppUsageInterval()
    private var namesByBundlePath: [String: String] = [:]

    public init() {}

    public mutating func reset() {
        interval.reset()
        namesByBundlePath.removeAll(keepingCapacity: false)
    }

    public mutating func sample() -> AppUsageSnapshot {
        let pids: [Int32]
        do {
            pids = try processIDs()
        } catch {
            reset()
            return AppUsageSnapshot(isWarmingUp: false, error: error.localizedDescription)
        }

        var processes: [ProcessUsageSample] = []
        var unavailable = 0
        var activeBundlePaths = Set<String>()
        for pid in pids where pid > 0 {
            var native = MSProcessReading()
            guard ms_read_process(pid, &native) == 0 else {
                unavailable += 1
                continue
            }
            let path = boundedString(&native.executable_path)
            let rawName = boundedString(&native.name)
            let name = rawName.isEmpty && !path.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : rawName
            let process = ProcessUsageSample(
                pid: pid, startTicks: native.start_ticks, userTicks: native.cpu_user_ticks,
                systemTicks: native.cpu_system_ticks, sampledTicks: native.sampled_ticks,
                memoryBytes: native.footprint_bytes, executablePath: path, name: name
            )
            processes.append(process)
            if let bundlePath = AppUsageGrouping.bundlePath(for: path) {
                activeBundlePaths.insert(bundlePath)
                if namesByBundlePath[bundlePath] == nil {
                    namesByBundlePath[bundlePath] = displayName(for: bundlePath)
                }
            }
        }

        // Bound label storage to applications represented in the current sample.
        namesByBundlePath = namesByBundlePath.filter { activeBundlePaths.contains($0.key) }
        guard !processes.isEmpty else {
            reset()
            return AppUsageSnapshot(
                isWarmingUp: false, unavailableProcessCount: unavailable,
                error: "Process statistics are unavailable."
            )
        }
        return interval.record(
            processes,
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            namesByBundlePath: namesByBundlePath,
            unavailableProcessCount: unavailable
        )
    }

    private func processIDs() throws -> [Int32] {
        let estimatedCount = ms_list_process_ids(nil, 0)
        guard estimatedCount > 0 else { throw ProcessEnumerationError.unavailable }
        var capacity = max(256, Int(estimatedCount) + 128)
        // Leave room for process creation between sizing and enumeration. Retry
        // a full buffer rather than silently presenting a truncated process list.
        for _ in 0..<3 {
            guard capacity <= 262_144 else { throw ProcessEnumerationError.tooManyProcesses }
            var pids = [Int32](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBufferPointer {
                ms_list_process_ids($0.baseAddress, Int32(capacity))
            }
            guard count > 0 else { throw ProcessEnumerationError.unavailable }
            if count < capacity { return Array(pids.prefix(Int(count))) }
            capacity *= 2
        }
        throw ProcessEnumerationError.changedTooQuickly
    }

    private func displayName(for bundlePath: String) -> String {
        let bundle = Bundle(path: bundlePath)
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = bundle?.object(forInfoDictionaryKey: key) as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return AppUsageGrouping.bundleName(for: bundlePath)
    }

    private func boundedString<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

private enum ProcessEnumerationError: LocalizedError {
    case unavailable
    case tooManyProcesses
    case changedTooQuickly

    var errorDescription: String? {
        switch self {
        case .unavailable: "Could not read the process list."
        case .tooManyProcesses: "The process list exceeds the sampling limit."
        case .changedTooQuickly: "The process list changed too quickly. Retrying next update."
        }
    }
}
