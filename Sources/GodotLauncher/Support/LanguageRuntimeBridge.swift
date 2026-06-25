import AppKit
import SwiftUI

enum LanguageWindowRole: Sendable {
    case main
    case settings
}

struct LanguageRuntimeBridge: NSViewRepresentable {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    let language: AppLanguage
    let role: LanguageWindowRole

    func makeNSView(context: Context) -> LanguageBridgeView {
        LanguageBridgeView(
            language: language,
            role: role,
            openSettings: { openSettings() },
            openMainWindow: { openWindow(id: AppConstants.mainWindowID) }
        )
    }

    func updateNSView(_ nsView: LanguageBridgeView, context: Context) {
        nsView.language = language
        nsView.role = role
        nsView.openSettings = { openSettings() }
        nsView.openMainWindow = { openWindow(id: AppConstants.mainWindowID) }
        nsView.applyLanguage()
    }
}

final class LanguageBridgeView: NSView {
    var language: AppLanguage
    var role: LanguageWindowRole
    var openSettings: @MainActor () -> Void
    var openMainWindow: @MainActor () -> Void
    private var titleObservation: NSKeyValueObservation?

    init(
        language: AppLanguage,
        role: LanguageWindowRole,
        openSettings: @escaping @MainActor () -> Void,
        openMainWindow: @escaping @MainActor () -> Void
    ) {
        self.language = language
        self.role = role
        self.openSettings = openSettings
        self.openMainWindow = openMainWindow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        titleObservation?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        titleObservation?.invalidate()
        if let window {
            titleObservation = window.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.enforceWindowTitle() }
            }
        }
        applyLanguage()
    }

    func applyLanguage() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.enforceWindowTitle()
            ApplicationMenuLocalizer.openSettingsAction = self.openSettings
            ApplicationMenuLocalizer.openMainWindowAction = self.openMainWindow
            ApplicationMenuLocalizer.apply()

            // SwiftUI can rebuild its Commands menu after the representable updates.
            DispatchQueue.main.async {
                self.enforceWindowTitle()
                ApplicationMenuLocalizer.apply()
            }
            for delay in [0.15, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.enforceWindowTitle()
                    ApplicationMenuLocalizer.apply()
                }
            }
        }
    }

    private func enforceWindowTitle() {
        let title = role == .main
            ? ApplicationMenuLocalizer.productName
            : L10n.tr("settings_window_title")
        if window?.title != title {
            window?.title = title
        }
    }
}

@MainActor
enum ApplicationMenuLocalizer {
    static let productName = AppConstants.displayName
    static var openSettingsAction: (@MainActor () -> Void)?
    static var openMainWindowAction: (@MainActor () -> Void)?
    private static var trackingObserver: NSObjectProtocol?
    private static var applicationMenuDelegate: ApplicationMenuDelegateProxy?

    private struct Translation {
        let key: String
        let aliases: Set<String>
    }

    private struct MenuReference: @unchecked Sendable {
        let menu: NSMenu
    }

