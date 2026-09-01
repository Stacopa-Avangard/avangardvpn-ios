//
//  ByteFormat.swift — human-readable byte counts and rates.
//
//  ⚠️ Base 1000, not 1024, and deliberately NOT ByteCountFormatter.
//
//  The backend accumulates quota in base-1000 units and the portal prints them
//  that way, so a 10 GB plan has to read as "10.0 GB" and not as "9.3 GB". This
//  file is a direct port of Android's `util/Format.kt` for that reason — the
//  same account viewed on the two clients must show the same number.
//
//  QuotaMeter used to call ByteCountFormatter with `.binary`, which is where
//  the two clients disagreed.
//
import Foundation

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let bytes = max(0, bytes)
        if bytes < 1000 { return "\(bytes) B" }

        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1000
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }

    static func rate(_ bytesPerSecond: Int64) -> String {
        "\(string(bytesPerSecond))/s"
    }
}
