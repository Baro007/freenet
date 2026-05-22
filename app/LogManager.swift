import Foundation
import Combine

class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logs: [String] = []
    private let maxLines = 100
    
    // Performance optimization buffer and queue
    private var buffer: [String] = []
    private let queue = DispatchQueue(label: "com.freenet.logqueue")
    private var isSchedulePending = false
    
    func appendLog(_ line: String) {
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLine.isEmpty else { return }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.buffer.append(cleanLine)
            
            if !self.isSchedulePending {
                self.isSchedulePending = true
                // Batch and flush logs to UI every 200ms
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.flushBuffer()
                }
            }
        }
    }
    
    private func flushBuffer() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let pendingLogs = self.buffer
            self.buffer.removeAll()
            self.isSchedulePending = false
            
            guard !pendingLogs.isEmpty else { return }
            
            DispatchQueue.main.async {
                var currentLogs = self.logs
                currentLogs.append(contentsOf: pendingLogs)
                
                if currentLogs.count > self.maxLines {
                    currentLogs.removeFirst(currentLogs.count - self.maxLines)
                }
                self.logs = currentLogs
            }
        }
    }
    
    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.buffer.removeAll()
            DispatchQueue.main.async {
                self.logs.removeAll()
            }
        }
    }
}
