import Foundation
@testable import RoadCore

/// An in-memory shared pool, so everything above `PooledReportStore` is testable with no network,
/// no iCloud account and no entitlement.
///
/// Same shape as `MemoryCache` for `FragmentCache` and `FixtureTransport` for `Transport`:
/// the real implementation is the only file that touches the framework, and this is what the
/// tests actually run against.
actor MemoryPool: PooledReportStore {
    private(set) var published: [UUID: PooledReport] = [:]
    private(set) var flags: [UUID: Int] = [:]
    /// Thrown by the next call, so failure handling can be driven deterministically — the same
    /// trick `FixtureTransport.Response.status` uses to test a source that 500s.
    var failNext: PoolFailure?
    var contributes = true

    init(contributes: Bool = true) { self.contributes = contributes }

    func setFailNext(_ failure: PoolFailure?) { failNext = failure }

    private func checkFailure() throws {
        if let failNext { self.failNext = nil; throw failNext }
    }

    func reports(in cells: [PoolCell]) async throws -> [PooledReport] {
        try checkFailure()
        let wanted = Set(cells.map(\.identifier))
        return published.values.filter { wanted.contains($0.cell.identifier) }
    }

    func flagCounts(in cells: [PoolCell]) async throws -> [UUID: Int] {
        try checkFailure()
        return flags
    }

    func publish(_ report: PooledReport) async throws {
        try checkFailure()
        published[report.id] = report
    }

    func retract(id: UUID) async throws {
        try checkFailure()
        published[id] = nil
    }

    func flag(id: UUID) async throws {
        try checkFailure()
        flags[id, default: 0] += 1
    }

    func canContribute() async -> Bool { contributes }
}
