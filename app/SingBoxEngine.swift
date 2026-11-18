import Foundation

/// First-class Hızlı engine: hardened non-VPN censorship bypass & DNS shield.
/// Supports pure sing-box (TLS Record / TCP Fragment) and Hybrid Shield (sing-box + internal ciadpi).
final class SingBoxEngine: Engine {
    let id: EngineID = .singbox
    let privacyLevel: PrivacyLevel = .none

    static let socksPort = 1081
    static let hybridCiadpiPort = 1082

    private var process: Process?
    private var companionCiadpi: Process?
    private var activeFragmentMode: SingBoxFragmentMode = .hybridShield
    private var activeDNSProfile: SingBoxDNSProfile = .cloudflareSecurity

    var displayName: String {
        if isRunning {
            return "sing-box (\(activeFragmentMode.shortLabel))"
        }
        return "sing-box"
    }

    var isRunning: Bool {
        guard process?.isRunning == true else { return false }
        if let companion = companionCiadpi {
            return companion.isRunning
        }
        return true
    }

    var socksProxy: (host: String, port: Int)? {
        isRunning ? ("127.0.0.1", Self.socksPort) : nil
    }

    static var currentFragmentMode: SingBoxFragmentMode {
        SingBoxFragmentMode.fromStorage(
            UserDefaults.standard.string(forKey: SingBoxFragmentMode.storageKey)
        )
    }

    static var currentDNSProfile: SingBoxDNSProfile {
        SingBoxDNSProfile.fromStorage(
            UserDefaults.standard.string(forKey: SingBoxDNSProfile.storageKey)
        )
    }

    /// Canonical strengthened config generator.
    static func makeConfigJSON(
        fragmentMode: SingBoxFragmentMode = currentFragmentMode,
        dnsProfile: SingBoxDNSProfile = currentDNSProfile
    ) -> String {
        SingBoxConfig.makeJSON(
            listenPort: socksPort,
            fragmentMode: fragmentMode,
            dnsProfile: dnsProfile,
            ciadpiPort: hybridCiadpiPort
        )
    }

    /// Automatic DoH reachability check with failover if ISP blocks the preferred DoH server.
    private static func selectHealthyDNSProfile(preferred: SingBoxDNSProfile) -> SingBoxDNSProfile {
        for candidate in preferred.failoverCandidates {
            if ConnectionProbe.isTCPPortReachable(host: candidate.serverIP, port: 443, timeoutMs: 350) {
                if candidate != preferred {
                    LogManager.shared.appendLog("⚠️ DoH yedekleme: \(preferred.shortName) erişilemedi → \(candidate.shortName) seçildi")
                }
                return candidate
            }
        }
        return preferred
    }

    /// Launches internal localhost-only ciadpi (port 1082) for Hybrid Shield chaining.
    private func startCompanionCiadpiIfAvailable() -> Bool {
        guard let ciadpiPath = try? BinaryLocator.prepareExecutable("ciadpi") else {
            LogManager.shared.appendLog("⚠️ Hibrit Zırh için ciadpi bulunamadı — saf sing-box TLS Record moduna geçiliyor")
            return false
        }

        if ConnectionProbe.isLocalPortOpen(Self.hybridCiadpiPort) {
            _ = ProcessRunner.runSync("/usr/bin/pkill", args: ["-9", "-f", "ciadpi.*-p \(Self.hybridCiadpiPort)"])
            Thread.sleep(forTimeInterval: 0.1)
        }

        let args = [
            "-i", "127.0.0.1",
            "-p", String(Self.hybridCiadpiPort),
            "-r", "1+s", "-M", "h",
            "-A", "torst,redirect,ssl_err",
            "-s", "1+s", "-r", "1+s",
            "-A", "torst,redirect,ssl_err",
            "-d", "1", "-s", "1",
            "-L", "3", "-u", "3600"
        ]
        let proc = ProcessRunner.create(ciadpiPath, args: args)
        ProcessRunner.attachLogPipes(to: proc)
        do {
            try proc.run()
        } catch {
            LogManager.shared.appendLog("⚠️ Hibrit ciadpi başlatılamadı (\(error.localizedDescription)) — saf sing-box moduna geçiliyor")
            return false
        }
        companionCiadpi = proc

        let ready = ConnectionProbe.waitForLocalPort(Self.hybridCiadpiPort, timeout: 1.5, step: 0.05)
        if companionCiadpi?.isRunning != true || !ready {
            stopCompanionCiadpi()
            LogManager.shared.appendLog("⚠️ Hibrit ciadpi port \(Self.hybridCiadpiPort) açılamadı — saf sing-box moduna geçiliyor")
            return false
        }
        return true
    }

