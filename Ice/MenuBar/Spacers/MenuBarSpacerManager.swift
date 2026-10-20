//
//  MenuBarSpacerManager.swift
//  Ice
//

import Cocoa
import DragonKit
import Combine
import OSLog

struct MenuBarSpacer: Codable, Hashable, Identifiable {
    static let autosaveNamePrefix = "Ice.Spacer."

    /// How a separator is drawn in the menu bar.
    enum Style: String, Codable, CaseIterable, Identifiable {
        /// Empty space of a set width.
        case blank
        /// A thin vertical line centered in a set width.
        case line
        /// Custom text or emoji, sized to fit.
        case text

        var id: String { rawValue }

        @MainActor var localized: String {
            switch self {
            case .blank: L("app.layout.spacer.style.blank")
            case .line: L("app.layout.spacer.style.line")
            case .text: L("app.layout.spacer.style.text")
            }
        }
    }

    static let widthRange: ClosedRange<Double> = 4...80
    static let thicknessRange: ClosedRange<Double> = 1...3

    var id: UUID
    var name: String
    var width: Double
    var style: Style = .line
    var text: String = "•"
    var thickness: Double = 1

    var autosaveName: String {
        Self.autosaveNamePrefix + id.uuidString
    }
}

extension MenuBarSpacer {
    private enum CodingKeys: String, CodingKey {
        case id, name, width, style, text, thickness
    }

    /// Decodes a separator, treating ones saved before styles existed as blank space.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        width = try container.decode(Double.self, forKey: .width)
        style = try container.decodeIfPresent(Style.self, forKey: .style) ?? .blank
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? "•"
        thickness = try container.decodeIfPresent(Double.self, forKey: .thickness) ?? 1
    }
}

@MainActor
final class MenuBarSpacerManager: ObservableObject {
    @Published private(set) var spacers = [MenuBarSpacer]()

    @MainActor
    private final class SpacerStatusItem {
        let statusItem: NSStatusItem

        init(spacer: MenuBarSpacer, manager: MenuBarSpacerManager) {
            self.statusItem = NSStatusBar.system.statusItem(withLength: spacer.width)
            self.statusItem.autosaveName = spacer.autosaveName
            update(with: spacer, manager: manager)
        }

        deinit {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        func update(with spacer: MenuBarSpacer, manager: MenuBarSpacerManager) {
            guard let button = statusItem.button else {
                return
            }
            button.title = ""
            button.image = nil
            button.toolTip = spacer.name
            switch spacer.style {
            case .blank:
                statusItem.length = spacer.width
            case .line:
                statusItem.length = spacer.width
                button.image = Self.lineImage(width: spacer.width, thickness: spacer.thickness)
                button.imagePosition = .imageOnly
            case .text:
                statusItem.length = NSStatusItem.variableLength
                button.title = spacer.text
            }
            // Clicking a separator opens its menu: change the style, open Settings, or delete it.
            statusItem.menu = manager.makeMenu(for: spacer)
        }

        /// A thin vertical line, drawn as a dimmed template image so it follows the menu bar tint.
        private static func lineImage(width: CGFloat, thickness: CGFloat) -> NSImage {
            let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { rect in
                NSColor.black.withAlphaComponent(0.6).setFill()
                let line = NSRect(x: ((rect.width - thickness) / 2).rounded(), y: 1.5, width: thickness, height: 13)
                NSBezierPath(rect: line).fill()
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    /// A menu item that runs a closure when chosen.
    private final class ActionMenuItem: NSMenuItem {
        private let handler: () -> Void

        init(title: String, handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(run), keyEquivalent: "")
            self.target = self
        }

        @available(*, unavailable)
        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func run() {
            handler()
        }
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var storage = [MenuBarSpacer.ID: SpacerStatusItem]()
    private var cancellables = Set<AnyCancellable>()
    private weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        syncStatusItems()
        configureCancellables()
    }

    func createSpacer() {
        let spacer = MenuBarSpacer(
            id: UUID(),
            name: String(format: L("app.layout.spacerName"), spacers.count + 1),
            width: 12
        )
        spacers.append(spacer)
    }

    func deleteSpacer(_ spacer: MenuBarSpacer) {
        spacers.removeAll { $0.id == spacer.id }
    }

    func setWidth(_ width: Double, for spacer: MenuBarSpacer) {
        guard let index = spacers.firstIndex(where: { $0.id == spacer.id }) else {
            return
        }
        spacers[index].width = width.clamped(min: MenuBarSpacer.widthRange.lowerBound, max: MenuBarSpacer.widthRange.upperBound)
    }

    func setStyle(_ style: MenuBarSpacer.Style, for spacer: MenuBarSpacer) {
        guard let index = spacers.firstIndex(where: { $0.id == spacer.id }) else {
            return
        }
        spacers[index].style = style
    }

    func setText(_ text: String, for spacer: MenuBarSpacer) {
        guard let index = spacers.firstIndex(where: { $0.id == spacer.id }) else {
            return
        }
        spacers[index].text = text
    }

    func setThickness(_ thickness: Double, for spacer: MenuBarSpacer) {
        guard let index = spacers.firstIndex(where: { $0.id == spacer.id }) else {
            return
        }
        spacers[index].thickness = thickness.clamped(
            min: MenuBarSpacer.thicknessRange.lowerBound,
            max: MenuBarSpacer.thicknessRange.upperBound
        )
    }

    /// The menu shown when the user clicks a separator in the menu bar.
    fileprivate func makeMenu(for spacer: MenuBarSpacer) -> NSMenu {
        let menu = NSMenu(title: spacer.name)
        for style in MenuBarSpacer.Style.allCases {
            let item = ActionMenuItem(title: style.localized) { [weak self] in
                self?.setStyle(style, for: spacer)
            }
            item.state = spacer.style == style ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: L("app.layout.spacer.openSettings")) { [weak self] in
            self?.openLayoutSettings()
        })
        menu.addItem(ActionMenuItem(title: L("app.common.delete")) { [weak self] in
            self?.deleteSpacer(spacer)
        })
        return menu
    }

    private func openLayoutSettings() {
        guard let appState else {
            return
        }
        appState.navigationState.settingsNavigationIdentifier = .layout
        // Activating and opening a window back-to-back is unreliable for an accessory app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }

    private func loadInitialState() {
        guard let data = Defaults.data(forKey: .menuBarSpacers) else {
            return
        }
        do {
            spacers = try decoder.decode([MenuBarSpacer].self, from: data)
        } catch {
            Logger.serialization.error("Error decoding menu bar spacers: \(error, privacy: .public)")
        }
    }

    private func configureCancellables() {
        $spacers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spacers in
                guard let self else {
                    return
                }
                syncStatusItems()
                do {
                    let data = try encoder.encode(spacers)
                    Defaults.set(data, forKey: .menuBarSpacers)
                } catch {
                    Logger.serialization.error("Error encoding menu bar spacers: \(error, privacy: .public)")
                }
            }
            .store(in: &cancellables)
    }

    private func syncStatusItems() {
        let currentIDs = Set(spacers.map(\.id))
        for id in storage.keys where !currentIDs.contains(id) {
            storage[id] = nil
        }

        for spacer in spacers {
            if let item = storage[spacer.id] {
                item.update(with: spacer, manager: self)
            } else {
                storage[spacer.id] = SpacerStatusItem(spacer: spacer, manager: self)
            }
        }

        Task {
            await appState?.itemManager.cacheItemsRegardless()
        }
    }
}
