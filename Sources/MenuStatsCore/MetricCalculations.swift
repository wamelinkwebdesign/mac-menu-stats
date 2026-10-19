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
}
