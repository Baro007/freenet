import Foundation
import Darwin

/// Live checks: is system really using Tor / what IP is visible.
enum ConnectionProbe {
    struct TorCheck: Equatable {
        let isTor: Bool
        let exitIP: String?
        let detail: String
    }

    /// Query check.torproject.org through local SOCKS (not system proxy alone).
    static func checkTorSOCKS(host: String = "127.0.0.1", port: Int = 9050, timeout: TimeInterval = 12) -> TorCheck {
        // Prefer curl --socks5-hostname so DNS also goes through Tor
        let curl = "/usr/bin/curl"
        guard FileManager.default.isExecutableFile(atPath: curl) else {
            return TorCheck(isTor: false, exitIP: nil, detail: "curl yok — Tor doğrulanamadı")
        }
        let url = "https://check.torproject.org/api/ip"
        let r = ProcessRunner.captureOutput(curl, args: [
            "-sS", "--max-time", "\(Int(timeout))",
            "--socks5-hostname", "\(host):\(port)",
            url
        ])
        if r.status != 0 {
            let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return TorCheck(isTor: false, exitIP: nil, detail: "Tor SOCKS yanıt yok (\(err.isEmpty ? "timeout/bağlantı" : err))")
        }
        let body = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TorCheck(isTor: false, exitIP: nil, detail: "Tor API parse hatası")
        }
        let isTor = (obj["IsTor"] as? Bool) ?? false
        let ip = obj["IP"] as? String
        if isTor {
            return TorCheck(isTor: true, exitIP: ip, detail: "Tor AĞINDA · exit \(ip ?? "?")")
        }
        return TorCheck(isTor: false, exitIP: ip, detail: "SOCKS açık ama IsTor=false · \(ip ?? "?")")
    }

    static func checkDirectIP(timeout: TimeInterval = 8) -> String? {
        let r = ProcessRunner.captureOutput("/usr/bin/curl", args: [
            "-sS", "--max-time", "\(Int(timeout))",
            "--noproxy", "*",
            "https://api.ipify.org"
        ])
        guard r.status == 0 else { return nil }
        let ip = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return ip.isEmpty ? nil : ip
    }

    /// Query visible exit IP through an active local SOCKS5 proxy (e.g. sing-box WARP on 1083).
    static func checkProxiedIP(host: String, port: Int, timeout: TimeInterval = 6) -> String? {
        let r = ProcessRunner.captureOutput("/usr/bin/curl", args: [
            "-sS", "--max-time", "\(Int(timeout))",
            "--socks5-hostname", "\(host):\(port)",
            "https://api.ipify.org"
        ])
        guard r.status == 0 else { return nil }
        let ip = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return ip.isEmpty ? nil : ip
    }

    struct WarpCheck: Equatable {
        let isWarp: Bool
        let ip: String?
        let colo: String?
    }

    /// Verifies Cloudflare WARP trace (`warp=on`, exit IP, datacenter) via proxy or system route.
    static func checkWarpTrace(socksProxy: (host: String, port: Int)?, timeout: TimeInterval = 6) -> WarpCheck {
        var args = ["-sS", "--max-time", "\(Int(timeout))"]
        if let p = socksProxy {
            args.append(contentsOf: ["--socks5-hostname", "\(p.host):\(p.port)"])
        } else {
            args.append(contentsOf: ["--noproxy", "*"])
        }
        args.append("https://cloudflare.com/cdn-cgi/trace")
        let r = ProcessRunner.captureOutput("/usr/bin/curl", args: args)
        guard r.status == 0 else {
            return WarpCheck(isWarp: false, ip: nil, colo: nil)
        }
        var isWarp = false
        var ip: String?
        var colo: String?
        for line in r.stdout.components(separatedBy: .newlines) {
            if line == "warp=on" || line == "warp=plus" { isWarp = true }
            else if line.hasPrefix("ip=") { ip = String(line.dropFirst(3)) }
            else if line.hasPrefix("colo=") { colo = String(line.dropFirst(5)) }
        }
        return WarpCheck(isWarp: isWarp, ip: ip, colo: colo)
    }

    /// Fast zero-subprocess check: non-blocking TCP connect to IPv4 host:port.
    static func isTCPPortReachable(host: String, port: Int, timeoutMs: Int32 = 150) -> Bool {
        guard port > 0 && port <= 65535 else { return false }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            return false
        }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if res == 0 { return true }
        if errno != EINPROGRESS { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollRes = Darwin.poll(&pfd, 1, timeoutMs)
        guard pollRes > 0 else { return false }

        var sockErr: Int32 = 0
        var errLen = socklen_t(MemoryLayout<Int32>.size)
        if Darwin.getsockopt(fd, SOL_SOCKET, SO_ERROR, &sockErr, &errLen) == 0 {
            return sockErr == 0
        }
        return false
    }

    /// Fast zero-subprocess check: non-blocking TCP connect to 127.0.0.1:<port>.
    static func isLocalPortOpen(_ port: Int, timeoutMs: Int32 = 150) -> Bool {
        isTCPPortReachable(host: "127.0.0.1", port: port, timeoutMs: timeoutMs)
    }

    /// Wait up to `timeout` seconds for a local TCP listener to come up.
    static func waitForLocalPort(_ port: Int, timeout: TimeInterval = 1.5, step: TimeInterval = 0.05) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isLocalPortOpen(port, timeoutMs: 80) {
                return true
            }
            Thread.sleep(forTimeInterval: step)
        }
        return isLocalPortOpen(port, timeoutMs: 80)
    }
}
