import Darwin
import Foundation

/// Synchronous, dependency-free sampler. The caller controls its polling interval.
public struct SystemSampler: Sendable {
    private var cpuInterval = CPUInterval()
    private let dataVolumeURL = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)

    public init() {}

    public mutating func sample() -> SystemSnapshot {
        var errors: [String] = []
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var cpu: Double?
        do {
            cpu = cpuInterval.record(try readCPUTicks(host: host))
        } catch {
            _ = cpuInterval.record(nil)
            errors.append("CPU: \(error.localizedDescription)")
        }

        var memory: MemoryReading?
        do {
            memory = try readMemory(host: host)
        } catch {
            errors.append("Memory: \(error.localizedDescription)")
        }

        var disk: DiskReading?
        do {
            disk = try readDisk()
        } catch {
            errors.append("Disk: \(error.localizedDescription)")
        }

        return SystemSnapshot(
            cpuPercent: cpu,
            memory: memory,
            disk: disk,
            sampledAt: Date(),
            errors: errors
        )
    }

    private func readCPUTicks(host: host_t) throws -> CPUTicks {
        var info = host_cpu_load_info_data_t()
        let expectedCount = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var count = expectedCount
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(expectedCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw SampleError.mach(result) }
        guard count >= expectedCount else { throw SampleError.incompleteStatistics }
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    private func readMemory(host: host_t) throws -> MemoryReading {
        var info = vm_statistics64_data_t()
        let capacity = MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw SampleError.mach(result) }
        // Revision 1 ends immediately before swapped_count. It includes every
        // field used below and is available on the minimum supported macOS.
        let minimumBytes = MemoryLayout<vm_statistics64_data_t>.offset(of: \.swapped_count)!
        guard Int(count) * MemoryLayout<integer_t>.stride >= minimumBytes else {
            throw SampleError.incompleteStatistics
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else { throw SampleError.mach(pageResult) }
        guard let reading = MetricCalculations.memory(
            internalPages: UInt64(info.internal_page_count),
            wiredPages: UInt64(info.wire_count),
            compressedPages: UInt64(info.compressor_page_count),
            purgeablePages: UInt64(info.purgeable_count),
            pageSize: UInt64(pageSize),
            totalBytes: ProcessInfo.processInfo.physicalMemory
        ) else { throw SampleError.invalidStatistics }
        return reading
    }

    private func readDisk() throws -> DiskReading {
        var info = statfs()
        let result = dataVolumeURL.path.withCString { statfs($0, &info) }
        guard result == 0 else { throw SampleError.posix(errno) }
        let volumeName = (try? dataVolumeURL.resourceValues(forKeys: [.volumeNameKey]).volumeName)
            ?? "Startup Data"
        // f_bavail is blocks available to this user now. It does not add
        // purgeable capacity or claim APFS shared space belongs to this volume.
        guard let reading = MetricCalculations.disk(
            availableBlocks: info.f_bavail,
            totalBlocks: info.f_blocks,
            blockSize: UInt64(info.f_bsize),
            volumeName: volumeName
        ) else { throw SampleError.invalidStatistics }
        return reading
    }
}

private enum SampleError: LocalizedError {
    case mach(kern_return_t)
    case posix(Int32)
    case incompleteStatistics
    case invalidStatistics

    var errorDescription: String? {
        switch self {
        case .mach(let code):
            return "System statistics unavailable (Mach error \(code))."
        case .posix(let code):
            return String(cString: strerror(code))
        case .incompleteStatistics:
            return "The system returned incomplete statistics."
        case .invalidStatistics:
            return "The system returned invalid capacity values."
        }
    }
}
