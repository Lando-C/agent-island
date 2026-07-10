// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import ApplicationServices
import Foundation

enum ClaudeAppFocuser {
    private static let bundleID = "com.anthropic.claudefordesktop"
    private static var didRequestAccessibility = false

    static func focus(_ target: ClaudeAppJumpTarget) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) else {
            return false
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        let windows = (attributeValue(application, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        if let targetWindow = windows.first(where: { window in
            descendants(of: window, limit: 1_600)
                .contains(where: { elementURL($0).contains("/epitaxy/\(target.localSessionID)") })
        }) {
            raise(targetWindow, in: app)
            islandLog("focused Claude exact window localSession=\(target.localSessionID)")
            return true
        }

        let elements = descendants(of: application, limit: 1_600)
        let candidates = focusCandidates(target)
        for candidate in candidates {
            let matches = elements.filter { element in
                let role = attributeString(element, kAXRoleAttribute)
                return (role == kAXButtonRole || role == kAXPopUpButtonRole)
                    && labels(for: element).contains(where: { labelMatches($0, candidate: candidate) })
            }
            guard matches.count == 1, let button = matches.first else { continue }

            activate(app)
            if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                islandLog("focused Claude localSession=\(target.localSessionID) label=\(candidate)")
                return true
            }
        }

        if focusWindowViaSystemEvents(title: target.title) {
            islandLog("focused Claude via System Events localSession=\(target.localSessionID)")
            return true
        }

        if !AXIsProcessTrusted(), !didRequestAccessibility {
            didRequestAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            islandLog("requested Accessibility permission for Claude exact focus")
        }

        activate(app)
        let buttonLabels = elements
            .filter { attributeString($0, kAXRoleAttribute) == kAXButtonRole }
            .flatMap(labels)
            .filter { !$0.isEmpty }
        let diagnosticLabels = buttonLabels
            .filter { label in
                let normalized = normalizedLabel(label)
                return normalized.contains("session")
                    || normalized.contains("response")
                    || candidates.contains(where: { normalized.contains(normalizedLabel($0)) })
            }
            .prefix(12)
            .joined(separator: " | ")
        islandLog(
            "Claude exact focus unavailable localSession=\(target.localSessionID) "
                + "trusted=\(AXIsProcessTrusted()) elements=\(elements.count) buttons=\(buttonLabels.count) "
                + "candidates=\(candidates.joined(separator: ",")) labels=\(diagnosticLabels); activated app only"
        )
        return true
    }

    private static func focusWindowViaSystemEvents(title: String?) -> Bool {
        guard let title = title.map(AgentText.singleLine), !title.isEmpty else { return false }
        let titleLiteral = appleScriptLiteral(title)
        let script = """
        tell application "System Events"
            if not (exists process "Claude") then return ""
            tell process "Claude"
                set frontmost to true
                set targetWindowTitle to \(titleLiteral)
                set titleWindows to every window whose name is targetWindowTitle
                if (count of titleWindows) is not 1 then return ""
                set index of item 1 of titleWindows to 1
                return "focused"
            end tell
        end tell
        """
        return runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "focused"
    }

    private static func descendants(of root: AXUIElement, limit: Int) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = [root]
        var index = 0

        while index < queue.count, result.count < limit {
            let element = queue[index]
            index += 1
            result.append(element)
            if let children = attributeValue(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return result
    }

    private static func focusCandidates(_ target: ClaudeAppJumpTarget) -> [String] {
        var candidates: [String] = []
        if let title = target.title,
           !isGenericTitle(title) {
            appendUnique(title, to: &candidates)
        }
        if let cwd = target.cwd {
            let workspace = URL(fileURLWithPath: cwd).lastPathComponent
            appendUnique(workspace, to: &candidates)
            let humanized = workspace.replacingOccurrences(
                of: #"([A-Za-z])([0-9])"#,
                with: "$1 $2",
                options: .regularExpression
            )
            appendUnique(humanized, to: &candidates)
        }
        return candidates.sorted { $0.count > $1.count }
    }

    private static func labels(for element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .compactMap { attributeString(element, $0) }
            .filter { !$0.isEmpty }
    }

    private static func labelMatches(_ rawLabel: String, candidate rawCandidate: String) -> Bool {
        let label = normalizedLabel(rawLabel)
        let candidate = normalizedLabel(rawCandidate)
        guard candidate.count >= 3 else { return false }
        return label == candidate
            || label.hasSuffix(" \(candidate)")
            || label.hasSuffix(": \(candidate)")
    }

    private static func normalizedLabel(_ value: String) -> String {
        AgentText.singleLine(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isGenericTitle(_ value: String) -> Bool {
        let title = normalizedLabel(value)
        return title.isEmpty || ["new session", "untitled", "resume"].contains(title)
    }

    private static func appendUnique(_ rawValue: String, to values: inout [String]) {
        let value = AgentText.singleLine(rawValue)
        guard value.count >= 3, !values.contains(value) else { return }
        values.append(value)
    }

    private static func elementURL(_ element: AXUIElement) -> String {
        if let url = attributeValue(element, kAXURLAttribute) as? URL {
            return url.absoluteString
        }
        return attributeString(element, kAXURLAttribute) ?? ""
    }

    private static func attributeString(_ element: AXUIElement, _ attribute: String) -> String? {
        if let value = attributeValue(element, attribute) as? String {
            return value
        }
        return nil
    }

    private static func attributeValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func activate(_ app: NSRunningApplication) {
        _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private static func raise(_ window: AXUIElement, in app: NSRunningApplication) {
        activate(app)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func runAppleScript(_ source: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { ["-e", String($0)] }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
