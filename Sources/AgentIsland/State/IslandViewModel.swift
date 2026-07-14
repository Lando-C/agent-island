// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

/// Presentation state shared by the notch panel and the detached companion.
final class IslandViewModel: ObservableObject {
    let monitor: AgentMonitor
    let pendingRequests: PendingRequestStore

    private let soundManager: SoundManager
    private var cancellables = Set<AnyCancellable>()
    private var previousPhases: [String: AgentPhase] = [:]

    init(
        monitor: AgentMonitor,
        pendingRequests: PendingRequestStore,
        soundManager: SoundManager = .shared
    ) {
        self.monitor = monitor
        self.pendingRequests = pendingRequests
        self.soundManager = soundManager

        monitor.$snapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshots in
                self?.handleSnapshotChanges(snapshots)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        pendingRequests.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var activeSnapshots: [AgentSnapshot] {
        monitor.snapshots.filter { $0.phase != .offline && $0.phase != .available }
    }

    var primarySnapshot: AgentSnapshot? {
        activeSnapshots.sorted {
            if $0.phase.rank != $1.phase.rank { return $0.phase.rank < $1.phase.rank }
            return ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast)
        }.first
    }

    var headline: String { monitor.headline }

    private func handleSnapshotChanges(_ snapshots: [AgentSnapshot]) {
        defer { previousPhases = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0.phase) }) }
        guard !previousPhases.isEmpty else { return }
        for snapshot in snapshots {
            guard let previous = previousPhases[snapshot.id], previous != snapshot.phase else { continue }
            let key = "\(snapshot.id)::\(snapshot.phase.rawValue)"
            switch snapshot.phase {
            case .working, .thinking:
                soundManager.play(.started, key: key)
            case .done:
                soundManager.play(.completed, key: key)
            case .needsAttention, .error, .queued:
                soundManager.play(.needsAttention, key: key)
            case .online, .idle, .available, .offline:
                break
            }
        }
    }
}
