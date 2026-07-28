// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct DiagnosticsHistoryFilter: Equatable {
    var transportID: String?
    var state: TransportConnectionState?
    var query: String

    init(
        transportID: String? = nil,
        state: TransportConnectionState? = nil,
        query: String = ""
    ) {
        self.transportID = transportID
        self.state = state
        self.query = query
    }
}

enum DiagnosticsHistoryExportFormat: Equatable {
    case json
    case text
}

enum DiagnosticsHistoryPolicy {
    static let exportSchemaVersion = 1

    /// Filters newest-first history without changing its ordering. Returned
    /// entries have crossed the same redaction boundary used by exports.
    static func filter(
        _ entries: [DiagnosticsHistoryEntry],
        using filter: DiagnosticsHistoryFilter
    ) -> [DiagnosticsHistoryEntry] {
        let transportID = normalized(filter.transportID ?? "")
        let queryTerms = filter.query
            .split(whereSeparator: \.isWhitespace)
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }

        return entries
            .map(DiagnosticsHistoryStore.sanitizedForExternalUse)
            .filter { entry in
                if !transportID.isEmpty,
                   normalized(entry.transportID) != transportID {
                    return false
                }
                if let state = filter.state, entry.state != state {
                    return false
                }
                guard !queryTerms.isEmpty else { return true }
                let searchable = normalized([
                    entry.transportID,
                    entry.transportName,
                    entry.state.rawValue,
                    entry.state.label,
                    entry.protocolVersion ?? "",
                    entry.endpoint ?? "",
                    entry.failure ?? ""
                ].joined(separator: " "))
                return queryTerms.allSatisfy(searchable.contains)
            }
    }

    /// Exports only the explicit redacted diagnostics projection. Conversation
    /// text, commands, credentials, raw payloads, and source snapshots are not
    /// part of the export schema.
    static func export(
        _ entries: [DiagnosticsHistoryEntry],
        format: DiagnosticsHistoryExportFormat
    ) throws -> String {
        let records = entries
            .map(DiagnosticsHistoryStore.sanitizedForExternalUse)
            .map(DiagnosticsHistoryExportRecord.init)
        switch format {
        case .json:
            return try jsonExport(records)
        case .text:
            return textExport(records)
        }
    }

    /// Writes an export through a same-directory 0600 temporary file before
    /// moving it into place. Sensitive content is never created with broader
    /// default permissions.
    static func export(
        _ entries: [DiagnosticsHistoryEntry],
        format: DiagnosticsHistoryExportFormat,
        to destination: URL
    ) throws {
        let output = try export(entries, format: format)
        let fileManager = FileManager.default
        let temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: Data(output.utf8),
            attributes: [.posixPermissions: 0o600]
        ), privatePermissions(at: temporaryURL) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        guard privatePermissions(at: destination) else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func privatePermissions(at url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
        return permissions == 0o600
    }

    private static func jsonExport(
        _ records: [DiagnosticsHistoryExportRecord]
    ) throws -> String {
        let document = DiagnosticsHistoryExportDocument(
            schemaVersion: exportSchemaVersion,
            privacy: "redacted transport metadata only",
            entries: records
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard let value = String(data: data, encoding: .utf8) else {
            throw DiagnosticsHistoryExportError.invalidUTF8
        }
        return value
    }

    private static func textExport(
        _ records: [DiagnosticsHistoryExportRecord]
    ) -> String {
        var lines = [
            "Agent Island Diagnostics History",
            "Privacy: redacted transport metadata only",
            "Entries: \(records.count)"
        ]
        for record in records {
            var fields = [
                ISO8601DateFormatter().string(from: record.recordedAt),
                "transport=\(record.transportName)",
                "transport_id=\(record.transportID)",
                "state=\(record.state.rawValue)"
            ]
            if let protocolVersion = record.protocolVersion {
                fields.append("protocol=\(protocolVersion)")
            }
            if let endpoint = record.endpoint {
                fields.append("endpoint=\(endpoint)")
            }
            if let failure = record.failure {
                fields.append("failure=\(failure)")
            }
            lines.append(fields.joined(separator: " | "))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

private struct DiagnosticsHistoryExportDocument: Encodable {
    let schemaVersion: Int
    let privacy: String
    let entries: [DiagnosticsHistoryExportRecord]
}

private struct DiagnosticsHistoryExportRecord: Encodable {
    let id: UUID
    let recordedAt: Date
    let transportID: String
    let transportName: String
    let state: TransportConnectionState
    let protocolVersion: String?
    let endpoint: String?
    let failure: String?

    init(_ entry: DiagnosticsHistoryEntry) {
        id = entry.id
        recordedAt = entry.recordedAt
        transportID = entry.transportID
        transportName = entry.transportName
        state = entry.state
        protocolVersion = entry.protocolVersion
        endpoint = entry.endpoint
        failure = entry.failure
    }
}

private enum DiagnosticsHistoryExportError: Error {
    case invalidUTF8
}
