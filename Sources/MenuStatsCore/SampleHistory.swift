/// A fixed-size record of recent samples. Failed samples stay as nil gaps.
public struct SampleHistory: Sendable, Equatable {
    public let capacity: Int
    public private(set) var values: [Double?] = []

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func append(_ value: Double?) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
    }
}
