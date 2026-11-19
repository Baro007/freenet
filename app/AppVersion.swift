import Foundation

/// Single source of truth for displayed version (must match Info.plist).
enum AppVersion {
    /// Marketing version. Keep in sync with CFBundleShortVersionString and VERSION file.
    static let marketing = "1.2.1"
    static let build = "4"

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

    /// Supports plain `1.2.0` or JSON `{"version":"1.2.0","notes":"...","url":"...","sha256":"..."}`.
    static func parseVERSIONFile(_ text: String) -> (version: String, notes: String?, url: String?)? {
        guard let m = parseVersionManifest(text) else { return nil }
        return (m.version, m.notes, m.url)
    }

    struct VersionManifest: Equatable {
        let version: String
        let notes: String?
        let url: String?
        let sha256: String?
    }

    static func parseVersionManifest(_ text: String) -> VersionManifest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = obj["version"] as? String, !v.isEmpty {
            let rawHash = obj["sha256"] as? String
            let sha = rawHash.flatMap { UpdateSecurity.parseSHA256Text($0) }
            return VersionManifest(
                version: v,
                notes: obj["notes"] as? String,
                url: obj["url"] as? String,
                sha256: sha
            )
        }
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            let ver = s.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? s
            if !ver.isEmpty {
                return VersionManifest(version: ver, notes: nil, url: nil, sha256: nil)
            }
        }
        return nil
    }
}

/// Pure security checks for self-update downloads and checksums (unit-tested directly).
public enum UpdateSecurity {
    /// Strict HTTPS + GitHub origin allowlist for Baro007/freenet release assets.
    public static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        let path = url.path
        switch host {
        case "github.com":
            return path.hasPrefix("/Baro007/freenet/")
        case "raw.githubusercontent.com":
            return path.hasPrefix("/Baro007/freenet/")
        case "objects.githubusercontent.com",
             "release-assets.githubusercontent.com",
             "github-releases.githubusercontent.com":
            return !path.isEmpty
        default:
            return false
        }
    }

    /// Parses `<64-hex>`, `sha256:<64-hex>`, or `shasum -a 256` output `<64-hex>  file.zip`.
    public static func parseSHA256Text(_ text: String) -> String? {
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            var token = s.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? s
            if token.lowercased().hasPrefix("sha256:") {
                token = String(token.dropFirst("sha256:".count))
            }
            let lower = token.lowercased()
            if lower.count == 64 && lower.unicodeScalars.allSatisfy({ hexChars.contains($0) }) {
                return lower
            }
        }
        return nil
    }
}

/// Pure parser for GitHub `/releases/latest` JSON payload (unit-tested directly).
public struct UpdateReleaseInfo: Equatable {
    public let tag: String
    public let htmlURL: URL
    public let body: String?
    public let zipDownloadURL: URL?
    public let checksumURL: URL?
    public let digestSHA256: String?
}

public enum UpdateReleaseParser {
    public static func parseLatestRelease(data: Data, fallbackPageURL: URL) -> UpdateReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String, !tag.isEmpty else {
            return nil
        }
        let htmlURL = (obj["html_url"] as? String).flatMap(URL.init(string:)) ?? fallbackPageURL
        let body = obj["body"] as? String

        var zipURL: URL?
        var zipDigest: String?
        var checksumURL: URL?

        if let assets = obj["assets"] as? [[String: Any]] {
            // Prefer freenet*.zip; fall back to any .zip
            let zipAsset = assets.first(where: {
                let n = ($0["name"] as? String ?? "").lowercased()
                return n.contains("freenet") && n.hasSuffix(".zip")
            }) ?? assets.first(where: {
                ($0["name"] as? String ?? "").lowercased().hasSuffix(".zip")
            })

            if let za = zipAsset,
               let urlStr = za["browser_download_url"] as? String,
               let parsedURL = URL(string: urlStr),
               UpdateSecurity.isAllowedDownloadURL(parsedURL) {
                zipURL = parsedURL
                if let digest = za["digest"] as? String {
                    zipDigest = UpdateSecurity.parseSHA256Text(digest)
                }
            }

            let sumAsset = assets.first(where: {
                let n = ($0["name"] as? String ?? "").lowercased()
                return n.hasSuffix(".zip.sha256") || n.hasSuffix(".sha256") || n == "sha256sums"
            })
            if let sa = sumAsset,
               let urlStr = sa["browser_download_url"] as? String,
               let parsedURL = URL(string: urlStr),
               UpdateSecurity.isAllowedDownloadURL(parsedURL) {
                checksumURL = parsedURL
            }
        }

        return UpdateReleaseInfo(
            tag: tag,
            htmlURL: htmlURL,
            body: body,
            zipDownloadURL: zipURL,
            checksumURL: checksumURL,
            digestSHA256: zipDigest
        )
    }
}
