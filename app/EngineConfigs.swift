import Foundation

/// Anti-DPI strategy for sing-box (Hızlı / Basit mod — VPN'siz tam hat hızı).
/// Note: in sing-box 1.13+, `tls_record_fragment` and `tls_fragment` are mutually exclusive.
public enum SingBoxFragmentMode: String, CaseIterable {
    case hybridShield = "Hibrit Zırh (sing-box + ciadpi)"
    case recordFragment = "TLS Record (Hızlı)"
    case tcpFragment = "TCP Fragment (Sert DPI)"

    public static let storageKey = "freenetSingBoxFragmentMode"

    public var shortLabel: String {
        switch self {
        case .hybridShield: return "Hibrit Zırh"
        case .recordFragment: return "TLS Record"
        case .tcpFragment: return "TCP Fragment"
        }
    }

    public static func fromStorage(_ raw: String?) -> SingBoxFragmentMode {
        guard let raw = raw else { return .hybridShield }
        if raw == "TLS Record (Önerilen)" { return .recordFragment }
        return SingBoxFragmentMode(rawValue: raw) ?? .hybridShield
    }
}

/// Encrypted DoH DNS profiles (defeats ISP DNS poisoning + optional malware/ad/tracker blocking).
public enum SingBoxDNSProfile: String, CaseIterable {
    case cloudflareSecurity = "Cloudflare Güvenlik (Zararlı Engel · 1.1.1.2)"
    case adguardShield = "AdGuard Kalkan (Reklam + İzleyici · 94.140.14.14)"
    case cloudflareFast = "Cloudflare Hızlı (Temiz · 1.1.1.1)"
    case quad9Security = "Quad9 Güvenlik (İsviçre · 9.9.9.9)"
    case google = "Google DoH (8.8.8.8)"

    public static let storageKey = "freenetSingBoxDNSProfile"

    public var serverIP: String {
        switch self {
        case .cloudflareSecurity: return "1.1.1.2"
        case .adguardShield: return "94.140.14.14"
        case .cloudflareFast: return "1.1.1.1"
        case .quad9Security: return "9.9.9.9"
        case .google: return "8.8.8.8"
        }
    }

    public var secondaryIP: String {
        switch self {
        case .cloudflareSecurity: return "1.0.0.2"
        case .adguardShield: return "94.140.15.15"
        case .cloudflareFast: return "1.0.0.1"
        case .quad9Security: return "149.112.112.112"
        case .google: return "8.8.4.4"
        }
    }

    public var shortName: String {
        switch self {
        case .cloudflareSecurity: return "CF-Güvenlik (1.1.1.2)"
        case .adguardShield: return "AdGuard (94.140.14.14)"
        case .cloudflareFast: return "Cloudflare (1.1.1.1)"
        case .quad9Security: return "Quad9 (9.9.9.9)"
        case .google: return "Google (8.8.8.8)"
        }
    }

    /// Ordered failover list starting with self so blocked DoH IPs automatically fail over.
    public var failoverCandidates: [SingBoxDNSProfile] {
        let all: [SingBoxDNSProfile] = [
            self, .cloudflareSecurity, .cloudflareFast, .adguardShield, .quad9Security, .google
        ]
        var seen = Set<SingBoxDNSProfile>()
        return all.filter { seen.insert($0).inserted }
    }

    public static func fromStorage(_ raw: String?) -> SingBoxDNSProfile {
        guard let raw = raw else { return .cloudflareSecurity }
        return SingBoxDNSProfile(rawValue: raw) ?? .cloudflareSecurity
    }
}

/// Pure generator for hardened sing-box 1.13+ non-VPN configuration (unit-tested directly).
public enum SingBoxConfig {
    /// Server-speaks-first & non-censored system/mail/messaging ports that must bypass
    /// protocol sniffing, TLS fragmentation, and WARP IP-reputation blocks:
    /// - SSH (22), SMTP (25, 465, 587, 2525), POP3 (110, 995), IMAP (143, 993)
    /// - WhatsApp XMPP/Noise (5222), Apple Push / iMessage / Mail Push (5223)
    public static let directBypassPorts = [22, 25, 110, 143, 465, 587, 993, 995, 2525, 5222, 5223]

    /// Messaging & Apple push domains that must bypass TLS fragmentation / shared WARP IP blocks.
    public static let directBypassDomainSuffixes = [
        ".whatsapp.com", ".whatsapp.net", ".wa.me", "push.apple.com"
    ]

