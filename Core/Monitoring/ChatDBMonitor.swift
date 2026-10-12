import Foundation

final class ChatDBMonitor {
    static let shared = ChatDBMonitor()

    private var timer: Timer?
    private var lastModification: Date?

    private init() {}

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let chatDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Messages")
            .appendingPathComponent("chat.db")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: chatDB.path),
              let mod = attrs[.modificationDate] as? Date else { return }
        if let last = lastModification, mod <= last { return }
        lastModification = mod
        print("🔔 ChatDBMonitor: Detected chat.db modification at \(mod)")
        Task { @MainActor in
            ImportSyncCoordinator.shared.scheduleIncrementalMessageSync(debounceSeconds: 5)
        }
    }
}
