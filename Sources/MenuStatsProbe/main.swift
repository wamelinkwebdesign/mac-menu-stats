import Darwin
import Foundation
import MenuStatsCore

// Two samples are required because CPU utilization is an interval measurement.
var sampler = SystemSampler()
let first = sampler.sample()
Thread.sleep(forTimeInterval: 1)
let second = sampler.sample()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let output = try encoder.encode([first, second])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
if second.cpuPercent == nil || second.memory == nil || second.disk == nil || !second.errors.isEmpty {
    exit(EXIT_FAILURE)
}
