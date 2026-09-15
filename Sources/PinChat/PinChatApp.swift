import AppKit

@main
struct PinChatApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = PinChatApplicationDelegate.shared
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class PinChatApplicationDelegate: NSObject, NSApplicationDelegate {
    static let shared = PinChatApplicationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.launch()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        AppController.shared.showCompactWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // App-owned persistence is written incrementally as state changes.
    }
}
