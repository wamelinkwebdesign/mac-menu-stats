import Darwin
import Foundation
import MenuStatsCore

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601

func printJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try encoder.encode(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// Two samples are required because CPU utilization is an interval measurement.
if CommandLine.arguments.contains("--apps") {
    var sampler = AppUsageSampler()
    let first = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let second = sampler.sample()
    try printJSON([first, second])
    if second.error != nil || second.apps.isEmpty || second.apps.allSatisfy({ $0.cpuPercent == nil }) {
        exit(EXIT_FAILURE)
    }
} else {
    var sampler = SystemSampler()
    let first = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let second = sampler.sample()
    try printJSON([first, second])
    if second.cpuPercent == nil || second.memory == nil || second.disk == nil || !second.errors.isEmpty {
        exit(EXIT_FAILURE)
    }
}
