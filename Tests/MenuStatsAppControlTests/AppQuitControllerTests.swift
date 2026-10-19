import XCTest
import MenuStatsCore
@testable import MenuStatsAppControl

@MainActor
final class AppQuitControllerTests: XCTestCase {
    func testPrepareDoesNotQuitUntilRequested() throws {
        let app = FakeApplication()
        let controller = controller(apps: { [app] })
        let target = try XCTUnwrap(controller.prepare(reading()))
        XCTAssertEqual(target.name, "Browser")
        XCTAssertEqual(target.instanceCount, 1)
        XCTAssertEqual(app.quitRequests, 0)
        XCTAssertEqual(controller.requestQuit(target), .requested)
        XCTAssertEqual(app.quitRequests, 1)
        XCTAssertEqual(app.requestedModes, [.normal])
        // Request acceptance is not proof that the app exited.
        XCTAssertFalse(app.isTerminated)
    }

    func testRequiresExactStandardizedBundlePathNotAppName() throws {
        let other = FakeApplication(bundle: "/Elsewhere/Browser.app")
        let expected = FakeApplication()
        let controller = controller(apps: { [other, expected] })
        let target = try XCTUnwrap(controller.prepare(reading(path: "/Applications/./Browser.app")))
        XCTAssertEqual(controller.requestQuit(target), .requested)
        XCTAssertEqual(other.quitRequests, 0)
        XCTAssertEqual(expected.quitRequests, 1)
    }

    func testStandaloneHelpersSelfAndTerminatedAppsAreIneligible() {
        let helper = FakeApplication()
        helper.isRegular = false
        let terminated = FakeApplication()
        terminated.isTerminated = true
        let selfPID = FakeApplication(pid: 999)
        let selfBundle = FakeApplication(bundle: "/Applications/Menu Stats.app")
        let controller = controller(apps: { [helper, terminated, selfPID, selfBundle] })
        XCTAssertNil(controller.prepare(reading()))
        XCTAssertNil(controller.prepare(reading(path: "/Applications/Menu Stats.app")))
        XCTAssertNil(controller.prepare(reading(isApplication: false)))
        XCTAssertNil(controller.prepare(reading(path: nil)))
        XCTAssertNil(controller.prepare(reading(path: "relative/Browser.app")))
        XCTAssertTrue([helper, terminated, selfPID, selfBundle].allSatisfy { $0.quitRequests == 0 })
    }

    func testUnverifiableLifetimeDisablesWholeSelection() {
        let valid = FakeApplication()
        let missingDate = FakeApplication(pid: 2)
        missingDate.launchDate = nil
        let controller = controller(apps: { [valid, missingDate] })
        XCTAssertNil(controller.prepare(reading()))
        missingDate.launchDate = Date(timeIntervalSince1970: 10)
        missingDate.executableURL = nil
        XCTAssertNil(controller.prepare(reading()))
    }

    func testExitedSelectionDoesNotQuitRelaunchedAppOrReusedPID() throws {
        let original = FakeApplication()
        var live = [original]
        let controller = controller(apps: { live })
        let target = try XCTUnwrap(controller.prepare(reading()))
        original.isTerminated = true
        let replacement = FakeApplication()
        replacement.launchDate = Date(timeIntervalSince1970: 20)
        live = [replacement]
        for mode in [AppQuitMode.normal, .force] {
            XCTAssertEqual(controller.requestQuit(target, mode: mode), .noLongerRunning)
        }
        XCTAssertEqual(replacement.quitRequests, 0)
        XCTAssertEqual(original.quitRequests, 0)
    }

    func testNativeObjectIdentityIsRequiredEvenWhenMetadataMatches() throws {
        let original = FakeApplication()
        var live = [original]
        let controller = controller(apps: { live })
        let target = try XCTUnwrap(controller.prepare(reading()))
        let replacement = FakeApplication()
        live = [replacement]
        for mode in [AppQuitMode.normal, .force] {
            XCTAssertEqual(controller.requestQuit(target, mode: mode), .noLongerRunning)
        }
        XCTAssertEqual(replacement.quitRequests, 0)
    }

    func testRechecksExecutableAndEligibilityAtConfirmation() throws {
        let app = FakeApplication()
        let controller = controller(apps: { [app] })
        let target = try XCTUnwrap(controller.prepare(reading()))
        app.executableURL = URL(fileURLWithPath: "/Applications/Browser.app/Contents/MacOS/Replaced")
        for mode in [AppQuitMode.normal, .force] {
            XCTAssertEqual(controller.requestQuit(target, mode: mode), .noLongerRunning)
        }
        XCTAssertEqual(app.quitRequests, 0)

        let changedTarget = try XCTUnwrap(controller.prepare(reading()))
        app.isRegular = false
        for mode in [AppQuitMode.normal, .force] {
            XCTAssertEqual(controller.requestQuit(changedTarget, mode: mode), .noLongerRunning)
        }
        XCTAssertEqual(app.quitRequests, 0)
    }

