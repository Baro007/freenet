import Foundation
import Darwin

/// Dengeli (WARP) engine — Cloudflare IP masking with two selectable transports:
/// 1) `sing-box WARP` (default): userspace WireGuard inside bundled sing-box (127.0.0.1:1083).
///    No root, no utun routing hijack, zero disruption to local/cloudflared sockets,
///    automatic multi-IP/port failover with live `warp=on` verification, and DoH-over-WARP DNS shield.
/// 2) `Sistem Tüneli (wg-quick)`: full-device L3 utun tunnel with MTU 1380 + Keepalive 25 + DNS alignment.
final class WarpEngine: Engine {
    let id: EngineID = .warp
    let privacyLevel: PrivacyLevel = .ipMask

    static let warpProxyPort = 1083

    private let tunnelName = "wgcf"
    private let tunnelInternalIP = "172.16.0.2"
    private let syncedProfileKey = "freenetWarpSyncedProfile"

    private var singBoxProcess: Process?
    private var activeEndpoint: WarpEndpointTarget?
    private var activeTransport: WarpTransportMode = .singboxWarp

    var displayName: String {
        if singBoxProcess?.isRunning == true {
            if let ep = activeEndpoint {
                return "WARP (sing-box · :\(ep.port))"
            }
            return "WARP (sing-box)"
        }
        if isWgQuickInterfaceUp {
            return "WARP (Sistem Tüneli)"
        }
        return "WARP"
    }

    static var selectedTransport: WarpTransportMode {
        WarpTransportMode.fromStorage(
            UserDefaults.standard.string(forKey: WarpTransportMode.storageKey)
        )
    }

    static var selectedPort: WarpEndpointPort {
        WarpEndpointPort.fromStorage(
            UserDefaults.standard.string(forKey: WarpEndpointPort.storageKey)
        )
    }

    static var selectedDNSProfile: SingBoxDNSProfile {
        SingBoxDNSProfile.fromStorage(
            UserDefaults.standard.string(forKey: SingBoxDNSProfile.storageKey)
        )
    }

    var isRunning: Bool {
        singBoxProcess?.isRunning == true || isWgQuickInterfaceUp
    }

    var socksProxy: (host: String, port: Int)? {
        singBoxProcess?.isRunning == true ? ("127.0.0.1", Self.warpProxyPort) : nil
    }

