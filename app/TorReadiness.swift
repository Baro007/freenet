import Foundation

/// Pure readiness check for Tor binary layout (testable without launching processes).
enum TorReadiness {
    static let missingMessage =
        "Tor bulunamadı. `brew install tor` çalıştırın veya tor ikilisini Resources/bin altına koyun."

    /// Returns nil if tor is available under binDir or common system paths; otherwise error text.
    static func missingBinaryMessage(binDir: String, systemCandidates: [String] = defaultSystemCandidates) -> String? {
        let fm = FileManager.default
        let bundled = (binDir as NSString).appendingPathComponent("tor")
        if fm.fileExists(atPath: bundled) { return nil }
        for p in systemCandidates {
            if fm.fileExists(atPath: p) { return nil }
        }
        return missingMessage
    }

    static var defaultSystemCandidates: [String] {
        [
            "/opt/homebrew/bin/tor",
            "/opt/homebrew/opt/tor/bin/tor",
            "/usr/local/bin/tor",
            "/usr/local/opt/tor/bin/tor"
        ]
    }
}
