// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

struct CodexBrokerConnection {
    var fileDescriptor: Int32
    var path: String
}

/// Owns the filesystem and Unix-domain-socket boundary for the Codex broker.
///
/// Protocol initialization deliberately remains in `CodexBrokerClient`: opening
/// a socket does not prove that the peer implements a supported app-server
/// protocol.
enum CodexBrokerEndpoint {
    static let environmentKey = "AGENT_ISLAND_CODEX_BROKER_SOCKET"

    static func candidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        temporaryDirectory: String = NSTemporaryDirectory(),
        fileManager: FileManager = .default
    ) -> [String] {
        candidates(
            overridePath: environment[environmentKey],
            temporaryRoots: [temporaryDirectory, "/tmp"],
            fileManager: fileManager
        )
    }

    static func candidates(
        overridePath: String?,
        temporaryRoots: [String],
        fileManager: FileManager
    ) -> [String] {
        var discovered: [(date: Date, path: String)] = []
        if let overridePath, !overridePath.isEmpty, isTrustedSocket(overridePath) {
            discovered.append((.distantFuture, overridePath))
        }

        for root in Set(temporaryRoots) {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasPrefix("cxc-") {
                let path = URL(fileURLWithPath: root)
                    .appendingPathComponent(entry)
                    .appendingPathComponent("broker.sock")
                    .path
                guard isTrustedSocket(path) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: path)
                let date = attributes?[.modificationDate] as? Date ?? .distantPast
                discovered.append((date, path))
            }
        }

        var seen = Set<String>()
        return discovered
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.path < $1.path
            }
            .compactMap { candidate in
                guard seen.insert(candidate.path).inserted else { return nil }
                return candidate.path
            }
    }

    static func connectFirst(
        candidates: [String],
        onAttempt: (String) -> Void = { _ in },
        connector: (String) -> Int32? = connect
    ) -> CodexBrokerConnection? {
        for path in candidates {
            onAttempt(path)
            if let fileDescriptor = connector(path) {
                return CodexBrokerConnection(fileDescriptor: fileDescriptor, path: path)
            }
        }
        return nil
    }

    private static func connect(path: String) -> Int32? {
        guard isTrustedSocket(path) else { return nil }
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(socketFD)
            return nil
        }
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { target in
                for (index, byte) in bytes.enumerated() {
                    target[index] = CChar(bitPattern: byte)
                }
                target[bytes.count] = 0
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(socketFD)
            return nil
        }
        return socketFD
    }

    /// A broker can request approval responses, so discovery must not trust an
    /// arbitrary newer socket created by another local account in `/tmp`.
    static func isTrustedSocket(_ path: String, effectiveUID: uid_t = geteuid()) -> Bool {
        var socketMetadata = stat()
        guard lstat(path, &socketMetadata) == 0,
              socketMetadata.st_mode & S_IFMT == S_IFSOCK,
              socketMetadata.st_uid == effectiveUID else {
            return false
        }

        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var parentMetadata = stat()
        guard lstat(parent, &parentMetadata) == 0,
              parentMetadata.st_mode & S_IFMT == S_IFDIR,
              parentMetadata.st_uid == effectiveUID else {
            return false
        }
        let writableByOthers = mode_t(S_IWGRP | S_IWOTH)
        return parentMetadata.st_mode & writableByOthers == 0
    }
}
