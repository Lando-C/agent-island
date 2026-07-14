// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// Owns the island window, its mode-specific root view, geometry, and screen
/// restoration. AppDelegate remains responsible only for application lifecycle.
final class PanelCoordinator: NSObject {
    private let viewModel: IslandViewModel
    private let onSnapshotDetails: (AgentSnapshot) -> Void
    private var panel: IslandPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var displayMode = IslandDisplayModeStore.mode
    private var panelPositionGeneration = 0
    private var moveObserver: NSObjectProtocol?

    private(set) var isExpanded = false

    init(
        viewModel: IslandViewModel,
        onSnapshotDetails: @escaping (AgentSnapshot) -> Void
    ) {
        self.viewModel = viewModel
        self.onSnapshotDetails = onSnapshotDetails
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    func start() {
        guard panel == nil else { return }
        let initialSize = panelSize(on: NSScreen.main)
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = NotchPlacement.collectionBehavior(showInFullScreenApps: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.returnToNotch = { [weak self] in self?.returnToNotch() }
        self.panel = panel
        configurePanelForMode()
        replaceRootView()
        positionPanel(animate: false)
        panel.orderFrontRegardless()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.panelDidMove()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.panel?.orderFrontRegardless()
            self?.positionPanel(animate: false)
        }
        islandLog("panel coordinator started mode=\(displayMode.rawValue)")
    }

    func stop() {
        panel?.orderOut(nil)
    }

    func show() {
        panel?.orderFrontRegardless()
        positionPanel(animate: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggleIsland() {
        if panel?.isVisible != true { show() }
        NotificationCenter.default.post(name: AgentIslandControlKeys.toggleRequested, object: nil)
    }

    func toggleFloatingMode() {
        displayMode == .floating ? returnToNotch() : enterFloatingMode()
    }

    func enterFloatingMode() {
        guard displayMode != .floating, let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        if let screen { IslandDisplayModeStore.setFloatingOrigin(panel.frame.origin, on: screen) }
        displayMode = .floating
        IslandDisplayModeStore.mode = .floating
        isExpanded = false
        configurePanelForMode()
        replaceRootView()
        positionPanel(animate: true)
        islandLog("display mode floating")
    }

    func returnToNotch() {
        guard displayMode != .notch, let panel else { return }
        if let screen = panel.screen ?? NSScreen.main {
            IslandDisplayModeStore.setFloatingOrigin(panel.frame.origin, on: screen)
        }
        displayMode = .notch
        IslandDisplayModeStore.mode = .notch
        isExpanded = false
        configurePanelForMode()
        replaceRootView()
        positionPanel(animate: true)
        islandLog("display mode notch")
    }

    func applySettings() {
        let requestedMode = IslandDisplayModeStore.mode
        if requestedMode != displayMode {
            requestedMode == .floating ? enterFloatingMode() : returnToNotch()
        } else {
            positionPanel(animate: true)
        }
    }

    func screenChanged() {
        positionPanel(animate: false)
    }

    private func configurePanelForMode() {
        guard let panel else { return }
        let floating = displayMode == .floating
        panel.isMovable = floating
        panel.isMovableByWindowBackground = floating
    }

    private func replaceRootView() {
        guard let panel else { return }
        let root: AnyView
        if displayMode == .floating {
            root = AnyView(FloatingCompanionView(
                viewModel: viewModel,
                onBubbleChange: { [weak self] expanded in self?.setExpanded(expanded) },
                onOpen: { snapshot in AgentLauncher.focus(snapshot) },
                onDetails: { [weak self] snapshot in self?.onSnapshotDetails(snapshot) }
            ))
        } else {
            root = AnyView(IslandView(
                monitor: viewModel.monitor,
                pendingRequests: viewModel.pendingRequests,
                onExpandedChange: { [weak self] expanded in self?.setExpanded(expanded) },
                onSnapshotAction: { snapshot in AgentLauncher.focus(snapshot) },
                onSnapshotDetails: { [weak self] snapshot in self?.onSnapshotDetails(snapshot) },
                onDetachRequested: { [weak self] in self?.enterFloatingMode() }
            ))
        }
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView = hosting
        panel.contentView = hosting
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        schedulePanelPosition(animate: true)
    }

    private func panelDidMove() {
        guard displayMode == .floating,
              let panel,
              let screen = panel.screen ?? NSScreen.main else { return }
        IslandDisplayModeStore.setFloatingOrigin(panel.frame.origin, on: screen)
    }

    private func schedulePanelPosition(animate: Bool) {
        panelPositionGeneration &+= 1
        let generation = panelPositionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panelPositionGeneration == generation else { return }
            self.positionPanel(animate: animate)
        }
    }

    private func panelSize(on screen: NSScreen?) -> NSSize {
        if displayMode == .floating { return FloatingCompanionView.panelSize(expanded: isExpanded) }
        return IslandPanelSizing.size(expanded: isExpanded, on: screen)
    }

    private func positionPanel(animate: Bool) {
        guard let panel, let screen = preferredScreen(for: panel) else { return }
        let size = panelSize(on: screen)
        let frame: NSRect
        if displayMode == .floating {
            let defaultOrigin = NSPoint(
                x: screen.visibleFrame.maxX - size.width - 24,
                y: screen.visibleFrame.midY - size.height / 2
            )
            let origin = IslandDisplayModeStore.floatingOrigin(on: screen) ?? defaultOrigin
            frame = clampedFloatingFrame(NSRect(origin: origin, size: size), screen: screen)
        } else {
            frame = NotchPlacement.frame(for: size, on: screen)
        }
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func preferredScreen(for panel: NSPanel) -> NSScreen? {
        if displayMode == .floating,
           let displayID = IslandDisplayModeStore.lastFloatingDisplayID,
           let restored = NSScreen.screens.first(where: { $0.displayId == displayID }) {
            return restored
        }
        if displayMode == .floating, let current = panel.screen { return current }
        return NSScreen.main ?? panel.screen
    }

    private func clampedFloatingFrame(_ frame: NSRect, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        let y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
