import Foundation

@MainActor
public final class AppCoordinator {
    public private(set) var config: Config = Config()
    public private(set) var configError: ConfigError?
    public private(set) var startError: ControllerError?
    public private(set) var watchingTrust = false

    private let controller: any FocusControlling
    private let isTrusted: @MainActor () -> Bool

    public init(controller: any FocusControlling, isTrusted: @escaping @MainActor () -> Bool) {
        self.controller = controller
        self.isTrusted = isTrusted
    }

    public func load(_ result: Result<Config, ConfigError>) {
        switch result {
        case .failure(let error):
            configError = error
            controller.stop()
            watchingTrust = !isTrusted()
        case .success(let loadedConfig):
            config = loadedConfig
            configError = nil
            controller.apply(loadedConfig)
            tryStart()
            watchingTrust = !isTrusted() || startError == .accessibilityNotTrusted
        }
    }

    public func trustTick() {
        guard watchingTrust else { return }
        guard isTrusted() else { return }
        watchingTrust = false
        if configError == nil && !controller.isRunning {
            tryStart()
        }
    }

    public func update(_ change: (inout Config) -> Void) {
        change(&config)
        controller.apply(config)
    }

    private func tryStart() {
        do {
            try controller.start()
            startError = nil
        } catch let error as ControllerError {
            startError = error
        } catch {
            startError = .eventTapFailed
        }
    }
}
