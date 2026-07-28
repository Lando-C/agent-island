// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit

/// Pure panel geometry. `NSScreen` is adapted to rectangles at the UI boundary,
/// so tests can replay display layouts without a logged-in WindowServer session.
enum PanelGeometryPolicy {
    static let screenInset: CGFloat = 16
    static let topGap: CGFloat = 4
    static let floatingEdgeInset: CGFloat = 8
    static let floatingDefaultTrailingGap: CGFloat = 24

    private static let collapsedHeight: CGFloat = 58
    private static let expandedHeight: CGFloat = 326

    static func islandSize(
        expanded: Bool,
        preferredWidth: CGFloat,
        visibleFrame: NSRect?
    ) -> NSSize {
        guard let visibleFrame else {
            return NSSize(
                width: preferredWidth,
                height: expanded ? expandedHeight : collapsedHeight
            )
        }

        // Visible bounds win over the preferred minimum on unusually compact
        // or virtual displays; a 280pt panel cannot preserve 16pt insets on a
        // 300pt-wide screen.
        let maxWidth = max(1, visibleFrame.width - screenInset * 2)
        let minimumWidth = min(maxWidth, expanded ? 420 : 340)
        let width = max(minimumWidth, min(preferredWidth, maxWidth))
        let desiredHeight = expanded ? expandedHeight : collapsedHeight
        let maxHeight = max(1, visibleFrame.height - screenInset * 2)
        return NSSize(width: width, height: min(desiredHeight, maxHeight))
    }

    static func notchCenterX(
        screenFrame: NSRect,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?
    ) -> CGFloat {
        guard let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea,
              !leftArea.isEmpty,
              !rightArea.isEmpty else {
            return round(screenFrame.midX)
        }

        let midpoint = (leftArea.maxX + rightArea.minX) / 2
        if midpoint < screenFrame.minX || midpoint > screenFrame.maxX {
            return round(screenFrame.minX + midpoint)
        }
        return round(midpoint)
    }

    static func notchFrame(
        panelSize: NSSize,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?,
        horizontalOffset: CGFloat
    ) -> NSRect {
        let centerX = notchCenterX(
            screenFrame: screenFrame,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea
        )
        let desiredX = centerX - panelSize.width / 2 + horizontalOffset
        let minX = visibleFrame.minX + screenInset
        let maxX = visibleFrame.maxX - panelSize.width - screenInset
        let x = maxX >= minX
            ? min(max(desiredX, minX), maxX)
            : visibleFrame.midX - panelSize.width / 2
        let preferredY = visibleFrame.maxY - panelSize.height - topGap
        let minY = visibleFrame.minY + screenInset
        return NSRect(
            origin: NSPoint(x: x, y: max(preferredY, minY)),
            size: panelSize
        )
    }

    static func floatingSize(expanded: Bool) -> NSSize {
        expanded ? NSSize(width: 292, height: 154) : NSSize(width: 154, height: 64)
    }

    static func defaultFloatingFrame(panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.maxX - panelSize.width - floatingDefaultTrailingGap,
            y: visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func clampedFloatingFrame(_ frame: NSRect, visibleFrame: NSRect) -> NSRect {
        let bounds = visibleFrame.insetBy(dx: floatingEdgeInset, dy: floatingEdgeInset)
        let x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
        let y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
    }
}

enum PanelScreenSelectionPolicy {
    static func preferredDisplayID(
        displayMode: IslandDisplayMode,
        savedFloatingDisplayID: UInt32?,
        currentDisplayID: UInt32?,
        mainDisplayID: UInt32?,
        availableDisplayIDs: [UInt32]
    ) -> UInt32? {
        let available = Set(availableDisplayIDs)
        if displayMode == .floating {
            if let savedFloatingDisplayID, available.contains(savedFloatingDisplayID) {
                return savedFloatingDisplayID
            }
            if let currentDisplayID, available.contains(currentDisplayID) {
                return currentDisplayID
            }
        }
        if let mainDisplayID, available.contains(mainDisplayID) {
            return mainDisplayID
        }
        if let currentDisplayID, available.contains(currentDisplayID) {
            return currentDisplayID
        }
        return availableDisplayIDs.first
    }
}
