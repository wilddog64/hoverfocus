public struct RecentCache<Key: Hashable, Value> {
    private let capacity: Int
    private var values: [Key: Value] = [:]
    private var recency: [Key] = []

    public init(capacity: Int) {
        precondition(capacity >= 1)
        self.capacity = capacity
    }

    public var count: Int { values.count }

    public mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        recency.removeAll { $0 == key }
        recency.append(key)
        return value
    }

    public mutating func set(_ value: Value, for key: Key) {
        if values[key] == nil && values.count == capacity {
            let oldest = recency.removeFirst()
            values.removeValue(forKey: oldest)
        } else {
            recency.removeAll { $0 == key }
        }
        values[key] = value
        recency.append(key)
    }
}
