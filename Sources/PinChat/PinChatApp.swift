import AppKit

@main
struct PinChatApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = PinChatApplicationDelegate.shared
        application.delegate = delegate
        application.mainMenu = PinChatMenuFactory.makeMainMenu()
        application.run()
    }
}

@MainActor
enum PinChatMenuFactory {
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "PinChat")
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(editMenuItem())
        return mainMenu
    }

    private static func applicationMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "PinChat")
        menu.addItem(
            menuItem(
                title: "关于 PinChat",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                title: "隐藏 PinChat",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
        )
        menu.addItem(
            menuItem(
                title: "隐藏其他应用",
                action: #selector(NSApplication.hideOtherApplications(_:)),
                keyEquivalent: "h",
                modifiers: [.command, .option]
            )
        )
        menu.addItem(
            menuItem(
                title: "显示全部",
                action: #selector(NSApplication.unhideAllApplications(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                title: "退出 PinChat",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        root.submenu = menu
        return root
    }

    private static func editMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        menu.autoenablesItems = true
        menu.addItem(
            menuItem(
                title: "撤销",
                action: Selector(("undo:")),
                keyEquivalent: "z"
            )
        )
        menu.addItem(
            menuItem(
                title: "重做",
                action: Selector(("redo:")),
                keyEquivalent: "z",
                modifiers: [.command, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                title: "剪切",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            )
        )
        menu.addItem(
            menuItem(
                title: "复制",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
        )
        menu.addItem(
            menuItem(
                title: "粘贴",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        menu.addItem(
            menuItem(
                title: "粘贴并匹配样式",
                action: #selector(NSTextView.pasteAsPlainText(_:)),
                keyEquivalent: "v",
                modifiers: [.command, .option, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                title: "全选",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        root.submenu = menu
        return root
    }

    private static func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : modifiers
        return item
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
