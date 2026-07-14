// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

enum IslandDisplayMode: String {
    case notch
    case floating
}

enum IslandDisplayModeStore {
    private static let modeKey = "agentIsland.display.mode"
    private static let floatingXKey = "agentIsland.display.floatingX"
    private static let floatingYKey = "agentIsland.display.floatingY"
    private static let floatingOriginsKey = "agentIsland.display.floatingOrigins"

    static var mode: IslandDisplayMode {
        get { IslandDisplayMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .notch }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var floatingOrigin: NSPoint? {
        get {
            guard UserDefaults.standard.object(forKey: floatingXKey) != nil,
                  UserDefaults.standard.object(forKey: floatingYKey) != nil else { return nil }
            return NSPoint(
                x: UserDefaults.standard.double(forKey: floatingXKey),
                y: UserDefaults.standard.double(forKey: floatingYKey)
            )
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: floatingXKey)
                UserDefaults.standard.removeObject(forKey: floatingYKey)
                return
            }
            UserDefaults.standard.set(newValue.x, forKey: floatingXKey)
            UserDefaults.standard.set(newValue.y, forKey: floatingYKey)
        }
    }

    static func floatingOrigin(on screen: NSScreen) -> NSPoint? {
        let key = String(screen.displayId)
        guard let origins = UserDefaults.standard.dictionary(forKey: floatingOriginsKey),
              let value = origins[key] as? [String: Double],
              let x = value["x"],
              let y = value["y"] else {
            return floatingOrigin
        }
        return NSPoint(x: x, y: y)
    }

    static func setFloatingOrigin(_ origin: NSPoint?, on screen: NSScreen) {
        guard let origin else { return }
        var origins = UserDefaults.standard.dictionary(forKey: floatingOriginsKey) ?? [:]
        origins[String(screen.displayId)] = ["x": origin.x, "y": origin.y]
        UserDefaults.standard.set(origins, forKey: floatingOriginsKey)
        floatingOrigin = origin
    }
}