    private static let translations: [Translation] = [
        Translation(key: "menu_settings", aliases: ["Settings", "Preferences", "设置", "偏好设置"]),
        Translation(key: "menu_services", aliases: ["Services", "服务"]),
        Translation(key: "menu_hide_others", aliases: ["Hide Others", "隐藏其他"]),
        Translation(key: "menu_show_all", aliases: ["Show All", "全部显示"]),
        Translation(key: "menu_new_window", aliases: ["New Window", "新建窗口"]),
        Translation(key: "menu_close", aliases: ["Close", "关闭"]),
        Translation(key: "menu_close_all", aliases: ["Close All", "全部关闭"]),
        Translation(key: "menu_undo", aliases: ["Undo", "撤销"]),
        Translation(key: "menu_redo", aliases: ["Redo", "重做"]),
        Translation(key: "menu_cut", aliases: ["Cut", "剪切"]),
        Translation(key: "menu_copy", aliases: ["Copy", "拷贝", "复制"]),
        Translation(key: "menu_paste", aliases: ["Paste", "粘贴"]),
        Translation(key: "menu_paste_match_style", aliases: ["Paste and Match Style", "粘贴并匹配样式"]),
        Translation(key: "menu_delete", aliases: ["Delete", "删除"]),
        Translation(key: "menu_select_all", aliases: ["Select All", "全选"]),
        Translation(key: "menu_find", aliases: ["Find", "查找"]),
        Translation(key: "menu_spelling_grammar", aliases: ["Spelling and Grammar", "拼写和语法"]),
        Translation(key: "menu_substitutions", aliases: ["Substitutions", "替换"]),
        Translation(key: "menu_transformations", aliases: ["Transformations", "转换"]),
        Translation(key: "menu_speech", aliases: ["Speech", "语音"]),
        Translation(key: "menu_start_dictation", aliases: ["Start Dictation", "开始听写"]),
        Translation(key: "menu_emoji_symbols", aliases: ["Emoji & Symbols", "表情与符号"]),
        Translation(key: "menu_writing_tools", aliases: ["Writing Tools", "写作工具"]),
        Translation(key: "menu_autofill", aliases: ["AutoFill", "自动填充"]),
        Translation(key: "menu_show_toolbar", aliases: ["Show Toolbar", "显示工具栏"]),
        Translation(key: "menu_hide_toolbar", aliases: ["Hide Toolbar", "隐藏工具栏"]),
        Translation(key: "menu_customize_toolbar", aliases: ["Customize Toolbar", "自定工具栏"]),
        Translation(key: "menu_show_sidebar", aliases: ["Show Sidebar", "显示边栏"]),
        Translation(key: "menu_hide_sidebar", aliases: ["Hide Sidebar", "隐藏边栏"]),
        Translation(key: "menu_toggle_sidebar", aliases: ["Toggle Sidebar", "切换边栏"]),
        Translation(key: "menu_enter_full_screen", aliases: ["Enter Full Screen", "进入全屏幕"]),
        Translation(key: "menu_exit_full_screen", aliases: ["Exit Full Screen", "退出全屏幕"]),
        Translation(key: "menu_minimize", aliases: ["Minimize", "最小化"]),
        Translation(key: "menu_zoom", aliases: ["Zoom", "缩放"]),
        Translation(key: "menu_bring_all_to_front", aliases: ["Bring All to Front", "前置全部窗口"])
    ]

    private static let actionKeys: [String: String] = [
        "hide:": "menu_hide_app",
        "hideOtherApplications:": "menu_hide_others",
        "unhideAllApplications:": "menu_show_all",
        "terminate:": "menu_quit",
        "undo:": "menu_undo",
        "redo:": "menu_redo",
        "cut:": "menu_cut",
        "copy:": "menu_copy",
        "paste:": "menu_paste",
        "delete:": "menu_delete",
        "selectAll:": "menu_select_all",
        "performClose:": "menu_close",
        "minimize:": "menu_minimize",
        "zoom:": "menu_zoom",
        "arrangeInFront:": "menu_bring_all_to_front",
        "toggleFullScreen:": "menu_enter_full_screen"
    ]

    static func apply() {
        installTrackingObserverIfNeeded()
        guard let mainMenu = NSApp.mainMenu else { return }

        if let applicationItem = mainMenu.items.first(where: { item in
            normalized(item.title) == productName || isApplicationMenu(item.submenu)
        }) {
            applicationItem.title = productName
            applicationItem.submenu?.title = productName
            installApplicationMenuDelegate(on: applicationItem.submenu)
            localizeApplicationMenu(applicationItem.submenu)
        }

        localizeTopLevelMenus(mainMenu)
        for item in mainMenu.items {
            localizeRecursively(item.submenu)
        }
    }

