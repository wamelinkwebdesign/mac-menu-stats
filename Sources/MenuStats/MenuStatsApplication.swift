import AppKit
import Combine
import SwiftUI

@main
enum MenuStatsApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = StatsStore()
    private let updates = UpdateController()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.willShowUpdateUI = { [weak self] in self?.popover.performClose(nil) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.autosaveName = "MenuStatsStatusItem"

        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.title = StatsFormat.menuTitle(nil)
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Menu Stats: taking first reading")
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: StatsPanel(
            store: store,
            updates: updates,
            checkForUpdates: { [weak self] in self?.checkForUpdates() },
            openActivityMonitor: { [weak self] in self?.openActivityMonitor() },
            quit: { NSApplication.shared.terminate(nil) }
        ))

        subscription = store.$snapshot.combineLatest(updates.$availableUpdateVersion).sink { [weak self] snapshot, updateVersion in
            let title = StatsFormat.menuTitle(snapshot) + (updateVersion == nil ? "" : "  ↑")
            let detail = updateVersion.map { "Menu Stats \($0) is available. Click to update." } ?? "Click for details"
            self?.statusItem?.button?.title = title
            self?.statusItem?.button?.toolTip = "\(title)\n\(detail)"
            self?.statusItem?.button?.setAccessibilityLabel("Menu Stats: \(title). \(detail)")
        }
        store.start()
        updates.start()

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func popoverWillShow(_ notification: Notification) {
        store.setPanelVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        store.setPanelVisible(false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func openActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Activity Monitor could not open"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
        popover.performClose(nil)
    }

    private func checkForUpdates() {
        popover.performClose(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        updates.checkForUpdates()
    }
}
