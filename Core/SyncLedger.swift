import Foundation

public struct SyncConflict: Codable, Identifiable, Sendable {
    public var id: String { remote.key }
    public let remote: SyncRecord
    public let local: SyncRecord
}

public struct SyncLedger: Codable, Sendable {
    public private(set) var cursor: Int64 = 0
    public private(set) var baseline: [String: SyncRecord] = [:]
    public private(set) var pending: SyncRequest?
    public private(set) var conflicts: [SyncConflict] = []
    private var sentLocal: [String: SyncRecord] = [:]
    public init() {}

    public mutating func prepare(local: [SyncRecord]) -> SyncRequest {
        if let pending { return pending }
        let values = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        let blocked = Set(conflicts.map(\.id))
        var changes: [SyncRecord] = []
        for value in local where !blocked.contains(value.key) {
            if let previous = baseline[value.key], value.sameContent(as: previous) { continue }
            var update = value; update.revision = baseline[value.key]?.revision ?? 0
            changes.append(update)
        }
        for previous in baseline.values where !previous.deleted && values[previous.key] == nil && !blocked.contains(previous.key) {
            changes.append(previous.tombstone())
        }
        changes.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .habit }
            return lhs.key < rhs.key
        }
        let batch = Array(changes.prefix(100))
        let request = SyncRequest(cursor: cursor, mutationID: batch.isEmpty ? "" : UUID().uuidString.lowercased(), changes: batch)
        sentLocal = values
        pending = request
        return request
    }

    public mutating func receive(_ response: SyncResponse, local: [SyncRecord]) -> [SyncRecord] {
        let current = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        var updates: [SyncRecord] = []
        let sentKeys = Set(pending?.changes.map(\.key) ?? [])
        let latest = (response.changes + response.applied).reduce(into: [String: SyncRecord]()) { result, record in
            if result[record.key].map({ $0.revision < record.revision }) ?? true { result[record.key] = record }
        }
        for remote in latest.values {
            if let old = baseline[remote.key], old.revision >= remote.revision { continue }
            let before = baseline[remote.key]
            baseline[remote.key] = remote
            let value = current[remote.key]
            let atRequest = sentLocal[remote.key]
            let unchangedDuringRequest = contentEqual(value, atRequest)
            let hadUnsyncedEdit = !contentEqual(atRequest, before?.deleted == false ? before : nil)
            if value?.sameContent(as: remote) == true || (value == nil && remote.deleted) { continue }
            if unchangedDuringRequest && (sentKeys.contains(remote.key) || !hadUnsyncedEdit) {
                updates.removeAll { $0.key == remote.key }
                updates.append(remote)
            } else if !sentKeys.contains(remote.key), hadUnsyncedEdit || !unchangedDuringRequest, let local = value ?? before?.tombstone() {
                conflicts.removeAll { $0.id == remote.key }
                conflicts.append(SyncConflict(remote: remote, local: local))
            }
        }
        cursor = max(cursor, response.cursor)
        pending = nil; sentLocal = [:]
        return updates
    }

    public mutating func reject(conflicts remote: [SyncRecord], local: [SyncRecord]) {
        let values = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        for record in remote {
            baseline[record.key] = record
            if let local = values[record.key] ?? baseline[record.key]?.tombstone(), !local.sameContent(as: record) {
                conflicts.removeAll { $0.id == record.key }
                conflicts.append(SyncConflict(remote: record, local: local))
            }
        }
        pending = nil; sentLocal = [:]
    }

    public mutating func resolve(_ key: String, keepLocal: Bool) -> SyncRecord? {
        guard let conflict = conflicts.first(where: { $0.id == key }) else { return nil }
        conflicts.removeAll { $0.id == key }
        return keepLocal ? nil : conflict.remote
    }

    private func contentEqual(_ lhs: SyncRecord?, _ rhs: SyncRecord?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return lhs.sameContent(as: rhs)
        default: return false
        }
    }
}