    /// Generates a hardened, VPN-free sing-box config:
    /// 1) `mixed` inbound with `reuse_addr` (SOCKS5 + HTTP/HTTPS CONNECT on localhost)
    /// 2) Pre-sniff direct bypass for Mail (SMTP/IMAP/POP3), SSH, WhatsApp & Apple Push
    ///    (prevents server-speaks-first deadlocks and strict mail-server TLS-fragment rejections)
    /// 3) Encrypted DoH (Cloudflare Security / AdGuard / Quad9 / Cloudflare / Google) + 4096 cache
    /// 4) Local DNS bypass (.local/.test/.lan/.home.arpa/localhost) + HTTPS/SVCB stripping (anti-QUIC)
    /// 5) `hijack-dns` on protocol=dns / port=53 (zero plaintext DNS leaks through proxy)
    /// 6) Private/LAN bypass both pre- and post-resolve
    /// 7) QUIC + UDP/443 rejection (instant TCP fallback, no 3-5s stalls)
    /// 8) Sinkhole & BTK block-page IP rejection (0.0.0.0/8, 195.175.254.2/32)
    /// 9) 3-mode anti-DPI: TLS Record, TCP Fragment, or Hybrid Shield (chained to local ciadpi)
    public static func makeJSON(
        listenPort: Int = 1081,
        fragmentMode: SingBoxFragmentMode = .hybridShield,
        dnsProfile: SingBoxDNSProfile = .cloudflareSecurity,
        ciadpiPort: Int = 1082
    ) -> String {
        let bypassPortsJSON = directBypassPorts.map(String.init).joined(separator: ", ")
        let bypassDomainsJSON = directBypassDomainSuffixes.map { "\"\($0)\"" }.joined(separator: ", ")
        let extraOutbound: String
        let bypassRules: String

        switch fragmentMode {
        case .hybridShield:
            extraOutbound = """
                ,
                {
                  "type": "socks",
                  "tag": "ciadpi-out",
                  "server": "127.0.0.1",
                  "server_port": \(ciadpiPort),
                  "version": "5",
                  "network": "tcp"
                }
            """
            bypassRules = """
                  {
                    "protocol": ["tls", "http"],
                    "outbound": "ciadpi-out"
                  },
                  {
                    "port": [80, 443],
                    "outbound": "ciadpi-out"
                  }
            """
        case .recordFragment:
            extraOutbound = ""
            bypassRules = """
                  {
                    "protocol": "tls",
                    "action": "route-options",
                    "tls_record_fragment": true
                  },
                  {
                    "port": 443,
                    "action": "route-options",
                    "tls_record_fragment": true
                  }
            """
        case .tcpFragment:
            extraOutbound = ""
            bypassRules = """
                  {
                    "protocol": "tls",
                    "action": "route-options",
                    "tls_fragment": true,
                    "tls_fragment_fallback_delay": "200ms"
                  },
                  {
                    "port": 443,
                    "action": "route-options",
                    "tls_fragment": true,
                    "tls_fragment_fallback_delay": "200ms"
                  }
            """
        }

        return """
        {
          "log": {
            "level": "warn",
            "timestamp": true
          },
          "dns": {
            "servers": [
              {
                "tag": "doh-primary",
                "type": "https",
                "server": "\(dnsProfile.serverIP)",
                "server_port": 443,
                "path": "/dns-query"
              },
              {
                "tag": "local",
                "type": "local"
              }
            ],
            "rules": [
              {
                "domain_suffix": [".local", ".test", ".lan", ".home.arpa", "localhost"],
                "server": "local"
              },
              {
                "query_type": ["HTTPS", "SVCB"],
                "action": "reject"
              }
            ],
            "final": "doh-primary",
            "strategy": "ipv4_only",
            "independent_cache": true,
            "cache_capacity": 4096
          },
          "inbounds": [
            {
              "type": "mixed",
              "tag": "mixed-in",
              "listen": "127.0.0.1",
              "listen_port": \(listenPort),
              "reuse_addr": true
            }
          ],
          "outbounds": [
            {
              "type": "direct",
              "tag": "direct-out",
              "udp_fragment": true
            }\(extraOutbound)
          ],
          "route": {
            "default_domain_resolver": {
              "server": "doh-primary",
              "strategy": "ipv4_only"
            },
            "rules": [
              {
                "port": [\(bypassPortsJSON)],
                "outbound": "direct-out"
              },
              {
                "domain_suffix": [\(bypassDomainsJSON)],
                "outbound": "direct-out"
              },
              {
                "inbound": ["mixed-in"],
                "action": "sniff",
                "timeout": "300ms"
              },
              {
                "protocol": "dns",
                "action": "hijack-dns"
              },
              {
                "port": 53,
                "action": "hijack-dns"
              },
              {
                "ip_is_private": true,
                "outbound": "direct-out"
              },
              {
                "protocol": "quic",
                "action": "reject"
              },
              {
                "network": "udp",
                "port": 443,
                "action": "reject"
              },
              {
                "action": "resolve",
                "strategy": "ipv4_only"
              },
              {
                "ip_cidr": ["0.0.0.0/8", "195.175.254.2/32"],
                "action": "reject"
              },
              {
                "ip_is_private": true,
                "outbound": "direct-out"
              },
        \(bypassRules)
            ],
            "final": "direct-out"
          }
        }
        """
    }
}

