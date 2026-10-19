import XCTest
@testable import MenuStatsCore

final class MetricCalculationsTests: XCTestCase {
    func testCPUIntervalRequiresBaselineAndCountsUserSystemAndNiceAsBusy() {
        var interval = CPUInterval()
        XCTAssertNil(interval.record(CPUTicks(user: 1_000, system: 200, idle: 8_000, nice: 100)))
        let result = interval.record(CPUTicks(user: 1_010, system: 205, idle: 8_080, nice: 105))
        XCTAssertEqual(result!, 20, accuracy: 0.0001)
    }

    func testIdleAndFullyBusyIntervals() {
        let baseline = CPUTicks(user: 10, system: 20, idle: 30, nice: 40)
        XCTAssertEqual(CPUTicks(user: 10, system: 20, idle: 130, nice: 40).busyPercent(since: baseline), 0)
        XCTAssertEqual(CPUTicks(user: 110, system: 20, idle: 30, nice: 40).busyPercent(since: baseline), 100)
        XCTAssertNil(baseline.busyPercent(since: baseline))
    }

    func testCPUHandlesCounterWrapBeforeWidening() {
        let baseline = CPUTicks(user: UInt32.max - 4, system: 10, idle: UInt32.max - 9, nice: 5)
        // Wrapped deltas: 10 user + 5 system + 5 nice + 80 idle = 100 ticks.
        let next = CPUTicks(user: 5, system: 15, idle: 70, nice: 10)
        XCTAssertEqual(next.busyPercent(since: baseline)!, 20, accuracy: 0.0001)
    }

    func testFailedCPUSampleResetsBaseline() {
        var interval = CPUInterval()
        _ = interval.record(CPUTicks(user: 0, system: 0, idle: 0, nice: 0))
        XCTAssertNil(interval.record(nil))
        XCTAssertNil(interval.record(CPUTicks(user: 5, system: 0, idle: 5, nice: 0)))
        XCTAssertEqual(interval.record(CPUTicks(user: 10, system: 0, idle: 10, nice: 0)), 50)
    }

    func testMemoryIncludesAnonymousWiredAndPhysicalCompressorLessPurgeable() throws {
        let memory = try XCTUnwrap(MetricCalculations.memory(
            internalPages: 300, wiredPages: 100, compressedPages: 50,
            purgeablePages: 25, pageSize: 16_384, totalBytes: 16_384_000
        ))
        XCTAssertEqual(memory.usedBytes, 425 * 16_384)
        XCTAssertEqual(memory.percentUsed, 42.5)
    }

    func testPurgeableUnderflowDoesNotSubtractWiredOrCompressor() throws {
        let memory = try XCTUnwrap(MetricCalculations.memory(
            internalPages: 10, wiredPages: 20, compressedPages: 30,
            purgeablePages: 100, pageSize: 4_096, totalBytes: 4_096_000
        ))
        XCTAssertEqual(memory.usedBytes, 50 * 4_096)
    }

    func testMemoryBoundsConcurrentCounterSkewAndRejectsOverflow() throws {
        let memory = try XCTUnwrap(MetricCalculations.memory(
            internalPages: 900, wiredPages: 200, compressedPages: 100,
            purgeablePages: 0, pageSize: 4_096, totalBytes: 4_096_000
        ))
        XCTAssertEqual(memory.percentUsed, 100)
        XCTAssertNil(MetricCalculations.memory(
            internalPages: UInt64.max, wiredPages: 1, compressedPages: 0,
            purgeablePages: 0, pageSize: 4_096, totalBytes: UInt64.max
        ))
        XCTAssertNil(MetricCalculations.memory(
            internalPages: 1, wiredPages: 1, compressedPages: 1,
            purgeablePages: 0, pageSize: 4_096, totalBytes: 0
        ))
    }

    func testDiskUsesAvailableBlocksAndHandlesFullDisk() throws {
        let disk = try XCTUnwrap(MetricCalculations.disk(
            availableBlocks: 25, totalBlocks: 100, blockSize: 4_096, volumeName: "Data"
        ))
        XCTAssertEqual(disk.freeBytes, 102_400)
        XCTAssertEqual(disk.totalBytes, 409_600)
        XCTAssertEqual(disk.percentUsed, 75)
        let full = try XCTUnwrap(MetricCalculations.disk(
            availableBlocks: 0, totalBlocks: 100, blockSize: 4_096, volumeName: "Data"
        ))
        XCTAssertEqual(full.freeBytes, 0)
        XCTAssertEqual(full.percentUsed, 100)
    }

    func testDiskBoundsAndInvalidCapacity() throws {
        let disk = try XCTUnwrap(MetricCalculations.disk(
            availableBlocks: 200, totalBlocks: 100, blockSize: 4_096, volumeName: "Data"
        ))
        XCTAssertEqual(disk.freeBytes, disk.totalBytes)
        XCTAssertEqual(disk.percentUsed, 0)
        XCTAssertNil(MetricCalculations.disk(
            availableBlocks: 0, totalBlocks: 0, blockSize: 4_096, volumeName: "Data"
        ))
        XCTAssertNil(MetricCalculations.disk(
            availableBlocks: 1, totalBlocks: UInt64.max, blockSize: 4_096, volumeName: "Data"
        ))
    }
}
