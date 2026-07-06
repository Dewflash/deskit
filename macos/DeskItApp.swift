import AppKit
import SwiftUI

struct AppSize: Codable, Hashable {
    let width: Double
    let height: Double
}

struct DeskItAppEntry: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let entryPath: String?
    let bridgeHandler: String?
    let storageNamespace: String
    let symbolName: String
    let accentHex: String
    let defaultPopoverSize: AppSize
}

enum DeskItRegistry {
    static func load() -> [DeskItAppEntry] {
        guard let url = Bundle.main.url(forResource: "app-registry", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let apps = try? JSONDecoder().decode([DeskItAppEntry].self, from: data),
              !apps.isEmpty else {
            return []
        }

        return apps
    }
}

@MainActor
final class DeskItState: ObservableObject {
    @Published private(set) var apps: [DeskItAppEntry]
    @Published var selectedAppID: String {
        didSet {
            defaults.set(selectedAppID, forKey: selectedAppKey)
        }
    }

    private let defaults = UserDefaults.standard
    private let selectedAppKey = "deskit.host.selectedAppID"

    init(apps: [DeskItAppEntry]) {
        self.apps = apps
        let saved = defaults.string(forKey: selectedAppKey)
        if let saved, apps.contains(where: { $0.id == saved }) {
            self.selectedAppID = saved
        } else {
            self.selectedAppID = apps.first?.id ?? ""
        }
    }

    var selectedApp: DeskItAppEntry? {
        apps.first { $0.id == selectedAppID } ?? apps.first
    }

    var selectedPopoverSize: NSSize {
        selectedApp?.popoverSize ?? NSSize(width: 420, height: 260)
    }

    func select(_ app: DeskItAppEntry) {
        selectedAppID = app.id
    }
}

extension DeskItAppEntry {
    var popoverSize: NSSize {
        NSSize(width: defaultPopoverSize.width, height: defaultPopoverSize.height)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let colorDropModel = ColorDropModel()
    private var state: DeskItState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePopover()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "DeskIt")
        appMenu.addItem(NSMenuItem(title: "Quit DeskIt", action: #selector(quit), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "lamp.desk", accessibilityDescription: "DeskIt")
            ?? DeskLampStatusIcon.image()
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.toolTip = "DeskIt"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        let apps = DeskItRegistry.load()
        let state = DeskItState(apps: apps)
        self.state = state

        popover.behavior = .transient
        popover.contentSize = state.selectedPopoverSize
        popover.contentViewController = NSHostingController(rootView: DeskItRootView(state: state, colorDropModel: colorDropModel))
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        if state?.selectedApp?.id == "colourdrop" {
            if popover.isShown {
                popover.performClose(sender)
            }
            colorDropModel.pickColor()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            resizePopoverToSelectedApp()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        if let state {
            for app in state.apps {
                let item = NSMenuItem(title: app.name, action: #selector(selectAppFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.id
                item.state = app.id == state.selectedAppID ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(title: "Quit DeskIt", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectAppFromMenu(_ sender: NSMenuItem) {
        guard let appID = sender.representedObject as? String,
              let app = state?.apps.first(where: { $0.id == appID }) else {
            return
        }

        state?.select(app)
        resizePopoverToSelectedApp()
        if app.id == "colourdrop", popover.isShown {
            popover.performClose(sender)
        }
    }

    private func resizePopoverToSelectedApp() {
        guard let state else { return }
        popover.contentSize = state.selectedPopoverSize
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

struct DeskItRootView: View {
    @ObservedObject var state: DeskItState
    @ObservedObject var colorDropModel: ColorDropModel
    @StateObject private var textCleanerModel = TextCleanerModel(defaults: UserDefaults(suiteName: "com.kevinyongcj.deskit.text-cleaner") ?? .standard)

    var body: some View {
        content
            .frame(
                width: state.selectedPopoverSize.width,
                height: state.selectedPopoverSize.height
            )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if let app = state.selectedApp {
            switch app.kind {
            case "web":
                WebModuleView(app: app)
                    .id(app.id)
            case "native":
                nativeModule(for: app)
            default:
                MissingModuleView(title: app.name, message: "Unsupported module type: \(app.kind)")
            }
        } else {
            MissingModuleView(title: "DeskIt", message: "No apps are registered. Check config/apps.json and rebuild.")
        }
    }

    @ViewBuilder
    private func nativeModule(for app: DeskItAppEntry) -> some View {
        switch app.id {
        case "colourdrop":
            ColorDropModuleView(model: colorDropModel)
        case "text-cleaner":
            TextCleanerModuleView(model: textCleanerModel)
        default:
            MissingModuleView(title: app.name, message: "Native module is registered but not implemented in DeskIt.")
        }
    }
}

struct MissingModuleView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum DeskLampStatusIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let stroke = NSBezierPath()
        stroke.lineWidth = 1.8
        stroke.lineCapStyle = .round
        stroke.lineJoinStyle = .round

        stroke.move(to: NSPoint(x: 4.4, y: 12.9))
        stroke.line(to: NSPoint(x: 9.0, y: 15.2))
        stroke.line(to: NSPoint(x: 13.2, y: 10.8))
        stroke.line(to: NSPoint(x: 8.5, y: 8.7))
        stroke.close()
        stroke.stroke()

        let arm = NSBezierPath()
        arm.lineWidth = 1.9
        arm.lineCapStyle = .round
        arm.move(to: NSPoint(x: 8.4, y: 8.7))
        arm.line(to: NSPoint(x: 7.3, y: 4.7))
        arm.stroke()

        let base = NSBezierPath()
        base.lineWidth = 1.9
        base.lineCapStyle = .round
        base.move(to: NSPoint(x: 4.4, y: 2.8))
        base.line(to: NSPoint(x: 11.0, y: 2.8))
        base.move(to: NSPoint(x: 7.3, y: 4.7))
        base.line(to: NSPoint(x: 7.3, y: 2.9))
        base.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

@main
enum DeskItMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
