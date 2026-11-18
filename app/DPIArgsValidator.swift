import Foundation

/// Validates user-supplied ciadpi arguments before process launch.
/// Never pass raw strings into AppleScript/shell interpolation.
public enum DPIArgsValidator {
    /// Allowlisted flags supported by bundled ciadpi / ByeDPI (v17+).
    public static let allowedFlags: Set<String> = [
        "-i", "-d", "-p", "-s", "-f", "-t", "-a", "-r", "-n", "-e",
        "-w", "-S", "-O", "-M", "-K", "-A", "-u", "-g", "-b",
        "-o", "-q", "-L", "-c", "-m", "-U", "-N",
        "--disorder", "--split", "--ttl", "--port", "--ip",
        "--auto", "--auto-mode", "--cache-ttl", "--tlsrec",
        "--mod-http", "--max-conn", "--no-udp", "--no-domain"
    ]

    /// Hardened multi-strategy localhost-only default for Turkish ISP DPI bypass:
    /// 1) TLS record split at SNI + HTTP host case-mix
    /// 2) Fallback on RST/redirect/SSL-err: SNI split + TLS record split
    /// 3) Fallback: TCP disorder + split
    /// With auto-sorting (-L 3) and 1-hour IP cache (-u 3600).
    public static let defaultArgs =
        "-i 127.0.0.1 -p 1080 -r 1+s -M h -A torst,redirect,ssl_err -s 1+s -r 1+s -A torst,redirect,ssl_err -d 1 -s 1 -L 3 -u 3600"
    public static let defaultPort = 1080
    public static let minPort = 1024
    public static let maxPort = 65535

    public struct Result: Equatable {
        public let arguments: [String]
        public let port: Int
        public let errorMessage: String?

        public var isValid: Bool { errorMessage == nil }
    }

    /// Tokenize and validate. On failure returns empty args + error message.
    public static func validate(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return parseTokens(defaultArgs.split(separator: " ").map(String.init))
        }

        // Reject shell metacharacters entirely (defense in depth).
        let forbidden = CharacterSet(charactersIn: ";|&$`\n\r<>(){}[]!\\\"'")
        if trimmed.rangeOfCharacter(from: forbidden) != nil {
            return Result(arguments: [], port: defaultPort, errorMessage: "DPI args contain forbidden shell characters")
        }

        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return parseTokens(tokens)
    }

    private static func parseTokens(_ tokens: [String]) -> Result {
        var i = 0
        var port = defaultPort
        var out: [String] = []

        while i < tokens.count {
            let t = tokens[i]
            if t.hasPrefix("-") {
                let flag = t
                // Normalize long form aliases we accept as flags only
                if !allowedFlags.contains(flag) {
                    return Result(arguments: [], port: defaultPort, errorMessage: "DPI flag not allowlisted: \(flag)")
                }
                out.append(flag)
                i += 1
                // Flags that expect a numeric/string value
                if needsValue(flag) {
                    guard i < tokens.count else {
                        return Result(arguments: [], port: defaultPort, errorMessage: "Missing value for \(flag)")
                    }
                    let value = tokens[i]
                    if value.hasPrefix("-") {
                        return Result(arguments: [], port: defaultPort, errorMessage: "Missing value for \(flag)")
                    }
                    if !isSafeValue(value) {
                        return Result(arguments: [], port: defaultPort, errorMessage: "Unsafe value for \(flag)")
                    }
                    if flag == "-p" || flag == "--port" {
                        guard let p = Int(value), p >= minPort, p <= maxPort else {
                            return Result(arguments: [], port: defaultPort, errorMessage: "Port out of range (\(minPort)-\(maxPort))")
                        }
                        port = p
                    }
                    out.append(value)
                    i += 1
                }
            } else {
                return Result(arguments: [], port: defaultPort, errorMessage: "Unexpected token: \(t)")
            }
        }

        if out.isEmpty {
            return Result(arguments: [], port: defaultPort, errorMessage: "No valid DPI arguments")
        }
        return Result(arguments: out, port: port, errorMessage: nil)
    }

    private static func needsValue(_ flag: String) -> Bool {
        switch flag {
        case "-i", "-d", "-p", "-s", "-f", "-t", "-e", "-w", "-S", "-O", "-M", "-K", "-A", "-u", "-g", "-b",
             "-r", "-a", "-o", "-q", "-L", "-c", "-m",
             "--disorder", "--split", "--ttl", "--port", "--ip",
             "--auto", "--auto-mode", "--cache-ttl", "--tlsrec", "--mod-http", "--max-conn":
            return true
        default:
            return false
        }
    }

    private static func isSafeValue(_ value: String) -> Bool {
        // Alphanumeric, dots, colons (IPv6), commas, hyphens, underscores, plus (SNI offset expressions like 1+s)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:-,_+"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