    func testQuitsOnlyCapturedInstancesDespiteNewInstanceAndReranking() throws {
        let first = FakeApplication(pid: 1)
        let second = FakeApplication(pid: 2)
        var live = [first, second]
        let controller = controller(apps: { live })
        let target = try XCTUnwrap(controller.prepare(reading()))
        let newInstance = FakeApplication(pid: 3)
        let otherApp = FakeApplication(pid: 4, bundle: "/Applications/Editor.app")
        live = [otherApp, newInstance, second, first]
        XCTAssertEqual(target.instanceCount, 2)
        XCTAssertEqual(controller.requestQuit(target), .requested)
        XCTAssertEqual(first.quitRequests, 1)
        XCTAssertEqual(second.quitRequests, 1)
        XCTAssertEqual(newInstance.quitRequests, 0)
        XCTAssertEqual(otherApp.quitRequests, 0)
    }

    func testRejectedRequestReportsFailureWithoutForceQuitFallback() throws {
        let app = FakeApplication()
        app.acceptsRequest = false
        let controller = controller(apps: { [app] })
        let target = try XCTUnwrap(controller.prepare(reading()))
        XCTAssertEqual(controller.requestQuit(target), .failed)
        XCTAssertEqual(app.quitRequests, 1)
        XCTAssertEqual(app.requestedModes, [.normal])
    }

    func testExplicitForceDispatchesOnlyForceRequest() throws {
        let app = FakeApplication()
        let controller = controller(apps: { [app] })
        let target = try XCTUnwrap(controller.prepare(reading()))
        XCTAssertTrue(app.requestedModes.isEmpty)
        XCTAssertEqual(controller.requestQuit(target, mode: .force), .requested)
        XCTAssertEqual(app.requestedModes, [.force])
        // The native result reports request acceptance, not observed termination.
        XCTAssertFalse(app.isTerminated)
    }

    func testFailedForceRequestReportsFailureWithoutRetry() throws {
        let app = FakeApplication()
        app.acceptsRequest = false
        let controller = controller(apps: { [app] })
        let target = try XCTUnwrap(controller.prepare(reading()))
        XCTAssertEqual(controller.requestQuit(target, mode: .force), .failed)
        XCTAssertEqual(app.requestedModes, [.force])
    }

    func testMixedInstanceResponsesReportPartialRequest() throws {
        for mode in [AppQuitMode.normal, .force] {
            let accepting = FakeApplication(pid: 1)
            let rejecting = FakeApplication(pid: 2)
            rejecting.acceptsRequest = false
            let controller = controller(apps: { [accepting, rejecting] })
            let target = try XCTUnwrap(controller.prepare(reading()))
            XCTAssertEqual(controller.requestQuit(target, mode: mode), .partiallyRequested)
            XCTAssertEqual(accepting.requestedModes, [mode])
            XCTAssertEqual(rejecting.requestedModes, [mode])
        }
    }

    private func controller(apps: @escaping () -> [any QuitApplication]) -> AppQuitController {
        AppQuitController(
            currentProcessIdentifier: 999,
            ownBundleURL: URL(fileURLWithPath: "/Applications/Menu Stats.app"),
            runningApplications: apps
        )
    }

    private func reading(
        path: String? = "/Applications/Browser.app", isApplication: Bool = true
    ) -> AppUsageReading {
        AppUsageReading(id: "test", name: "Browser", bundlePath: path,
                        memoryBytes: 100, isApplication: isApplication)
    }
}

@MainActor
private final class FakeApplication: QuitApplication {
    let processIdentifier: pid_t
    var bundleURL: URL?
    var executableURL: URL?
    var launchDate: Date? = Date(timeIntervalSince1970: 10)
    var isTerminated = false
    var isRegular = true
    var requestedModes: [AppQuitMode] = []
    var quitRequests: Int { requestedModes.count }
    var acceptsRequest = true

    init(pid: pid_t = 1, bundle: String = "/Applications/Browser.app") {
        processIdentifier = pid
        bundleURL = URL(fileURLWithPath: bundle)
        executableURL = URL(fileURLWithPath: bundle + "/Contents/MacOS/App")
    }

    func representsSameApplication(as other: any QuitApplication) -> Bool { self === other }
    func requestTermination(mode: AppQuitMode) -> Bool {
        requestedModes.append(mode)
        return acceptsRequest
    }
}
