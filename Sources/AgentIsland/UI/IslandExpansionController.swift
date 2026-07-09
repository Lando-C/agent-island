// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

final class IslandExpansionController: ObservableObject {
    enum ExpansionReason {
        case none
        case hover
        case manual
        case spotlight
    }

    @Published private(set) var expanded = false
    @Published private(set) var spotlightSnapshot: AgentSnapshot?

    var onExpandedChange: (Bool) -> Void = { _ in }

    private var reason: ExpansionReason = .none
    private var hovering = false
    private var collapseOnHoverExit = false
    private var activeSpotlightKey: String?
    private var suppressHoverUntil: Date?
    private var suppressSpotlightUntil: Date?
    private var dismissedSpotlightKeys: [String: Date] = [:]
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var hoverCollapseWorkItem: DispatchWorkItem?
    private var autoCollapseWorkItem: DispatchWorkItem?

    func toggleFromHeader() {
        if expanded {
            dismissByUser()
        } else {
            cancelHoverWork()
            setExpanded(true, reason: .manual)
        }
    }

    func dismissByUser() {
        cancelAllWork()
        markActiveSpotlightDismissed()
        suppressHoverUntil = Date().addingTimeInterval(1.2)
        suppressSpotlightUntil = Date().addingTimeInterval(12)
        collapseOnHoverExit = false
        activeSpotlightKey = nil
        spotlightSnapshot = nil
        setExpanded(false, reason: .none)
    }

    func dismissAfterSnapshotAction() {
        cancelAllWork()
        suppressHoverUntil = Date().addingTimeInterval(1.0)
        suppressSpotlightUntil = Date().addingTimeInterval(8)
        collapseOnHoverExit = false
        activeSpotlightKey = nil
        spotlightSnapshot = nil
        setExpanded(false, reason: .none)
    }

    func handleHoverChange(_ isHovering: Bool) {
        guard isHovering != hovering else { return }
        hovering = isHovering
        cancelHoverWork()

        if isHovering {
            guard !expanded else { return }
            guard !isSuppressed(until: suppressHoverUntil) else { return }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.hovering, !self.expanded else { return }
                self.setExpanded(true, reason: .hover)
            }
            hoverExpandWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
            return
        }

        if collapseOnHoverExit {
            collapseOnHoverExit = false
            collapseSpotlight()
            return
        }

        guard reason == .hover else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering, self.reason == .hover else { return }
            self.setExpanded(false, reason: .none)
        }
        hoverCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: workItem)
    }

    func showSpotlight(_ snapshot: AgentSnapshot, duration: TimeInterval) {
        guard duration > 0 else { return }
        guard !isSuppressed(until: suppressSpotlightUntil) else { return }

        let key = spotlightKey(for: snapshot)
        guard !isDismissed(key) else { return }
        guard activeSpotlightKey != key else { return }

        autoCollapseWorkItem?.cancel()
        let keepManualExpansion = expanded && reason == .manual
        activeSpotlightKey = key
        spotlightSnapshot = snapshot
        collapseOnHoverExit = false
        setExpanded(true, reason: keepManualExpansion ? .manual : .spotlight)

        guard !keepManualExpansion else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeSpotlightKey == key else { return }
            if self.hovering {
                self.collapseOnHoverExit = true
                return
            }
            self.collapseSpotlight()
        }
        autoCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func setExpanded(_ value: Bool, reason nextReason: ExpansionReason) {
        if value {
            reason = nextReason
        } else {
            reason = .none
        }

        guard expanded != value else { return }
        expanded = value
        onExpandedChange(value)
    }

    private func collapseSpotlight() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        activeSpotlightKey = nil
        spotlightSnapshot = nil
        suppressSpotlightUntil = Date().addingTimeInterval(2)
        setExpanded(false, reason: .none)
    }

    private func markActiveSpotlightDismissed() {
        guard let activeSpotlightKey else { return }
        dismissedSpotlightKeys[activeSpotlightKey] = Date().addingTimeInterval(2 * 60)
    }

    private func isDismissed(_ key: String) -> Bool {
        purgeExpiredDismissals()
        guard let until = dismissedSpotlightKeys[key] else { return false }
        return Date() <= until
    }

    private func purgeExpiredDismissals() {
        let now = Date()
        dismissedSpotlightKeys = dismissedSpotlightKeys.filter { now <= $0.value }
    }

    private func isSuppressed(until: Date?) -> Bool {
        guard let until else { return false }
        return Date() <= until
    }

    private func spotlightKey(for snapshot: AgentSnapshot) -> String {
        let updated = snapshot.lastUpdated?.timeIntervalSince1970 ?? 0
        return "\(snapshot.id)::\(snapshot.phase.rawValue)::\(Int(updated))"
    }

    private func cancelHoverWork() {
        hoverExpandWorkItem?.cancel()
        hoverExpandWorkItem = nil
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
    }

    private func cancelAllWork() {
        cancelHoverWork()
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
    }
}
