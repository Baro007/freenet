import Foundation
import Combine

class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logs: [String] = []
    private let maxLines = 100
    
    func appendLog(_ line: String) {
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLine.isEmpty else { return }
        
        DispatchQueue.main.async {
            self.logs.append(cleanLine)
            if self.logs.count > self.maxLines {
                self.logs.removeFirst(self.logs.count - self.maxLines)
            }
        }
    }
    
    func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}
