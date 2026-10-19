import AppKit
import MenuStatsCore

/// A frozen selection. Its original application handles live only as long as this value.
@MainActor
public struct AppQuitTarget: Identifiable {
    public nonisolated let id: UUID
    public nonisolated let name: String
    public nonisolated let bundlePath: String
    public nonisolated let instanceCount: Int
    fileprivate let applications: [CapturedApplication]
}

public enum AppQuitMode: Equatable, Sendable {
    case normal
    case force
}

public enum AppQuitResult: Equatable, Sendable {
    /// A quit request was accepted. This is not proof that the app has exited.
    case requested
    /// At least one original instance accepted the request and at least one rejected it.
    case partiallyRequested
    case noLongerRunning
    case failed
}

@MainActor
public final class AppQuitController {
    private let currentProcessIdentifier: pid_t
    private let ownBundleURL: URL?
    private let runningApplications: () -> [any QuitApplication]

    public init() {
        currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        ownBundleURL = Bundle.main.bundleURL.standardizedFileURL
        runningApplications = {
            NSWorkspace.shared.runningApplications.map(NativeQuitApplication.init)
        }
    }

    init(
        currentProcessIdentifier: pid_t,
        ownBundleURL: URL?,
        runningApplications: @escaping () -> [any QuitApplication]
    ) {
        self.currentProcessIdentifier = currentProcessIdentifier
        self.ownBundleURL = ownBundleURL?.standardizedFileURL
        self.runningApplications = runningApplications
    }

    /// Background entries and apps without a verifiable lifetime do not offer Quit.
    public func prepare(_ reading: AppUsageReading) -> AppQuitTarget? {
        guard reading.isApplication,
              let path = reading.bundlePath,
              path.hasPrefix("/") else { return nil }
        let bundleURL = URL(fileURLWithPath: path).standardizedFileURL
        guard bundleURL != ownBundleURL else { return nil }

        let matches = runningApplications().filter {
            $0.isRegular && !$0.isTerminated &&
            $0.processIdentifier != currentProcessIdentifier &&
            $0.bundleURL?.standardizedFileURL == bundleURL
        }
        guard !matches.isEmpty else { return nil }
        let captures = matches.compactMap { app -> CapturedApplication? in
            guard let identity = identity(of: app) else { return nil }
            return CapturedApplication(identity: identity, application: app)
        }
        // Do not offer a partially identifiable app group as a complete selection.
        guard captures.count == matches.count else { return nil }
        return AppQuitTarget(
            id: UUID(), name: reading.name, bundlePath: bundleURL.path,
            instanceCount: captures.count, applications: captures
        )
    }

    /// Both modes revalidate the frozen selection. A rejected normal request never escalates.
    public func requestQuit(_ target: AppQuitTarget, mode: AppQuitMode = .normal) -> AppQuitResult {
        let liveApplications = runningApplications()
        var requested = false
        var failed = false
        for captured in target.applications {
            guard identity(of: captured.application) == captured.identity,
                  let live = liveApplications.first(where: {
                      identity(of: $0) == captured.identity &&
                      $0.representsSameApplication(as: captured.application)
                  }),
                  identity(of: live) == captured.identity else { continue }
            if live.requestTermination(mode: mode) {
                requested = true
            } else {
                failed = true
            }
        }
        if failed { return requested ? .partiallyRequested : .failed }
        return requested ? .requested : .noLongerRunning
    }

    private func identity(of app: any QuitApplication) -> ApplicationIdentity? {
        guard app.isRegular, !app.isTerminated,
              app.processIdentifier != currentProcessIdentifier,
              let bundleURL = app.bundleURL?.standardizedFileURL,
              bundleURL != ownBundleURL,
              let executableURL = app.executableURL?.standardizedFileURL,
              let launchDate = app.launchDate else { return nil }
        return ApplicationIdentity(
            processIdentifier: app.processIdentifier, bundleURL: bundleURL,
            executableURL: executableURL, launchDate: launchDate
        )
    }
}

private struct ApplicationIdentity: Equatable {
    let processIdentifier: pid_t
    let bundleURL: URL
    let executableURL: URL
    let launchDate: Date
}

@MainActor
private struct CapturedApplication {
    let identity: ApplicationIdentity
    let application: any QuitApplication
}

/// Narrow seam for identity and request tests. Production uses only NSRunningApplication.
@MainActor
protocol QuitApplication: AnyObject {
    var processIdentifier: pid_t { get }
    var bundleURL: URL? { get }
    var executableURL: URL? { get }
    var launchDate: Date? { get }
    var isTerminated: Bool { get }
    var isRegular: Bool { get }
    func representsSameApplication(as other: any QuitApplication) -> Bool
    func requestTermination(mode: AppQuitMode) -> Bool
}

@MainActor
private final class NativeQuitApplication: QuitApplication {
    private let app: NSRunningApplication

    init(_ app: NSRunningApplication) { self.app = app }
    var processIdentifier: pid_t { app.processIdentifier }
    var bundleURL: URL? { app.bundleURL }
    var executableURL: URL? { app.executableURL }
    var launchDate: Date? { app.launchDate }
    var isTerminated: Bool { app.isTerminated }
    var isRegular: Bool { app.activationPolicy == .regular }

    func representsSameApplication(as other: any QuitApplication) -> Bool {
        guard let other = other as? NativeQuitApplication else { return false }
        return app.isEqual(other.app)
    }

    func requestTermination(mode: AppQuitMode) -> Bool {
        switch mode {
        case .normal: app.terminate()
        case .force: app.forceTerminate()
        }
    }
}
