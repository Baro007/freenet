import Foundation

enum BinaryLocator {
    static var resourcesBinDir: String {
        Bundle.main.bundlePath + "/Contents/Resources/bin"
    }

    static func path(for name: String) -> String {
        resourcesBinDir + "/" + name
    }

    static func checksumFilePath() -> String {
        path(for: "CHECKSUMS.sha256")
    }

    /// Candidate absolute paths for a named helper binary.
    /// For `tor`, prefer Homebrew/system first (correct dylib linkage), then bundle.
    /// Other tools: bundle first, then system.
    static func candidatePaths(for name: String) -> [String] {
        let system: [String] = [
            "/opt/homebrew/bin/\(name)",
            "/opt/homebrew/opt/\(name)/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/local/opt/\(name)/bin/\(name)"
        ]
        var list: [String] = []
        if name == "tor" {
            list.append(contentsOf: system)
            list.append(path(for: name))
        } else {
            list.append(path(for: name))
            list.append(contentsOf: system)
        }
        if let which = which(name) {
            list.append(which)
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    static func resolve(_ name: String) -> String? {
        let fm = FileManager.default
        for p in candidatePaths(for: name) {
            if fm.isExecutableFile(atPath: p) || fm.fileExists(atPath: p) {
                return p
            }
        }
        return nil
    }

    static func exists(_ name: String) -> Bool {
        resolve(name) != nil
    }

    /// Ensure executable bit; verify checksum when binary is the bundled copy.
    static func prepareExecutable(_ name: String) throws -> String {
        guard let p = resolve(name) else {
            throw EngineError.binaryMissing(name)
        }
        // Checksum only for files inside our app bundle
        if p.hasPrefix(resourcesBinDir) {
            let check = ChecksumVerifier.assertSafeToRun(binaryPath: p, checksumFilePath: checksumFilePath())
            if !check.ok {
                throw EngineError.checksumFailed(check.message ?? "checksum failed")
            }
        }
        _ = ProcessRunner.runSync("/bin/chmod", args: ["+x", p])
        return p
    }

    /// Try to place Homebrew tor into the app bundle for next launches (best-effort).
    @discardableResult
    static func tryBundleSystemTor() -> Bool {
        let dest = path(for: "tor")
        if FileManager.default.fileExists(atPath: dest) { return true }
        guard let src = resolve("tor"), !src.hasPrefix(resourcesBinDir) else { return false }
        do {
            try FileManager.default.createDirectory(atPath: resourcesBinDir, withIntermediateDirectories: true)
            // If Resources is read-only in /Applications, this may fail — that's OK
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(atPath: src, toPath: dest)
            _ = ProcessRunner.runSync("/bin/chmod", args: ["+x", dest])
            LogManager.shared.appendLog("Tor sistem kopyası bundle'a alındı.")
            return true
        } catch {
            LogManager.shared.appendLog("Tor bundle kopyası atlandı: \(error.localizedDescription)")
            return false
        }
    }

    private static func which(_ name: String) -> String? {
        let r = ProcessRunner.captureOutput("/usr/bin/which", args: [name])
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

enum EngineError: LocalizedError {
    case binaryMissing(String)
    case checksumFailed(String)
    case startFailed(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let n):
            if n == "tor" {
                return TorReadiness.missingMessage
            }
            return "Gerekli ikili bulunamadı: \(n). Resources/bin veya Homebrew yoluna yerleştirin."
        case .checksumFailed(let m):
            return m
        case .startFailed(let m):
            return m
        case .invalidConfiguration(let m):
            return m
        }
    }
}
