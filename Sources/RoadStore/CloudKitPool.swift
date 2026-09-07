import Foundation
import CloudKit
import RoadCore

/// The shared pool, in CloudKit's public database.
///
/// **The only file in the project that imports CloudKit.** Everything interesting — the
/// redaction, the rounding, the vocabulary round-trip — lives in `RoadCore/Pool` and is tested on
/// macOS with no network and no account. What is left here is an adapter between
/// `[String: PoolValue]` and `CKRecord`, small enough to have nowhere to hide.
///
/// A plain `actor`, like `ReportStore` and `SwiftDataFragmentCache`. Note for anyone tempted to
/// copy `DriveActivityController`'s non-isolated class with a lock: that pattern exists because
/// `Activity` genuinely is not `Sendable`. `CKRecord`, `CKQuery`, `CKContainer` and `CKDatabase`
/// all are at this deployment floor, so there is no isolation to fight here.
///
/// Deliberately **not** SwiftData's CloudKit mirroring. That forbids `@Attribute(.unique)`, which
/// both `StoredReport.id` and `StoredFragment.key` rely on, so switching it on would force a
/// schema change on the local fragment *cache* as collateral — in a project with no
/// `VersionedSchema` anywhere. The two stores stay strangers: SwiftData owns "what I saw",
/// CloudKit owns "what everyone saw", and the only traffic between them is a one-way publish.
public actor CloudKitPool: PooledReportStore {
    public static let containerIdentifier = "iCloud.com.roadapp.whobuiltthis"
    static let reportType = "PooledReport"
    static let flagType = "PooledFlag"
    /// One page is plenty for a viewport; three is the cap. A map does not need every pin, and
    /// six hundred markers is already past what is useful to look at.
    static let pageSize = 200
    static let maximumPages = 3

    private let containerIdentifier: String
    /// Built on first use, never in `init`. `swift test` runs an unsigned binary on macOS with no
    /// iCloud entitlement, so constructing a container eagerly would fail there — and tests use
    /// `MemoryPool`, so this is never reached.
    private var cached: CKDatabase?

    public init(containerIdentifier: String = CloudKitPool.containerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    private func database() -> CKDatabase {
        if let cached { return cached }
        let database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
        cached = database
        return database
    }

    // MARK: - Reading

    public func reports(in cells: [PoolCell]) async throws -> [PooledReport] {
        guard !cells.isEmpty else { return [] }
        let records = try await fetch(Self.reportType, in: cells)
        // Anything this build cannot read is dropped rather than fatal — a later version will
        // publish vocabulary values this one has never heard of.
        return records.compactMap { record in
            guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
            return PooledReport(fields: Self.values(of: record), id: id)
        }
    }

    public func flagCounts(in cells: [PoolCell]) async throws -> [UUID: Int] {
        guard !cells.isEmpty else { return [:] }
        let records = try await fetch(Self.flagType, in: cells)
        var counts: [UUID: Int] = [:]
        for record in records {
            guard let text = record["reportID"] as? String, let id = UUID(uuidString: text)
            else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    private func fetch(_ type: String, in cells: [PoolCell]) async throws -> [CKRecord] {
        // `IN` over the grid, never `distanceToLocation:fromLocation:` — that predicate's index
        // resolution is documented as no less than 10 km, its radius unit is ambiguous in Apple's
        // own materials, and it would send the user's exact position on every map settle.
        let predicate = NSPredicate(format: "%K IN %@", "cell", cells.map(\.identifier))
        let query = CKQuery(recordType: type, predicate: predicate)

        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        do {
            for page in 0..<Self.maximumPages {
                let (matches, next): ([(CKRecord.ID, Result<CKRecord, any Error>)],
                                      CKQueryOperation.Cursor?)
                if page == 0 {
                    (matches, next) = try await database()
                        .records(matching: query, resultsLimit: Self.pageSize)
                } else if let cursor {
                    (matches, next) = try await database()
                        .records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
                } else {
                    break
                }
                // Per-record failures arrive inside the results rather than being thrown.
                collected += matches.compactMap { try? $0.1.get() }
                cursor = next
                if next == nil { break }
            }
        } catch {
            throw Self.failure(from: error)
        }
        return collected
    }

    // MARK: - Writing

    public func publish(_ report: PooledReport) async throws {
        // The record name is the report's own UUID, which makes publishing idempotent and lets
        // CloudKit's `_creator` role enforce "only you can remove yours" with no identity code.
        let record = CKRecord(recordType: Self.reportType,
                              recordID: CKRecord.ID(recordName: report.id.uuidString))
        Self.apply(report.fields, to: record)
        do {
            _ = try await database().save(record)
        } catch {
            throw Self.failure(from: error)
        }
    }

    public func retract(id: UUID) async throws {
        do {
            _ = try await database().deleteRecord(withID: CKRecord.ID(recordName: id.uuidString))
        } catch let error as CKError where error.code == .unknownItem {
            return   // already gone is the outcome asked for
        } catch {
            throw Self.failure(from: error)
        }
    }

    public func flag(id: UUID) async throws {
        // Deterministic name, so one flag per person per report is structural rather than
        // enforced. `userRecordID` is a private call about yourself; it is never displayed and
        // never leaves this actor.
        let container = CKContainer(identifier: containerIdentifier)
        let me = try await container.userRecordID()
        let name = "flag-\(id.uuidString)-\(abs(me.recordName.hashValue))"
        let record = CKRecord(recordType: Self.flagType,
                              recordID: CKRecord.ID(recordName: name))
        record["reportID"] = id.uuidString as CKRecordValue
        do {
            _ = try await database().save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            return   // already flagged by this person
        } catch {
            throw Self.failure(from: error)
        }
    }

    public func canContribute() async -> Bool {
        let status = try? await CKContainer(identifier: containerIdentifier).accountStatus()
        return status == .available
    }

    // MARK: - Adapter

    static func apply(_ fields: [String: PoolValue], to record: CKRecord) {
        for (key, value) in fields {
            switch value {
            case .text(let text): record[key] = text as CKRecordValue
            case .number(let number): record[key] = number as CKRecordValue
            case .date(let date): record[key] = date as CKRecordValue
            }
        }
    }

    static func values(of record: CKRecord) -> [String: PoolValue] {
        var values: [String: PoolValue] = [:]
        for key in record.allKeys() {
            switch record[key] {
            case let text as String: values[key] = .text(text)
            case let number as Double: values[key] = .number(number)
            case let number as Int64: values[key] = .number(Double(number))
            case let date as Date: values[key] = .date(date)
            default: continue
            }
        }
        return values
    }

    /// CloudKit's errors, translated into the four things the map can actually say.
    static func failure(from error: any Error) -> PoolFailure {
        guard let ck = error as? CKError else { return .unknown(error.localizedDescription) }
        switch ck.code {
        case .networkUnavailable, .networkFailure:
            return .offline
        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
            return .rateLimited(retryAfter: ck.retryAfterSeconds)
        case .notAuthenticated:
            return .notSignedIn
        case .permissionFailure, .quotaExceeded, .badContainer, .badDatabase:
            return .misconfigured(ck.localizedDescription)
        case .unknownItem:
            // On a query this means the record type is absent — the classic symptom of a schema
            // that was never promoted to Production, which is what every TestFlight build talks to.
            return .misconfigured("The shared map is not set up for this build.")
        default:
            return .unknown(ck.localizedDescription)
        }
    }
}
