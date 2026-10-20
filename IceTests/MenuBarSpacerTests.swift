//
//  MenuBarSpacerTests.swift
//  IceTests
//

import Foundation
import Testing
@testable import Ice_2

struct MenuBarSpacerTests {
    @Test func decodesSpacersSavedBeforeStylesAsBlank() throws {
        let json = #"[{"id":"11111111-2222-3333-4444-555555555555","name":"Spacer 1","width":24}]"#
        let spacers = try JSONDecoder().decode([MenuBarSpacer].self, from: Data(json.utf8))
        #expect(spacers.count == 1)
        #expect(spacers[0].style == .blank)
        #expect(spacers[0].width == 24)
        #expect(spacers[0].text == "•")
        #expect(spacers[0].thickness == 1)
    }

    @Test func roundTripsStyleTextAndThickness() throws {
        var spacer = MenuBarSpacer(id: UUID(), name: "Separator 1", width: 12)
        #expect(spacer.style == .line)
        spacer.style = .text
        spacer.text = "🍋"
        spacer.thickness = 2
        let decoded = try JSONDecoder().decode(MenuBarSpacer.self, from: JSONEncoder().encode(spacer))
        #expect(decoded == spacer)
    }

    @MainActor
    @Test func styleMetadata() {
        #expect(MenuBarSpacer.Style.allCases.map(\.rawValue) == ["blank", "line", "text"])
        withEnglish {
            #expect(MenuBarSpacer.Style.blank.localized == "Blank")
            #expect(MenuBarSpacer.Style.line.localized == "Line")
            #expect(MenuBarSpacer.Style.text.localized == "Text")
        }
    }
}
