import Foundation

protocol Engine: AnyObject {
    var id: EngineID { get }
    var displayName: String { get }
    var privacyLevel: PrivacyLevel { get }
    var isRunning: Bool { get }
    var socksProxy: (host: String, port: Int)? { get }

    func start() throws
    func stop()
}

extension Engine {
    var socksProxy: (host: String, port: Int)? { nil }
}
