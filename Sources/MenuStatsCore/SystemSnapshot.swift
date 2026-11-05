import Foundation

public struct SystemSnapshot: Sendable, Codable, Equatable {
    public let cpuPercent: Double?
    public let memory: MemoryReading?
    public let memoryPressure: MemoryPressure?
    public let swap: SwapReading?
    public let disk: DiskReading?
    public let network: NetworkReading?
    public let battery: BatteryStatus?
    public let sampledAt: Date
    public let errors: [String]

    public init(
        cpuPercent: Double? = nil,
        memory: MemoryReading? = nil,
        memoryPressure: MemoryPressure? = nil,
        swap: SwapReading? = nil,
        disk: DiskReading? = nil,
        network: NetworkReading? = nil,
        battery: BatteryStatus? = nil,
        sampledAt: Date = Date(),
        errors: [String] = []
    ) {
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.memoryPressure = memoryPressure
        self.swap = swap
        self.disk = disk
        self.network = network
        self.battery = battery
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

/// The kernel's memory pressure level, as shown by Activity Monitor.
public enum MemoryPressure: String, Sendable, Codable, Equatable {
    case normal
    case warning
    case critical
}

public struct SwapReading: Sendable, Codable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

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

/// Throughput since the previous sample, summed over Ethernet-type interfaces.
public struct NetworkReading: Sendable, Codable, Equatable {
    public let receivedBytesPerSecond: Double
    public let sentBytesPerSecond: Double
    public let interfaceCount: Int

    init(receivedBytesPerSecond: Double, sentBytesPerSecond: Double, interfaceCount: Int) {
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
        self.interfaceCount = interfaceCount
    }
}

public enum BatteryStatus: Sendable, Codable, Equatable {
    case notInstalled
    case installed(BatteryReading)
}

/// Each field is nil when macOS does not report it, never zero.
public struct BatteryReading: Sendable, Codable, Equatable {
    public let chargePercent: Double?
    public let isCharging: Bool?
    public let isOnPower: Bool?
    /// Full charge capacity as a share of design capacity, capped at 100.
    public let healthPercent: Double?
    public let cycleCount: Int?
    public let temperatureCelsius: Double?
    /// A non-normal condition reported by macOS, such as "Service Recommended".
    public let condition: String?

    init(
        chargePercent: Double?,
        isCharging: Bool?,
        isOnPower: Bool?,
        healthPercent: Double?,
        cycleCount: Int?,
        temperatureCelsius: Double?,
        condition: String?
    ) {
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.isOnPower = isOnPower
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.condition = condition
    }
}
