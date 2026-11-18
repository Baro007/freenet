import Foundation

enum ProcessRunner {
    static func create(_ executable: String, args: [String]) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
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

    @discardableResult
    static func runSync(_ executable: String, args: [String]) -> Int32 {
        let task = create(executable, args: args)
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }

    static func captureOutput(_ executable: String, args: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let task = create(executable, args: args)
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        return (
            task.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    static func attachLogPipes(to process: Process) {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let handler: (FileHandle) -> Void = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty { return }
            if let string = String(data: data, encoding: .utf8) {
                for line in string.components(separatedBy: .newlines) where !line.isEmpty {
                    LogManager.shared.appendLog(line)
                }
            }
        }
        outPipe.fileHandleForReading.readabilityHandler = handler
        errPipe.fileHandleForReading.readabilityHandler = handler
    }

    static func detachLogPipes(from process: Process?) {
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
    }
}
