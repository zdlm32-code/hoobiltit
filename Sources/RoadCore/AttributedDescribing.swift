import Foundation

/// Lets UI and diagnostics read a value's provenance without knowing its payload type.
public protocol AttributedDescribing {
    var sourceName: String { get }
    var sourceURL: URL { get }
    var fetchedAt: Date { get }
    var confidence: MatchConfidence { get }
    var isBundled: Bool { get }
}

extension Attributed: AttributedDescribing {
    public var sourceName: String { provenance.sourceName }
    public var sourceURL: URL { provenance.url }
    public var fetchedAt: Date { provenance.fetchedAt }
    public var isBundled: Bool { provenance.isBundled }
}
