import Foundation

final class DPIEngine: Engine {
    let id: EngineID = .dpi
    let displayName = "DPI (ciadpi)"
    let privacyLevel: PrivacyLevel = .none

    private var process: Process?
    private(set) var lastPort: Int = DPIArgsValidator.defaultPort

    var isRunning: Bool { process?.isRunning == true }

    var socksProxy: (host: String, port: Int)? {
        isRunning ? ("127.0.0.1", lastPort) : nil
    }

    func start() throws {
        let path = try BinaryLocator.prepareExecutable("ciadpi")
        let raw = UserDefaults.standard.string(forKey: "dpiArgs") ?? DPIArgsValidator.defaultArgs
        // Auto-upgrade legacy weak default ("-d 1 -p 1080") to hardened multi-strategy localhost default
        let effectiveRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines) == "-d 1 -p 1080"
            ? DPIArgsValidator.defaultArgs
            : raw
        let validated = DPIArgsValidator.validate(effectiveRaw)
        guard validated.isValid else {
            throw EngineError.invalidConfiguration(validated.errorMessage ?? "Invalid DPI args")
        }
        lastPort = validated.port

        // Defense-in-depth: never expose ciadpi on 0.0.0.0 if user omitted -i / --ip
        var launchArgs = validated.arguments
        if !launchArgs.contains("-i") && !launchArgs.contains("--ip") {
            launchArgs = ["-i", "127.0.0.1"] + launchArgs
        }

        if ConnectionProbe.isLocalPortOpen(lastPort) {
            _ = ProcessRunner.runSync("/usr/bin/killall", args: ["-9", "ciadpi"])
            Thread.sleep(forTimeInterval: 0.15)
        }

        let proc = ProcessRunner.create(path, args: launchArgs)
        ProcessRunner.attachLogPipes(to: proc)
        LogManager.shared.appendLog("--- ciadpi başlatılıyor (\(launchArgs.joined(separator: " "))) ---")
        do {
            try proc.run()
        } catch {
            throw EngineError.startFailed(error.localizedDescription)
        }
        process = proc
        let ready = ConnectionProbe.waitForLocalPort(lastPort, timeout: 1.5, step: 0.05)
        if process?.isRunning != true {
            process = nil
            throw EngineError.startFailed("ciadpi process hemen çıktı.")
        }
        if !ready {
            stop()
            throw EngineError.startFailed("ciadpi port \(lastPort) dinlemeye geçemedi.")
        }
        if !ProxyService.shared.enableSOCKS(host: "127.0.0.1", port: lastPort) {
            // Keep process for retry; still fail so user sees password / sudoers need
            stop()
            throw EngineError.startFailed(
                "SOCKS proxy açılamadı (macOS parola veya «Şifresiz Geçişi Aktif Et» gerekli). Port \(lastPort)."
            )
        }
    }

    func stop() {
        let had = process != nil || isRunning
        ProcessRunner.detachLogPipes(from: process)
        process?.terminate()
        process = nil
        if had {
            LogManager.shared.appendLog("--- ciadpi durduruldu ---")
            _ = ProcessRunner.runSync("/usr/bin/killall", args: ["-9", "ciadpi"])
            ProxyService.shared.disableSOCKS()
        }
    }
}
