import Foundation
import Observation
import SwiftData

@MainActor @Observable final class AccountSyncService {
    private(set) var syncing = false
    private(set) var lastSuccess: Date?
    private(set) var message: String?
    private(set) var ledger: SyncLedger
    private let url: URL
    private let api: AccountAPI
    private let context: ModelContext
    private let userID: UUID
    private var active = true

    init(userID: UUID, context: ModelContext, api: AccountAPI) throws {
        self.api = api; self.context = context; self.userID = userID
        url = try AccountStoreLocation().ledgerURL(for: userID)
        if FileManager.default.fileExists(atPath: url.path) {
            ledger = try AccountCoding.decoder().decode(SyncLedger.self, from: Data(contentsOf: url))
        } else { ledger = SyncLedger() }
    }
    func stop() { active = false }
    func synchronize() async {
        guard active, !syncing else { return }
        syncing = true; message = nil
        defer { syncing = false }
        do {
            var hasMore = true
            var rounds = 0
            while active && hasMore && rounds < 50 {
                let request = try inScope {
                    let request = ledger.prepare(local: try AccountRecords.snapshot(in: context))
                    try persist()
                    return request
                }
                do {
                    let response = try await api.synchronize(request, userID: userID)
                    guard active else { return }
                    try inScope {
                        let previous = ledger
                        let updates = ledger.receive(response, local: try AccountRecords.snapshot(in: context))
                        do {
                            try AccountRecords.apply(updates, in: context)
                            try persist()
                        } catch { ledger = previous; throw error }
                    }
                    hasMore = response.hasMore || request.changes.count == 100
                } catch AccountAPIError.conflict(let conflicts) {
                    guard active else { return }
                    try inScope {
                        ledger.reject(conflicts: conflicts, local: try AccountRecords.snapshot(in: context))
                        try persist()
                    }
                    hasMore = true
                }
                rounds += 1
            }
            if active { lastSuccess = Date() }
        } catch {
            if active { message = String(localized: "Sincronizzazione in pausa. I progressi restano sul dispositivo; riproveremo alla prossima connessione.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        }
    }
    func resolve(_ conflict: SyncConflict, keepLocal: Bool) throws {
        guard !syncing else { return }
        try inScope {
            let previous = ledger
            let update = ledger.resolve(conflict.id, keepLocal: keepLocal)
            do {
                if let update { try AccountRecords.apply([update], in: context) }
                try persist()
            } catch { ledger = previous; throw error }
        }
    }
    private func inScope<T>(_ operation: () throws -> T) throws -> T {
        try ScopeRegistry().withScope(expected: StoreScope.account(userID).key) { _ in try operation() }
    }
    private func persist() throws {
        try AccountCoding.encoder().encode(ledger).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
