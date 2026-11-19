import Cocoa
import SwiftUI

// freenet — Intent-based hybrid censorship bypass + optional Tor anonymity
// Visible via Dock + main window (not menubar-only).

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    private var ipTimer: Timer?

    private var isOn = false
    private var isTransitioning = false
    private var isCheckingStatus = false
    private var currentIntent: IntentMode = .fast
    private var fastPreference: FastEnginePreference = .auto
    private var currentIPInfo = "Mevcut IP: Denetleniyor..."

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var aboutWindow: NSWindow?

    private var updateStatusLine = "Güncelleme: kontrol edilmedi"
    private var pendingUpdatePackage: UpdateChecker.UpdatePackage?
    /// Live Tor / connection truth (not just "button ON")
    private var torStatusLine = "Tor: kontrol edilmedi"
    private var torReallyOn = false
    private var directIPLine = "Gerçek IP: —"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let wantsConnect = args.contains("--connect") || args.contains("-c")
        let wantsDisconnect = args.contains("--disconnect") || args.contains("-d")
        let wantsToggle = args.contains("--toggle") || args.contains("-t")

        // Single instance
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "net.freenet.app")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            if wantsConnect {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("net.freenet.connect"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                print("freenet: Bağlanma sinyali gönderildi.")
            } else if wantsDisconnect {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("net.freenet.disconnect"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                print("freenet: Bağlantıyı kesme sinyali gönderildi.")
            } else if wantsToggle {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("net.freenet.toggle"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                print("freenet: Durum değiştirme sinyali gönderildi.")
            } else {
                existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("net.freenet.showMain"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowMain),
            name: Notification.Name("net.freenet.showMain"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleRemoteConnect),
            name: Notification.Name("net.freenet.connect"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleRemoteDisconnect),
            name: Notification.Name("net.freenet.disconnect"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleRemoteToggle),
            name: Notification.Name("net.freenet.toggle"),
            object: nil
        )

        // Classic menubar agent — this is what showed the shield at the start
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        if let idx = args.firstIndex(of: "--intent"), idx + 1 < args.count {
            currentIntent = IntentMode.fromStorage(args[idx + 1])
            UserDefaults.standard.set(currentIntent.rawValue, forKey: "freenetIntent")
        } else {
            currentIntent = IntentMode.fromStorage(UserDefaults.standard.string(forKey: "freenetIntent"))
        }

        fastPreference = FastEnginePreference.fromStorage(
            UserDefaults.standard.string(forKey: FastEnginePreference.storageKey)
        )

        EngineManager.shared.cleanupOrphanedProxy()
        if EngineManager.shared.adoptRunningWarpIfPresent() {
            isOn = true
            currentIntent = .balanced
            UserDefaults.standard.set(currentIntent.rawValue, forKey: "freenetIntent")
        }

        updateIcon()
        rebuildMenu()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        refreshStatus()

        ipTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshConnectionTruth()
        }
        refreshConnectionTruth()

        UpdateChecker.shared.check { [weak self] status in
            self?.applyUpdateStatus(status, presentAlert: false)
        }

        LogManager.shared.appendLog("freenet \(AppVersion.display) — menü çubuğu kalkanı + accessory mode")

        if wantsConnect || UserDefaults.standard.bool(forKey: "freenetAutoConnect") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                if !self.isOn && !self.isTransitioning {
                    LogManager.shared.appendLog("freenet: Otomatik bağlanma tetiklendi...")
                    self.performToggle(forceReconnect: false)
                }
            }
        }
    }

    @objc private func handleRemoteConnect() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isOn && !self.isTransitioning {
                LogManager.shared.appendLog("freenet: Uzaktan BAĞLAN sinyali alındı.")
                self.performToggle(forceReconnect: false)
            }
        }
    }

    @objc private func handleRemoteDisconnect() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isOn && !self.isTransitioning {
                LogManager.shared.appendLog("freenet: Uzaktan KES sinyali alındı.")
                self.performToggle(forceReconnect: false)
            }
        }
    }

    @objc private func handleRemoteToggle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isTransitioning {
                LogManager.shared.appendLog("freenet: Uzaktan TOGGLE sinyali alındı.")
                self.performToggle(forceReconnect: false)
            }
        }
    }

    @objc private func handleShowMain() {
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isOn {
            EngineManager.shared.stop()
        }
    }

    // MARK: - Main window (always visible path)

    @objc func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 610),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "freenet \(AppVersion.display)"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MainPanel")
            mainWindow = window
        }
        refreshMainWindowContent(force: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshMainWindowContent(force: Bool = false) {
        guard let mainWindow = mainWindow else { return }
        if !force && !mainWindow.isVisible { return }
        let eng = EngineManager.shared.activeEngine?.displayName
            ?? (isOn ? "?" : "—")
        let view = MainPanelView(
            version: AppVersion.fullLabel,
            isOn: isOn,
            isTransitioning: isTransitioning,
            intent: currentIntent,
            engineName: eng,
            ipInfo: currentIPInfo,
            torStatus: torStatusLine,
            torReallyOn: torReallyOn,
            directIP: directIPLine,
            updateLine: updateStatusLine,
            onToggle: { [weak self] in self?.toggleTunnel() },
            onSelectIntent: { [weak self] mode in
                guard let self = self, !self.isTransitioning else { return }
                if self.currentIntent == mode { return }
                self.currentIntent = mode
                UserDefaults.standard.set(mode.rawValue, forKey: "freenetIntent")
                if self.isOn {
                    self.performToggle(forceReconnect: true)
                } else {
                    self.rebuildMenu()
                    self.refreshMainWindowContent()
                }
            },
            onOpenDashboard: { [weak self] in self?.showDashboard() },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onCheckUpdates: { [weak self] in self?.checkForUpdates() },
            onInstallSudoers: { [weak self] in self?.installSudoers() },
            onRecheckTor: { [weak self] in self?.refreshConnectionTruth() },
            onQuit: { [weak self] in self?.quitApp() }
        )
        mainWindow.contentView = NSHostingView(rootView: view)
        mainWindow.title = "freenet \(AppVersion.display)" + (isOn ? " · AÇIK" : "")
    }

    // MARK: - Status item (classic shield — same style that worked at first launch)

    private func setupStatusItem() {
        // Remove previous if recreating
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else {
            LogManager.shared.appendLog("❌ statusItem.button nil")
            return
        }
        button.imagePosition = .imageOnly
        button.toolTip = "freenet \(AppVersion.display)"
        // Menu only (assigned in rebuildMenu) — matches original working app
        LogManager.shared.appendLog("Menü çubuğu kalkanı eklendi")
    }

    /// Refresh real IP vs visible (proxied/WARP/Tor) IP truth.
    private func refreshConnectionTruth() {
        let currentlyOn = isOn
        let currentMode = currentIntent
        let activeProxy = EngineManager.shared.activeEngine?.socksProxy
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let direct = ConnectionProbe.checkDirectIP()
            let portOpen = ConnectionProbe.isLocalPortOpen(TorEngine.socksPort)
            let socksOn = ProxyService.shared.isSOCKSEnabled()

            var torLine = "Tor: kapalı"
            var torOK = false
            var apparent = "—"

            if currentlyOn && currentMode == .maxPrivacy {
                if !portOpen {
                    torLine = "Tor: process/port 9050 YOK (yalnızca UI AÇIK olabilir)"
                } else {
                    let check = ConnectionProbe.checkTorSOCKS(port: TorEngine.socksPort)
                    torOK = check.isTor
                    torLine = check.detail
                    if let exit = check.exitIP { apparent = exit }
                }
            } else if currentlyOn && currentMode == .balanced {
                let warp = ConnectionProbe.checkWarpTrace(socksProxy: activeProxy)
                if warp.isWarp {
                    if let wip = warp.ip { apparent = wip }
                    else if let p = activeProxy, let pip = ConnectionProbe.checkProxiedIP(host: p.host, port: p.port) { apparent = pip }
                    else if let d = direct { apparent = d }
                    let colo = warp.colo.map { " (\($0))" } ?? ""
                    torLine = "WARP DOĞRULANDI\(colo) · IP maskeli (anonimlik değil)"
                } else {
                    if let p = activeProxy, let pip = ConnectionProbe.checkProxiedIP(host: p.host, port: p.port) {
                        apparent = pip
                    } else if let d = direct {
                        apparent = d
                    }
                    torLine = "WARP: doğrulama bekleniyor…"
                }
            } else if currentlyOn {
                // Fast mode: IP remains visible (direct ISP speed)
                if let p = activeProxy, let pip = ConnectionProbe.checkProxiedIP(host: p.host, port: p.port) {
                    apparent = pip
                } else if let d = direct {
                    apparent = d
                }
                torLine = "Hızlı: DPI + DoH aktif · IP görünür"
            } else {
                if let d = direct { apparent = d }
                torLine = "Tor: freenet kapalı"
            }

            let directText = direct.map { "Gerçek (proxy’siz) IP: \($0)" } ?? "Gerçek IP: alınamadı"
            let socksText = socksOn ? "Sistem SOCKS: AÇIK" : "Sistem SOCKS: kapalı"

            DispatchQueue.main.async {
                self.torReallyOn = torOK
                self.torStatusLine = torLine
                self.directIPLine = directText
                self.currentIPInfo = "Görünen IP: \(apparent) · \(socksText)"
                if currentlyOn && currentMode == .maxPrivacy {
                    LogManager.shared.appendLog(torOK ? "✅ \(torLine)" : "⚠️ \(torLine)")
                }
                self.rebuildMenu()
                self.refreshMainWindowContent()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        if isTransitioning {
            symbol = "shield.lefthalf.filled.trianglebadge.exclamationmark"
        } else if isOn {
            // Green sense via filled shield when Tor proven or simply on
            symbol = torReallyOn || isOn ? "shield.lefthalf.filled" : "shield.slash"
        } else {
            symbol = "shield.slash"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "freenet")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageOnly
        button.title = ""
        var tip = isOn ? "freenet AÇIK · \(currentIntent.rawValue)" : "freenet kapalı"
        if currentIntent == .maxPrivacy && isOn {
            tip += torReallyOn ? " · Tor DOĞRULANDI" : " · Tor henüz doğrulanmadı"
        }
        button.toolTip = tip
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let verItem = NSMenuItem(title: "freenet \(AppVersion.display)", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        menu.addItem(verItem)

        let openMain = NSMenuItem(title: "Kontrol Paneli…", action: #selector(showMainWindow), keyEquivalent: "m")
        openMain.target = self
        menu.addItem(openMain)

        let hint = NSMenuItem(
            title: "İkon yoksa: Control Center › Menü Çubuğu veya «« taşma",
            action: nil,
            keyEquivalent: ""
        )
        hint.isEnabled = false
        menu.addItem(hint)

        let ipItem = NSMenuItem(title: currentIPInfo, action: nil, keyEquivalent: "")
        ipItem.isEnabled = false
        menu.addItem(ipItem)

        let directItem = NSMenuItem(title: directIPLine, action: nil, keyEquivalent: "")
        directItem.isEnabled = false
        menu.addItem(directItem)

        let torItem = NSMenuItem(title: torStatusLine, action: nil, keyEquivalent: "")
        torItem.isEnabled = false
        menu.addItem(torItem)

        let recheck = NSMenuItem(title: "Tor / IP Doğrula…", action: #selector(manualRecheck), keyEquivalent: "r")
        recheck.target = self
        menu.addItem(recheck)

        if let pkg = pendingUpdatePackage {
            let updItem = NSMenuItem(
                title: pkg.canAutoInstall ? "⬆ v\(pkg.latest) Hazır — Otomatik Güncelle…" : "⬆ Yeni sürüm: v\(pkg.latest)",
                action: #selector(triggerPendingUpdate),
                keyEquivalent: ""
            )
            updItem.target = self
            menu.addItem(updItem)
        } else {
            let updItem = NSMenuItem(title: updateStatusLine, action: nil, keyEquivalent: "")
            updItem.isEnabled = false
            menu.addItem(updItem)
        }
        menu.addItem(NSMenuItem.separator())

        let stateText = isTransitioning ? "Geçiş yapılıyor…" : (isOn ? "● freenet AÇIK" : "○ freenet kapalı")
        let header = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if isOn {
            let engName = EngineManager.shared.activeEngine.map { $0.displayName } ?? "?"
            let info = NSMenuItem(title: "\(currentIntent.rawValue) · \(engName)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            if currentIntent == .maxPrivacy {
                let t = NSMenuItem(
                    title: torReallyOn ? "✅ Tor ağı GERÇEKTEN aktif" : "⚠️ Tor henüz kanıtlanmadı",
                    action: nil,
                    keyEquivalent: ""
                )
                t.isEnabled = false
                menu.addItem(t)
            }
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

        let intentSub = NSMenu()
        for intent in IntentMode.allCases {
            let item = NSMenuItem(
                title: "\(intent.rawValue) — \(intent.detail)",
                action: #selector(selectIntent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = intent.rawValue
            item.state = (currentIntent == intent) ? .on : .off
            intentSub.addItem(item)
        }
        let intentMenu = NSMenuItem(title: "Niyet (Mod)", action: nil, keyEquivalent: "")
        intentMenu.submenu = intentSub
        intentMenu.isEnabled = !isTransitioning
        menu.addItem(intentMenu)

        if !ProxyService.shared.isSudoersInstalled() {
            menu.addItem(NSMenuItem.separator())
            let sudoItem = NSMenuItem(
                title: "Şifresiz Geçişi Aktif Et ⚡️",
                action: #selector(installSudoers),
                keyEquivalent: ""
            )
            sudoItem.target = self
            menu.addItem(sudoItem)
        } else if !ProxyService.shared.hasExtendedProxySudoers() {
            menu.addItem(NSMenuItem.separator())
            let sudoItem = NSMenuItem(
                title: "Tam Proxy Yetkisini Güncelle (HTTP+HTTPS+Bypass) ⚡️",
                action: #selector(installSudoers),
                keyEquivalent: ""
            )
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

        let checkUpd = NSMenuItem(title: "Güncellemeleri Kontrol Et…", action: #selector(checkForUpdates), keyEquivalent: "u")
        checkUpd.target = self
        menu.addItem(checkUpd)

        let about = NSMenuItem(title: "Hakkında…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func checkForUpdates() {
        updateStatusLine = "Güncelleme: kontrol ediliyor…"
        rebuildMenu()
        refreshMainWindowContent()
        UpdateChecker.shared.check { [weak self] status in
            self?.applyUpdateStatus(status, presentAlert: true)
        }
    }

    @objc private func manualRecheck() {
        torStatusLine = "Tor: kontrol ediliyor…"
        rebuildMenu()
        refreshMainWindowContent()
        refreshConnectionTruth()
    }

    @objc private func triggerPendingUpdate() {
        if let pkg = pendingUpdatePackage {
            UpdateChecker.shared.presentAlert(for: .updateAvailable(pkg)) { [weak self] st in
                self?.applyUpdateStatus(st, presentAlert: false)
            }
        } else {
            checkForUpdates()
        }
    }

    private func applyUpdateStatus(_ status: UpdateChecker.Status, presentAlert: Bool) {
        switch status {
        case .checking:
            updateStatusLine = "Güncelleme: kontrol ediliyor…"
        case .upToDate(let current):
            updateStatusLine = "Güncel · v\(current)"
            pendingUpdatePackage = nil
        case .updateAvailable(let pkg):
            updateStatusLine = pkg.canAutoInstall
                ? "⬆ Yeni sürüm: v\(pkg.latest) (otomatik)"
                : "⬆ Yeni sürüm: v\(pkg.latest)"
            pendingUpdatePackage = pkg
        case .installing(let step):
            updateStatusLine = "⏳ \(step)"
        case .failed:
            updateStatusLine = "Güncelleme: kontrol edilemedi"
        }
        rebuildMenu()
        refreshMainWindowContent()
        if presentAlert {
            UpdateChecker.shared.presentAlert(for: status) { [weak self] st in
                self?.applyUpdateStatus(st, presentAlert: false)
            }
        }
    }

    @objc private func selectIntent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let intent = IntentMode(rawValue: raw) else { return }
        guard currentIntent != intent else { return }
        currentIntent = intent
        UserDefaults.standard.set(intent.rawValue, forKey: "freenetIntent")
        if isOn && !isTransitioning {
            performToggle(forceReconnect: true)
        } else {
            rebuildMenu()
            refreshMainWindowContent()
        }
    }

    @objc private func installSudoers() {
        if ProxyService.shared.installSudoers() {
            showInfo(detail: "Şifresiz geçiş başarıyla aktif edildi!")
            rebuildMenu()
        } else {
            showError(detail: "Şifresiz geçiş kurulamadı.")
        }
    }

    @objc private func toggleTunnel() {
        performToggle(forceReconnect: false)
    }

    private func performToggle(forceReconnect: Bool) {
        guard !isTransitioning else { return }
        isTransitioning = true
        updateIcon()
        rebuildMenu()
        refreshMainWindowContent()

        let intent = currentIntent
        let pref = FastEnginePreference.fromStorage(
            UserDefaults.standard.string(forKey: FastEnginePreference.storageKey)
        )
        fastPreference = pref
        
        let currentlyOn = isOn

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if currentlyOn && !forceReconnect {
                EngineManager.shared.stop()
                DispatchQueue.main.async {
                    self.isOn = false
                    self.isTransitioning = false
                    self.updateIcon()
                    self.rebuildMenu()
                    self.refreshMainWindowContent()
                    self.refreshConnectionTruth()
                }
            } else {
                do {
                    try EngineManager.shared.start(intent: intent, fastPreference: pref)
                    DispatchQueue.main.async {
                        self.isOn = EngineManager.shared.isConnected || ProxyService.shared.isSOCKSEnabled()
                        self.isTransitioning = false
                        if !self.isOn {
                            self.showError(detail: EngineManager.shared.lastError ?? "Bağlantı kurulamadı")
                        } else {
                            let eng = EngineManager.shared.activeEngine?.displayName ?? "?"
                            LogManager.shared.appendLog("✅ Bağlandı: \(intent.rawValue) / \(eng)")
                        }
                        self.updateIcon()
                        self.rebuildMenu()
                        self.refreshMainWindowContent()
                        self.refreshConnectionTruth()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isOn = false
                        self.isTransitioning = false
                        self.showError(detail: error.localizedDescription)
                        self.updateIcon()
                        self.rebuildMenu()
                        self.refreshMainWindowContent()
                        self.refreshConnectionTruth()
                    }
                }
            }
        }
    }

    private func refreshStatus() {
        guard !isTransitioning, !isCheckingStatus, isOn else { return }
        isCheckingStatus = true
        let intent = currentIntent
        let pref = FastEnginePreference.fromStorage(
            UserDefaults.standard.string(forKey: FastEnginePreference.storageKey)
        )
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let healed = EngineManager.shared.healIfNeeded(
                expectedOn: true,
                intent: intent,
                fastPreference: pref
            )
            let nowOn = EngineManager.shared.isConnected || ProxyService.shared.isSOCKSEnabled()
            DispatchQueue.main.async {
                self.isCheckingStatus = false
                guard !self.isTransitioning else { return }
                if healed || nowOn != self.isOn {
                    self.isOn = nowOn
                    self.updateIcon()
                    self.rebuildMenu()
                    self.refreshMainWindowContent()
                    self.refreshConnectionTruth()
                }
            }
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
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
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Freenet Canlı Dashboard"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.center()
            window.setFrameAutosaveName("DashboardWindow")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DashboardView(
                intentProvider: { [weak self] in self?.currentIntent.rawValue ?? "—" },
                engineProvider: {
                    EngineManager.shared.activeEngine?.displayName
                        ?? (EngineManager.shared.isConnected ? "?" : "—")
                },
                isOnProvider: { [weak self] in self?.isOn ?? false }
            ))
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.center()
            window.title = "Freenet Hakkında"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: AboutView())
            window.isReleasedWhenClosed = false
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        if isOn { EngineManager.shared.stop() }
        NSApp.terminate(nil)
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
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
// Menubar agent (classic) — shield in status bar like the first working build
app.setActivationPolicy(.accessory)
app.run()
