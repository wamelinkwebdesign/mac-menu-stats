import Darwin

/// Reads 64-bit interface byte counters from the routing sysctl.
enum NetworkCounterReader {
    // Wi-Fi and wired Ethernet both report IFT_ETHER. Loopback, VPN tunnels,
    // and bridges are excluded so the same traffic is not counted twice.
    private static let etherType: UInt8 = 0x06

    static func read() throws -> [UInt32: NetworkCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else {
            throw SampleError.posix(errno)
        }
        // Interfaces can appear between the size query and the read.
        length += length / 8 + 1_024
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            throw SampleError.posix(errno)
        }
        return try parse(buffer.prefix(length))
    }

    static func parse(_ bytes: ArraySlice<UInt8>) throws -> [UInt32: NetworkCounters] {
        var counters: [UInt32: NetworkCounters] = [:]
        try Array(bytes).withUnsafeBytes { raw in
            let headerSize = MemoryLayout<if_msghdr>.size
            var offset = 0
            while offset + headerSize <= raw.count {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= raw.count else {
                    throw SampleError.incompleteStatistics
                }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if info.ifm_data.ifi_type == etherType {
                        counters[UInt32(info.ifm_index)] = NetworkCounters(
                            bytesIn: info.ifm_data.ifi_ibytes,
                            bytesOut: info.ifm_data.ifi_obytes
                        )
                    }
                }
                offset += messageLength
            }
        }
        return counters
    }
}
