public struct Engine: FocusDeciding {
    public private(set) var config: Config
    public init(config: Config) { self.config = config }
    public mutating func observe(_ sample: PointerSample, under target: WindowTarget?, state: SystemState) -> Decision { .none }
    public mutating func tick(nowMs: UInt64, state: SystemState) -> Decision { .none }
}
