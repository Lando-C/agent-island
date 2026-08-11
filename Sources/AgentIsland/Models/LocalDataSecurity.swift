// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

/// Applies the local privacy boundary used by Agent Island-owned state.
/// Directories are owner-only and files are never opened through symlinks.
enum LocalDataSecurity {
    static let directoryPermissions: mode_t = S_IRWXU
    static let filePermissions: mode_t = S_IRUSR | S_IWUSR

    static func ensurePrivateDirectory(at url: URL) throws {
        var metadata = stat()
        if lstat(url.path, &metadata) == 0 {
            guard metadata.st_mode & S_IFMT == S_IFDIR else {
                throw POSIXError(.ENOTDIR)
            }
            guard metadata.st_uid == geteuid() else {
                throw POSIXError(.EACCES)
            }
        } else if errno == ENOENT {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: directoryPermissions)]
            )
        } else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        guard chmod(url.path, directoryPermissions) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    static func writePrivate(_ data: Data, to url: URL) throws {
        try ensurePrivateDirectory(at: url.deletingLastPathComponent())
        try validateExistingFile(at: url)

        var template = Array(
            url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).XXXXXX")
                .path.utf8CString
        )
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let temporaryPath = String(cString: template)
        var shouldClose = true
        defer {
            if shouldClose { close(descriptor) }
            unlink(temporaryPath)
        }

        guard fchmod(descriptor, filePermissions) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        try writeAll(data, to: descriptor)
        guard fsync(descriptor) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard close(descriptor) == 0 else {
            shouldClose = false
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        shouldClose = false
        guard rename(temporaryPath, url.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    static func writePrivate(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try writePrivate(data, to: url)
    }

    static func appendPrivate(_ data: Data, to url: URL) throws {
        try ensurePrivateDirectory(at: url.deletingLastPathComponent())
        let descriptor = open(
            url.path,
            O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
            filePermissions
        )
        guard descriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        try validateRegularOwnerFile(descriptor)
        guard fchmod(descriptor, filePermissions) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        try writeAll(data, to: descriptor)
    }

    static func readPrivate(_ url: URL, maximumBytes: Int = 65_536) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        try validateRegularOwnerFile(descriptor)
        guard fchmod(descriptor, filePermissions) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.count <= maximumBytes {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                result.append(buffer, count: count)
            } else if count == 0 {
                return result
            } else if errno == EINTR {
                continue
            } else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        throw CocoaError(.fileReadTooLarge)
    }

    static func readPrivateString(_ url: URL, maximumBytes: Int = 65_536) throws -> String {
        guard let value = String(data: try readPrivate(url, maximumBytes: maximumBytes), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return value
    }

    private static func validateExistingFile(at url: URL) throws {
        var metadata = stat()
        if lstat(url.path, &metadata) == 0 {
            guard metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_uid == geteuid() else {
                throw POSIXError(.EACCES)
            }
        } else if errno != ENOENT {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private static func validateRegularOwnerFile(_ descriptor: Int32) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == geteuid() else {
            throw POSIXError(.EACCES)
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        let succeeded = data.withUnsafeBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        guard succeeded else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }
}
