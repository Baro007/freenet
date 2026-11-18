# Freenet Threat Model

This document states **honestly** what each intent protects against.  
**Real anonymity is only Maks. Gizlilik (Tor).** WARP is free IP masking, not anonymity.

## Actors

| Actor | Capability |
|-------|------------|
| Local ISP / national DPI | Inspect/block cleartext DNS, SNI, HTTP `Host`, QUIC, known VPN ports (e.g. UDP `2408`); IP-block destinations |
| Network eavesdropper (café Wi‑Fi) | Same LAN as you; can see unencrypted metadata |
| Destination website | Sees the source IP that connects to it (and TLS content keys with you) |
| Cloudflare (WARP) | Sees your real IP, `wgcf` device key, and destinations when Dengeli is on |
| Tor entry / guard | Sees that you use Tor, not full destination path |
| Tor exit | Sees destination (not your IP) for cleartext/TLS SNI as usual |
| Freenet app / binary supply chain | Runs privileged network config; malicious binary = full compromise |

## Intent × Threat Matrix

| Threat | Hızlı (Hibrit Zırh / sing-box / DPI) | Dengeli (WARP: sing-box or wg-quick) | Maks. Gizlilik (Tor) |
|--------|--------------------------------------|--------------------------------------|----------------------|
| ISP DPI / SNI / HTTP-80 block | **Mitigated** (TLS/TCP fragment + `ciadpi` 3-tier desync + HTTP Host obfuscation) | **Mitigated** (encrypted WireGuard tunnel + non-2408 port failover) | **Mitigated** (with bridges/PT) |
| ISP DNS poisoning | **Mitigated** (encrypted DoH + `port 53` hijack + auto failover) | **Mitigated** (DoH routed inside WARP tunnel) | **Mitigated** (Tor DNS) |
| QUIC / HTTP3 stalls & leaks | **Mitigated** (`HTTPS`/`SVCB` strip + QUIC/UDP:443 reject) | Tunnel-routed | Tor TCP-only |
| Malware / Ad / Tracker domains | **Optional DNS Shield** (Cloudflare Security `1.1.1.2`, AdGuard `94.140.14.14`, Quad9 `9.9.9.9`) | **Optional DNS Shield** (inside WARP) | Browser/extension responsibility |
| Destination IP ban | **No** | **Often yes** (Cloudflare IP) | **Yes** (Tor exit IP) |
| ISP learns destination IP | **Often yes** (direct connection) | Cloudflare endpoint only | **No** (onion routing) |
| Destination learns your real IP | **Yes** | **No** (sees Cloudflare IP) | **No** (sees Tor exit IP) |
| Single company sees full path | No extra tunnel operator | **Yes — Cloudflare** | **No** |
| Throughput / latency | **Best** (near-100% ISP wire speed) | **Good** (minor WireGuard/Cloudflare overhead) | **Poor** (multi-hop Tor latency) |
| "Anonymous activist" threat model | **Inadequate** | **Inadequate** | **Best effort (Tor)** |

## Explicit Non-Goals

- Fast + anonymous in one mode  
- Hiding Freenet use from a global passive adversary with unlimited correlation  
- Protecting against malware already running on the same Mac  
- Guaranteeing access if an ISP blocks all direct IPs, WireGuard UDP, and Tor bridges simultaneously

## Residual Risks (All Modes)

- System proxy (`networksetup` SOCKS5 + optional HTTP/HTTPS) covers browsers, macOS URLSession apps, Electron apps, and proxy-aware CLIs; non-proxy apps/UDP require `Sistem Tüneli (wg-quick)` or future Network Extension ([docs/NETWORK_EXTENSION.md](NETWORK_EXTENSION.md)).
- Force-quit edge cases are mitigated by orphan proxy cleanup on next launch.
- Bundled binaries are verified against `CHECKSUMS.sha256` before launch (`ciadpi` is strictly bound to `127.0.0.1` and validated via flag allowlist).
