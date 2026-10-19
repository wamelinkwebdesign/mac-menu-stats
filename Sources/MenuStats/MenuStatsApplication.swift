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
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatsStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: StatsPanel(
            store: store,
            openActivityMonitor: { [weak self] in self?.openActivityMonitor() },
            quit: { NSApplication.shared.terminate(nil) }
        ))

        subscription = store.$snapshot.sink { [weak self] snapshot in
            let title = StatsFormat.menuTitle(snapshot)
            self?.statusItem?.button?.title = title
            self?.statusItem?.button?.toolTip = "\(title)\nClick for details"
            self?.statusItem?.button?.setAccessibilityLabel("Menu Stats: \(title)")
        }
        store.start()

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
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
}
