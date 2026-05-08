import SwiftUI

struct SettingsView: View {
    @AppStorage("dpiArgs") private var dpiArgs: String = "-d 1 -p 1080"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DPI Motoru Ayarları (ciadpi)")
                .font(.headline)
            
            Text("İnternet servis sağlayıcınızın DPI türüne göre parametreleri değiştirebilirsiniz. Değişikliklerin aktif olması için DPI modunu kapatıp açmalısınız.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("Parametreler", text: $dpiArgs)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(.body, design: .monospaced))
            
            HStack {
                Button("Varsayılana Dön") {
                    dpiArgs = "-d 1 -p 1080"
                }
                Spacer()
            }
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

struct DashboardView: View {
    @ObservedObject var logManager = LogManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Canlı DPI Logları")
                    .font(.headline)
                Spacer()
                Button(action: {
                    logManager.clearLogs()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.primary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Logları Temizle")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logManager.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .background(Color.black)
                .onChange(of: logManager.logs.count) { _ in
                    if !logManager.logs.isEmpty {
                        withAnimation {
                            proxy.scrollTo(logManager.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
            
            Text("Freenet")
                .font(.largeTitle)
                .bold()
            
            Text("Sıfır Sürtünme, Sınırsız Özgürlük.")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    Image(systemName: "hare.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text("DPI Modu (Hız Odaklı)")
                            .font(.headline)
                        Text("Ağ paketlerinizi parçalayarak engelleri aşar. Trafiğiniz şifrelenmez veya başka bir sunucuya yönlendirilmez. %0 hız kaybıyla en yüksek performansı sunar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                HStack(alignment: .top) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text("WARP Tünel Modu (Ağır Zırh)")
                            .font(.headline)
                        Text("Cloudflare altyapısını kullanarak tüm trafiğinizi aşılmaz ve şifreli bir tünelden geçirir. IP bazlı devasa banları aşar, sizi tamamen anonimleştirir.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            Text("v1.0.0 | MIT License | Baro007")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 10)
        }
        .padding(30)
        .frame(width: 450, height: 450)
    }
}
