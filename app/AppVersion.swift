import Foundation

/// Single source of truth for displayed version (must match Info.plist).
enum AppVersion {
    /// Marketing version. Keep in sync with CFBundleShortVersionString and VERSION file.
    static let marketing = "1.2.0"
    static let build = "3"

    static var display: String { "v\(shortVersion)" }

    /// Prefer Info.plist at runtime; fall back to compile-time constant.
    static var shortVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !v.isEmpty {
            return v
        }
        return marketing
    }

    static var buildNumber: String {
        if let v = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !v.isEmpty {
            return v
        }
        return build
    }

    static var fullLabel: String {
        "\(display) (\(buildNumber))"
    }

    /// Compare dotted versions: returns true if `remote` is newer than `local`.
    static func isRemoteNewer(_ remote: String, than local: String) -> Bool {
        let r = parse(remote)
        let l = parse(local)
        let n = max(r.count, l.count)
        for i in 0..<n {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func parse(_ s: String) -> [Int] {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return cleaned.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    /// Supports plain `1.2.0` or JSON `{"version":"1.2.0","notes":"...","url":"..."}`.
    static func parseVERSIONFile(_ text: String) -> (version: String, notes: String?, url: String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = obj["version"] as? String {
            return (v, obj["notes"] as? String, obj["url"] as? String)
        }
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            let ver = s.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? s
            if !ver.isEmpty { return (ver, nil, nil) }
        }
        return nil
    }
}
