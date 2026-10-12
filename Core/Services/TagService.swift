import Foundation

@MainActor
final class TagService: ObservableObject {
    @Published private(set) var tags: [Tag] = []
    
    private let repository: TagRepository
    private let notificationCenter = NotificationCenter.default
    private var observationTask: Task<Void, Never>?
    private var connectionObservers: [NSObjectProtocol] = []
    
    init(repository: TagRepository? = nil) {
        self.repository = repository ?? TagRepository()
        setupConnectionMonitoring()
    }
    
    deinit {
        observationTask?.cancel()
        connectionObservers.forEach(notificationCenter.removeObserver)
        connectionObservers.removeAll()
    }
    
    // MARK: - Observation
    
    private func setupConnectionMonitoring() {
        let connectObserver = notificationCenter.addObserver(
            forName: .grdbDatabaseDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartObserving()
        }
        let disconnectObserver = notificationCenter.addObserver(
            forName: .grdbDatabaseDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopObserving()
        }
        connectionObservers.append(contentsOf: [connectObserver, disconnectObserver])
        
        Task { [weak self] in
            await self?.startObservationIfConnected()
        }
    }
    
    private func startObservationIfConnected() async {
        guard GRDBDatabaseManager.shared.isConnected else {
            LogManager.shared.warning("⚠️ TagService: Waiting for database connection before observing tags")
            return
        }
        startObserving()
    }
    
    private func restartObserving() {
        stopObserving()
        startObserving()
    }
    
    private func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        tags = []
    }
    
    private func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task {
            do {
                for try await items in repository.observeAll() {
                    self.tags = items
                }
            } catch {
                LogManager.shared.error("❌ Tag observation failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Queries
    
    func allTags() -> [Tag] {
        tags
    }
    
    func tag(uuid: UUID) -> Tag? {
        tags.first { $0.id == uuid }
    }
    
    func ensureTag(name: String, colorHex: String? = nil) async throws -> Tag {
        try await repository.findOrCreate(name: name, colorHex: colorHex)
    }
    
    func update(tag: Tag) async throws {
        try await repository.update(tag)
    }
    
    func delete(uuid: UUID) async throws {
        try await repository.delete(uuid: uuid)
    }
    
    // MARK: - Linking helpers
    
    func assign(tagUUID: UUID, toContact contactID: Int64) async throws {
        try await repository.link(tagUUID: tagUUID, toContact: contactID)
    }
    
    func remove(tagUUID: UUID, fromContact contactID: Int64) async throws {
        try await repository.unlink(tagUUID: tagUUID, fromContact: contactID)
    }
    
    func assign(tagUUID: UUID, toGroup groupUUID: UUID) async throws {
        try await repository.link(tagUUID: tagUUID, toGroup: groupUUID)
    }
    
    func remove(tagUUID: UUID, fromGroup groupUUID: UUID) async throws {
        try await repository.unlink(tagUUID: tagUUID, fromGroup: groupUUID)
    }
}

