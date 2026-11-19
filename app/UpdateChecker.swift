import Foundation
import AppKit

/// Checks GitHub for a newer freenet version and performs SHA-256 verified in-app self-update.
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let repoOwner = "Baro007"
    static let repoName = "freenet"
    static let versionURL = URL(string: "https://raw.githubusercontent.com/Baro007/freenet/main/VERSION")!
    static let releasesURL = URL(string: "https://api.github.com/repos/Baro007/freenet/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/Baro007/freenet/releases")!
    static let repoPage = URL(string: "https://github.com/Baro007/freenet")!

    struct UpdatePackage: Equatable {
        let current: String
        let latest: String
        let notes: String?
        let pageURL: URL
        let downloadURL: URL?
        let expectedSHA256: String?
        let checksumURL: URL?

        /// True only when both an allowlisted HTTPS zip URL and a SHA-256 source exist.
        var canAutoInstall: Bool {
            downloadURL != nil && (expectedSHA256 != nil || checksumURL != nil)
        }
    }

    enum Status: Equatable {
        case checking
        case upToDate(current: String)
        case updateAvailable(UpdatePackage)
        case installing(String)
        case failed(String)
    }

    private let session: URLSession
    private var isInstallingUpdate = false

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: cfg)
    }

    /// Async check; completion always on main queue.
    func check(completion: @escaping (Status) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = self.checkSync()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Blocking check for tests / scripts.
    /// `currentVersionOverride` allows testing update detection against live releases.
    func checkSync(currentVersionOverride: String? = nil) -> Status {
        let current = currentVersionOverride ?? AppVersion.shortVersion

        // 1) Prefer GitHub Releases API (provides verified .zip + .sha256 / digest for auto-install)
        let release = fetchLatestRelease()
        let releaseVer = release?.tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        // 2) Also read VERSION manifest on main (fast fallback / override)
        let manifest = fetchVERSIONManifest()

        if let rel = release, let rv = releaseVer, AppVersion.isRemoteNewer(rv, than: current) {
            // If VERSION is even newer than latest release, prefer VERSION number while keeping page link
            if let m = manifest, AppVersion.isRemoteNewer(m.version, than: rv) {
                let dl = m.url.flatMap(URL.init(string:)).flatMap { UpdateSecurity.isAllowedDownloadURL($0) ? $0 : nil }
                return .updateAvailable(UpdatePackage(
                    current: current,
                    latest: m.version,
                    notes: m.notes,
                    pageURL: rel.htmlURL,
                    downloadURL: dl,
                    expectedSHA256: m.sha256,
                    checksumURL: nil
                ))
            }
            return .updateAvailable(UpdatePackage(
                current: current,
                latest: rv,
                notes: rel.body,
                pageURL: rel.htmlURL,
                downloadURL: rel.zipDownloadURL,
                expectedSHA256: rel.digestSHA256,
                checksumURL: rel.checksumURL
            ))
        }

        if let m = manifest {
            if AppVersion.isRemoteNewer(m.version, than: current) {
                let page = m.url.flatMap(URL.init(string:)) ?? Self.releasesPage
                let dl = m.url.flatMap(URL.init(string:)).flatMap {
                    ($0.path.lowercased().hasSuffix(".zip") && UpdateSecurity.isAllowedDownloadURL($0)) ? $0 : nil
                }
                return .updateAvailable(UpdatePackage(
                    current: current,
                    latest: m.version,
                    notes: m.notes,
                    pageURL: page,
                    downloadURL: dl,
                    expectedSHA256: m.sha256,
                    checksumURL: nil
                ))
            }
            return .upToDate(current: current)
        }

        if release != nil {
            return .upToDate(current: current)
        }

        return .failed("Güncelleme bilgisi alınamadı (ağ veya GitHub).")
    }

    // MARK: - Verified Staging & Atomic Self-Update

    struct StagedUpdate {
        let stagingDir: String
        let extractedAppPath: String
        let verifiedSHA256: String
    }

    enum UpdateError: LocalizedError {
        case untrustedURL
        case missingChecksum
        case downloadFailed(String)
        case checksumMismatch(expected: String, actual: String)
        case extractFailed(String)
        case invalidBundle(String)
        case applyFailed(String)

        var errorDescription: String? {
            switch self {
            case .untrustedURL:
                return "Güvenlik: Güncelleme adresi izin verilen GitHub kaynakları dışında."
            case .missingChecksum:
                return "Güvenlik: Bu sürüm için SHA-256 doğrulama özeti bulunamadı. Otomatik kurulum durduruldu."
            case .downloadFailed(let msg):
                return "Güncelleme indirilemedi: \(msg)"
            case .checksumMismatch(let exp, let act):
                return "SHA-256 uyuşmazlığı! Beklenen \(exp.prefix(12))…, alınan \(act.prefix(12))…. Kurulum güvenlik nedeniyle iptal edildi."
            case .extractFailed(let msg):
                return "Arşiv açılamadı: \(msg)"
            case .invalidBundle(let msg):
                return "İndirilen uygulama paketi geçersiz: \(msg)"
            case .applyFailed(let msg):
                return "Güncelleme uygulanamadı: \(msg)"
            }
        }
    }

    /// Downloads, SHA-256 verifies, extracts via `ditto`, and validates inner binary checksums.
    /// Safe to run standalone in dry-run tests without replacing the installed app.
    func downloadAndVerifyStage(
        package: UpdatePackage,
        progress: ((String) -> Void)? = nil
    ) throws -> StagedUpdate {
        guard let dlURL = package.downloadURL, UpdateSecurity.isAllowedDownloadURL(dlURL) else {
            throw UpdateError.untrustedURL
        }

        progress?("SHA-256 özeti alınıyor…")
        let expectedHash: String
        if let directHash = package.expectedSHA256, let parsed = UpdateSecurity.parseSHA256Text(directHash) {
            expectedHash = parsed
        } else if let sumURL = package.checksumURL {
            guard UpdateSecurity.isAllowedDownloadURL(sumURL) else {
                throw UpdateError.untrustedURL
            }
            guard let text = fetchTextSync(url: sumURL),
                  let parsed = UpdateSecurity.parseSHA256Text(text) else {
                throw UpdateError.missingChecksum
            }
            expectedHash = parsed
        } else {
            throw UpdateError.missingChecksum
        }

        let stagingDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("freenet-update-\(UUID().uuidString)")
        let zipPath = (stagingDir as NSString).appendingPathComponent("freenet.zip")
        let extractDir = (stagingDir as NSString).appendingPathComponent("extracted")
        try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)

        do {
            progress?("v\(package.latest) indiriliyor…")
            try downloadFileSync(from: dlURL, to: zipPath)

            progress?("SHA-256 doğrulanıyor…")
            let actualHash = try ChecksumVerifier.sha256Hex(ofFileAt: zipPath)
            guard actualHash == expectedHash else {
                throw UpdateError.checksumMismatch(expected: expectedHash, actual: actualHash)
            }

            progress?("Paket açılıyor…")
            let ditto = ProcessRunner.captureOutput("/usr/bin/ditto", args: ["-x", "-k", zipPath, extractDir])
            guard ditto.status == 0 else {
                throw UpdateError.extractFailed(ditto.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let appPath = try locateExtractedApp(in: extractDir)
            try validateExtractedBundle(at: appPath)

            return StagedUpdate(
                stagingDir: stagingDir,
                extractedAppPath: appPath,
                verifiedSHA256: actualHash
            )
        } catch {
            try? FileManager.default.removeItem(atPath: stagingDir)
            throw error
        }
    }

    /// Full automated update: download → SHA-256 verify → stop engine → atomic swap → relaunch.
    func performAutoUpdate(
        package: UpdatePackage,
        onStatus: @escaping (Status) -> Void
    ) {
        guard !isInstallingUpdate else { return }
        isInstallingUpdate = true
        DispatchQueue.main.async { onStatus(.installing("Güncelleme hazırlanıyor…")) }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let staged = try self.downloadAndVerifyStage(package: package) { msg in
                    DispatchQueue.main.async { onStatus(.installing(msg)) }
                }

                DispatchQueue.main.async { onStatus(.installing("Kuruluyor ve yeniden başlatılıyor…")) }
                let wasConnected = EngineManager.shared.isConnected || ProxyService.shared.isSOCKSEnabled()
                if wasConnected {
                    EngineManager.shared.stop()
                }

                let targetApp = self.resolveInstallTargetPath()
                try self.spawnAtomicSwapAndRelaunch(
                    stagedAppPath: staged.extractedAppPath,
                    stagingDir: staged.stagingDir,
                    targetAppPath: targetApp,
                    reconnectAfterLaunch: wasConnected
                )

                LogManager.shared.appendLog(
                    "✅ v\(package.latest) doğrulandı (SHA-256 \(staged.verifiedSHA256.prefix(12))…) — yeniden başlatılıyor…"
                )
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            } catch {
                self.isInstallingUpdate = false
                let msg = error.localizedDescription
                LogManager.shared.appendLog("❌ Otomatik güncelleme başarısız: \(msg)")
                DispatchQueue.main.async {
                    onStatus(.failed(msg))
                    self.presentFailureAlert(message: msg, fallbackURL: package.pageURL)
                }
            }
        }
    }

    // MARK: - Interactive Alerts

    /// Show native alert for interactive menu/panel action.
    func presentAlert(for status: Status, onStatusChange: ((Status) -> Void)? = nil) {
        let alert = NSAlert()
        switch status {
        case .checking, .installing:
            return
        case .upToDate(let current):
            alert.messageText = "Güncelsiniz"
            alert.informativeText = "Freenet \(AppVersion.display) (kurulu: \(current)) en son sürüm."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Tamam")
            alert.runModal()
        case .updateAvailable(let pkg):
            alert.messageText = "Yeni sürüm var: v\(pkg.latest)"
            var body = "Kurulu: v\(pkg.current)\nYeni: v\(pkg.latest)"
            if pkg.canAutoInstall {
                body += "\n\nOtomatik güncelleme paketi GitHub'dan indirir, SHA-256 ile doğrular, kurar ve uygulamayı yeniden başlatır."
            }
            if let notes = pkg.notes, !notes.isEmpty {
                let short = notes.prefix(400)
                body += "\n\n\(short)"
            }
            alert.informativeText = body
            alert.alertStyle = .informational
            if pkg.canAutoInstall {
                alert.addButton(withTitle: "Şimdi Güncelle (Otomatik)")
                alert.addButton(withTitle: "GitHub’da Gör")
                alert.addButton(withTitle: "Sonra")
                let resp = alert.runModal()
                if resp == .alertFirstButtonReturn {
                    performAutoUpdate(package: pkg) { st in
                        onStatusChange?(st)
                    }
                } else if resp == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(pkg.pageURL)
                }
            } else {
                alert.addButton(withTitle: "İndir (GitHub)")
                alert.addButton(withTitle: "Sonra")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(pkg.pageURL)
                }
            }
        case .failed(let msg):
            presentFailureAlert(message: msg, fallbackURL: Self.repoPage)
        }
    }

    private func presentFailureAlert(message: String, fallbackURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Güncelleme kontrolü"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Tamam")
        alert.addButton(withTitle: "GitHub’ı Aç")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    // MARK: - Network & Bundle Helpers

    private func fetchVERSIONManifest() -> AppVersion.VersionManifest? {
        guard let text = fetchTextSync(url: Self.versionURL) else { return nil }
        return AppVersion.parseVersionManifest(text)
    }

    private func fetchLatestRelease() -> UpdateReleaseInfo? {
        var req = URLRequest(url: Self.releasesURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 8
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("freenet-macos/\(AppVersion.shortVersion)", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var data: Data?
        var status = 0
        session.dataTask(with: req) { d, resp, _ in
            data = d
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        guard status == 200, let data = data else { return nil }
        return UpdateReleaseParser.parseLatestRelease(data: data, fallbackPageURL: Self.releasesPage)
    }

    private func fetchTextSync(url: URL) -> String? {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10
        req.setValue("freenet-macos/\(AppVersion.shortVersion)", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var out: String?
        session.dataTask(with: req) { d, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let d = d {
                if let finalURL = http.url, !UpdateSecurity.isAllowedDownloadURL(finalURL) {
                    out = nil
                } else {
                    out = String(data: d, encoding: .utf8)
                }
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 12)
        return out
    }

    private func downloadFileSync(from url: URL, to destinationPath: String) throws {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 90
        req.setValue("freenet-macos/\(AppVersion.shortVersion)", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var caughtError: Error?

        session.downloadTask(with: req) { tmpURL, resp, err in
            defer { sem.signal() }
            if let err = err {
                caughtError = UpdateError.downloadFailed(err.localizedDescription)
                return
            }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                caughtError = UpdateError.downloadFailed("HTTP \(code)")
                return
            }
            if let finalURL = http.url, !UpdateSecurity.isAllowedDownloadURL(finalURL) {
                caughtError = UpdateError.untrustedURL
                return
            }
            guard let tmpURL = tmpURL else {
                caughtError = UpdateError.downloadFailed("Geçici dosya oluşturulamadı")
                return
            }
            do {
                let destURL = URL(fileURLWithPath: destinationPath)
                if FileManager.default.fileExists(atPath: destinationPath) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tmpURL, to: destURL)
            } catch {
                caughtError = UpdateError.downloadFailed(error.localizedDescription)
            }
        }.resume()

        if sem.wait(timeout: .now() + 95) == .timedOut {
            throw UpdateError.downloadFailed("İndirme zaman aşımına uğradı")
        }
        if let err = caughtError {
            throw err
        }
    }

    private func locateExtractedApp(in extractDir: String) throws -> String {
        let fm = FileManager.default
        let direct = (extractDir as NSString).appendingPathComponent("freenet.app")
        if fm.fileExists(atPath: direct) { return direct }
        if let entries = try? fm.contentsOfDirectory(atPath: extractDir) {
            for e in entries where e.hasSuffix(".app") {
                return (extractDir as NSString).appendingPathComponent(e)
            }
        }
        throw UpdateError.invalidBundle("Arşiv içinde freenet.app bulunamadı")
    }

    private func validateExtractedBundle(at appPath: String) throws {
        let fm = FileManager.default
        let execPath = (appPath as NSString).appendingPathComponent("Contents/MacOS/freenet")
        guard fm.isExecutableFile(atPath: execPath) else {
            throw UpdateError.invalidBundle("Contents/MacOS/freenet çalıştırılabilir değil")
        }
        let binDir = (appPath as NSString).appendingPathComponent("Contents/Resources/bin")
        let sumPath = (binDir as NSString).appendingPathComponent("CHECKSUMS.sha256")
        if fm.fileExists(atPath: sumPath) {
            for name in ["ciadpi", "sing-box"] {
                let binPath = (binDir as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: binPath) {
                    let check = ChecksumVerifier.assertSafeToRun(binaryPath: binPath, checksumFilePath: sumPath)
                    if !check.ok {
                        throw UpdateError.invalidBundle(check.message ?? "\(name) checksum hatası")
                    }
                }
            }
        }
    }

    private func resolveInstallTargetPath() -> String {
        let current = Bundle.main.bundlePath
        if current.hasSuffix(".app") {
            let parent = (current as NSString).deletingLastPathComponent
            if FileManager.default.isWritableFile(atPath: parent) {
                return current
            }
        }
        return "/Applications/freenet.app"
    }

    private func spawnAtomicSwapAndRelaunch(
        stagedAppPath: String,
        stagingDir: String,
        targetAppPath: String,
        reconnectAfterLaunch: Bool
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let backupPath = targetAppPath + ".update_backup"
        let scriptPath = (stagingDir as NSString).appendingPathComponent("apply_update.sh")
        let openCmd = reconnectAfterLaunch
            ? "/usr/bin/open -a \(shellQuote(targetAppPath)) --args --connect"
            : "/usr/bin/open -a \(shellQuote(targetAppPath))"

        let script = """
        #!/bin/sh
        TARGET=\(shellQuote(targetAppPath))
        BACKUP=\(shellQuote(backupPath))
        STAGED=\(shellQuote(stagedAppPath))
        STAGING_DIR=\(shellQuote(stagingDir))
        PID=\(pid)

        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 40 ]; do
          sleep 0.2
          i=$((i + 1))
        done

        rm -rf "$BACKUP"
        if [ -e "$TARGET" ]; then
          if ! mv "$TARGET" "$BACKUP"; then
            exit 1
          fi
        fi

        if ! mv "$STAGED" "$TARGET"; then
          if [ -e "$BACKUP" ]; then
            mv "$BACKUP" "$TARGET"
          fi
          exit 1
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        rm -rf "$BACKUP" "$STAGING_DIR"
        \(openCmd)
        """

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        _ = ProcessRunner.runSync("/bin/chmod", args: ["700", scriptPath])

        let parentDir = (targetAppPath as NSString).deletingLastPathComponent
        if FileManager.default.isWritableFile(atPath: parentDir) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [scriptPath]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try task.run()
        } else {
            // Rare fallback if installed in a root-only directory
            let cmd = "/bin/sh \(shellQuote(scriptPath)) >/dev/null 2>&1 &"
            let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            var err: NSDictionary?
            NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
                .executeAndReturnError(&err)
            if err != nil {
                throw UpdateError.applyFailed("Yönetici izni alınamadı.")
            }
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
