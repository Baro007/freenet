import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat = 1.02
    var hoverColor: Color = Color.white.opacity(0.08)

    func body(content: Content) -> some View {
        content
            .background(isHovered ? hoverColor : Color.clear)
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in self.isHovered = hovering }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.02, hoverColor: Color = Color.white.opacity(0.08)) -> some View {
        modifier(HoverEffectModifier(scale: scale, hoverColor: hoverColor))
    }
}

/// Always-visible control surface (Dock + window) — does not rely on menubar only.
struct MainPanelView: View {
    var version: String
    var isOn: Bool
    var isTransitioning: Bool
    var intent: IntentMode
    var engineName: String
    var ipInfo: String
    var torStatus: String
    var torReallyOn: Bool
    var directIP: String
    var updateLine: String
    var onToggle: () -> Void
    var onSelectIntent: (IntentMode) -> Void
    var onOpenDashboard: () -> Void
    var onOpenSettings: () -> Void
    var onCheckUpdates: () -> Void
    var onInstallSudoers: () -> Void
    var onRecheckTor: () -> Void
    var onQuit: () -> Void

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: isOn ? "shield.lefthalf.filled" : "shield.slash")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(isOn ? (torReallyOn || torStatus.contains("DOĞRULANDI") ? .green : .orange) : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("freenet")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(version)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Text(isTransitioning ? "Geçiş…" : (isOn ? "AÇIK" : "Kapalı"))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(ipInfo)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(directIP)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(torStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor((torReallyOn || torStatus.contains("DOĞRULANDI")) ? .green : (isOn && intent == .maxPrivacy ? .orange : .secondary))
                    if isOn && intent == .maxPrivacy && !torReallyOn {
                        Text("UI AÇIK olsa bile Tor kanıtlanmadıysa gerçek anonimlik YOK.")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(updateLine)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Niyet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(IntentMode.allCases, id: \.rawValue) { mode in
                        Button(action: { onSelectIntent(mode) }) {
                            HStack {
                                Image(systemName: intent == mode ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(intent == mode ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(mode.detail)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(intent == mode ? Color.orange.opacity(0.12) : Color.white.opacity(0.04))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isTransitioning)
                    }
                }

                if isOn {
                    Text("Motor: \(engineName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyan)
                }

                Button(action: onToggle) {
                    Text(isOn ? "KAPAT" : "AÇ")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isOn ? Color.red.opacity(0.85) : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isTransitioning)

                HStack(spacing: 10) {
                    smallBtn("Dashboard", action: onOpenDashboard)
                    smallBtn("Ayarlar", action: onOpenSettings)
                    smallBtn("Tor doğrula", action: onRecheckTor)
                }

                HStack(spacing: 10) {
                    smallBtn("Güncelle", action: onCheckUpdates)
                }

                Button("Şifresiz Geçişi Aktif Et") { onInstallSudoers() }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                Text("Bağlanmak için AÇ’a bas. SOCKS için bir kez parola gerekebilir.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Çıkış") { onQuit() }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 18)
        }
        .frame(width: 380, height: 610)
    }

    private func smallBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsView: View {
    @AppStorage("dpiArgs") private var dpiArgs: String = DPIArgsValidator.defaultArgs
    @AppStorage("freenetFastEngine") private var fastEngineRaw: String = FastEnginePreference.auto.rawValue
    @AppStorage(SingBoxFragmentMode.storageKey) private var fragmentModeRaw: String = SingBoxFragmentMode.hybridShield.rawValue
    @AppStorage(SingBoxDNSProfile.storageKey) private var dnsProfileRaw: String = SingBoxDNSProfile.cloudflareSecurity.rawValue
    @AppStorage(WarpTransportMode.storageKey) private var warpTransportRaw: String = WarpTransportMode.singboxWarp.rawValue
    @AppStorage(WarpEndpointPort.storageKey) private var warpPortRaw: String = WarpEndpointPort.port500.rawValue
    @AppStorage("freenetTorBridges") private var torBridges: String = ""
    @State private var dpiError: String?

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // Fast engine preference (sing-box first-class)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hızlı niyeti motoru (VPN'siz Tam Hız)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("sing-box: Mixed SOCKS5/HTTP, DoH + DNS Hijack, QUIC + BTK engeli, 4096 DNS önbelleği.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Picker("Motor", selection: $fastEngineRaw) {
                            ForEach(FastEnginePreference.allCases, id: \.rawValue) { pref in
                                Text(pref.rawValue).tag(pref.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Divider().padding(.vertical, 2)

                        Text("Anti-DPI Katmanı (sing-box)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("Anti-DPI", selection: $fragmentModeRaw) {
                            ForEach(SingBoxFragmentMode.allCases, id: \.rawValue) { mode in
                                Text(mode.rawValue).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Hibrit Zırh: sing-box (DoH + QUIC/BTK engel) + ciadpi (3 kademeli DPI + HTTP-80 koruma).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider().padding(.vertical, 2)

                        Text("DNS Kalkanı (Şifreli DoH + Otomatik Yedekleme)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("DNS Kalkanı", selection: $dnsProfileRaw) {
                            ForEach(SingBoxDNSProfile.allCases, id: \.rawValue) { prof in
                                Text(prof.rawValue).tag(prof.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)

                    // WARP (Dengeli) performance tuning
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dengeli (WARP) motor & hız optimizasyonu")
                            .font(.system(size: 12, weight: .semibold))

                        Picker("WARP Motoru", selection: $warpTransportRaw) {
                            ForEach(WarpTransportMode.allCases, id: \.rawValue) { m in
                                Text(m.rawValue).tag(m.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("sing-box WARP: rootsuz, yerel/cloudflared soketlerini koparmaz, otomatik IP/port yedekli + tünel içi DoH kalkanlı.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Picker("WARP UDP Portu", selection: $warpPortRaw) {
                            ForEach(WarpEndpointPort.allCases, id: \.rawValue) { p in
                                Text(p.rawValue).tag(p.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("MTU \(WarpConfigOptimizer.optimalMTU) · Keepalive \(WarpConfigOptimizer.defaultKeepalive)sn · 162.159.193.1 + ISP 2408 kısıt aşımı.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)

                    // DPI args
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DPI (ciadpi) parametreleri")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("Parametreler", text: $dpiArgs)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(10)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(6)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: dpiArgs) { newVal in
                                let r = DPIArgsValidator.validate(newVal)
                                dpiError = r.errorMessage
                            }

                        if let dpiError = dpiError {
                            Text(dpiError)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }

                        Button("Varsayılana Dön") {
                            dpiArgs = DPIArgsValidator.defaultArgs
                            dpiError = nil
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.orange)
                    }

                    // Tor bridges
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tor köprüleri (Maks. Gizlilik, opsiyonel)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Her satıra bir Bridge. Boş bırakılırsa doğrudan Tor.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextEditor(text: $torBridges)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 72)
                            .border(Color.secondary.opacity(0.3))
                    }

                    Text("⚠ Maks. Gizlilik (Tor) yavaştır; gerçek anonimlik yalnızca bu niyettedir.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.purple)
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 540)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Ayarlar")
                    .font(.headline)
                Text("Niyet motorları ve güvenli parametreler")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DashboardView: View {
    @ObservedObject var logManager = LogManager.shared
    var intentProvider: () -> String
    var engineProvider: () -> String
    var isOnProvider: () -> Bool

    @State private var intentLabel = "—"
    @State private var engineLabel = "—"
    @State private var onLabel = false

    private func getLogColor(_ log: String) -> Color {
        let lower = log.lowercased()
        if lower.contains("hata") || lower.contains("error") || lower.contains("fail") || lower.contains("❌") {
            return .red
        } else if lower.contains("⚠️") || lower.contains("warning") || lower.contains("kopma") {
            return .orange
        } else if log.hasPrefix("---") || lower.contains("tor") {
            return .cyan
        } else if lower.contains("aktif") || lower.contains("✅") || lower.contains("connected") {
            return .green
        }
        return Color.white.opacity(0.9)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            VStack(spacing: 0) {
                // Status strip: intent + engine
                HStack(spacing: 16) {
                    statusChip(title: "Durum", value: onLabel ? "AÇIK" : "Kapalı", color: onLabel ? .green : .secondary)
                    statusChip(title: "Niyet", value: intentLabel, color: .orange)
                    statusChip(title: "Motor", value: engineLabel, color: .cyan)
                    Spacer()
                    if intentLabel.contains("Gizlilik") {
                        Text("Tor yavaş / site engeli olabilir")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    Button(action: { logManager.clearLogs() }) {
                        Label("Temizle", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.15))
                .onAppear(perform: refreshMeta)
                .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                    refreshMeta()
                }

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if logManager.logs.isEmpty {
                                Text("Henüz log kaydı yok.")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 280)
                            } else {
                                ForEach(Array(logManager.logs.enumerated()), id: \.offset) { index, log in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(String(format: "%04d", index + 1))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(log)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(getLogColor(log))
                                            .textSelection(.enabled)
                                    }
                                    .id(index)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .background(Color.black.opacity(0.45))
                    .onChange(of: logManager.logs.count) { _ in
                        if !logManager.logs.isEmpty {
                            proxy.scrollTo(logManager.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 460)
    }

    private func refreshMeta() {
        intentLabel = intentProvider()
        engineLabel = engineProvider()
        onLabel = isOnProvider()
    }

    private func statusChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct AboutView: View {
    @State private var isHoveringDev = false
    @State private var updateLine = "Güncelleme kontrolü…"

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            ScrollView {
                VStack(spacing: 16) {
                    Text("freenet")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(AppVersion.fullLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("Niyet seç. Sansür aş veya anonim ol — ikisi birden değil.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    intentCard(
                        title: "Hızlı",
                        badge: "sing-box / DPI",
                        colors: [.orange, .red],
                        body: "DPI ve gelişmiş TLS fragment (sing-box) ile sansürü aşar. IP’niz görünür kalır. Anonimlik yoktur."
                    )
                    intentCard(
                        title: "Dengeli",
                        badge: "WARP · Cloudflare",
                        colors: [.blue, .purple],
                        body: "WireGuard/WARP ile IP maskeler. Cloudflare trafiğinizi ve hedeflerinizi görür — tek şirkete güven modeli; gerçek anonimlik değildir."
                    )
                    intentCard(
                        title: "Maks. Gizlilik",
                        badge: "Tor",
                        colors: [.purple, .indigo],
                        body: "Çok-sıçramalı Tor ağı. Gerçek anonimlik burada. Yavaştır; bazı siteler Tor çıkışını engelleyebilir. Tor: bundle veya Homebrew."
                    )

                    Text(updateLine)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Güncellemeleri Kontrol Et") {
                        updateLine = "Kontrol ediliyor…"
                        UpdateChecker.shared.check { status in
                            switch status {
                            case .upToDate(let c):
                                updateLine = "Güncel (v\(c))"
                            case .updateAvailable(_, let latest, _, _):
                                updateLine = "Yeni sürüm: v\(latest)"
                            case .failed(let m):
                                updateLine = m
                            case .checking:
                                updateLine = "Kontrol ediliyor…"
                            }
                            UpdateChecker.shared.presentAlert(for: status)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.orange)

                    Text("\(AppVersion.display) · MIT · macOS only")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Button(action: {
                        if let url = URL(string: "https://github.com/Baro007/freenet") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Kaynak: github.com/Baro007/freenet")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isHoveringDev ? .orange : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHoveringDev = $0 }
                }
                .padding(24)
            }
        }
        .frame(width: 480, height: 640)
        .onAppear {
            UpdateChecker.shared.check { status in
                switch status {
                case .upToDate(let c): updateLine = "Güncel (v\(c))"
                case .updateAvailable(_, let latest, _, _): updateLine = "Yeni sürüm: v\(latest)"
                case .failed(let m): updateLine = m
                case .checking: break
                }
            }
        }
    }

    private func intentCard(title: String, badge: String, colors: [Color], body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colors[0].opacity(0.15))
                        .foregroundColor(colors[0])
                        .cornerRadius(4)
                }
                Text(body)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
}
