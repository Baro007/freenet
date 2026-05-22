import Cocoa
import SwiftUI

// freenet — Hibrit DPI ve Tünel Yönetimi

enum Mode: String {
    case dpi = "DPI Modu (Yerel)"
    case warp = "Tünel Modu (WARP)"
    case singbox = "sing-box Modu"
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
    private var singboxProcess: Process?
    
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var aboutWindow: NSWindow?

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
            else if currentMode == .warp { stopWARP() }
            else { stopSingBox() }
        }
    }

    private func cleanupOrphanedProxy() {
        let ciadpiRunning = (ciadpiProcess?.isRunning == true)
        let singboxRunning = (singboxProcess?.isRunning == true)
        if !ciadpiRunning && !singboxRunning && checkProxyOn() {
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
        let task = createProcess("/usr/bin/sudo", args: ["-n", "/usr/bin/true"])
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
            "\(user) ALL=(ALL) NOPASSWD: \(wgQuickPath) down wgcf",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/true"
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
            let task = createProcess("/usr/bin/sudo", args: [cmd] + args)
            try? task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } else {
            let fullCmd = "\(cmd) " + args.joined(separator: " ")
            let escaped = fullCmd.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"export PATH=\\\"/opt/homebrew/bin:/usr/local/bin:\\$PATH\\\"; \(escaped)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            return err == nil
        }
    }

    private func createProcess(_ cmd: String, args: [String]) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cmd)
        task.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        let homebrewPath = "/opt/homebrew/bin:/usr/local/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(homebrewPath):\(currentPath)"
        } else {
            env["PATH"] = homebrewPath
        }
        task.environment = env
        return task
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

        let singboxItem = NSMenuItem(title: Mode.singbox.rawValue, action: #selector(selectSingBoxMode), keyEquivalent: "")
        singboxItem.target = self
        singboxItem.state = (currentMode == .singbox) ? .on : .off
        modeSubmenu.addItem(singboxItem)
        
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
    
    @objc private func selectSingBoxMode() {
        currentMode = .singbox
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
                } else if self.currentMode == .warp {
                    self.stopWARP()
                } else {
                    self.stopSingBox()
                }
            } else {
                if self.currentMode == .dpi {
                    self.startDPI()
                } else if self.currentMode == .warp {
                    self.startWARP()
                } else {
                    self.startSingBox()
                }
            }
            
            DispatchQueue.main.async {
                self.isOn = self.checkTunnelUp()
                self.isTransitioning = false
                self.updateIcon()
                self.rebuildMenu()
                self.fetchIP()
            }
        }
    }
    
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Freenet Ayarları"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
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
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Freenet Canlı Dashboard"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
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
        let chmodTask = createProcess("/bin/chmod", args: ["+x", ciadpiPath])
        try? chmodTask.run()
        chmodTask.waitUntilExit()
        
        let dpiArgsStr = UserDefaults.standard.string(forKey: "dpiArgs") ?? "-d 1 -p 1080"
        let args = dpiArgsStr.components(separatedBy: " ").filter { !$0.isEmpty }
        ciadpiProcess = createProcess(ciadpiPath, args: args)
        
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
        let killTask = createProcess("/usr/bin/killall", args: ["-9", "ciadpi"])
        try? killTask.run()
        
        let primaryInterfaces = ["Wi-Fi", "Ethernet"]
        for interface in primaryInterfaces {
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxystate", interface, "off"])
        }
    }

    private func startSingBox() {
        let singboxPath = Bundle.main.bundlePath + "/Contents/Resources/bin/sing-box"
        let chmodTask = createProcess("/bin/chmod", args: ["+x", singboxPath])
        try? chmodTask.run()
        chmodTask.waitUntilExit()
        
        let configDir = NSString(string: "~/.config/freenet").expandingTildeInPath
        let configPath = configDir + "/sing-box.json"
        
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        
        let configJson = """
        {
          "log": {
            "level": "info",
            "timestamp": true
          },
          "inbounds": [
            {
              "type": "socks",
              "tag": "socks-in",
              "listen": "127.0.0.1",
              "listen_port": 1081
            }
          ],
          "outbounds": [
            {
              "type": "direct",
              "tag": "direct-out"
            }
          ],
          "route": {
            "rules": [
              {
                "inbound": ["socks-in"],
                "action": "sniff"
              },
              {
                "port": 443,
                "action": "route-options",
                "tls_record_fragment": true
              }
            ]
          },
          "dns": {
            "servers": [
              {
                "tag": "cloudflare-doh",
                "type": "https",
                "server": "1.1.1.1",
                "server_port": 443,
                "path": "/dns-query"
              }
            ],
            "strategy": "ipv4_only"
          }
        }
        """
        
        try? configJson.write(toFile: configPath, atomically: true, encoding: .utf8)
        
        singboxProcess = createProcess(singboxPath, args: ["run", "-c", configPath])
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        singboxProcess?.standardOutput = outPipe
        singboxProcess?.standardError = errPipe
        
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
        
        LogManager.shared.appendLog("--- sing-box başlatılıyor (SOCKS5 Port: 1081, DoH, Fragment) ---")
        do {
            try singboxProcess?.run()
        } catch {
            showError(detail: "sing-box başlatılamadı: \(error.localizedDescription)")
            return
        }
        
        let primaryInterfaces = ["Wi-Fi", "Ethernet"]
        for interface in primaryInterfaces {
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxy", interface, "127.0.0.1", "1081"])
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxystate", interface, "on"])
        }
    }
    
    private func stopSingBox() {
        (singboxProcess?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (singboxProcess?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        singboxProcess?.terminate()
        singboxProcess = nil
        LogManager.shared.appendLog("--- sing-box durduruldu ---")
        
        let killTask = createProcess("/usr/bin/killall", args: ["-9", "sing-box"])
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
                    showInfo(detail: "Homebrew bulunamadı. Kurulum komutu Terminal'de otomatik açılacaktır. Lütfen Terminal'deki talimatları izleyip kurulum bittiğinde freenet'i tekrar çalıştırın.")
                }
                let script = "tell application \"Terminal\" to do script \"/bin/bash -c \\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\"\""
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                return false
            }
            
            let task = createProcess(brewPath, args: ["install", "wireguard-tools", "wgcf"])
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
            
            let regTask = createProcess(wgcfPath, args: ["register", "--accept-tos"])
            regTask.currentDirectoryURL = URL(fileURLWithPath: configDir)
            try? regTask.run()
            regTask.waitUntilExit()
            
            let genTask = createProcess(wgcfPath, args: ["generate"])
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
            let cpCmd = "/bin/mkdir -p /etc/wireguard && /bin/cp '\(configPath)' '\(destConfig)' && /bin/chmod 600 '\(destConfig)'"
            let script = "do shell script \"\(cpCmd)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
        
        return true
    }

    private func startWARP() {
        if !ensureWARPSetup() {
            return
        }
        
        let script = "do shell script \"export PATH=\\\"/opt/homebrew/bin:/usr/local/bin:\\$PATH\\\"; \(wgQuickPath) up \(tunnelName)\" with administrator privileges"
        
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
            let cmd = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; \(wgQuickPath) down \(tunnelName)"
            let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }

    private func checkTunnelUp() -> Bool {
        if currentMode == .warp {
            let task = createProcess("/sbin/ifconfig", args: [])
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do { try task.run() } catch { return false }
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return out.contains("inet \(tunnelInternalIP)")
        } else if currentMode == .singbox {
            let proxyOn = checkProxyOn()
            return (singboxProcess?.isRunning == true) || proxyOn
        } else {
            let proxyOn = checkProxyOn()
            return (ciadpiProcess?.isRunning == true) || proxyOn
        }
    }
    
    private func checkProxyOn() -> Bool {
        let task = createProcess(networksetupPath, args: ["-getsocksfirewallproxy", "Wi-Fi"])
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
        guard !isTransitioning else { return }
        let nowOn = checkTunnelUp()
        
        if isOn && !nowOn {
            LogManager.shared.appendLog("⚠️ Bağlantı kopması algılandı! Otomatik olarak yeniden bağlanılıyor (Self-Healing)...")
            isTransitioning = true
            updateIcon()
            rebuildMenu()
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                if self.currentMode == .dpi {
                    self.stopDPI()
                    self.startDPI()
                } else if self.currentMode == .warp {
                    self.stopWARP()
                    self.startWARP()
                } else {
                    self.stopSingBox()
                    self.startSingBox()
                }
                
                DispatchQueue.main.async {
                    self.isTransitioning = false
                    self.isOn = self.checkTunnelUp()
                    self.updateIcon()
                    self.rebuildMenu()
                    self.fetchIP()
                }
            }
        } else if nowOn != isOn {
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
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Freenet Hakkında"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: AboutView())
            window.isReleasedWhenClosed = false
            self.aboutWindow = window
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        if isOn {
            if currentMode == .dpi { stopDPI() }
            else if currentMode == .warp { stopWARP() }
            else { stopSingBox() }
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
