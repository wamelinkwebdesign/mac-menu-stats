import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var isAvailable = false
    @Published private(set) var initializationError: String?
    @Published private(set) var availableUpdateVersion: String?

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    var willShowUpdateUI: (() -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var hasAttemptedStart = false

    override init() {
        super.init()

        guard Bundle.main.bundleURL.pathExtension == "app" else {
            initializationError = "Updates are available in the packaged Menu Stats app."
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard !hasAttemptedStart, let controller else { return }
        hasAttemptedStart = true
        do {
            try controller.updater.start()
            isAvailable = true
        } catch {
            initializationError = "Updates could not start: \(error.localizedDescription)"
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isAvailable, let controller else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard isAvailable, canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            willShowUpdateUI?()
        } else {
            availableUpdateVersion = update.displayVersionString
        }
    }

    func standardUserDriverWillShowModalAlert() {
        willShowUpdateUI?()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableUpdateVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableUpdateVersion = nil
    }
}
