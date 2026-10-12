import Foundation

struct LogFindings {
    let errors: [String]
    let warnings: [String]
}

final class LogScanService {
    static let shared = LogScanService()
    private init() {}

    private var logFileURL: URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let myCRM = appSupport?.appendingPathComponent("My_CRM").appendingPathComponent("Logs")
        let file = myCRM?.appendingPathComponent("crm_debug.log")
        return file
    }

    func currentLogFileSize() -> UInt64 {
        guard let url = logFileURL,
              let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? NSNumber else { return 0 }
        return size.uint64Value
    }

    func scanSince(offset: UInt64) -> LogFindings {
        guard let url = logFileURL,
              let handle = try? FileHandle(forReadingFrom: url) else { return LogFindings(errors: [], warnings: []) }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
        } catch {}

        let data = (try? handle.readToEnd()) ?? Data()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return LogFindings(errors: [], warnings: [])
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let errors = lines.filter { $0.localizedCaseInsensitiveContains("error") || $0.contains("❌") }
        let warnings = lines.filter { $0.localizedCaseInsensitiveContains("warning") || $0.contains("⚠️") }
        return LogFindings(errors: errors, warnings: warnings)
    }
}




