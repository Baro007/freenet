import Foundation

/// Placeholder for future Packet Tunnel Provider integration (Faz 3).
/// Not a functional VPN extension — see docs/NETWORK_EXTENSION.md.
enum NetworkExtensionStub {
    static let statusNote = """
    Network Extension (Packet Tunnel) bu ortamda imzalanıp kurulamadı. \
    Freenet şu an system SOCKS (networksetup) kullanıyor. \
    Tam sistem tüneli ve kill-switch için Apple Developer + NE entitlement gerekir.
    """

    static var isAvailable: Bool { false }

    /// Future: start tunnel provider session.
    static func startTunnelIfAvailable() -> Bool {
        LogManager.shared.appendLog("NE stub: \(statusNote)")
        return false
    }
}
