import Cocoa
import SwiftUI

// freenet — Hibrit DPI ve Tünel Yönetimi

enum Mode: String {
    case dpi = "DPI Modu (Yerel)"
    case warp = "Tünel Modu (WARP)"
}

final class AppController: NSObject, NSApplicationDelegate {
    private let tunnelName = "wgcf"
    private let tunnelInternalIP = "172.16.0.2"
    private let networksetupPath = "/usr/sbin/networksetup"
    
    private var wgQuickPath: String {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/opt/homebrew/bin/wg-quick") { return "/opt/homebrew/bin/wg-quick" }
        return "/usr/local/bin/wg-quick"
    }
    
    private var brewPrefix: String {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/opt/homebrew/bin/brew") { return "/opt/homebrew/bin" }
        return "/usr/local/bin"
    }
    
    private var statusItem: NSStatusItem!
    private var statusTimer: Timer?
    private var ipTimer: Timer?
    
    private var isOn = false
    private var isTransitioning = false
    private var currentMode: Mode = .dpi
    private var currentIPInfo = "Mevcut IP: Denetleniyor..."
    
    private var ciadpiProcess: Process?
    
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        
        let savedMode = UserDefaults.standard.string(forKey: "freenetMode") ?? Mode.dpi.rawValue
        currentMode = Mode(rawValue: savedMode) ?? .dpi
        
        // Başlatmada kalan proxy'yi temizle (Force Quit koruması)
        cleanupOrphanedProxy()
        
        updateIcon()
        rebuildMenu()
        
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        refreshStatus()
        
        ipTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.fetchIP()
        }
        fetchIP()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isOn {
            if currentMode == .dpi { stopDPI() }
            else { stopWARP() }
        }
    }

    private func cleanupOrphanedProxy() {
        let ciadpiRunning = (ciadpiProcess?.isRunning == true)
        if !ciadpiRunning && checkProxyOn() {
            let interfaces = ["Wi-Fi", "Ethernet"]
            for iface in interfaces {
                _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxystate", iface, "off"])
            }
        }
    }

    private func fetchIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let data = data, let ip = String(data: data, encoding: .utf8) {
                    self.currentIPInfo = "Mevcut IP: \(ip)"
                } else {
                    self.currentIPInfo = "Mevcut IP: Bulunamadı"
                }
                self.rebuildMenu()
            }
        }
        task.resume()
    }

    private func isSudoersInstalled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", networksetupPath, "-version"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    @objc private func installSudoers() {
        let user = NSUserName()
        let rules = [
            "\(user) ALL=(ALL) NOPASSWD: \(networksetupPath) -setsocksfirewallproxy *",
            "\(user) ALL=(ALL) NOPASSWD: \(networksetupPath) -setsocksfirewallproxystate *",
            "\(user) ALL=(ALL) NOPASSWD: \(wgQuickPath) up wgcf",
            "\(user) ALL=(ALL) NOPASSWD: \(wgQuickPath) down wgcf"
        ]
        let content = rules.joined(separator: "\n")
        let script = """
        echo '\(content)' > /tmp/freenet_sudoers
        chmod 440 /tmp/freenet_sudoers
        chown root:wheel /tmp/freenet_sudoers
        mv /tmp/freenet_sudoers /etc/sudoers.d/freenet
        """
        let escaped = script.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if err == nil {
            showInfo(detail: "Şifresiz geçiş başarıyla aktif edildi!")
            rebuildMenu()
        } else {
            showError(detail: "Şifresiz geçiş kurulamadı.")
        }
    }

    private func runSudoCommand(_ cmd: String, args: [String]) -> Bool {
        if isSudoersInstalled() {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            task.arguments = [cmd] + args
            try? task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } else {
            let fullCmd = "\(cmd) " + args.joined(separator: " ")
            let escaped = fullCmd.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin && do shell script \"\(escaped)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            return err == nil
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if isTransitioning {
            symbol = "shield.lefthalf.filled.trianglebadge.exclamationmark"
        } else if isOn {
            symbol = "shield.lefthalf.filled"
        } else {
            symbol = "shield.slash"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "freenet")
        img?.isTemplate = true
        button.image = img
        button.toolTip = isOn ? "freenet AÇIK" : "freenet kapalı"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        
        let ipItem = NSMenuItem(title: currentIPInfo, action: nil, keyEquivalent: "")
        ipItem.isEnabled = false
        menu.addItem(ipItem)
        menu.addItem(NSMenuItem.separator())

        let stateText = isTransitioning ? "Geçiş yapılıyor…" : (isOn ? "● freenet AÇIK" : "○ freenet kapalı")
        let header = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if isOn {
            let info = NSMenuItem(title: currentMode.rawValue, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(
            title: isOn ? "KAPAT" : "AÇ",
            action: #selector(toggleTunnel),
            keyEquivalent: "t"
        )
        toggle.target = self
        toggle.isEnabled = !isTransitioning
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())
        
        let modeSubmenu = NSMenu()
        let dpiItem = NSMenuItem(title: Mode.dpi.rawValue, action: #selector(selectDPIMode), keyEquivalent: "")
        dpiItem.target = self
        dpiItem.state = (currentMode == .dpi) ? .on : .off
        modeSubmenu.addItem(dpiItem)
        
        let warpItem = NSMenuItem(title: Mode.warp.rawValue, action: #selector(selectWARPMode), keyEquivalent: "")
        warpItem.target = self
        warpItem.state = (currentMode == .warp) ? .on : .off
        modeSubmenu.addItem(warpItem)
        
        let modeMenuItem = NSMenuItem(title: "Bağlantı Modu", action: nil, keyEquivalent: "")
        modeMenuItem.submenu = modeSubmenu
        modeMenuItem.isEnabled = !isOn && !isTransitioning
        menu.addItem(modeMenuItem)
        
        if !isSudoersInstalled() {
            menu.addItem(NSMenuItem.separator())
            let sudoItem = NSMenuItem(title: "Şifresiz Geçişi Aktif Et ⚡️", action: #selector(installSudoers), keyEquivalent: "")
            sudoItem.target = self
            menu.addItem(sudoItem)
        }

        menu.addItem(NSMenuItem.separator())
        
        let dashboardItem = NSMenuItem(title: "Canlı Dashboard...", action: #selector(showDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        
        let settingsItem = NSMenuItem(title: "Ayarlar...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let about = NSMenuItem(title: "Hakkında…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }
    
    @objc private func selectDPIMode() {
        currentMode = .dpi
        UserDefaults.standard.set(currentMode.rawValue, forKey: "freenetMode")
        rebuildMenu()
    }
    
    @objc private func selectWARPMode() {
        currentMode = .warp
        UserDefaults.standard.set(currentMode.rawValue, forKey: "freenetMode")
        rebuildMenu()
    }

    @objc private func toggleTunnel() {
        guard !isTransitioning else { return }
        isTransitioning = true
        updateIcon()
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if self.isOn {
                if self.currentMode == .dpi {
                    self.stopDPI()
                } else {
                    self.stopWARP()
                }
            } else {
                if self.currentMode == .dpi {
                    self.startDPI()
                } else {
                    self.startWARP()
                }
            }
            
            DispatchQueue.main.async {
                self.isTransitioning = false
                self.refreshStatus()
                self.updateIcon()
                self.rebuildMenu()
            }
        }
    }
    
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "Freenet Ayarları"
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Freenet Canlı Dashboard"
            window.center()
            window.setFrameAutosaveName("DashboardWindow")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DashboardView())
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func startDPI() {
        let ciadpiPath = Bundle.main.bundlePath + "/Contents/Resources/bin/ciadpi"
        let chmodTask = Process()
        chmodTask.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodTask.arguments = ["+x", ciadpiPath]
        try? chmodTask.run()
        chmodTask.waitUntilExit()
        
        ciadpiProcess = Process()
        ciadpiProcess?.executableURL = URL(fileURLWithPath: ciadpiPath)
        
        let dpiArgsStr = UserDefaults.standard.string(forKey: "dpiArgs") ?? "-d 1 -p 1080"
        let args = dpiArgsStr.components(separatedBy: " ").filter { !$0.isEmpty }
        ciadpiProcess?.arguments = args
        
        // Port'u argümanlardan parse et (varsayılan: 1080)
        var proxyPort = "1080"
        if let pIdx = args.firstIndex(of: "-p"), pIdx + 1 < args.count {
            proxyPort = args[pIdx + 1]
        }
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        ciadpiProcess?.standardOutput = outPipe
        ciadpiProcess?.standardError = errPipe
        
        let logHandler: (FileHandle) -> Void = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty { return }
            if let string = String(data: data, encoding: .utf8) {
                let lines = string.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    LogManager.shared.appendLog(line)
                }
            }
        }
        outPipe.fileHandleForReading.readabilityHandler = logHandler
        errPipe.fileHandleForReading.readabilityHandler = logHandler
        
        LogManager.shared.appendLog("--- ciadpi başlatılıyor (\(dpiArgsStr)) ---")
        do {
            try ciadpiProcess?.run()
        } catch {
            showError(detail: "DPI motoru başlatılamadı: \(error.localizedDescription)")
            return
        }
        
        let primaryInterfaces = ["Wi-Fi", "Ethernet"]
        for interface in primaryInterfaces {
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxy", interface, "127.0.0.1", proxyPort])
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxystate", interface, "on"])
        }
    }
    
    private func stopDPI() {
        (ciadpiProcess?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (ciadpiProcess?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        ciadpiProcess?.terminate()
        ciadpiProcess = nil
        LogManager.shared.appendLog("--- ciadpi durduruldu ---")
        
        // Ensure proxy is killed
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["-9", "ciadpi"]
        try? killTask.run()
        
        let primaryInterfaces = ["Wi-Fi", "Ethernet"]
        for interface in primaryInterfaces {
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxystate", interface, "off"])
        }
    }
    
    private func ensureWARPSetup() -> Bool {
        let fm = FileManager.default
        let brewPath = brewPrefix + "/brew"
        let wgcfPath = brewPrefix + "/wgcf"
        let wgQuick = brewPrefix + "/wg-quick"
        
        if !fm.fileExists(atPath: wgcfPath) || !fm.fileExists(atPath: wgQuick) {
            DispatchQueue.main.sync {
                showInfo(detail: "Tünel modu için gerekli paketler (wireguard-tools, wgcf) indiriliyor. Bu işlem birkaç dakika sürebilir, lütfen bekleyin...")
            }
            
            if !fm.fileExists(atPath: brewPath) {
                DispatchQueue.main.sync {
                    showError(detail: "Homebrew bulunamadı. Lütfen önce https://brew.sh adresinden Homebrew yükleyin.")
                }
                return false
            }
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: brewPath)
            task.arguments = ["install", "wireguard-tools", "wgcf"]
            try? task.run()
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                DispatchQueue.main.sync {
                    showError(detail: "Bağımlılıklar yüklenemedi. Lütfen Terminal'te manuel olarak çalıştırın: brew install wireguard-tools wgcf")
                }
                return false
            }
        }
        
        let configDir = NSString(string: "~/.config/wireguard").expandingTildeInPath
        let configPath = configDir + "/wgcf.conf"
        
        if !fm.fileExists(atPath: configPath) {
            DispatchQueue.main.sync {
                showInfo(detail: "WARP profiliniz oluşturuluyor. Bu işlem bir kereye mahsustur, lütfen bekleyin...")
            }
            
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
            
            let regTask = Process()
            regTask.executableURL = URL(fileURLWithPath: wgcfPath)
            regTask.arguments = ["register", "--accept-tos"]
            regTask.currentDirectoryURL = URL(fileURLWithPath: configDir)
            try? regTask.run()
            regTask.waitUntilExit()
            
            let genTask = Process()
            genTask.executableURL = URL(fileURLWithPath: wgcfPath)
            genTask.arguments = ["generate"]
            genTask.currentDirectoryURL = URL(fileURLWithPath: configDir)
            try? genTask.run()
            genTask.waitUntilExit()
            
            if !fm.fileExists(atPath: configPath) {
                DispatchQueue.main.sync {
                    showError(detail: "WARP profili oluşturulamadı.")
                }
                return false
            }
        }
        
        let destConfig = "/etc/wireguard/wgcf.conf"
        if !fm.fileExists(atPath: destConfig) {
            let cpCmd = "mkdir -p /etc/wireguard && cp '\(configPath)' '\(destConfig)' && chmod 600 '\(destConfig)'"
            let script = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin && do shell script \"\(cpCmd)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
        
        return true
    }

    private func startWARP() {
        if !ensureWARPSetup() {
            return
        }
        
        let script = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin && do shell script \"\(wgQuickPath) up \(tunnelName)\" with administrator privileges"
        
        if isSudoersInstalled() {
            _ = runSudoCommand(wgQuickPath, args: ["up", tunnelName])
        } else {
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }
    
    private func stopWARP() {
        if isSudoersInstalled() {
            _ = runSudoCommand(wgQuickPath, args: ["down", tunnelName])
        } else {
            let cmd = "\(wgQuickPath) down \(tunnelName)"
            let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin && do shell script \"\(escaped)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }

    private func checkTunnelUp() -> Bool {
        if currentMode == .warp {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do { try task.run() } catch { return false }
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return out.contains("inet \(tunnelInternalIP)")
        } else {
            let proxyOn = checkProxyOn()
            return (ciadpiProcess?.isRunning == true) || proxyOn
        }
    }
    
    private func checkProxyOn() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: networksetupPath)
        task.arguments = ["-getsocksfirewallproxy", "Wi-Fi"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8) {
            return out.contains("Yes")
        }
        return false
    }
    
    private func refreshStatus() {
        let nowOn = checkTunnelUp()
        if nowOn != isOn {
            isOn = nowOn
            updateIcon()
            rebuildMenu()
            fetchIP()
        }
    }

    private func showError(detail: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "freenet hata"
            alert.informativeText = detail
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Tamam")
            alert.runModal()
        }
    }
    
    private func showInfo(detail: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "freenet"
            alert.informativeText = detail
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Tamam")
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "freenet"
        alert.informativeText = """
        Türkiye İnternet Engel Atlatma Aracı (Hibrit)
        
        Modlar:
        - DPI Modu: ByeDPI (ciadpi) ile SOCKS5 tabanlı (Hızlı, Anonim değil)
        - Tünel Modu: Cloudflare WARP üzerinden WireGuard tabanlı (IP bloklarını aşar)

        Açık Kaynak Geliştirme.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }

    @objc private func quitApp() {
        if isOn {
            if currentMode == .dpi { stopDPI() }
            else { stopWARP() }
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
