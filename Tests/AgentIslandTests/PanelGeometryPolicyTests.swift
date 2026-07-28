// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private struct DisplayGeometryFixture {
    let name: String
    let frame: NSRect
    let visible: NSRect
    let left: NSRect?
    let right: NSRect?
    let expectedCenterX: CGFloat
}

private let displayGeometryFixtures = [
    DisplayGeometryFixture(
        name: "13-inch notch", frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visible: NSRect(x: 0, y: 0, width: 1440, height: 875),
        left: NSRect(x: 0, y: 875, width: 620, height: 25),
        right: NSRect(x: 820, y: 875, width: 620, height: 25), expectedCenterX: 720
    ),
    DisplayGeometryFixture(
        name: "14-inch notch", frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
        visible: NSRect(x: 0, y: 0, width: 1512, height: 947),
        left: NSRect(x: 0, y: 947, width: 656, height: 35),
        right: NSRect(x: 856, y: 947, width: 656, height: 35), expectedCenterX: 756
    ),
    DisplayGeometryFixture(
        name: "16-inch notch", frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
        visible: NSRect(x: 0, y: 0, width: 1728, height: 1082),
        left: NSRect(x: 0, y: 1082, width: 754, height: 35),
        right: NSRect(x: 974, y: 1082, width: 754, height: 35), expectedCenterX: 864
    ),
    DisplayGeometryFixture(
        name: "non-notch built-in", frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visible: NSRect(x: 0, y: 0, width: 1440, height: 875),
        left: nil, right: nil, expectedCenterX: 720
    ),
    DisplayGeometryFixture(
        name: "offset external", frame: NSRect(x: 1512, y: -240, width: 2560, height: 1440),
        visible: NSRect(x: 1512, y: -240, width: 2560, height: 1415),
        left: nil, right: nil, expectedCenterX: 2792
    )
]

private func geometryFailures() -> [String] {
    displayGeometryFixtures.flatMap { fixture -> [String] in
        let center = PanelGeometryPolicy.notchCenterX(
            screenFrame: fixture.frame,
            auxiliaryTopLeftArea: fixture.left,
            auxiliaryTopRightArea: fixture.right
        )
        let size = PanelGeometryPolicy.islandSize(
            expanded: true, preferredWidth: 660, visibleFrame: fixture.visible
        )
        let panel = PanelGeometryPolicy.notchFrame(
            panelSize: size,
            screenFrame: fixture.frame,
            visibleFrame: fixture.visible,
            auxiliaryTopLeftArea: fixture.left,
            auxiliaryTopRightArea: fixture.right,
            horizontalOffset: -10
        )
        var failures: [String] = []
        if center != fixture.expectedCenterX {
            failures.append("\(fixture.name): center \(center)")
        }
        if panel.minX < fixture.visible.minX + 16 || panel.maxX > fixture.visible.maxX - 16 {
            failures.append("\(fixture.name): horizontal bounds \(panel)")
        }
        if panel.minY < fixture.visible.minY + 16 || panel.maxY > fixture.visible.maxY - 4 {
            failures.append("\(fixture.name): vertical bounds \(panel)")
        }
        return failures
    }
}

private func selectionFailures() -> [String] {
    let builtIn: UInt32 = 1
    let external: UInt32 = 2
    let fixtures: [(String, IslandDisplayMode, UInt32?, UInt32?, UInt32?, [UInt32], UInt32?)] = [
        ("external connected", .floating, external, builtIn, builtIn, [builtIn, external], external),
        ("external removed", .floating, external, builtIn, builtIn, [builtIn], builtIn),
        ("external restored", .floating, external, builtIn, builtIn, [builtIn, external], external),
        ("notch follows main", .notch, external, external, builtIn, [builtIn, external], builtIn),
        ("no displays", .floating, external, builtIn, builtIn, [], nil)
    ]
    return fixtures.compactMap { name, mode, saved, current, main, available, expected in
        let actual = PanelScreenSelectionPolicy.preferredDisplayID(
            displayMode: mode,
            savedFloatingDisplayID: saved,
            currentDisplayID: current,
            mainDisplayID: main,
            availableDisplayIDs: available
        )
        return actual == expected ? nil : "\(name): expected \(String(describing: expected)), got \(String(describing: actual))"
    }
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Panel geometry fixtures")
struct PanelGeometryPolicyTests {
    @Test("Notch, non-notch and external fixtures remain inside visible bounds")
    func displays() { #expect(geometryFailures().isEmpty) }

    @Test("Compact display clamps expanded size")
    func compactSize() {
        #expect(PanelGeometryPolicy.islandSize(
            expanded: true, preferredWidth: 900,
            visibleFrame: NSRect(x: 0, y: 0, width: 300, height: 240)
        ) == NSSize(width: 268, height: 208))
    }

    @Test("Display removal and restoration are deterministic")
    func selection() { #expect(selectionFailures().isEmpty) }

    @Test("Detached companion clamps into an offset external display")
    func companionBounds() {
        let visible = NSRect(x: 1512, y: -240, width: 2560, height: 1415)
        let size = PanelGeometryPolicy.floatingSize(expanded: true)
        let initial = PanelGeometryPolicy.defaultFloatingFrame(panelSize: size, visibleFrame: visible)
        #expect(initial.maxX == visible.maxX - 24)
        #expect(initial.midY == visible.midY)
        let clamped = PanelGeometryPolicy.clampedFloatingFrame(
            NSRect(x: 5000, y: -1000, width: size.width, height: size.height),
            visibleFrame: visible
        )
        #expect(clamped.minX >= visible.minX + 8)
        #expect(clamped.maxX <= visible.maxX - 8)
        #expect(clamped.minY >= visible.minY + 8)
        #expect(clamped.maxY <= visible.maxY - 8)
    }
}
#elseif canImport(XCTest)
final class PanelGeometryPolicyTests: XCTestCase {
    func testDisplays() { XCTAssertEqual(geometryFailures(), []) }

    func testCompactSize() {
        XCTAssertEqual(PanelGeometryPolicy.islandSize(
            expanded: true, preferredWidth: 900,
            visibleFrame: NSRect(x: 0, y: 0, width: 300, height: 240)
        ), NSSize(width: 268, height: 208))
    }

    func testSelection() { XCTAssertEqual(selectionFailures(), []) }

    func testCompanionBounds() {
        let visible = NSRect(x: 1512, y: -240, width: 2560, height: 1415)
        let size = PanelGeometryPolicy.floatingSize(expanded: true)
        let initial = PanelGeometryPolicy.defaultFloatingFrame(panelSize: size, visibleFrame: visible)
        XCTAssertEqual(initial.maxX, visible.maxX - 24)
        XCTAssertEqual(initial.midY, visible.midY)
        let clamped = PanelGeometryPolicy.clampedFloatingFrame(
            NSRect(x: 5000, y: -1000, width: size.width, height: size.height),
            visibleFrame: visible
        )
        XCTAssertGreaterThanOrEqual(clamped.minX, visible.minX + 8)
        XCTAssertLessThanOrEqual(clamped.maxX, visible.maxX - 8)
        XCTAssertGreaterThanOrEqual(clamped.minY, visible.minY + 8)
        XCTAssertLessThanOrEqual(clamped.maxY, visible.maxY - 8)
    }
}
#endif
