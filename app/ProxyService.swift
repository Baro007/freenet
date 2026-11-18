import Foundation
import CFNetwork

/// System SOCKS configuration via networksetup (pre-NetworkExtension path).
/// Commands use fixed argument arrays — never interpolate untrusted user strings into AppleScript.
final class ProxyService {
    static let shared = ProxyService()

    private let networksetupPath = "/usr/sbin/networksetup"
    private let fallbackInterfaces = ["Wi-Fi", "Ethernet"]
    private var cachedServices: (services: [String], timestamp: Date)?

    private init() {}

    /// Dynamically discovers enabled network services (Wi-Fi, USB LAN, Ethernet, etc.),
    /// skipping disabled (`*`) entries and Thunderbolt Bridge.
    func activeNetworkServices(forceRefresh: Bool = false) -> [String] {
        if !forceRefresh, let cached = cachedServices,
           Date().timeIntervalSince(cached.timestamp) < 30 {
            return cached.services
        }
        let r = ProcessRunner.captureOutput(networksetupPath, args: ["-listallnetworkservices"])
        guard r.status == 0 else { return fallbackInterfaces }
        let ignored: Set<String> = ["Thunderbolt Bridge", "Bluetooth PAN", "iPhone USB"]
        let parsed = r.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("An asterisk")
                    && !line.hasPrefix("*")
                    && !ignored.contains(line)
            }
        let result = parsed.isEmpty ? fallbackInterfaces : parsed
        cachedServices = (result, Date())
        return result
    }

    var wgQuickPath: String {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/opt/homebrew/bin/wg-quick") { return "/opt/homebrew/bin/wg-quick" }
        return "/usr/local/bin/wg-quick"
    }

    var brewPrefix: String {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/opt/homebrew/bin/brew") { return "/opt/homebrew/bin" }
        return "/usr/local/bin"
    }

    private var _cachedSudoersStatus: Bool?
    private var _cachedExtendedProxySudoers: Bool?
    private var webProxyWasEnabled = false

    private let bypassDomains = [
        "localhost", "127.0.0.1", "::1",
        "*.local", "*.test", "*.lan",
        "169.254/16", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"
    ]

    func isSudoersInstalled() -> Bool {
        if let cached = _cachedSudoersStatus { return cached }
        let result = ProcessRunner.captureOutput("/usr/bin/sudo", args: ["-n", "/usr/bin/true"])
        let isInstalled = result.status == 0
        _cachedSudoersStatus = isInstalled
        return isInstalled
    }

    /// True if /etc/sudoers.d/freenet also permits passwordless HTTP/HTTPS web proxy + bypass domains.
    func hasExtendedProxySudoers() -> Bool {
        if let cached = _cachedExtendedProxySudoers { return cached }
        guard isSudoersInstalled() else {
            _cachedExtendedProxySudoers = false
            return false
        }
        let r = ProcessRunner.captureOutput("/usr/bin/sudo", args: ["-l", "-n"])
        let ok = r.status == 0
            && r.stdout.contains("-setwebproxy")
            && r.stdout.contains("-setsecurewebproxy")
            && r.stdout.contains("-setproxybypassdomains")
        _cachedExtendedProxySudoers = ok
        return ok
    }

    /// Install narrow sudoers rules with a fixed template (username only from NSUserName).
    func installSudoers() -> Bool {
        let user = NSUserName()
        // Username: only allow safe characters
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard user.unicodeScalars.allSatisfy({ allowed.contains($0) }), !user.isEmpty else {
            return false
        }
        let nsp = networksetupPath
        let wq = wgQuickPath
        // Fixed command shapes only
        let rules = [
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setsocksfirewallproxy *",
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setsocksfirewallproxystate *",
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setwebproxy *",
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setwebproxystate *",
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setsecurewebproxy *",
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setsecurewebproxystate *",
            "\(user) ALL=(ALL) NOPASSWD: \(nsp) -setproxybypassdomains *",
            "\(user) ALL=(ALL) NOPASSWD: \(wq) up wgcf",
            "\(user) ALL=(ALL) NOPASSWD: \(wq) down wgcf",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/true"
        ]
        let content = rules.joined(separator: "\n")
        // Write via admin script built from fixed pieces; content has no user free text beyond sanitized username
        let tmp = "/tmp/freenet_sudoers"
        let script =
            "echo \(shellSingleQuote(content)) > \(tmp) && " +
            "chmod 440 \(tmp) && chown root:wheel \(tmp) && mv \(tmp) /etc/sudoers.d/freenet"
        let ok = runAdminShell(script)
        if ok {
            _cachedSudoersStatus = true
            _cachedExtendedProxySudoers = true
        }
        return ok
    }

    /// Enables SOCKS5 and (when passwordless sudoers permits) HTTP + HTTPS proxy + LAN bypass domains
    /// so browsers, Electron apps, and CLI tools all route cleanly through sing-box's mixed listener.
    @discardableResult
    func enableMixedProxy(host: String, port: Int) -> Bool {
        let socksOK = enableSOCKS(host: host, port: port)
        guard socksOK, hasExtendedProxySudoers() else {
            return socksOK
        }
        let portStr = String(port)
        var anyWebOK = false
        for iface in activeNetworkServices() {
            let w1 = runPrivileged(networksetupPath, args: ["-setwebproxy", iface, "127.0.0.1", portStr])
            let w2 = runPrivileged(networksetupPath, args: ["-setwebproxystate", iface, "on"])
            let s1 = runPrivileged(networksetupPath, args: ["-setsecurewebproxy", iface, "127.0.0.1", portStr])
            let s2 = runPrivileged(networksetupPath, args: ["-setsecurewebproxystate", iface, "on"])
            _ = runPrivileged(networksetupPath, args: ["-setproxybypassdomains", iface] + bypassDomains)
            if w1 && w2 && s1 && s2 { anyWebOK = true }
        }
        if anyWebOK {
            webProxyWasEnabled = true
            LogManager.shared.appendLog("Sistem HTTP+HTTPS+SOCKS5 proxy + LAN bypass aktif (127.0.0.1:\(portStr))")
        }
        return socksOK
    }

    /// Returns true if at least one interface has SOCKS enabled afterward.
    @discardableResult
    func enableSOCKS(host: String, port: Int) -> Bool {
        // host/port only from our engines (127.0.0.1 + validated port)
        guard host == "127.0.0.1" || host == "localhost" else {
            LogManager.shared.appendLog("ProxyService: refused non-local SOCKS host")
            return false
        }
        guard port >= 1024 && port <= 65535 else { return false }
        let portStr = String(port)
        var anyOK = false
        for iface in activeNetworkServices(forceRefresh: true) {
            let a = runPrivileged(networksetupPath, args: ["-setsocksfirewallproxy", iface, "127.0.0.1", portStr])
            let b = runPrivileged(networksetupPath, args: ["-setsocksfirewallproxystate", iface, "on"])
            if a && b { anyOK = true }
            LogManager.shared.appendLog("SOCKS \(iface) → 127.0.0.1:\(portStr) \(a && b ? "OK" : "FAIL")")
        }
        // Re-check system state (networksetup may report success but Wi-Fi only exists)
        if isSOCKSEnabled() { return true }
        return anyOK
    }

    func disableSOCKS() {
        let services = activeNetworkServices()
        for iface in services {
            _ = runPrivileged(networksetupPath, args: ["-setsocksfirewallproxystate", iface, "off"])
            if webProxyWasEnabled || (hasExtendedProxySudoers() && isWebProxyEnabled()) {
                _ = runPrivileged(networksetupPath, args: ["-setwebproxystate", iface, "off"])
                _ = runPrivileged(networksetupPath, args: ["-setsecurewebproxystate", iface, "off"])
            }
        }
        webProxyWasEnabled = false
    }

    private func isWebProxyEnabled() -> Bool {
        guard let unmanaged = CFNetworkCopySystemProxySettings(),
              let dict = unmanaged.takeRetainedValue() as? [String: Any] else {
            return false
        }
        let httpOn = (dict[kCFNetworkProxiesHTTPEnable as String] as? Int) == 1
        let httpsOn = (dict[kCFNetworkProxiesHTTPSEnable as String] as? Int) == 1
        return httpOn || httpsOn
    }

    /// Zero-subprocess check via CFNetworkCopySystemProxySettings (works across Wi-Fi/USB LAN/Ethernet).
    func isSOCKSEnabled() -> Bool {
        guard let unmanaged = CFNetworkCopySystemProxySettings(),
              let dict = unmanaged.takeRetainedValue() as? [String: Any] else {
            return false
        }
        if let enabled = dict[kCFNetworkProxiesSOCKSEnable as String] as? Int, enabled == 1 {
            return true
        }
        if let enabled = dict[kCFNetworkProxiesSOCKSEnable as String] as? Bool, enabled {
            return true
        }
        return false
    }

    /// Orphan cleanup: only turn SOCKS off if it is on AND no freenet engine port is listening.
    /// (App restart used to kill SOCKS while Tor process was still alive on 9050.)
    func cleanupOrphanedProxyIfNeeded(enginesRunning: Bool) {
        guard isSOCKSEnabled() else { return }
        if enginesRunning { return }
        let listeners =
            ConnectionProbe.isLocalPortOpen(1080)
            || ConnectionProbe.isLocalPortOpen(1081)
            || ConnectionProbe.isLocalPortOpen(1083)
            || ConnectionProbe.isLocalPortOpen(9050)
        if listeners {
            LogManager.shared.appendLog("SOCKS açık ve 1080/1081/1083/9050 dinleniyor — yetim temizlik atlandı")
            return
        }
        LogManager.shared.appendLog("Yetim SOCKS proxy temizleniyor (dinleyici yok)…")
        disableSOCKS()
    }

    func runPrivileged(_ cmd: String, args: [String]) -> Bool {
        // Only allow known absolute binaries
        let allowedBins: Set<String> = [
            networksetupPath,
            wgQuickPath,
            "/usr/bin/true",
            "/bin/mkdir",
            "/bin/cp",
            "/bin/chmod"
        ]
        guard allowedBins.contains(cmd) || cmd.hasSuffix("/wg-quick") else {
            LogManager.shared.appendLog("ProxyService: blocked privileged cmd \(cmd)")
            return false
        }
        // Reject any arg that looks like shell metachar injection
        for a in args {
            if a.rangeOfCharacter(from: CharacterSet(charactersIn: ";|&$`\n\r")) != nil {
                return false
            }
        }

        if isSudoersInstalled() {
            let status = ProcessRunner.runSync("/usr/bin/sudo", args: [cmd] + args)
            return status == 0
        }
        // Fixed argv form via admin shell — each arg single-quoted
        let joined = ([cmd] + args).map { shellSingleQuote($0) }.joined(separator: " ")
        let pathExport = "export PATH='/opt/homebrew/bin:/usr/local/bin:$PATH'; "
        return runAdminShell(pathExport + joined)
    }

    private func runAdminShell(_ command: String) -> Bool {
        // AppleScript with escaped quotes — command must already be trusted construction
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil
    }

    private func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