    private func stopCompanionCiadpi() {
        guard let comp = companionCiadpi else { return }
        let pid = comp.processIdentifier
        ProcessRunner.detachLogPipes(from: comp)
        comp.terminate()
        if pid > 0 {
            _ = ProcessRunner.runSync("/bin/kill", args: ["-9", String(pid)])
        }
        companionCiadpi = nil
    }

    func start() throws {
        let path = try BinaryLocator.prepareExecutable("sing-box")
        let configDir = NSString(string: "~/.config/freenet").expandingTildeInPath
        let configPath = configDir + "/sing-box.json"

        var effectiveMode = Self.currentFragmentMode
        if effectiveMode == .hybridShield {
            if !startCompanionCiadpiIfAvailable() {
                effectiveMode = .recordFragment
            }
        }
        let effectiveDNS = Self.selectHealthyDNSProfile(preferred: Self.currentDNSProfile)
        activeFragmentMode = effectiveMode
        activeDNSProfile = effectiveDNS

        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try Self.makeConfigJSON(fragmentMode: effectiveMode, dnsProfile: effectiveDNS)
            .write(toFile: configPath, atomically: true, encoding: .utf8)

        // Clear stale orphan sing-box if our port is already occupied
        if ConnectionProbe.isLocalPortOpen(Self.socksPort) {
            _ = ProcessRunner.runSync("/usr/bin/killall", args: ["-9", "sing-box"])
            Thread.sleep(forTimeInterval: 0.15)
        }

        let proc = ProcessRunner.create(path, args: ["run", "-c", configPath])
        ProcessRunner.attachLogPipes(to: proc)
        LogManager.shared.appendLog(
            "--- sing-box başlatılıyor (Mixed 127.0.0.1:\(Self.socksPort), DoH \(effectiveDNS.shortName), QUIC+DNS-Hijack+BTK-Block, \(effectiveMode.shortLabel)) ---"
        )
        do {
            try proc.run()
        } catch {
            stopCompanionCiadpi()
            throw EngineError.startFailed(error.localizedDescription)
        }
        process = proc
        let ready = ConnectionProbe.waitForLocalPort(Self.socksPort, timeout: 1.5, step: 0.05)
        if process?.isRunning != true {
            process = nil
            stopCompanionCiadpi()
            throw EngineError.startFailed("sing-box process hemen çıktı.")
        }
        if !ready {
            stop()
            throw EngineError.startFailed("sing-box port \(Self.socksPort) dinlemeye geçemedi.")
        }
        if !ProxyService.shared.enableMixedProxy(host: "127.0.0.1", port: Self.socksPort) {
            stop()
            throw EngineError.startFailed(
                "Sistem proxy açılamadı (macOS parola veya «Şifresiz Geçişi Aktif Et» gerekli). Port \(Self.socksPort)."
            )
        }
    }

    func stop() {
        let had = process != nil || companionCiadpi != nil || isRunning
        ProcessRunner.detachLogPipes(from: process)
        process?.terminate()
        process = nil
        stopCompanionCiadpi()
        if had {
            LogManager.shared.appendLog("--- sing-box durduruldu ---")
            _ = ProcessRunner.runSync("/usr/bin/killall", args: ["-9", "sing-box"])
            ProxyService.shared.disableSOCKS()
        }
    }
}
