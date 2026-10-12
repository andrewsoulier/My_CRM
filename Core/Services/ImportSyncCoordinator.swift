import Foundation

/// Coordinates contact/message import, enrichment, and UI refresh.
@MainActor
final class ImportSyncCoordinator {
    static let shared = ImportSyncCoordinator()

    private let logger = LogManager.shared
    private var isSyncing = false
    private var pendingSyncTask: Task<Void, Never>?

    private init() {}

    func runStartupImports(useContacts: Bool, useMessages: Bool) async {
        guard !isSyncing else {
            logger.info("⏳ ImportSyncCoordinator: Startup import already in progress")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        async let contactsTask: ContactsImportResult? = {
            guard useContacts else { return nil }
            return await Task.detached(priority: .userInitiated) {
                ContactsImporter().run()
            }.value
        }()

        async let messagesTask: Void = {
            guard useMessages, PermissionManager.shared.hasFullDiskAccess() else {
                if useMessages {
                    logger.warning("⚠️ ImportSyncCoordinator: Skipping message import (Full Disk Access required)")
                }
                return
            }
            await runMessageImportPipeline(reason: "startup")
        }()

        if let result = await contactsTask {
            logger.info("👤 ImportSyncCoordinator: Contacts read=\(result.totalRead) inserted=\(result.totalInserted) updated=\(result.totalUpdated)")
        }

        await messagesTask

        await refreshUIIfConnected()
        NotificationCenter.default.post(name: .importSyncCompleted, object: nil)
    }

    func scheduleIncrementalMessageSync(debounceSeconds: TimeInterval = 5) {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            } catch {
                return
            }
            await runIncrementalMessageSync()
        }
    }

    func runIncrementalMessageSync() async {
        guard !isSyncing else { return }
        guard PermissionManager.shared.hasFullDiskAccess() else { return }

        isSyncing = true
        defer { isSyncing = false }

        await runMessageImportPipeline(reason: "incremental")
        await refreshUIIfConnected()
        NotificationCenter.default.post(name: .importSyncCompleted, object: nil)
    }

    private func runMessageImportPipeline(reason: String) async {
        let stats = await Task.detached(priority: .userInitiated) {
            MessagesImporter().run()
        }.value
        logger.info("💬 ImportSyncCoordinator (\(reason)): importedNew=\(stats.importedNew) totalInChatDB=\(stats.totalMessages)")

        let enrichment = await Task.detached(priority: .utility) {
            ContactMessageEnrichmentService().run()
        }.value
        logger.info("📊 ImportSyncCoordinator (\(reason)): enrichment updated \(enrichment.contactsUpdated) contacts")
    }

    private func refreshUIIfConnected() async {
        if let dataProvider = GlobalCanvasService.shared.getDataProvider(),
           dataProvider.isConnectedToDatabase {
            await dataProvider.refreshUIData()
        }
    }
}
