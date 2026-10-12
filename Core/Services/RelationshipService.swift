import Foundation

@MainActor
final class RelationshipService: ObservableObject {
    @Published private(set) var relationships: [Relationship] = []
    
    private let repository: RelationshipRepository
    private let notificationCenter = NotificationCenter.default
    private var observationTask: Task<Void, Never>?
    private var connectionObservers: [NSObjectProtocol] = []
    
    init(repository: RelationshipRepository? = nil) {
        self.repository = repository ?? RelationshipRepository()
        setupConnectionMonitoring()
    }
    
    deinit {
        observationTask?.cancel()
        connectionObservers.forEach(notificationCenter.removeObserver)
        connectionObservers.removeAll()
    }
    
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
            LogManager.shared.warning("⚠️ RelationshipService: Waiting for database connection before observing relationships")
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
        relationships = []
    }
    
    private func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task {
            do {
                for try await items in repository.observeAll() {
                    self.relationships = items
                }
            } catch {
                LogManager.shared.error("❌ Relationship observation failed: \(error.localizedDescription)")
            }
        }
    }
    
    func allRelationships() -> [Relationship] {
        relationships
    }
    
    func relationship(uuid: UUID) -> Relationship? {
        relationships.first { $0.id == uuid }
    }
    
    func ensureRelationship(name: String, colorHex: String? = nil) async throws -> Relationship {
        try await repository.findOrCreate(name: name, colorHex: colorHex)
    }
    
    func update(relationship: Relationship) async throws {
        try await repository.update(relationship)
    }
    
    func delete(uuid: UUID) async throws {
        try await repository.delete(uuid: uuid)
    }
    
    func assign(relationshipUUID: UUID, toContact contactID: Int64) async throws {
        try await repository.link(relationshipUUID: relationshipUUID, toContact: contactID)
    }
    
    func remove(relationshipUUID: UUID, fromContact contactID: Int64) async throws {
        try await repository.unlink(relationshipUUID: relationshipUUID, fromContact: contactID)
    }
    
    func assign(relationshipUUID: UUID, toGroup groupUUID: UUID) async throws {
        try await repository.link(relationshipUUID: relationshipUUID, toGroup: groupUUID)
    }
    
    func remove(relationshipUUID: UUID, fromGroup groupUUID: UUID) async throws {
        try await repository.unlink(relationshipUUID: relationshipUUID, fromGroup: groupUUID)
    }
}

