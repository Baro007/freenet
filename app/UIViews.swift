import SwiftUI

// Translucent visual effect view for beautiful macOS styling
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

// Custom Hover Effect Modifier for interactive feel
struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat = 1.02
    var hoverColor: Color = Color.white.opacity(0.08)
    
    func body(content: Content) -> some View {
        content
            .background(isHovered ? hoverColor : Color.clear)
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                self.isHovered = hovering
            }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.02, hoverColor: Color = Color.white.opacity(0.08)) -> some View {
        self.modifier(HoverEffectModifier(scale: scale, hoverColor: hoverColor))
    }
}

struct SettingsView: View {
    @AppStorage("dpiArgs") private var dpiArgs: String = "-d 1 -p 1080"
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack(alignment: .leading, spacing: 16) {
                // Header with Badge
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DPI Motoru Ayarları")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("ciadpi parametre yapılandırması")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                // Explanatory Note Box
                VStack(alignment: .leading, spacing: 6) {
                    Text("💡 Önemli Bilgi")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text("İnternet servis sağlayıcınızın DPI türüne göre parametreleri değiştirebilirsiniz. Değişikliklerin aktif olması için bağlantı modunu kapatıp açmalısınız.")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                
                // Parameters Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Çalıştırma Parametreleri")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("Parametreler", text: $dpiArgs)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))
                }
                
                // Actions
                HStack {
                    Button(action: {
                        dpiArgs = "-d 1 -p 1080"
                    }) {
                        Text("Varsayılana Dön")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.03, hoverColor: Color.orange.opacity(0.05))
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(width: 440, height: 280)
    }
}

struct DashboardView: View {
    @ObservedObject var logManager = LogManager.shared
    
    // Dynamically color logs based on level/type
    private func getLogColor(_ log: String) -> Color {
        let lower = log.lowercased()
        if lower.contains("hata") || lower.contains("error") || lower.contains("fail") || lower.contains("could not") {
            return Color.red
        } else if lower.contains("⚠️") || lower.contains("warning") || lower.contains("uyarı") || lower.contains("kopma") {
            return Color.orange
        } else if log.hasPrefix("---") {
            return Color.cyan
        } else if lower.contains("connected") || lower.contains("aktif") || lower.contains("başarıyla") {
            return Color.green
        } else {
            return Color.white.opacity(0.9)
        }
    }
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack(spacing: 0) {
                // Header Panel
                HStack {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.teal, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Canlı Sistem Günlüğü")
                                .font(.system(size: 13, weight: .bold))
                            Text("Ağ ve motor logları")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Clear Logs Button
                    Button(action: {
                        logManager.clearLogs()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Temizle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(scale: 1.05, hoverColor: Color.red.opacity(0.12))
                    .help("Logları Temizle")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.15))
                
                Divider()
                
                // Terminal Console
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if logManager.logs.isEmpty {
                                VStack(spacing: 10) {
                                    Spacer()
                                    Image(systemName: "square.stack.3d.up.slash")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary.opacity(0.4))
                                    Text("Henüz log kaydı yok.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 300)
                            } else {
                                ForEach(Array(logManager.logs.enumerated()), id: \.offset) { index, log in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(String(format: "%04d", index + 1))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .frame(width: 32, alignment: .trailing)
                                        
                                        Text(log)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(getLogColor(log))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 2)
                                    .cornerRadius(4)
                                    .hoverEffect(scale: 1.0, hoverColor: Color.white.opacity(0.03))
                                    .id(index)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .background(Color.black.opacity(0.45))
                    .onChange(of: logManager.logs.count) { _ in
                        if !logManager.logs.isEmpty {
                            withAnimation {
                                proxy.scrollTo(logManager.logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 580, height: 420)
    }
}

struct AboutView: View {
    @State private var isHoveringDev = false
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack(spacing: 20) {
                // Top header / Brand glow
                VStack(spacing: 12) {
                    ZStack {
                        // Glowing Background
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 84, height: 84)
                            .blur(radius: 8)
                            .opacity(0.6)
                        
                        if let appIcon = NSApplication.shared.applicationIconImage {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 80, height: 80)
                        } else {
                            Image(systemName: "shield.white")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .frame(width: 80, height: 80)
                                .background(Color.blue)
                                .cornerRadius(18)
                        }
                    }
                    
                    Text("freenet")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Sıfır Sürtünme, Sınırsız Özgürlük.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
                
                Divider()
                    .padding(.horizontal, 10)
                
                // Content Cards (DPI, WARP and sing-box Modes)
                VStack(spacing: 12) {
                    // DPI Mode Card
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "hare.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("DPI Modu (Hız Odaklı)")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text("Yerel Motor")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                            
                            Text("Ağ paketlerinizi akıllıca parçalayarak ISS sansürlerini ve engellerini aşar. Verileriniz şifrelenmez veya başka bir ülkeye yönlendirilmez. Sıfır ping ve tam hızla çalışır.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .hoverEffect(scale: 1.01)
                    
                    // WARP Mode Card
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("WARP Tünel Modu (Güvenli Tünel)")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text("WireGuard")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                            
                            Text("Cloudflare ağ altyapısını ve WireGuard protokolünü kullanarak tüm cihaz trafiğinizi şifreli tünelden geçirir. IP bazlı sansürleri aşar ve sizi internette gizler.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .hoverEffect(scale: 1.01)
                    
                    // sing-box Mode Card
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [Color.cyan, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "network")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("sing-box Modu (Gelişmiş Tünel)")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text("sing-box")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.15))
                                    .foregroundColor(.cyan)
                                    .cornerRadius(4)
                            }
                            
                            Text("Yerel SOCKS5 tüneli oluşturur. TLS el sıkışma fragmantasyonu (TCP bölünmesi) ve şifreli DNS (DoH) protokolü kullanarak gelişmiş DPI / sansür mekanizmalarını atlatır.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .hoverEffect(scale: 1.01)
                }
                
                Spacer()
                
                // Footer
                VStack(spacing: 4) {
                    Text("v1.0.1 | MIT License")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        if let url = URL(string: "https://github.com/sadikbarisadiguzel") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Geliştirici: Baro007")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isHoveringDev ? .orange : .secondary)
                            .underline(isHoveringDev)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isHoveringDev = hovering
                    }
                }
                .padding(.bottom, 5)
            }
            .padding(24)
        }
        .frame(width: 460, height: 580)
    }
}