/// Transport mode for Dengeli (WARP):
/// - `singboxWarp`: native WireGuard inside bundled sing-box (no root, no utun route hijack,
///   automatic multi-IP/port failover, DoH-through-WARP + ad/malware shield, LAN/.test direct bypass).
/// - `systemTunnel`: classic L3 `wg-quick` / `wireguard-go` utun covering all non-proxy apps too.
public enum WarpTransportMode: String, CaseIterable {
    case singboxWarp = "sing-box WARP (Önerilen)"
    case systemTunnel = "Sistem Tüneli (wg-quick)"

    public static let storageKey = "freenetWarpTransport"

    public static func fromStorage(_ raw: String?) -> WarpTransportMode {
        guard let raw = raw else { return .singboxWarp }
        return WarpTransportMode(rawValue: raw) ?? .singboxWarp
    }
}

/// Official Cloudflare WARP WireGuard UDP ports.
/// Non-2408 ports (500, 4500, 1701) bypass ISP UDP-2408 throttling / QoS shaping.
public enum WarpEndpointPort: String, CaseIterable {
    case port500 = "500 (Hızlı / Kısıt Aşımı)"
    case port4500 = "4500 (Alternatif UDP)"
    case port1701 = "1701 (Alternatif)"
    case port2408 = "2408 (Varsayılan)"

    public static let storageKey = "freenetWarpPort"

    public var portNumber: Int {
        switch self {
        case .port500: return 500
        case .port4500: return 4500
        case .port1701: return 1701
        case .port2408: return 2408
        }
    }

    public static func fromStorage(_ raw: String?) -> WarpEndpointPort {
        guard let raw = raw else { return .port500 }
        return WarpEndpointPort(rawValue: raw) ?? .port500
    }
}

public struct WarpEndpointTarget: Equatable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

/// Parsed fields from wgcf.conf / wgcf-profile.conf (never logged).
public struct WgcfConfig: Equatable {
    public let privateKey: String
    public let publicKey: String
    public let addresses: [String]
    public let endpointHost: String
    public let endpointPort: Int

    public init(
        privateKey: String,
        publicKey: String,
        addresses: [String],
        endpointHost: String,
        endpointPort: Int
    ) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.addresses = addresses
        self.endpointHost = endpointHost
        self.endpointPort = endpointPort
    }
}

public enum WgcfConfigParser {
    /// Parses a standard wgcf WireGuard INI file.
    public static func parse(_ raw: String) -> WgcfConfig? {
        var section = ""
        var privateKey = ""
        var publicKey = ""
        var addresses: [String] = []
        var endpointHost = "162.159.193.1"
        var endpointPort = 2408

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = line
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !val.isEmpty else { continue }

            if section == "[Interface]" {
                switch key {
                case "privatekey":
                    privateKey = val
                case "address":
                    let parts = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    addresses.append(contentsOf: parts)
                default:
                    break
                }
            } else if section == "[Peer]" {
                switch key {
                case "publickey":
                    publicKey = val
                case "endpoint":
                    if val.hasPrefix("["), let close = val.lastIndex(of: "]") {
                        endpointHost = String(val[val.index(after: val.startIndex)..<close])
                        let after = val[val.index(after: close)...]
                        if after.hasPrefix(":"), let p = Int(after.dropFirst()) {
                            endpointPort = p
                        }
                    } else if let colon = val.lastIndex(of: ":") {
                        let h = String(val[..<colon])
                        if !h.isEmpty { endpointHost = h }
                        if let p = Int(val[val.index(after: colon)...]) {
                            endpointPort = p
                        }
                    } else {
                        endpointHost = val
                    }
                default:
                    break
                }
            }
        }

