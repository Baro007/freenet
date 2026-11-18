import Foundation
import AppKit

/// Checks GitHub for a newer freenet version (VERSION file + releases API).
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let repoOwner = "Baro007"
    static let repoName = "freenet"
    static let versionURL = URL(string: "https://raw.githubusercontent.com/Baro007/freenet/main/VERSION")!
    static let releasesURL = URL(string: "https://api.github.com/repos/Baro007/freenet/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/Baro007/freenet/releases")!
    static let repoPage = URL(string: "https://github.com/Baro007/freenet")!

    enum Status: Equatable {
        case checking
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String, notes: String?, pageURL: URL)
        case failed(String)
    }

    private init() {}

    /// Async check; completion always on main queue.
    func check(completion: @escaping (Status) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = self.checkSync()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Blocking check for tests / scripts.
    func checkSync(session: URLSession = .shared) -> Status {
        let current = AppVersion.shortVersion

        // 1) Prefer VERSION file on main (simple, works without GitHub Releases)
        if let remote = fetchVERSION(session: session) {
            if AppVersion.isRemoteNewer(remote.version, than: current) {
                let page = remote.url.flatMap(URL.init(string:)) ?? Self.releasesPage
                return .updateAvailable(current: current, latest: remote.version, notes: remote.notes, pageURL: page)
            }
            return .upToDate(current: current)
        }

        // 2) Fallback: GitHub Releases latest
        if let release = fetchLatestRelease(session: session) {
            let tag = release.tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if AppVersion.isRemoteNewer(tag, than: current) {
                let page = URL(string: release.htmlURL) ?? Self.releasesPage
                return .updateAvailable(current: current, latest: tag, notes: release.body, pageURL: page)
            }
            return .upToDate(current: current)
        }

        return .failed("Güncelleme bilgisi alınamadı (ağ veya GitHub).")
    }

    private struct RemoteVERSION {
        let version: String
        let notes: String?
        let url: String?
    }

    private func fetchVERSION(session: URLSession) -> RemoteVERSION? {
        var req = URLRequest(url: Self.versionURL)
        req.timeoutInterval = 8
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
        guard status == 200, let data = data, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parseVERSIONFile(text)
    }

    private func parseVERSIONFile(_ text: String) -> RemoteVERSION? {
        guard let p = AppVersion.parseVERSIONFile(text) else { return nil }
        return RemoteVERSION(version: p.version, notes: p.notes, url: p.url)
    }

    private struct ReleaseInfo {
        let tag: String
        let htmlURL: String
        let body: String?
    }

    private func fetchLatestRelease(session: URLSession) -> ReleaseInfo? {
        var req = URLRequest(url: Self.releasesURL)
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
        guard status == 200, let data = data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else {
            return nil
        }
        return ReleaseInfo(
            tag: tag,
            htmlURL: obj["html_url"] as? String ?? Self.releasesPage.absoluteString,
            body: obj["body"] as? String
        )
    }

    /// Show native alert for interactive menu action.
    func presentAlert(for status: Status) {
        let alert = NSAlert()
        switch status {
        case .checking:
            return
        case .upToDate(let current):
            alert.messageText = "Güncelsiniz"
            alert.informativeText = "Freenet \(AppVersion.display) (kurulu: \(current)) en son sürüm."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Tamam")
            alert.runModal()
        case .updateAvailable(let current, let latest, let notes, let pageURL):
            alert.messageText = "Yeni sürüm var: v\(latest)"
            var body = "Kurulu: v\(current)\nYeni: v\(latest)"
            if let notes = notes, !notes.isEmpty {
                let short = notes.prefix(400)
                body += "\n\n\(short)"
            }
            alert.informativeText = body
            alert.alertStyle = .informational
            alert.addButton(withTitle: "İndir")
            alert.addButton(withTitle: "Sonra")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(pageURL)
            }
        case .failed(let msg):
            alert.messageText = "Güncelleme kontrolü"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Tamam")
            alert.addButton(withTitle: "GitHub’ı Aç")
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(Self.repoPage)
            }
        }
    }
}
