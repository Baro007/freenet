import Cocoa

// freenet — Hibrit DPI ve Tünel Yönetimi

enum Mode: String {
    case dpi = "DPI Modu (Yerel)"
    case warp = "Tünel Modu (WARP)"
}

final class AppController: NSObject, NSApplicationDelegate {
    private let tunnelName = "wgcf"
    private let tunnelInternalIP = "172.16.0.2"
    private let wgQuickPath = "/opt/homebrew/bin/wg-quick"
    private let networksetupPath = "/usr/sbin/networksetup"
    
    private var statusItem: NSStatusItem!
    private var statusTimer: Timer?
    private var ipTimer: Timer?
    
    private var isOn = false
    private var isTransitioning = false
    private var currentMode: Mode = .dpi
    private var currentIPInfo = "Mevcut IP: Denetleniyor..."
    
    private var ciadpiProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        
        let savedMode = UserDefaults.standard.string(forKey: "freenetMode") ?? Mode.dpi.rawValue
        currentMode = Mode(rawValue: savedMode) ?? .dpi
        
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
        let script = """
        echo "\(NSUserName()) ALL=(ALL) NOPASSWD: \(wgQuickPath), \(networksetupPath)" > /tmp/freenet_sudoers
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
    
    private func startDPI() {
        let ciadpiPath = Bundle.main.bundlePath + "/Contents/Resources/bin/ciadpi"
        let chmodTask = Process()
        chmodTask.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodTask.arguments = ["+x", ciadpiPath]
        try? chmodTask.run()
        chmodTask.waitUntilExit()
        
        ciadpiProcess = Process()
        ciadpiProcess?.executableURL = URL(fileURLWithPath: ciadpiPath)
        // Use optimal bypass arguments
        ciadpiProcess?.arguments = ["-d", "1", "-p", "1080"]
        try? ciadpiProcess?.run()
        
        let primaryInterfaces = ["Wi-Fi", "Ethernet"]
        for interface in primaryInterfaces {
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxy", interface, "127.0.0.1", "1080"])
            _ = runSudoCommand(networksetupPath, args: ["-setsocksfirewallproxystate", interface, "on"])
        }
    }
    
    private func stopDPI() {
        ciadpiProcess?.terminate()
        ciadpiProcess = nil
        
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
    
    private func startWARP() {
        let configSrc = NSString(string: "~/.config/wireguard/wgcf.conf").expandingTildeInPath
        let configDst = "/etc/wireguard/wgcf.conf"
        
        let cpCmd = "mkdir -p /etc/wireguard && cp '\(configSrc)' '\(configDst)' && chmod 600 '\(configDst)'"
        let fullCmd = "\(cpCmd) && \(wgQuickPath) up \(tunnelName)"
        
        let escaped = fullCmd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin && do shell script \"\(escaped)\" with administrator privileges"
        
        // wg-quick up requires evaluating full command chain, sudoers helps only if we adapt it.
        // To utilize passwordless sudo for WARP, we can just run sudo wg-quick up wgcf
        // Wait, copying the config requires sudo too if /etc/wireguard doesn't exist.
        // Let's assume the config is already copied or we just use AppleScript for WARP setup
        // But to keep it passwordless, we must run `sudo wg-quick up wgcf`.
        if isSudoersInstalled() {
            // Assume config is in /etc/wireguard/wgcf.conf already (we can copy it manually once if needed)
            // Or just try wg-quick up directly
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
