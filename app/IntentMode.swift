import Foundation

/// Product surface: user-facing intents (not raw motor names).
enum IntentMode: String, CaseIterable {
    case fast = "Hızlı"
    case balanced = "Dengeli"
    case maxPrivacy = "Maks. Gizlilik"

    var storageKey: String { "freenetIntent" }

    /// Short subtitle for menus / dashboard.
    var detail: String {
        switch self {
        case .fast:
            return "Sansür aş · IP görünür · yüksek hız"
        case .balanced:
            return "IP maskele · Cloudflare güven modeli"
        case .maxPrivacy:
            return "Gerçek anonimlik (Tor) · yavaş"
        }
    }

    var privacyLevel: PrivacyLevel {
        switch self {
        case .fast: return .none
        case .balanced: return .ipMask
        case .maxPrivacy: return .anonymity
        }
    }

    /// True when UI must show an honesty warning (slowness / not for speed).
    var showsSlownessWarning: Bool { self == .maxPrivacy }

    static func fromStorage(_ raw: String?) -> IntentMode {
        guard let raw = raw else { return .fast }
        return IntentMode(rawValue: raw) ?? .fast
    }
}

enum PrivacyLevel: String {
    case none
    case ipMask
    case anonymity
}

/// Preference for which engine powers IntentMode.fast
enum FastEnginePreference: String, CaseIterable {
    case auto = "Otomatik"
    case singbox = "sing-box"
    case dpi = "DPI (ciadpi)"

    static let storageKey = "freenetFastEngine"

    static func fromStorage(_ raw: String?) -> FastEnginePreference {
        guard let raw = raw else { return .auto }
        return FastEnginePreference(rawValue: raw) ?? .auto
    }
}

/// Engine identifiers used in mapping (shipped code path).
enum EngineID: String {
    case dpi
    case singbox
    case warp
    case tor
}

/// Pure mapping: intent (+ fast preference) → ordered engine IDs to try.
/// Tests call this directly — no Process/UI.
enum IntentEngineMapper {
    /// Primary engine for the intent. For `.auto` fast mode, primary is sing-box.
    static func primaryEngine(intent: IntentMode, fastPreference: FastEnginePreference) -> EngineID {
        switch intent {
        case .balanced:
            return .warp
        case .maxPrivacy:
            return .tor
        case .fast:
            switch fastPreference {
            case .dpi: return .dpi
            case .singbox, .auto: return .singbox
            }
        }
    }

    /// Ordered candidates for start / self-heal fallback (first success wins).
    static func engineCandidates(intent: IntentMode, fastPreference: FastEnginePreference) -> [EngineID] {
        switch intent {
        case .balanced:
            return [.warp]
        case .maxPrivacy:
            return [.tor]
        case .fast:
            switch fastPreference {
            case .singbox:
                return [.singbox]
            case .dpi:
                return [.dpi]
            case .auto:
                return [.singbox, .dpi]
            }
        }
    }

    static func displayEngineName(_ id: EngineID) -> String {
        switch id {
        case .dpi: return "DPI (ciadpi)"
        case .singbox: return "sing-box"
        case .warp: return "WARP"
        case .tor: return "Tor"
        }
    }
}