        guard !privateKey.isEmpty, !publicKey.isEmpty, !addresses.isEmpty else {
            return nil
        }
        return WgcfConfig(
            privateKey: privateKey,
            publicKey: publicKey,
            addresses: addresses,
            endpointHost: endpointHost,
            endpointPort: endpointPort
        )
    }

    /// Ordered official Cloudflare WARP IP:port targets for sequential failover.
    /// Prefers 162.159.192.1 + non-2408 ports first (verified fastest across TR ISPs).
    public static func failoverTargets(preferredPort: Int) -> [WarpEndpointTarget] {
        let candidates: [WarpEndpointTarget] = [
            WarpEndpointTarget(host: "162.159.192.1", port: preferredPort),
            WarpEndpointTarget(host: "162.159.193.1", port: preferredPort),
            WarpEndpointTarget(host: "162.159.192.1", port: 500),
            WarpEndpointTarget(host: "162.159.192.1", port: 4500),
            WarpEndpointTarget(host: "162.159.192.1", port: 1701),
            WarpEndpointTarget(host: "162.159.192.1", port: 2408)
        ]
        var out: [WarpEndpointTarget] = []
        for c in candidates where !out.contains(c) {
            out.append(c)
        }
        return out
    }
}

/// Pure generator for sing-box 1.13+ native WARP endpoint configuration.
/// Uses WireGuard-encrypted UDP DNS inside `warp-ep` (avoids sing-box 1.13 DoH-over-gvisor-endpoint
/// 10s timeout bug while remaining 100% encrypted inside WireGuard) and bypasses Mail (SMTP/IMAP/POP3),
/// SSH, WhatsApp, and Apple Push BEFORE sniffing so Mail.app & WhatsApp Desktop work reliably.
public enum SingBoxWarpConfig {
    public static func makeJSON(
        wgcf: WgcfConfig,
        endpoint: WarpEndpointTarget,
        listenPort: Int = 1083,
        dnsProfile: SingBoxDNSProfile = .cloudflareSecurity,
        mtu: Int = WarpConfigOptimizer.optimalMTU,
        keepalive: Int = WarpConfigOptimizer.defaultKeepalive
    ) -> String {
        let addrJSON = wgcf.addresses
            .map { "\"\(escapeJSON($0))\"" }
            .joined(separator: ", ")
        let bypassPortsJSON = SingBoxConfig.directBypassPorts.map(String.init).joined(separator: ", ")
        let bypassDomainsJSON = SingBoxConfig.directBypassDomainSuffixes.map { "\"\($0)\"" }.joined(separator: ", ")

        return """
        {
          "log": {
            "level": "warn",
            "timestamp": true
          },
          "dns": {
            "servers": [
              {
                "tag": "dns-warp",
                "type": "udp",
                "server": "\(dnsProfile.serverIP)",
                "server_port": 53,
                "detour": "warp-ep"
              },
              {
                "tag": "local",
                "type": "local"
              }
            ],
            "rules": [
              {
                "domain_suffix": [".local", ".test", ".lan", ".home.arpa", "localhost"],
                "server": "local"
              }
            ],
            "final": "dns-warp",
            "strategy": "ipv4_only",
            "independent_cache": true,
            "cache_capacity": 4096
          },
          "endpoints": [
            {
              "type": "wireguard",
              "tag": "warp-ep",
              "system": false,
              "address": [\(addrJSON)],
              "private_key": "\(escapeJSON(wgcf.privateKey))",
              "mtu": \(mtu),
              "peers": [
                {
                  "address": "\(escapeJSON(endpoint.host))",
                  "port": \(endpoint.port),
                  "public_key": "\(escapeJSON(wgcf.publicKey))",
                  "allowed_ips": ["0.0.0.0/0", "::/0"],
                  "persistent_keepalive_interval": \(keepalive)
                }
              ]
            }
          ],
          "inbounds": [
            {
              "type": "mixed",
              "tag": "mixed-in",
              "listen": "127.0.0.1",
              "listen_port": \(listenPort),
              "reuse_addr": true
            }
          ],
          "outbounds": [
            {
              "type": "direct",
              "tag": "direct-out"
            }
          ],
          "route": {
            "default_domain_resolver": {
              "server": "dns-warp",
              "strategy": "ipv4_only"
            },
            "rules": [
              {
                "port": [\(bypassPortsJSON)],
                "outbound": "direct-out"
              },
              {
                "domain_suffix": [\(bypassDomainsJSON)],
                "outbound": "direct-out"
              },
              {
                "inbound": ["mixed-in"],
                "action": "sniff",
                "timeout": "300ms"
              },
              {
                "protocol": "dns",
                "action": "hijack-dns"
              },
              {
                "port": 53,
                "action": "hijack-dns"
              },
              {
                "ip_is_private": true,
                "outbound": "direct-out"
              },
              {
                "action": "resolve",
                "strategy": "ipv4_only"
              },
              {
                "ip_cidr": ["0.0.0.0/8", "195.175.254.2/32"],
                "action": "reject"
              },
              {
                "ip_is_private": true,
                "outbound": "direct-out"
              }
            ],
            "final": "warp-ep"
          }
        }
        """
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Pure optimizer for classic wg-quick WireGuard configs:
/// - Tunes MTU (1280 → 1380) for PPPoE 1492 + WireGuard overhead without fragmentation
/// - Adds PersistentKeepalive = 25 to prevent CGNAT/router UDP mapping drops
/// - Rewrites Endpoint to preferred WARP IP (162.159.192.1) + selected non-2408 port
/// - Aligns DNS servers with selected DNS shield profile (malware/ad blocking even in L3 mode)
/// - Preserves keys, addresses, and AllowedIPs (no IPv6 leak)
public enum WarpConfigOptimizer {
    public static let optimalMTU = 1380
    public static let defaultKeepalive = 25
    public static let preferredEndpointHost = "162.159.192.1"

    public static func optimize(
        _ raw: String,
        port: Int = WarpEndpointPort.port500.portNumber,
        mtu: Int = optimalMTU,
        keepalive: Int = defaultKeepalive,
        endpointHost: String? = nil,
        dnsProfile: SingBoxDNSProfile? = nil
    ) -> String {
        let lines = raw.components(separatedBy: .newlines)
        var out: [String] = []
        var section = ""
        var sawMTU = false
        var sawKeepalive = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if section == "[Interface]" && !sawMTU {
                    out.append("MTU = \(mtu)")
                    sawMTU = true
                }
                if section == "[Peer]" && !sawKeepalive {
                    out.append("PersistentKeepalive = \(keepalive)")
                    sawKeepalive = true
                }
                section = trimmed
                out.append(line)
                continue
            }

            if section == "[Interface]", isKey(trimmed, named: "MTU") {
                out.append("MTU = \(mtu)")
                sawMTU = true
                continue
            }

            if section == "[Interface]", let dnsProfile = dnsProfile, isKey(trimmed, named: "DNS") {
                out.append("DNS = \(dnsProfile.serverIP), \(dnsProfile.secondaryIP)")
                continue
            }

            if section == "[Peer]", isKey(trimmed, named: "PersistentKeepalive") {
                out.append("PersistentKeepalive = \(keepalive)")
                sawKeepalive = true
                continue
            }

            if section == "[Peer]", isKey(trimmed, named: "Endpoint") {
                if let rewritten = rewriteEndpoint(line: trimmed, newHost: endpointHost, newPort: port) {
                    out.append(rewritten)
                    continue
                }
            }

            out.append(line)
        }

        // Remove trailing empty lines before appending missing keys cleanly
        while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            out.removeLast()
        }
        if section == "[Interface]" && !sawMTU {
            out.append("MTU = \(mtu)")
        } else if section == "[Peer]" && !sawKeepalive {
            out.append("PersistentKeepalive = \(keepalive)")
        }

