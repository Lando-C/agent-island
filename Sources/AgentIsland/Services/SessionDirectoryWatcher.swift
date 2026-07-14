// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import CoreServices
import Foundation

/// Coalesces recursive file changes from transcript roots into one refresh.
final class SessionDirectoryWatcher {
    private let paths: [String]
    private let handler: () -> Void
    private let queue = DispatchQueue(label: "local.agent-island.transcript-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingRefresh: DispatchWorkItem?

    init(paths: [String], handler: @escaping () -> Void) {
        self.paths = Array(Set(paths)).sorted()
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            Self.callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.15,
            flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handler() }
        pendingRefresh = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private static let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        Unmanaged<SessionDirectoryWatcher>.fromOpaque(info).takeUnretainedValue().scheduleRefresh()
    }
}
