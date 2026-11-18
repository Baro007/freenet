import Foundation
import CryptoKit

/// SHA-256 verification for bundled binaries (Faz 4 lite).
public enum ChecksumVerifier {
    public struct Entry: Equatable {
        public let hash: String
        public let filename: String
    }

    /// Parse `shasum -a 256` style lines: `<hex>  <filename>` or `<hex> *<filename>`
    public static func parseChecksumFile(_ contents: String) -> [Entry] {
        var entries: [Entry] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            let parts = s.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2 else { continue }
            let hash = String(parts[0]).lowercased()
            var name = String(parts[1])
            if name.hasPrefix("*") { name = String(name.dropFirst()) }
            // basename only for matching
            name = (name as NSString).lastPathComponent
            guard hash.count == 64, hash.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else {
                continue
            }
            entries.append(Entry(hash: hash, filename: name))
        }
        return entries
    }

    public static func sha256Hex(ofFileAt path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public enum VerifyStatus: Equatable {
        case noChecksumFile
        case noEntryForFile
        case match
        case mismatch(expected: String, actual: String)
        case readError(String)
    }

    /// Verify a single binary against a checksum file path.
    public static func verify(binaryPath: String, checksumFilePath: String) -> VerifyStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: checksumFilePath) else { return .noChecksumFile }
        guard let contents = try? String(contentsOfFile: checksumFilePath, encoding: .utf8) else {
            return .readError("Cannot read checksum file")
        }
        let name = (binaryPath as NSString).lastPathComponent
        let entries = parseChecksumFile(contents)
        guard let entry = entries.first(where: { $0.filename == name }) else {
            return .noEntryForFile
        }
        do {
            let actual = try sha256Hex(ofFileAt: binaryPath)
            if actual == entry.hash { return .match }
            return .mismatch(expected: entry.hash, actual: actual)
        } catch {
            return .readError(error.localizedDescription)
        }
    }

    /// Returns false only on hard mismatch; missing file/entry is soft-ok for gradual rollout.
    public static func assertSafeToRun(binaryPath: String, checksumFilePath: String) -> (ok: Bool, message: String?) {
        switch verify(binaryPath: binaryPath, checksumFilePath: checksumFilePath) {
        case .match, .noChecksumFile, .noEntryForFile:
            return (true, nil)
        case .mismatch(let expected, let actual):
            return (false, "Checksum mismatch for \((binaryPath as NSString).lastPathComponent): expected \(expected.prefix(12))… got \(actual.prefix(12))…")
        case .readError(let msg):
            return (false, "Checksum read error: \(msg)")
        }
    }
}