        return out.joined(separator: "\n") + "\n"
    }

    public static func profileSignature(
        port: Int,
        mtu: Int = optimalMTU,
        keepalive: Int = defaultKeepalive,
        endpointHost: String = preferredEndpointHost,
        dnsIP: String = SingBoxDNSProfile.cloudflareSecurity.serverIP
    ) -> String {
        "v2:host=\(endpointHost):port=\(port):mtu=\(mtu):ka=\(keepalive):dns=\(dnsIP)"
    }

    private static func isKey(_ trimmedLine: String, named key: String) -> Bool {
        guard let eq = trimmedLine.firstIndex(of: "=") else { return false }
        let lhs = trimmedLine[..<eq].trimmingCharacters(in: .whitespaces)
        return lhs.caseInsensitiveCompare(key) == .orderedSame
    }

    private static func rewriteEndpoint(line: String, newHost: String?, newPort: Int) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        if let host = newHost, !host.isEmpty {
            return "Endpoint = \(host):\(newPort)"
        }

        // Handle bracketed IPv6 [addr]:port or host:port
        if value.hasPrefix("["), let closeBracket = value.lastIndex(of: "]") {
            let host = String(value[...closeBracket])
            return "Endpoint = \(host):\(newPort)"
        }
        if let lastColon = value.lastIndex(of: ":") {
            let host = String(value[..<lastColon])
            guard !host.isEmpty else { return nil }
            return "Endpoint = \(host):\(newPort)"
        }
        return "Endpoint = \(value):\(newPort)"
    }
}
