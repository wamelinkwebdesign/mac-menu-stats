import XCTest
@testable import MenuStatsCore

final class AppUsageTests: XCTestCase {
    func testCPUUsesUserAndSystemMachTicksOverWholeMachineCapacity() throws {
        let previous = process(user: 100, system: 50, sampled: 1_000)
        let next = process(user: 400, system: 150, sampled: 1_200)
        // 400 busy ticks / (200 elapsed ticks * 8 logical CPUs) = 25%.
        XCTAssertEqual(try XCTUnwrap(next.cpuPercent(since: previous, processorCount: 8)), 25)
        XCTAssertEqual(try XCTUnwrap(next.cpuPercent(since: previous, processorCount: 2)), 100)
    }

    func testCPURatioDoesNotDependOnMachTimebase() throws {
        let previous = process(user: 24, system: 12, sampled: 240)
        let next = process(user: 72, system: 36, sampled: 480)
        // Apple Silicon uses a different tick frequency from nanoseconds.
        // Multiplying every counter by any common timebase preserves the ratio.
        let scaledPrevious = process(user: 24_000, system: 12_000, sampled: 240_000)
        let scaledNext = process(user: 72_000, system: 36_000, sampled: 480_000)
        XCTAssertEqual(
            try XCTUnwrap(next.cpuPercent(since: previous, processorCount: 4)),
            try XCTUnwrap(scaledNext.cpuPercent(since: scaledPrevious, processorCount: 4))
        )
    }

    func testCPURejectsPIDReuseClockRegressionAndInvalidCounters() {
        let previous = process(start: 1, user: 100, system: 50, sampled: 1_000)
        XCTAssertNil(process(pid: 2, user: 200, system: 60, sampled: 1_200).cpuPercent(since: previous, processorCount: 8))
        XCTAssertNil(process(start: 2, user: 200, system: 60, sampled: 1_200).cpuPercent(since: previous, processorCount: 8))
        XCTAssertNil(process(user: 200, system: 60, sampled: 900).cpuPercent(since: previous, processorCount: 8))
        XCTAssertNil(process(user: 90, system: 60, sampled: 1_200).cpuPercent(since: previous, processorCount: 8))
        XCTAssertNil(process(user: 200, system: 40, sampled: 1_200).cpuPercent(since: previous, processorCount: 8))
        XCTAssertNil(process(user: 200, system: 60, sampled: 1_200).cpuPercent(since: previous, processorCount: 0))
    }

    func testCPURequiresNewBaselineAfterExecChangesOwnership() {
        let previous = process(user: 100, sampled: 1_000, path: "/usr/bin/env")
        let next = process(user: 200, sampled: 1_200, path: "/usr/bin/python3")
        XCTAssertNil(next.cpuPercent(since: previous, processorCount: 8))
    }

    func testFirstSampleHasMemoryButNoInventedCPU() throws {
        var interval = AppUsageInterval()
        let snapshot = interval.record([process(memory: 512)], processorCount: 8, namesByBundlePath: [:])
        XCTAssertTrue(snapshot.isWarmingUp)
        let reading = try XCTUnwrap(snapshot.apps.first)
        XCTAssertNil(reading.cpuPercent)
        XCTAssertEqual(reading.memoryBytes, 512)
    }

