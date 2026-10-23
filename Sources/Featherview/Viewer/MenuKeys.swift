import AppKit
import FeatherviewCore

/// Menus show the single keys in their shortcut column (spec "Menu commands"), but only while a menu
/// is open: a plain key equivalent left in the menu would take that letter from every text field.
@MainActor
enum MenuKeys {
    private struct Saved {
        let item: NSMenuItem
        let title: String
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let shown: MenuKey
    }

    private static var saved: [Saved] = []

    static func install() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            let menu = (note.object as? NSMenu).map(ObjectIdentifier.init)  // Sendable, unlike the note
            MainActor.assumeIsolated { if menu != nil, menu == NSApp.mainMenu.map(ObjectIdentifier.init) { begin() } }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { note in
            let menu = (note.object as? NSMenu).map(ObjectIdentifier.init)  // Sendable, unlike the note
            MainActor.assumeIsolated { if menu != nil, menu == NSApp.mainMenu.map(ObjectIdentifier.init) { restore() } }
        }
    }

    /// SwiftUI rebuilds a menu's items each time it opens, so its delegate is wrapped to apply the keys after.
    private static var proxies: [ObjectIdentifier: DelegateProxy] = [:]

    private static func begin() {
        restore()
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items {
            guard let submenu = item.submenu, let delegate = submenu.delegate, !(delegate is DelegateProxy) else { continue }
            let proxy = DelegateProxy(delegate)
            proxies[ObjectIdentifier(submenu)] = proxy
            submenu.delegate = proxy
        }
        show(menu)
    }

    fileprivate static func show(_ menu: NSMenu) {
        for item in allItems(menu) {
            if let index = saved.firstIndex(where: { $0.item === item }) {
                if item.title == saved[index].shown.title, item.keyEquivalent == saved[index].shown.key { continue }
                saved.remove(at: index)  // SwiftUI put its title and shortcut back: those are the originals now
            }
            guard let key = menuKey(item) else { continue }
            saved.append(Saved(item: item, title: item.title, key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask, shown: key))
            item.title = key.title
            item.keyEquivalent = key.key
            var modifiers: NSEvent.ModifierFlags = []
            if key.modifiers.contains(.command) { modifiers.insert(.command) }
            if key.modifiers.contains(.shift) { modifiers.insert(.shift) }
            if key.modifiers.contains(.option) { modifiers.insert(.option) }
            if key.modifiers.contains(.control) { modifiers.insert(.control) }
            item.keyEquivalentModifierMask = modifiers
        }
    }

    private static func restore() {
        for entry in saved {
            entry.item.title = entry.title
            entry.item.keyEquivalent = entry.key
            entry.item.keyEquivalentModifierMask = entry.modifiers
        }
        saved = []
    }

    /// Our items name their key in the title; macOS's own (Settings, Minimize, Full Screen) by their shortcut.
    private static func menuKey(_ item: NSMenuItem) -> MenuKey? {
        if let key = MenuKey.parse(item.title) { return key }
        let plain = { (key: String) in MenuKey(title: item.title, key: key, modifiers: []) }
        switch (item.keyEquivalent, item.keyEquivalentModifierMask) {
        case ("m", .command): return plain("m")  // Minimize
        case ("f", [.control, .command]), ("f", .function): return plain("f")  // Enter/Exit Full Screen
        // Our Settings… item (SettingsWindow), single key P (spec).
        case (",", .command): return MenuKey(title: String(localized: "Settings…"), key: "p", modifiers: [])
        default: return nil
        }
    }

    private static func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }
}

/// Passes everything to SwiftUI's delegate, then shows the keys in the items it just built.
private final class DelegateProxy: NSObject, NSMenuDelegate {
    let original: NSMenuDelegate

    init(_ original: NSMenuDelegate) { self.original = original }

    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original.responds(to: selector) }
    override func forwardingTarget(for selector: Selector!) -> Any? { original }

    func menuNeedsUpdate(_ menu: NSMenu) {
        original.menuNeedsUpdate?(menu)
        MenuKeys.show(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        original.menuWillOpen?(menu)
        MenuKeys.show(menu)
    }
}
