import Cocoa

enum MenuBuilders {
    // A "Foo ▸" row opening a submenu of mutually-exclusive options, checkmark on `selected`.
    // Each option carries its key in representedObject so the @objc action can read it back.
    static func choiceSubmenu(title: String,
                              choices: [(label: String, key: String)],
                              selected: String,
                              action: Selector,
                              target: AnyObject) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for choice in choices {
            let it = NSMenuItem(title: choice.label, action: action, keyEquivalent: "")
            it.target = target
            it.representedObject = choice.key
            it.state = (choice.key == selected) ? .on : .off
            sub.addItem(it)
        }
        parent.submenu = sub
        return parent
    }

    // A toggle WITHOUT a left checkmark gutter: state stays .off so macOS reserves no gutter
    // (which would indent every item). The indicator is a native right-aligned NSMenuItemBadge
    // (macOS 14+) so it lines up with the system's own right-edge elements (⌘Q, submenu arrows).
    // `rightText` is optional fixed text (e.g. "1m+"); a "✓" is added when on. Older macOS falls
    // back to a standard left checkmark.
    static func rightToggle(title: String,
                            rightText: String?,
                            checked: Bool,
                            action: Selector,
                            target: AnyObject) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = target
        let badge = [rightText, checked ? "✓" : nil].compactMap { $0 }.joined(separator: " ")
        if #available(macOS 14.0, *) {
            if !badge.isEmpty { it.badge = NSMenuItemBadge(string: badge) }
        } else {
            it.state = checked ? .on : .off
            if let rightText { it.title = "\(title) (\(rightText))" }
        }
        return it
    }
}