    func testHelpersAggregateIntoOuterAppWithSummedFootprintsAndCPU() throws {
        var interval = AppUsageInterval()
        let app = "/Applications/Browser.app/Contents/MacOS/Browser"
        let helper = "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        _ = interval.record([
            process(pid: 1, user: 0, sampled: 1_000, path: app),
            process(pid: 2, user: 0, sampled: 1_000, path: helper)
        ], processorCount: 4, namesByBundlePath: [:])
        let snapshot = interval.record([
            process(pid: 1, user: 100, sampled: 1_200, memory: 1_024, path: app),
            process(pid: 2, user: 200, sampled: 1_200, memory: 2_048, path: helper)
        ], processorCount: 4, namesByBundlePath: ["/Applications/Browser.app": "Browser Display Name"])
        XCTAssertFalse(snapshot.isWarmingUp)
        XCTAssertEqual(snapshot.apps.count, 1)
        let reading = try XCTUnwrap(snapshot.apps.first)
        XCTAssertEqual(reading.name, "Browser Display Name")
        XCTAssertEqual(reading.bundlePath, "/Applications/Browser.app")
        XCTAssertEqual(reading.processCount, 2)
        XCTAssertEqual(reading.memoryBytes, 3_072)
        XCTAssertEqual(try XCTUnwrap(reading.cpuPercent), 37.5)
        XCTAssertTrue(reading.isApplication)
    }

    func testBundleGroupingRequiresContentsBoundaryAndUsesOutermostApp() {
        XCTAssertNil(AppUsageGrouping.bundlePath(for: "/tmp/demo.app.backup/bin/program"))
        XCTAssertNil(AppUsageGrouping.bundlePath(for: "/tmp/demo.app/program"))
        XCTAssertNil(AppUsageGrouping.bundlePath(for: "/tmp/demo.app/Contents"))
        XCTAssertNil(AppUsageGrouping.bundlePath(for: "relative/demo.app/Contents/MacOS/program"))
        XCTAssertEqual(
            AppUsageGrouping.bundlePath(for: "/Applications/Outer.app/Contents/Helpers/Inner.app/Contents/MacOS/Binary"),
            "/Applications/Outer.app"
        )
    }

    func testBackgroundProcessesStayVisibleAndGroupByExecutable() throws {
        var interval = AppUsageInterval()
        let snapshot = interval.record([
            process(pid: 1, memory: 100, path: "/usr/bin/python3", name: "python3"),
            process(pid: 2, memory: 200, path: "/usr/bin/python3", name: "python3"),
            process(pid: 3, memory: 400, path: "/opt/bin/python3", name: "python3")
        ], processorCount: 4, namesByBundlePath: [:])
        XCTAssertEqual(snapshot.apps.count, 2)
        XCTAssertEqual(snapshot.apps.reduce(0) { $0 + $1.memoryBytes }, 700)
        XCTAssertTrue(snapshot.apps.allSatisfy { !$0.isApplication && $0.bundlePath == nil })
        XCTAssertEqual(snapshot.apps.first { $0.id == "process:/usr/bin/python3" }?.processCount, 2)
    }

    func testUnavailablePathsKeepSameNamedProcessesSeparateAndTrackLifetime() throws {
        var interval = AppUsageInterval()
        let first = interval.record([
            process(pid: 1, start: 10, memory: 100, path: "", name: "worker"),
            process(pid: 2, start: 20, memory: 200, path: "", name: "worker")
        ], processorCount: 4, namesByBundlePath: [:])
        XCTAssertEqual(first.apps.count, 2)
        XCTAssertEqual(Set(first.apps.map(\.id)), ["process-id:1:10", "process-id:2:20"])
        XCTAssertTrue(first.apps.allSatisfy { $0.name == "worker" && $0.processCount == 1 })
        XCTAssertEqual(first.apps.first { $0.id == "process-id:1:10" }?.memoryBytes, 100)

        let next = interval.record([
            process(pid: 1, start: 30, user: 100, sampled: 1_200, path: "", name: "worker"),
            process(pid: 2, start: 20, user: 100, sampled: 1_200, path: "", name: "worker")
        ], processorCount: 4, namesByBundlePath: [:])
        XCTAssertEqual(Set(next.apps.map(\.id)), ["process-id:1:30", "process-id:2:20"])
        XCTAssertNil(next.apps.first { $0.id == "process-id:1:30" }?.cpuPercent)
        XCTAssertEqual(next.apps.first { $0.id == "process-id:2:20" }?.cpuPercent, 12.5)
    }

    func testNewProcessAndReusedPIDGetBaselinesWhileExistingProcessUpdates() throws {
        var interval = AppUsageInterval()
        _ = interval.record([
            process(pid: 1, user: 100, sampled: 1_000, path: "/one"),
            process(pid: 2, user: 100, sampled: 1_000, path: "/two")
        ], processorCount: 4, namesByBundlePath: [:])
        let snapshot = interval.record([
            process(pid: 1, user: 200, sampled: 1_100, path: "/one"),
            process(pid: 2, start: 2, user: 150, sampled: 1_100, path: "/two"),
            process(pid: 3, user: 500, sampled: 1_100, path: "/three")
        ], processorCount: 4, namesByBundlePath: [:])
        XCTAssertEqual(snapshot.apps.first { $0.id == "process:/one" }?.cpuPercent, 25)
        XCTAssertNil(snapshot.apps.first { $0.id == "process:/two" }?.cpuPercent)
        XCTAssertNil(snapshot.apps.first { $0.id == "process:/three" }?.cpuPercent)
    }

    func testExitedProcessBaselinesArePrunedAndResetStartsFresh() {
        var interval = AppUsageInterval()
        _ = interval.record([
            process(pid: 1), process(pid: 2), process(pid: 3)
        ], processorCount: 4, namesByBundlePath: [:])
        XCTAssertEqual(interval.previousProcessCount, 3)
        _ = interval.record([process(pid: 1)], processorCount: 4, namesByBundlePath: [:])
        XCTAssertEqual(interval.previousProcessCount, 1)
        interval.reset()
        XCTAssertEqual(interval.previousProcessCount, 0)
        let snapshot = interval.record([process(pid: 1, user: 500, sampled: 2_000)], processorCount: 4, namesByBundlePath: [:])
        XCTAssertTrue(snapshot.isWarmingUp)
        XCTAssertNil(snapshot.apps.first?.cpuPercent)
    }

    func testRankingUsesMeasuredCPUThenDeterministicTiesAndBoundsLimit() {
        let snapshot = AppUsageSnapshot(apps: [
            reading("large-unknown", cpu: nil, memory: 100_000),
            reading("small-busy", cpu: 50, memory: 1),
            reading("large-idle", cpu: 0, memory: 10_000),
            reading("tie-b", cpu: 5, memory: 100),
            reading("tie-a", cpu: 5, memory: 100)
        ])
        XCTAssertEqual(snapshot.topCPUApps().map(\.id), ["small-busy", "tie-a", "tie-b", "large-idle", "large-unknown"])
        XCTAssertEqual(snapshot.topMemoryApps(limit: 3).map(\.id), ["large-unknown", "large-idle", "tie-a"])
        XCTAssertTrue(snapshot.topCPUApps(limit: -1).isEmpty)
        XCTAssertTrue(snapshot.topMemoryApps(limit: 0).isEmpty)
    }

    func testDuplicatePIDsDoNotDoubleCountAndUnavailableCountIsPreserved() throws {
        var interval = AppUsageInterval()
        let duplicate = process(memory: 512)
        let snapshot = interval.record([duplicate, duplicate], processorCount: 4, namesByBundlePath: [:], unavailableProcessCount: 7)
        let reading = try XCTUnwrap(snapshot.apps.first)
        XCTAssertEqual(reading.memoryBytes, 512)
        XCTAssertEqual(reading.processCount, 1)
        XCTAssertEqual(snapshot.unavailableProcessCount, 7)
    }

    private func process(
        pid: Int32 = 1, start: UInt64 = 1, user: UInt64 = 0, system: UInt64 = 0,
        sampled: UInt64 = 1_000, memory: UInt64 = 100,
        path: String = "/Applications/Test.app/Contents/MacOS/Test", name: String = "Test"
    ) -> ProcessUsageSample {
        ProcessUsageSample(
            pid: pid, startTicks: start, userTicks: user, systemTicks: system,
            sampledTicks: sampled, memoryBytes: memory, executablePath: path, name: name
        )
    }

    private func reading(_ id: String, cpu: Double?, memory: UInt64) -> AppUsageReading {
        AppUsageReading(id: id, name: id, cpuPercent: cpu, memoryBytes: memory)
    }
}
