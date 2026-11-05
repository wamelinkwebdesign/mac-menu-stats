import Darwin
import XCTest
@testable import MenuStatsCore

final class ExtendedMetricsTests: XCTestCase {
    func testMemoryPressureLevelsAndUnknownValue() {
        XCTAssertEqual(MetricCalculations.memoryPressure(level: 1), .normal)
        XCTAssertEqual(MetricCalculations.memoryPressure(level: 2), .warning)
        XCTAssertEqual(MetricCalculations.memoryPressure(level: 4), .critical)
        XCTAssertNil(MetricCalculations.memoryPressure(level: 0))
        XCTAssertNil(MetricCalculations.memoryPressure(level: 3))
    }

    func testSwapUsageIsBoundedByTotal() {
        XCTAssertEqual(MetricCalculations.swap(usedBytes: 5, totalBytes: 10).usedBytes, 5)
        XCTAssertEqual(MetricCalculations.swap(usedBytes: 12, totalBytes: 10).usedBytes, 10)
    }

    func testNetworkRateRequiresBaselineAndSumsInterfaces() throws {
        var interval = NetworkInterval()
        XCTAssertNil(interval.record([
            1: NetworkCounters(bytesIn: 1_000, bytesOut: 500),
            2: NetworkCounters(bytesIn: 0, bytesOut: 0)
        ], at: 10))
        let reading = try XCTUnwrap(interval.record([
            1: NetworkCounters(bytesIn: 3_000, bytesOut: 1_500),
            2: NetworkCounters(bytesIn: 2_000, bytesOut: 1_000)
        ], at: 12))
        XCTAssertEqual(reading.receivedBytesPerSecond, 2_000)
        XCTAssertEqual(reading.sentBytesPerSecond, 1_000)
        XCTAssertEqual(reading.interfaceCount, 2)
    }

    func testNetworkSkipsNewAndResetInterfaces() throws {
        var interval = NetworkInterval()
        _ = interval.record([1: NetworkCounters(bytesIn: 5_000, bytesOut: 5_000)], at: 0)
        let reading = try XCTUnwrap(interval.record([
            1: NetworkCounters(bytesIn: 100, bytesOut: 100),
            7: NetworkCounters(bytesIn: 9_000, bytesOut: 9_000)
        ], at: 1))
        XCTAssertEqual(reading.receivedBytesPerSecond, 0)
        XCTAssertEqual(reading.sentBytesPerSecond, 0)
    }

    func testFailedNetworkSampleResetsBaselineAndZeroElapsedIsUnknown() {
        var interval = NetworkInterval()
        _ = interval.record([1: NetworkCounters(bytesIn: 0, bytesOut: 0)], at: 0)
        XCTAssertNil(interval.record(nil, at: 1))
        XCTAssertNil(interval.record([1: NetworkCounters(bytesIn: 10, bytesOut: 10)], at: 2))
        XCTAssertNil(interval.record([1: NetworkCounters(bytesIn: 20, bytesOut: 20)], at: 2))
    }

    func testNetworkParserReadsEtherInterfacesAndSkipsOthers() throws {
        var bytes = message(index: 4, type: 0x06, bytesIn: 1_234, bytesOut: 567)
        bytes += message(index: 1, type: 0x18, bytesIn: 99, bytesOut: 99)
        let counters = try NetworkCounterReader.parse(bytes[...])
        XCTAssertEqual(counters, [4: NetworkCounters(bytesIn: 1_234, bytesOut: 567)])
    }

    func testNetworkParserRejectsTruncatedMessage() {
        let bytes = message(index: 4, type: 0x06, bytesIn: 1, bytesOut: 1)
        XCTAssertThrowsError(try NetworkCounterReader.parse(bytes.dropLast(8)))
    }

    func testDesktopHasNoBattery() {
        XCTAssertEqual(MetricCalculations.battery(powerSource: nil, registry: nil), .notInstalled)
        XCTAssertEqual(
            MetricCalculations.battery(powerSource: ["Type": "UPS"], registry: nil),
            .notInstalled
        )
    }

    func testBatteryCombinesPowerSourceAndRegistry() throws {
        let status = MetricCalculations.battery(
            powerSource: [
                "Type": "InternalBattery", "Is Present": true,
                "Current Capacity": 84, "Max Capacity": 100,
                "Is Charging": true, "Power Source State": "AC Power",
                "BatteryHealthCondition": "Service Recommended"
            ],
            registry: [
                "BatteryInstalled": true, "DesignCapacity": 5_000,
                "NominalChargeCapacity": 4_600, "CycleCount": 312, "Temperature": 3_050
            ]
        )
        guard case .installed(let battery) = status else { return XCTFail("Expected a battery") }
        XCTAssertEqual(battery.chargePercent, 84)
        XCTAssertEqual(battery.isCharging, true)
        XCTAssertEqual(battery.isOnPower, true)
        XCTAssertEqual(try XCTUnwrap(battery.healthPercent), 92, accuracy: 0.001)
        XCTAssertEqual(battery.cycleCount, 312)
        XCTAssertEqual(try XCTUnwrap(battery.temperatureCelsius), 30.5, accuracy: 0.001)
        XCTAssertEqual(battery.condition, "Service Recommended")
    }

    func testBatteryLeavesMissingOrImplausibleValuesUnknown() {
        // Desktop Macs can expose an empty AppleSmartBattery node with zeros.
        let status = MetricCalculations.battery(
            powerSource: ["Type": "InternalBattery", "Current Capacity": 50, "Max Capacity": 0],
            registry: [
                "BatteryInstalled": false, "DesignCapacity": 0,
                "CycleCount": 0, "Temperature": 0
            ]
        )
        XCTAssertEqual(status, .installed(BatteryReading(
            chargePercent: nil, isCharging: nil, isOnPower: nil, healthPercent: nil,
            cycleCount: nil, temperatureCelsius: nil, condition: nil
        )))
    }

    func testBatteryHealthIsCappedAndFallsBackToRawCapacity() {
        let status = MetricCalculations.battery(
            powerSource: ["Type": "InternalBattery"],
            registry: ["BatteryInstalled": true, "DesignCapacity": 4_000, "AppleRawMaxCapacity": 4_200]
        )
        guard case .installed(let battery) = status else { return XCTFail("Expected a battery") }
        XCTAssertEqual(battery.healthPercent, 100)
    }

    func testHistoryKeepsNewestValuesAndGaps() {
        var history = SampleHistory(capacity: 3)
        [1, nil, 3, 4].forEach { history.append($0) }
        XCTAssertEqual(history.values, [nil, 3, 4])
        history.removeAll()
        XCTAssertEqual(history.values, [])
    }

    private func message(index: UInt16, type: UInt8, bytesIn: UInt64, bytesOut: UInt64) -> [UInt8] {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = index
        header.ifm_data.ifi_type = type
        header.ifm_data.ifi_ibytes = bytesIn
        header.ifm_data.ifi_obytes = bytesOut
        return withUnsafeBytes(of: header) { Array($0) }
    }
}
