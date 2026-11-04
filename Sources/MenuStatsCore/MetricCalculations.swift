import Foundation

struct CPUTicks: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func busyPercent(since previous: CPUTicks) -> Double? {
        // Each kernel counter can wrap independently. Widen only after subtraction.
        let busy = UInt64(user &- previous.user)
            + UInt64(system &- previous.system)
            + UInt64(nice &- previous.nice)
        let total = busy + UInt64(idle &- previous.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total) * 100
    }
}

struct CPUInterval: Sendable {
    private var previous: CPUTicks?

    mutating func record(_ ticks: CPUTicks?) -> Double? {
        defer { previous = ticks }
        guard let ticks, let previous else { return nil }
        return ticks.busyPercent(since: previous)
    }
}

struct NetworkCounters: Sendable, Equatable {
    let bytesIn: UInt64
    let bytesOut: UInt64
}

struct NetworkInterval: Sendable {
    private var previous: [UInt32: NetworkCounters]?
    private var previousTime: Double?

    /// Counters are keyed by interface index. Interfaces that appear, vanish,
    /// or reset between samples are skipped rather than counted as traffic.
    mutating func record(_ counters: [UInt32: NetworkCounters]?, at time: Double) -> NetworkReading? {
        defer {
            previous = counters
            previousTime = counters == nil ? nil : time
        }
        guard let counters, let previous, let previousTime else { return nil }
        let elapsed = time - previousTime
        guard elapsed > 0 else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (index, current) in counters {
            guard let old = previous[index],
                  current.bytesIn >= old.bytesIn,
                  current.bytesOut >= old.bytesOut else { continue }
            received &+= current.bytesIn - old.bytesIn
            sent &+= current.bytesOut - old.bytesOut
        }
        return NetworkReading(
            receivedBytesPerSecond: Double(received) / elapsed,
            sentBytesPerSecond: Double(sent) / elapsed,
            interfaceCount: counters.count
        )
    }
}

enum MetricCalculations {
    static func memory(
        internalPages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        purgeablePages: UInt64,
        pageSize: UInt64,
        totalBytes: UInt64
    ) -> MemoryReading? {
        guard pageSize > 0, totalBytes > 0 else { return nil }
        // Anonymous resident pages approximate app memory. File-backed cache is
        // excluded. Count the compressor's physical storage, not its logical size.
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let (appAndWired, firstOverflow) = appPages.addingReportingOverflow(wiredPages)
        let (usedPages, secondOverflow) = appAndWired.addingReportingOverflow(compressedPages)
        let (usedBytes, thirdOverflow) = usedPages.multipliedReportingOverflow(by: pageSize)
        guard !firstOverflow, !secondOverflow, !thirdOverflow else { return nil }
        // VM counters are sampled concurrently, so constrain transient skew.
        return MemoryReading(usedBytes: min(usedBytes, totalBytes), totalBytes: totalBytes)
    }

    static func disk(
        availableBlocks: UInt64,
        totalBlocks: UInt64,
        blockSize: UInt64,
        volumeName: String
    ) -> DiskReading? {
        guard blockSize > 0, totalBlocks > 0 else { return nil }
        let (totalBytes, totalOverflow) = totalBlocks.multipliedReportingOverflow(by: blockSize)
        let (freeBytes, freeOverflow) = min(availableBlocks, totalBlocks)
            .multipliedReportingOverflow(by: blockSize)
        guard !totalOverflow, !freeOverflow else { return nil }
        return DiskReading(freeBytes: freeBytes, totalBytes: totalBytes, volumeName: volumeName)
    }

    /// Levels from kern.memorystatus_vm_pressure_level.
    static func memoryPressure(level: Int32) -> MemoryPressure? {
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return nil
        }
    }

    static func swap(usedBytes: UInt64, totalBytes: UInt64) -> SwapReading {
        SwapReading(usedBytes: min(usedBytes, totalBytes), totalBytes: totalBytes)
    }

    /// Combines the internal battery's power source description with
    /// AppleSmartBattery registry properties. Desktops have no such source.
    static func battery(powerSource: [String: Any]?, registry: [String: Any]?) -> BatteryStatus {
        guard let powerSource else { return .notInstalled }
        guard powerSource["Type"] as? String == "InternalBattery" else { return .notInstalled }
        if let present = powerSource["Is Present"] as? Bool, !present { return .notInstalled }

        var charge: Double?
        if let current = int(powerSource["Current Capacity"]),
           let maximum = int(powerSource["Max Capacity"]), maximum > 0, current >= 0 {
            charge = min(100, Double(current) / Double(maximum) * 100)
        }

        // Registry values are only trusted when the gauge says a battery is installed.
        let battery = registry.flatMap { $0["BatteryInstalled"] as? Bool == true ? $0 : nil }
        var health: Double?
        if let battery, let design = int(battery["DesignCapacity"]), design > 0,
           let full = int(battery["NominalChargeCapacity"]) ?? int(battery["AppleRawMaxCapacity"]),
           full > 0 {
            health = min(100, Double(full) / Double(design) * 100)
        }
        let cycles = battery.flatMap { int($0["CycleCount"]) }.flatMap { $0 >= 0 ? $0 : nil }
        // AppleSmartBattery reports temperature in hundredths of a degree Celsius.
        let temperature = battery.flatMap { int($0["Temperature"]) }
            .map { Double($0) / 100 }
            .flatMap { (1...90).contains($0) ? $0 : nil }

        let condition = (powerSource["BatteryHealthCondition"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        return .installed(BatteryReading(
            chargePercent: charge,
            isCharging: powerSource["Is Charging"] as? Bool,
            isOnPower: (powerSource["Power Source State"] as? String).map { $0 == "AC Power" },
            healthPercent: health,
            cycleCount: cycles,
            temperatureCelsius: temperature,
            condition: condition
        ))
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
