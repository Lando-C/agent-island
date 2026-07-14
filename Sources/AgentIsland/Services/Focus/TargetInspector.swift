// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct ProcessRow: Equatable {
    var pid: Int
    var ppid: Int?
    var tty: String?
    var command: String

    init(pid: Int, ppid: Int?, tty: String? = nil, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.tty = tty
        self.command = command
    }
}

struct TmuxPaneState: Equatable {
    var paneID: String
    var socket: String?
    var tty: String?
    var pid: Int?
    var isDead: Bool
}

struct TerminalLivenessSnapshot: Equatable {
    var processProbeSucceeded: Bool
    var activeTTYs: Set<String>
    var tmuxInstalled: Bool
    var tmuxProbeSucceeded: Bool
    var tmuxPanes: [TmuxPaneState]

    static let unknown = TerminalLivenessSnapshot(
        processProbeSucceeded: false,
        activeTTYs: [],
        tmuxInstalled: false,
        tmuxProbeSucceeded: false,
        tmuxPanes: []
    )

    func pane(id: String, socket: String?) -> TmuxPaneState? {
        if let socket, !socket.isEmpty,
           let exact = tmuxPanes.first(where: { $0.paneID == id && $0.socket == socket }) {
            return exact
        }
        return tmuxPanes.first { $0.paneID == id }
    }
}

enum TargetInspector {
    static func readProcesses(health: TransportHealthStore = .shared) -> [ProcessRow] {
        health.markAttempt(id: TransportHealthStore.processProbeID, name: "Process / TTY Probe", endpoint: "/bin/ps")
        let result = run(executable: "/bin/ps", arguments: ["axww", "-o", "pid=,ppid=,tty=,command="])
        guard result.status == 0 else {
            health.markFailure(
                id: TransportHealthStore.processProbeID,
                name: "Process / TTY Probe",
                endpoint: "/bin/ps",
                error: result.error.nilIfBlank ?? "ps exited \(result.status)"
            )
            return []
        }

        let rows = result.output.split(separator: "\n").compactMap { line -> ProcessRow? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3)
            guard parts.count == 4, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { return nil }
            let rawTTY = String(parts[2])
            let tty = rawTTY == "??" || rawTTY == "?" || rawTTY == "-" ? nil : normalizeTTY(rawTTY)
            return ProcessRow(pid: pid, ppid: ppid, tty: tty, command: String(parts[3]))
        }
        health.markConnected(
            id: TransportHealthStore.processProbeID,
            name: "Process / TTY Probe",
            protocolVersion: "ps/bsd",
            endpoint: "/bin/ps",
            event: true
        )
        return rows
    }

    static func readTerminalLiveness(
        processRows: [ProcessRow],
        tmuxSockets: Set<String>,
        health: TransportHealthStore = .shared
    ) -> TerminalLivenessSnapshot {
        let activeTTYs = Set(processRows.compactMap(\.tty))
        guard let executable = executable(named: "tmux") else {
            health.markFailure(
                id: TransportHealthStore.tmuxProbeID,
                name: "tmux Pane Probe",
                state: .unavailable,
                error: "tmux is not installed"
            )
            return TerminalLivenessSnapshot(
                processProbeSucceeded: !processRows.isEmpty,
                activeTTYs: activeTTYs,
                tmuxInstalled: false,
                tmuxProbeSucceeded: false,
                tmuxPanes: []
            )
        }

        var targets: [String?] = [nil]
        targets.append(contentsOf: tmuxSockets.filter { !$0.isEmpty }.sorted().map(Optional.some))
        var seenTargets = Set<String>()
        var panes: [TmuxPaneState] = []
        var successes = 0
        var failures: [String] = []

        for socket in targets {
            let targetKey = socket ?? "<default>"
            guard seenTargets.insert(targetKey).inserted else { continue }
            var arguments: [String] = []
            if let socket { arguments.append(contentsOf: ["-S", socket]) }
            arguments.append(contentsOf: [
                "list-panes", "-a", "-F",
                "#{pane_id}\t#{pane_dead}\t#{pane_tty}\t#{pane_pid}"
            ])
            let result = run(executable: executable, arguments: arguments)
            guard result.status == 0 else {
                failures.append("\(targetKey): \(result.error.nilIfBlank ?? "no server")")
                continue
            }
            successes += 1
            for line in result.output.split(separator: "\n") {
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 4 else { continue }
                let tty = String(parts[2]).nilIfBlank.map(normalizeTTY)
                panes.append(TmuxPaneState(
                    paneID: String(parts[0]),
                    socket: socket,
                    tty: tty,
                    pid: Int(parts[3]),
                    isDead: parts[1] == "1"
                ))
            }
        }

        if successes > 0 {
            health.markConnected(
                id: TransportHealthStore.tmuxProbeID,
                name: "tmux Pane Probe",
                protocolVersion: "tmux/list-panes",
                endpoint: executable,
                event: true
            )
        } else {
            health.markFailure(
                id: TransportHealthStore.tmuxProbeID,
                name: "tmux Pane Probe",
                state: .unavailable,
                endpoint: executable,
                error: failures.first ?? "No accessible tmux server"
            )
        }
        return TerminalLivenessSnapshot(
            processProbeSucceeded: !processRows.isEmpty,
            activeTTYs: activeTTYs,
            tmuxInstalled: true,
            tmuxProbeSucceeded: successes > 0,
            tmuxPanes: panes
        )
    }

    private static func normalizeTTY(_ value: String) -> String {
        value.hasPrefix("/dev/") ? value : "/dev/\(value)"
    }

    private static func executable(named name: String) -> String? {
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func run(executable: String, arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? "",
            String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
