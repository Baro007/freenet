import Foundation

/// Orchestrates engines by intent; owns self-heal and orphan proxy cleanup.
final class EngineManager {
    static let shared = EngineManager()

    private let dpi = DPIEngine()
    private let singbox = SingBoxEngine()
    private let warp = WarpEngine()
    private let tor = TorEngine()

    private(set) var activeEngine: Engine?
    private(set) var activeIntent: IntentMode = .fast
    private(set) var lastError: String?

    private init() {}

    func engine(for id: EngineID) -> Engine {
        switch id {
        case .dpi: return dpi
        case .singbox: return singbox
        case .warp: return warp
        case .tor: return tor
        }
    }

    var anyLocalEngineRunning: Bool {
        dpi.isRunning || singbox.isRunning || tor.isRunning
    }

    var isConnected: Bool {
        if let active = activeEngine {
            return active.isRunning || (active.id == .warp && warp.isRunning)
        }
        return false
    }

    var activeEngineID: EngineID? { activeEngine?.id }

    /// Adopt an already-running WARP tunnel on app launch so UI accurately reflects active VPN state.
    @discardableResult
    func adoptRunningWarpIfPresent() -> Bool {
        guard activeEngine == nil, warp.isRunning else { return false }
        activeEngine = warp
        activeIntent = .balanced
        LogManager.shared.appendLog("Aktif WARP tüneli algılandı ve bağlandı.")
        return true
    }

    /// Force-quit safety: clear SOCKS if nothing we own is running.
    func cleanupOrphanedProxy() {
        ProxyService.shared.cleanupOrphanedProxyIfNeeded(enginesRunning: anyLocalEngineRunning || warp.isRunning)
    }

    func start(intent: IntentMode, fastPreference: FastEnginePreference) throws {
        lastError = nil
        activeIntent = intent
        stopAllQuiet()

        let candidates = IntentEngineMapper.engineCandidates(intent: intent, fastPreference: fastPreference)
        var errors: [String] = []

        for id in candidates {
            let eng = engine(for: id)
            do {
                try eng.start()
                // Confirm running where applicable
                if eng.id != .warp {
                    if !eng.isRunning {
                        eng.stop()
                        throw EngineError.startFailed("\(eng.displayName) process ayakta değil")
                    }
                } else if !warp.isRunning {
                    // WARP may need a moment
                    Thread.sleep(forTimeInterval: 0.5)
                    if !warp.isRunning {
                        throw EngineError.startFailed("WARP arayüzü görünmüyor")
                    }
                }
                activeEngine = eng
                LogManager.shared.appendLog("✅ Aktif: \(intent.rawValue) → \(eng.displayName)")
                return
            } catch {
                let msg = error.localizedDescription
                errors.append("\(id.rawValue): \(msg)")
                LogManager.shared.appendLog("⚠️ \(eng.displayName) başarısız: \(msg)")
                eng.stop()
            }
        }

        activeEngine = nil
        let joined = errors.joined(separator: "; ")
        lastError = joined
        throw EngineError.startFailed(joined.isEmpty ? "Motor başlatılamadı" : joined)
    }

    func stop() {
        if let active = activeEngine {
            active.stop()
        } else {
            stopAllQuiet()
        }
        activeEngine = nil
        lastError = nil
    }

    private func stopAllQuiet() {
        dpi.stop()
        singbox.stop()
        warp.stop()
        tor.stop()
    }

    /// Self-heal: if we believe we should be on but tunnel/proxy died, restart.
    func healIfNeeded(expectedOn: Bool, intent: IntentMode, fastPreference: FastEnginePreference) -> Bool {
        guard expectedOn else { return false }
        let up: Bool
        if let active = activeEngine {
            if active.id == .warp {
                up = warp.isRunning
            } else {
                up = active.isRunning || ProxyService.shared.isSOCKSEnabled()
            }
        } else {
            up = false
        }
        if up { return false }

        LogManager.shared.appendLog("⚠️ Bağlantı kopması algılandı! Self-heal yeniden bağlanıyor…")
        do {
            try start(intent: intent, fastPreference: fastPreference)
            return true
        } catch {
            lastError = error.localizedDescription
            LogManager.shared.appendLog("❌ Self-heal başarısız: \(error.localizedDescription)")
            activeEngine = nil
            return false
        }
    }
}
