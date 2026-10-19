import Foundation

public struct AppUsageSnapshot: Sendable, Codable, Equatable {
    public let apps: [AppUsageReading]
    public let sampledAt: Date
    public let isWarmingUp: Bool
    public let unavailableProcessCount: Int
    public let error: String?

    public init(
        apps: [AppUsageReading] = [],
        sampledAt: Date = Date(),
        isWarmingUp: Bool = true,
        unavailableProcessCount: Int = 0,
        error: String? = nil
    ) {
        self.apps = apps
        self.sampledAt = sampledAt
        self.isWarmingUp = isWarmingUp
        self.unavailableProcessCount = unavailableProcessCount
        self.error = error
    }

    public func topCPUApps(limit: Int = 5) -> [AppUsageReading] {
        Array(apps.sorted { lhs, rhs in
            if lhs.cpuPercent != rhs.cpuPercent {
                // An unavailable interval belongs after every measured value.
                return (lhs.cpuPercent ?? -1) > (rhs.cpuPercent ?? -1)
            }
            if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
            return lhs.id < rhs.id
        }.prefix(max(0, limit)))
    }

    public func topMemoryApps(limit: Int = 5) -> [AppUsageReading] {
        Array(apps.sorted { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
            return lhs.id < rhs.id
        }.prefix(max(0, limit)))
    }
}

public struct AppUsageReading: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let bundlePath: String?
    public let processCount: Int
    /// Percentage of the whole machine's logical CPU capacity, from 0 to 100.
    public let cpuPercent: Double?
    /// Sum of process physical footprints, including compressed memory charges.
    public let memoryBytes: UInt64
    public let isApplication: Bool

    public init(
        id: String,
        name: String,
        bundlePath: String? = nil,
        processCount: Int = 1,
        cpuPercent: Double? = nil,
        memoryBytes: UInt64,
        isApplication: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.processCount = processCount
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.isApplication = isApplication
    }
}