    /// Zero-subprocess check via POSIX getifaddrs() — avoids spawning /sbin/ifconfig every 3s.
    var isWgQuickInterfaceUp: Bool {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return false
        }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            if let sa = current.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = getnameinfo(
                    sa,
                    socklen_t(sa.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if rc == 0, String(cString: host) == tunnelInternalIP {
                    return true
                }
            }
            ptr = current.pointee.ifa_next
        }
        return false
    }

    func start() throws {
        let transport = Self.selectedTransport
        activeTransport = transport
        switch transport {
        case .singboxWarp:
            try startSingBoxWarp()
        case .systemTunnel:
            try startSystemTunnel()
        }
    }

    func stop() {
        let hadSingBox = singBoxProcess != nil
        if let proc = singBoxProcess {
            let pid = proc.processIdentifier
            ProcessRunner.detachLogPipes(from: proc)
            proc.terminate()
            if pid > 0 {
                _ = ProcessRunner.runSync("/bin/kill", args: ["-9", String(pid)])
            }
            singBoxProcess = nil
            activeEndpoint = nil
        }
        if hadSingBox {
            ProxyService.shared.disableSOCKS()
            LogManager.shared.appendLog("--- WARP (sing-box) durduruldu ---")
        }
        if isWgQuickInterfaceUp {
            let wq = ProxyService.shared.wgQuickPath
            _ = ProxyService.shared.runPrivileged(wq, args: ["down", tunnelName])
            LogManager.shared.appendLog("--- WARP (Sistem Tüneli) kapatıldı ---")
        }
    }

    // MARK: - sing-box Native WARP (Recommended: root-free, multi-endpoint failover, DoH-over-WARP)

    private func startSingBoxWarp() throws {
        // Never run two simultaneous WireGuard peers with the same private key.
        if isWgQuickInterfaceUp {
            let wq = ProxyService.shared.wgQuickPath
            _ = ProxyService.shared.runPrivileged(wq, args: ["down", tunnelName])
            Thread.sleep(forTimeInterval: 0.3)
        }

        let singBoxPath = try BinaryLocator.prepareExecutable("sing-box")
        guard let wgcf = loadOrCreateWgcfConfig() else {
            throw EngineError.startFailed(
                "WARP anahtarları bulunamadı (~/.config/wireguard/wgcf.conf). Önce `wgcf register && wgcf generate` veya Sistem Tüneli kurulumu gerekli."
            )
        }

        let configDir = NSString(string: "~/.config/freenet").expandingTildeInPath
        let configPath = configDir + "/sing-box-warp.json"
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        if ConnectionProbe.isLocalPortOpen(Self.warpProxyPort) {
            _ = ProcessRunner.runSync("/usr/bin/pkill", args: ["-9", "-f", "sing-box-warp.json"])
            Thread.sleep(forTimeInterval: 0.15)
        }

        let dnsProfile = Self.selectedDNSProfile
        let targets = WgcfConfigParser.failoverTargets(preferredPort: Self.selectedPort.portNumber)
        var triedSummary: [String] = []

        for target in targets {
            let json = SingBoxWarpConfig.makeJSON(
                wgcf: wgcf,
                endpoint: target,
                listenPort: Self.warpProxyPort,
                dnsProfile: dnsProfile
            )
            try json.write(toFile: configPath, atomically: true, encoding: .utf8)
            _ = ProcessRunner.runSync("/bin/chmod", args: ["600", configPath])

            let proc = ProcessRunner.create(singBoxPath, args: ["run", "-c", configPath])
            ProcessRunner.attachLogPipes(to: proc)
            LogManager.shared.appendLog(
                "WARP (sing-box) deneniyor: \(target.host):\(target.port) · DoH \(dnsProfile.shortName)…"
            )
            do {
                try proc.run()
            } catch {
                triedSummary.append("\(target.host):\(target.port) (launch err)")
                continue
            }
            singBoxProcess = proc

            let listening = ConnectionProbe.waitForLocalPort(Self.warpProxyPort, timeout: 1.5, step: 0.05)
            guard proc.isRunning, listening else {
                stopSingBoxWarpProcessOnly()
                triedSummary.append("\(target.host):\(target.port) (bind fail)")
                continue
            }

            if verifyWarpTrace(socksPort: Self.warpProxyPort) {
                activeEndpoint = target
                if !ProxyService.shared.enableMixedProxy(host: "127.0.0.1", port: Self.warpProxyPort) {
                    stop()
                    throw EngineError.startFailed(
                        "Sistem proxy açılamadı (macOS parola veya «Şifresiz Geçişi Aktif Et» gerekli). Port \(Self.warpProxyPort)."
                    )
                }
                LogManager.shared.appendLog(
                    "--- WARP (sing-box) doğrulandı ✅ \(target.host):\(target.port) · MTU \(WarpConfigOptimizer.optimalMTU) · DoH \(dnsProfile.shortName) ---"
                )
                return
            }

            LogManager.shared.appendLog("⚠️ WARP \(target.host):\(target.port) yanıt vermedi, sonraki endpoint deneniyor…")
            triedSummary.append("\(target.host):\(target.port) (timeout)")
            stopSingBoxWarpProcessOnly()
        }

        throw EngineError.startFailed(
            "WARP hiçbir port/endpoint üzerinden doğrulanamadı (\(triedSummary.joined(separator: ", ")))."
        )
    }

    private func stopSingBoxWarpProcessOnly() {
        guard let proc = singBoxProcess else { return }
        let pid = proc.processIdentifier
        ProcessRunner.detachLogPipes(from: proc)
        proc.terminate()
        if pid > 0 {
            _ = ProcessRunner.runSync("/bin/kill", args: ["-9", String(pid)])
        }
        singBoxProcess = nil
        activeEndpoint = nil
    }

    /// Verifies BOTH real DNS resolution AND Cloudflare WARP egress (`warp=on`) via domain query.
    private func verifyWarpTrace(socksPort: Int?) -> Bool {
        var args = ["-sS", "--max-time", "5"]
        if let port = socksPort {
            args.append(contentsOf: ["--socks5-hostname", "127.0.0.1:\(port)"])
        } else {
            args.append(contentsOf: ["--noproxy", "*"])
        }
        args.append("https://cloudflare.com/cdn-cgi/trace")
        let r = ProcessRunner.captureOutput("/usr/bin/curl", args: args)
        return r.status == 0 && (r.stdout.contains("warp=on") || r.stdout.contains("warp=plus"))
    }

    // MARK: - Classic System Tunnel (wg-quick / wireguard-go L3 utun)

    private func startSystemTunnel() throws {
        stopSingBoxWarpProcessOnly()
        guard ensureSystemTunnelSetup() else {
            throw EngineError.startFailed("WARP kurulumu tamamlanamadı (Homebrew / wgcf).")
        }
        let wq = ProxyService.shared.wgQuickPath
        let ok = ProxyService.shared.runPrivileged(wq, args: ["up", tunnelName])
        if !ok && !isWgQuickInterfaceUp {
            throw EngineError.startFailed("WARP tüneli açılamadı.")
        }
        let port = Self.selectedPort.portNumber
        if verifyWarpTrace(socksPort: nil) {
            LogManager.shared.appendLog(
                "--- WARP (Sistem Tüneli) doğrulandı ✅ (Port \(port), MTU \(WarpConfigOptimizer.optimalMTU), Cloudflare güven modeli) ---"
            )
        } else {
            LogManager.shared.appendLog(
                "⚠️ WARP arayüzü açıldı ancak UDP:\(port) yanıt doğrulaması başarısız — ağınız portu engelliyorsa Ayarlar'dan başka port veya sing-box WARP seçin."
            )
        }
    }

    /// Reads existing user wgcf.conf / wgcf-profile.conf, or generates one via Homebrew wgcf.
    private func loadOrCreateWgcfConfig() -> WgcfConfig? {
        let fm = FileManager.default
        let configDir = NSString(string: "~/.config/wireguard").expandingTildeInPath
        let configPath = configDir + "/wgcf.conf"
        let profilePath = configDir + "/wgcf-profile.conf"

        if let raw = (try? String(contentsOfFile: configPath, encoding: .utf8))
            ?? (try? String(contentsOfFile: profilePath, encoding: .utf8)),
           let parsed = WgcfConfigParser.parse(raw) {
            return parsed
        }

        // Attempt automatic wgcf registration if Homebrew wgcf is installed
        let wgcfPath = ProxyService.shared.brewPrefix + "/wgcf"
        guard fm.fileExists(atPath: wgcfPath) else { return nil }
        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: configDir + "/wgcf-account.toml") {
            let reg = ProcessRunner.create(wgcfPath, args: ["register", "--accept-tos"])
            reg.currentDirectoryURL = URL(fileURLWithPath: configDir)
            try? reg.run()
            reg.waitUntilExit()
        }
        let gen = ProcessRunner.create(wgcfPath, args: ["generate"])
        gen.currentDirectoryURL = URL(fileURLWithPath: configDir)
        try? gen.run()
        gen.waitUntilExit()

        // wgcf generate writes wgcf-profile.conf — mirror to wgcf.conf cleanly
        if !fm.fileExists(atPath: configPath), fm.fileExists(atPath: profilePath) {
            try? fm.copyItem(atPath: profilePath, toPath: configPath)
            _ = ProcessRunner.runSync("/bin/chmod", args: ["600", configPath])
        }
        guard let raw = (try? String(contentsOfFile: configPath, encoding: .utf8))
            ?? (try? String(contentsOfFile: profilePath, encoding: .utf8)) else {
            return nil
        }
        return WgcfConfigParser.parse(raw)
    }

    private func ensureSystemTunnelSetup() -> Bool {
        let fm = FileManager.default
        let brewPrefix = ProxyService.shared.brewPrefix
        let brewPath = brewPrefix + "/brew"
        let wgcfPath = brewPrefix + "/wgcf"
        let wgQuick = brewPrefix + "/wg-quick"

        if !fm.fileExists(atPath: wgcfPath) || !fm.fileExists(atPath: wgQuick) {
            LogManager.shared.appendLog("WARP bağımlılıkları kontrol ediliyor…")
            if !fm.fileExists(atPath: brewPath) {
                LogManager.shared.appendLog("Homebrew yok — WARP Sistem Tüneli için brew install wireguard-tools wgcf gerekli.")
                return false
            }
            let task = ProcessRunner.create(brewPath, args: ["install", "wireguard-tools", "wgcf"])
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                return false
            }
        }

        let configDir = NSString(string: "~/.config/wireguard").expandingTildeInPath
        let configPath = configDir + "/wgcf.conf"
        let profilePath = configDir + "/wgcf-profile.conf"

        if !fm.fileExists(atPath: configPath) {
            if fm.fileExists(atPath: profilePath) {
                try? fm.copyItem(atPath: profilePath, toPath: configPath)
                _ = ProcessRunner.runSync("/bin/chmod", args: ["600", configPath])
            } else {
                try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
                let reg = ProcessRunner.create(wgcfPath, args: ["register", "--accept-tos"])
                reg.currentDirectoryURL = URL(fileURLWithPath: configDir)
                try? reg.run()
                reg.waitUntilExit()
                let gen = ProcessRunner.create(wgcfPath, args: ["generate"])
                gen.currentDirectoryURL = URL(fileURLWithPath: configDir)
                try? gen.run()
                gen.waitUntilExit()
                if !fm.fileExists(atPath: configPath), fm.fileExists(atPath: profilePath) {
                    try? fm.copyItem(atPath: profilePath, toPath: configPath)
                    _ = ProcessRunner.runSync("/bin/chmod", args: ["600", configPath])
                }
                if !fm.fileExists(atPath: configPath) {
                    return false
                }
            }
        }

        // Optimize local wgcf.conf (MTU 1380, Keepalive 25, alternate IP 162.159.193.1 + non-2408 port, aligned DNS)
        let targetPort = Self.selectedPort.portNumber
        let dnsProfile = Self.selectedDNSProfile
        let targetHost = WarpConfigOptimizer.preferredEndpointHost
        let expectedProfile = WarpConfigOptimizer.profileSignature(
            port: targetPort,
            endpointHost: targetHost,
            dnsIP: dnsProfile.serverIP
        )
        if let rawConfig = try? String(contentsOfFile: configPath, encoding: .utf8) {
            let backupPath = configPath + ".orig.bak"
            if !fm.fileExists(atPath: backupPath) {
                try? rawConfig.write(toFile: backupPath, atomically: true, encoding: .utf8)
                _ = ProcessRunner.runSync("/bin/chmod", args: ["600", backupPath])
            }
            let optimized = WarpConfigOptimizer.optimize(
                rawConfig,
                port: targetPort,
                endpointHost: targetHost,
                dnsProfile: dnsProfile
            )
            if optimized != rawConfig {
                try? optimized.write(toFile: configPath, atomically: true, encoding: .utf8)
                _ = ProcessRunner.runSync("/bin/chmod", args: ["600", configPath])
            }
        }

        let destConfig = "/etc/wireguard/wgcf.conf"
        let needsInstall = !fm.fileExists(atPath: destConfig)
        let syncedProfile = UserDefaults.standard.string(forKey: syncedProfileKey)
        let needsSync = needsInstall || (fm.fileExists(atPath: configPath) && syncedProfile != expectedProfile)

        if needsSync {
            // Fixed paths only — no user free text
            let cp = "/bin/mkdir -p /etc/wireguard && /bin/cp \(shellQuote(configPath)) \(shellQuote(destConfig)) && /bin/chmod 600 \(shellQuote(destConfig))"
            let escaped = cp.replacingOccurrences(of: "\"", with: "\\\"")
            let source = "do shell script \"\(escaped)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            if err == nil {
                UserDefaults.standard.set(expectedProfile, forKey: syncedProfileKey)
                LogManager.shared.appendLog(
                    "WARP Sistem Tüneli optimize edildi (\(targetHost):\(targetPort), MTU \(WarpConfigOptimizer.optimalMTU), DNS \(dnsProfile.serverIP))."
                )
            } else if needsInstall {
                return false
            } else {
                LogManager.shared.appendLog("⚠️ WARP optimizasyon senkronizasyonu atlandı (mevcut /etc/wireguard/wgcf.conf kullanılacak).")
            }
        }
        return true
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