    private static func installTrackingObserverIfNeeded() {
        guard trackingObserver == nil else { return }
        trackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            let reference = MenuReference(menu: menu)
            Task { @MainActor in
                localizeMenuWhenTrackingBegins(reference.menu)
            }
        }
    }

    private static func localizeMenuWhenTrackingBegins(_ menu: NSMenu) {
        if isApplicationMenu(menu) {
            localizeApplicationMenu(menu)
        }
        localizeRecursively(menu)
    }

    private static func installApplicationMenuDelegate(on menu: NSMenu?) {
        guard let menu, menu.delegate !== applicationMenuDelegate else { return }
        let proxy = ApplicationMenuDelegateProxy(original: menu.delegate)
        applicationMenuDelegate = proxy
        menu.delegate = proxy
    }

    private static func localizeTopLevelMenus(_ menu: NSMenu) {
        let items = menu.items
        for item in items {
            switch normalized(item.title) {
            case "File", "文件": item.title = L10n.tr("menu_file")
            case "Edit", "编辑": item.title = L10n.tr("menu_edit")
            case "View", "显示": item.title = L10n.tr("menu_view")
            case "Releases", "版本": item.title = L10n.tr("versions")
            case "Window", "窗口": item.title = L10n.tr("menu_window")
            case "Help", "帮助": item.title = L10n.tr("menu_help")
            default: break
            }
            item.submenu?.title = item.title
        }

        if let windowMenu = NSApp.windowsMenu,
           let item = items.first(where: { $0.submenu === windowMenu }) {
            item.title = L10n.tr("menu_window")
            windowMenu.title = item.title
        }
        if let helpMenu = NSApp.helpMenu,
           let item = items.first(where: { $0.submenu === helpMenu }) {
            item.title = L10n.tr("menu_help")
            helpMenu.title = item.title
        }

    }

    fileprivate static func localizeApplicationMenu(_ menu: NSMenu?) {
        guard let menu else { return }
        let visibleItems = menu.items.filter { !$0.isSeparatorItem }
        visibleItems.first?.title = L10n.tr("menu_about", productName)

        for item in visibleItems {
            let action = item.action.map(NSStringFromSelector) ?? ""
            let title = normalized(item.title)
            if item.keyEquivalent == "," || action.localizedCaseInsensitiveContains("settings") || action.localizedCaseInsensitiveContains("preferences") || ["Settings", "Preferences", "设置", "偏好设置"].contains(title) {
                item.title = L10n.tr("menu_settings")
            } else if item.submenu === NSApp.servicesMenu {
                item.title = L10n.tr("menu_services")
                item.submenu?.title = item.title
            } else if action == "hide:" {
                item.title = L10n.tr("menu_hide_app", productName)
            } else if action == "terminate:" || item.keyEquivalent == "q" {
                item.title = L10n.tr("menu_quit", productName)
            }
        }
        applicationMenuDelegate?.stabilize(items: visibleItems.filter {
            $0.action != nil && $0.submenu == nil
        })
    }

    private static func isApplicationMenu(_ menu: NSMenu?) -> Bool {
        guard let menu else { return false }
        return menu.items.contains { item in
            let title = normalized(item.title)
            return title.hasPrefix("About ") || title.hasPrefix("关于")
                || title.hasPrefix("Quit ") || title.hasPrefix("退出Godot")
                || title.hasPrefix("退出 Godot")
        }
    }

    fileprivate static func localizeRecursively(_ menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items where !item.isSeparatorItem {
            let title = normalized(item.title)
            let action = item.action.map(NSStringFromSelector) ?? ""
            if title.contains(productName), (title.hasPrefix("New") || title.hasPrefix("新")) {
                item.title = L10n.tr("menu_new_app_window", productName)
                applicationMenuDelegate?.stabilize(item: item)
            } else if title.contains(productName), (title.hasSuffix("Help") || title.hasSuffix("帮助")) {
                item.title = L10n.tr("menu_app_help", productName)
                applicationMenuDelegate?.stabilize(item: item)
            } else if title.hasPrefix("About ") || title.hasPrefix("关于") {
                item.title = L10n.tr("menu_about", productName)
            } else if action == "hide:" || title.hasPrefix("隐藏Godot") || title.hasPrefix("隐藏 Godot") {
                item.title = L10n.tr("menu_hide_app", productName)
            } else if title.hasPrefix("Quit and Keep Windows") || title.hasPrefix("退出并保留窗口") {
                item.title = L10n.tr("menu_quit_keep_windows")
            } else if title.hasPrefix("Quit ") || title.hasPrefix("退出Godot") || title.hasPrefix("退出 Godot") {
                item.title = L10n.tr("menu_quit", productName)
            } else if action == "terminate:", item.isAlternate {
                item.title = L10n.tr("menu_quit_keep_windows")
            } else if let key = actionKeys[action] {
                if key == "menu_enter_full_screen",
                   ["Exit Full Screen", "退出全屏幕"].contains(title) {
                    item.title = L10n.tr("menu_exit_full_screen")
                } else {
                    item.title = formattedTitle(for: key)
                }
            } else if let translation = translations.first(where: { $0.aliases.contains(title) }) {
                item.title = L10n.tr(translation.key)
            }
            localizeRecursively(item.submenu)
        }
    }

    private static func formattedTitle(for key: String) -> String {
        switch key {
        case "menu_hide_app", "menu_quit": L10n.tr(key, productName)
        default: L10n.tr(key)
        }
    }

    private static func normalized(_ title: String) -> String {
        title
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class ApplicationMenuDelegateProxy: NSObject, NSMenuDelegate {
    private struct ForwardedAction {
        let target: AnyObject?
        let action: Selector
    }

    weak var original: NSMenuDelegate?
    private var forwardedActions: [ObjectIdentifier: ForwardedAction] = [:]

    init(original: NSMenuDelegate?) {
        self.original = original
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        original?.menuNeedsUpdate?(menu)
        localize(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        original?.menuWillOpen?(menu)
        localize(menu)
        DispatchQueue.main.async { self.localize(menu) }
    }

    func menuDidClose(_ menu: NSMenu) {
        original?.menuDidClose?(menu)
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        original?.menu?(menu, willHighlight: item)
    }

    private func localize(_ menu: NSMenu) {
        ApplicationMenuLocalizer.localizeApplicationMenu(menu)
        ApplicationMenuLocalizer.localizeRecursively(menu)
    }

    func stabilize(items: [NSMenuItem]) {
        for item in items { stabilize(item: item) }
    }

    func stabilize(item: NSMenuItem) {
        guard item.target !== self, let action = item.action else { return }
        forwardedActions[ObjectIdentifier(item)] = ForwardedAction(
            target: item.target,
            action: action
        )
        item.target = self
        item.action = #selector(performForwardedAction(_:))
    }

    @objc private func performForwardedAction(_ sender: NSMenuItem) {
        guard let forwarding = forwardedActions[ObjectIdentifier(sender)] else { return }
        if sender.keyEquivalent == ",", let openSettings = ApplicationMenuLocalizer.openSettingsAction {
            openSettings()
            return
        }
        if sender.keyEquivalent == "n", let openMainWindow = ApplicationMenuLocalizer.openMainWindowAction {
            openMainWindow()
            return
        }

        switch NSStringFromSelector(forwarding.action) {
        case "orderFrontStandardAboutPanel:":
            NSApp.orderFrontStandardAboutPanel(sender)
            return
        case "hide:":
            NSApp.hide(sender)
            return
        case "hideOtherApplications:":
            NSApp.hideOtherApplications(sender)
            return
        case "unhideAllApplications:":
            NSApp.unhideAllApplications(sender)
            return
        case "terminate:":
            NSApp.terminate(sender)
            return
        default:
            break
        }

        sender.target = forwarding.target
        sender.action = forwarding.action
        defer {
            sender.target = self
            sender.action = #selector(performForwardedAction(_:))
        }
        NSApp.sendAction(forwarding.action, to: forwarding.target, from: sender)
    }
}
