import Foundation

/// Maks. Gizlilik engine — real anonymity via Tor SOCKS.
/// Does not fake "connected" when tor binary is missing.
final class TorEngine: Engine {
    let id: EngineID = .tor
    let displayName = "Tor"
    let privacyLevel: PrivacyLevel = .anonymity

    static let socksPort = 9050
    static let controlPort = 9051

    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }

    var socksProxy: (host: String, port: Int)? {
        isRunning ? ("127.0.0.1", Self.socksPort) : nil
    }

    /// Optional bridge lines from UserDefaults (one per line). Logged masked.
    static var bridgeLines: [String] {
        let raw = UserDefaults.standard.string(forKey: "freenetTorBridges") ?? ""
        return raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func start() throws {
        // Prefer bundle; fall back to Homebrew/system tor. Never fake "connected".
        if TorReadiness.missingBinaryMessage(binDir: BinaryLocator.resourcesBinDir) != nil {
            // Last chance: PATH / brew may still resolve even if default candidates missed
            if BinaryLocator.resolve("tor") == nil {
                LogManager.shared.appendLog("❌ \(TorReadiness.missingMessage)")
                throw EngineError.binaryMissing("tor")
            }
        }
        _ = BinaryLocator.tryBundleSystemTor()
        let torPath = try BinaryLocator.prepareExecutable("tor")
        LogManager.shared.appendLog("Tor ikilisi: \(torPath)")

        let dataDir = NSString(string: "~/.config/freenet/tor").expandingTildeInPath
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        let torrcPath = dataDir + "/torrc"
        try writeTorrc(to: torrcPath, dataDir: dataDir)

        // Optional pluggable transports if present
        // ClientTransportPlugin lines already in torrc when binaries exist

        let proc = ProcessRunner.create(torPath, args: ["-f", torrcPath])
        ProcessRunner.attachLogPipes(to: proc)
        LogManager.shared.appendLog("--- Tor başlatılıyor (SOCKS \(Self.socksPort)) — yavaş olabilir ---")
        if !Self.bridgeLines.isEmpty {
            LogManager.shared.appendLog("Tor: \(Self.bridgeLines.count) köprü satırı yapılandırıldı (içerik maskeli)")
        }
        do {
            try proc.run()
        } catch {
            throw EngineError.startFailed(error.localizedDescription)
        }
        process = proc

        // Brief wait for bootstrap listen
        Thread.sleep(forTimeInterval: 0.8)
        if process?.isRunning != true {
            process = nil
            throw EngineError.startFailed("Tor process hemen çıktı. torrc / binary kontrol edin.")
        }

        if !ProxyService.shared.enableSOCKS(host: "127.0.0.1", port: Self.socksPort) {
            stop()
            throw EngineError.startFailed(
                "SOCKS proxy açılamadı (macOS parola veya «Şifresiz Geçişi Aktif Et» gerekli). Port \(Self.socksPort)."
            )
        }
        LogManager.shared.appendLog("Tor: SOCKS dinleyicisi 127.0.0.1:\(Self.socksPort) (bootstrap loglarına bakın)")
    }

    func stop() {
        let had = process != nil || isRunning
        ProcessRunner.detachLogPipes(from: process)
        process?.terminate()
        process = nil
        if had {
            LogManager.shared.appendLog("--- Tor durduruldu ---")
            _ = ProcessRunner.runSync("/usr/bin/killall", args: ["-9", "tor"])
            ProxyService.shared.disableSOCKS()
        }
    }

    private func writeTorrc(to path: String, dataDir: String) throws {
        var lines: [String] = [
            "DataDirectory \(dataDir)/data",
            "SocksPort 127.0.0.1:\(Self.socksPort)",
            "ControlPort 127.0.0.1:\(Self.controlPort)",
            "CookieAuthentication 1",
            "Log notice stdout",
            "AvoidDiskWrites 1"
        ]

        if BinaryLocator.exists("obfs4proxy") {
            let p = BinaryLocator.path(for: "obfs4proxy")
            lines.append("ClientTransportPlugin obfs4 exec \(p)")
        }
        if BinaryLocator.exists("snowflake-client") {
            let p = BinaryLocator.path(for: "snowflake-client")
            lines.append("ClientTransportPlugin snowflake exec \(p)")
        }

        let bridges = Self.bridgeLines
        if !bridges.isEmpty {
            lines.append("UseBridges 1")
            for b in bridges {
                // Only allow bridge lines that look like Tor bridge syntax
                if isSafeBridgeLine(b) {
                    lines.append("Bridge \(b)")
                } else {
                    LogManager.shared.appendLog("Tor: güvenli olmayan köprü satırı atlandı")
                }
            }
        }

        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: dataDir + "/data", withIntermediateDirectories: true)
    }

    private func isSafeBridgeLine(_ line: String) -> Bool {
        if line.count > 512 { return false }
        if line.rangeOfCharacter(from: CharacterSet(charactersIn: ";|&`\n\r$")) != nil { return false }
        // Expect starts with transport or IP
        return true
    }
}
