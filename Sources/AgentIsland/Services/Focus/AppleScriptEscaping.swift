// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

enum AppleScriptEscaping {
    /// Produces a single-line AppleScript string literal. Agent/session metadata
    /// can contain terminal titles or paths, so control and line-separator
    /// characters are removed before interpolation into executable source.
    static func literal(_ value: String) -> String {
        let singleLine = String.UnicodeScalarView(value.unicodeScalars.map { scalar in
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
                || scalar.value == 0x2028
                || scalar.value == 0x2029 {
                return UnicodeScalar(0x20)!
            }
            return scalar
        })
        let escaped = String(singleLine)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
