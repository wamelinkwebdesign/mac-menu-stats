import Foundation

public struct SystemSnapshot: Sendable, Codable, Equatable {
    public let cpuPercent: Double?
    public let memory: MemoryReading?
    public let disk: DiskReading?
    public let sampledAt: Date
    public let errors: [String]

    public init(
        cpuPercent: Double? = nil,
        memory: MemoryReading? = nil,
        disk: DiskReading? = nil,
        sampledAt: Date = Date(),
        errors: [String] = []
    ) {
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.disk = disk
        self.sampledAt = sampledAt
        self.errors = errors
    }
}

public struct MemoryReading: Sendable, Codable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public var percentUsed: Double { Double(usedBytes) / Double(totalBytes) * 100 }

    init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }
}

public struct DiskReading: Sendable, Codable, Equatable {
    public let freeBytes: UInt64
    public let totalBytes: UInt64
    public let volumeName: String
    public var percentUsed: Double {
        Double(totalBytes - freeBytes) / Double(totalBytes) * 100
    }

    init(freeBytes: UInt64, totalBytes: UInt64, volumeName: String) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.volumeName = volumeName
    }
}
