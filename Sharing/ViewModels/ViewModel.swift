//
//  ViewModel.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import CloudKit
import OSLog

@MainActor
final class ViewModel: ObservableObject {

    // MARK: - Error

    enum ViewModelError: Error {
        case invalidRemoteShare
    }

    // MARK: - State

    enum State {
        case loading
        case loaded(private: [ToDo], shared: [ToDo])
        case error(Error)
    }

    // MARK: - Properties

    /// State directly observable by our view.
    @Published private(set) var state: State = .loading
    /// Use the specified iCloud container ID, which should also be present in the entitlements file.
    lazy var container = CKContainer(identifier: Config.containerIdentifier)
    /// This project uses the user's private database.
    private lazy var database = container.privateCloudDatabase
    private lazy var sharedDatabase = container.sharedCloudDatabase
    /// Sharing requires using a custom record zone.
    let recordZone = CKRecordZone(zoneName: "ToDos")

    // MARK: - Init

    nonisolated init() {}

    /// Initializer to provide explicit state (e.g. for previews).
    init(state: State) {
        self.state = state
    }

    // MARK: - API

    /// Prepares container by creating custom zone if needed.
    func initialize() async throws {
        do {
            try await createZoneIfNeeded(overrride: false)
        } catch {
            state = .error(error)
        }
    }

    /// Fetches toDos from the remote databases and updates local state.
    func refresh() async throws {
        state = .loading
        do {
            let (privateToDos, sharedToDos) = try await fetchPrivateAndSharedToDos()
            state = .loaded(private: privateToDos, shared: sharedToDos)
        } catch {
            state = .error(error)
        }
    }

    func fetchPrivateAndSharedToDos() async throws -> (private: [ToDo], shared: [ToDo]) {
        async let privateToDos = fetchToDos(scope: .private, in: [recordZone])
        async let sharedToDos = fetchSharedToDos()

        return (private: try await privateToDos, shared: try await sharedToDos)
    }
    
    public func markAsChecked(_ toDo: ToDo) async {
        if (toDo.associatedRecord.share?.recordID != nil) {
            await removeShare(recordID: toDo.associatedRecord.share!.recordID)
        }
        await removeToDo(recordID: toDo.recordID)
    }

    func addToDo(name: String) async throws {
        let id = CKRecord.ID(zoneID: recordZone.zoneID)
        let toDoRecord = CKRecord(recordType: "ToDo", recordID: id)
        toDoRecord["name"] = name

        try await database.save(toDoRecord)
    }
    
    func removeToDo(recordID: CKRecord.ID) async {
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [recordID])
        } catch {
            print(error)
        }
    }
    
    func removeShare(recordID: CKRecord.ID) async {
        do {
            _ = try await sharedDatabase.modifyRecords(saving: [], deleting: [recordID])
        } catch {
            print(error)
        }
//         sharedDatabase.delete(withRecordID: recordID) { record, error in
//             guard error == nil else {
//                 print(error ?? "")
//                 return
//             }
//             print("Record deleted successfully")
//         }
    }

    func fetchOrCreateShare(toDo: ToDo) async throws -> (CKShare, CKContainer) {
        guard let existingShare = toDo.associatedRecord.share else {
            let share = CKShare(rootRecord: toDo.associatedRecord)
            share[CKShare.SystemFieldKey.title] = "ToDo: \(toDo.name)"
            _ = try await database.modifyRecords(saving: [toDo.associatedRecord, share], deleting: [])
            return (share, container)
        }

        guard let share = try await database.record(for: existingShare.recordID) as? CKShare else {
            throw ViewModelError.invalidRemoteShare
        }

        return (share, container)
    }

    // MARK: - Private

    /// Fetches toDos for a given set of zones in a given database scope.
    /// - Parameters:
    ///   - scope: Database scope to fetch from.
    ///   - zones: Record zones to fetch toDos from.
    /// - Returns: Combined set of toDos across all given zones.
    private func fetchToDos(
        scope: CKDatabase.Scope,
        in zones: [CKRecordZone]
    ) async throws -> [ToDo] {
        let database = container.database(with: scope)
        var allToDos: [ToDo] = []

        // Inner function retrieving and converting all ToDo records for a single zone.
        @Sendable func toDosInZone(_ zone: CKRecordZone) async throws -> [ToDo] {
            var allToDos: [ToDo] = []

            /// `recordZoneChanges` can return multiple consecutive changesets before completing, so
            /// we use a loop to process multiple results if needed, indicated by the `moreComing` flag.
            var awaitingChanges = true
            /// After each loop, if more changes are coming, they are retrieved by using the `changeToken` property.
            var nextChangeToken: CKServerChangeToken? = nil

            while awaitingChanges {
                let zoneChanges = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: nextChangeToken)
                let toDos = zoneChanges.modificationResultsByID.values
                    .compactMap { try? $0.get().record }
                    .compactMap { ToDo(record: $0) }
                allToDos.append(contentsOf: toDos)

                awaitingChanges = zoneChanges.moreComing
                nextChangeToken = zoneChanges.changeToken
            }

            return allToDos
        }

        // Using this task group, fetch each zone's toDos in parallel.
        try await withThrowingTaskGroup(of: [ToDo].self) { group in
            for zone in zones {
                group.addTask {
                    try await toDosInZone(zone)
                }
            }

            // As each result comes back, append it to a combined array to finally return.
            for try await toDosResult in group {
                allToDos.append(contentsOf: toDosResult)
            }
        }

        return allToDos
    }

    /// Fetches all shared ToDos from all available record zones.
    private func fetchSharedToDos() async throws -> [ToDo] {
        let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
        guard !sharedZones.isEmpty else {
            return []
        }

        return try await fetchToDos(scope: .shared, in: sharedZones)
    }

    /// Creates the custom zone in use if needed.
    private func createZoneIfNeeded(overrride:Bool) async throws {
        // Avoid the operation if this has already been done.
        // TODO: JONATHAN. I had to remove this because it wasn't creating a zone when it was supposed to
        guard !UserDefaults.standard.bool(forKey: "isZoneCreated") else {
            return
        }

        do {
            _ = try await database.modifyRecordZones(saving: [recordZone], deleting: [])
        } catch {
            print("ERROR: Failed to create custom zone: \(error.localizedDescription)")
            throw error
        }

        UserDefaults.standard.setValue(true, forKey: "isZoneCreated")
    }
}
