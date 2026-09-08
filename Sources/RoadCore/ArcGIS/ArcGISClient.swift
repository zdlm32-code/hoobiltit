import Foundation

/// Injection point for tests. `URLSession` conforms below.
public protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Transport {}

public enum ArcGISError: Error, LocalizedError {
    case badStatus(Int, url: URL)
    case service(code: Int?, message: String)
    case malformedResponse(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code, let url): "HTTP \(code) from \(url.host() ?? url.absoluteString)"
        case .service(let code, let message): "ArcGIS error \(code.map(String.init) ?? "?"): \(message)"
        case .malformedResponse(let underlying): "Unreadable response: \(underlying)"
        }
    }
}

/// A layer on an ArcGIS service, addressed the way the findings doc records it.
public struct ArcGISLayer: Sendable, Hashable {
    public let serviceURL: URL
    public let layerID: Int

    public init(serviceURL: URL, layerID: Int) {
        self.serviceURL = serviceURL
        self.layerID = layerID
    }

    public init?(_ service: String, layer: Int) {
        guard let url = URL(string: service) else { return nil }
        self.init(serviceURL: url, layerID: layer)
    }

    public var queryURL: URL {
        serviceURL.appending(path: "\(layerID)").appending(path: "query")
    }
}

/// Minimal ArcGIS REST query client.
///
/// It deliberately exposes only envelope queries. Point + `distance`/`units` returns zero
/// features with no error on the county's on-prem server (docs/ENDPOINTS.md §4), and the
/// safest way not to reintroduce that bug is to make it unrepresentable.
public struct ArcGISClient: Sendable {
    private let transport: Transport

    public init(transport: Transport = URLSession.shared) {
        self.transport = transport
    }

    /// Builds the request URL for an envelope query, exactly as `scripts/probe.sh` issues it.
    /// Exposed so provenance can cite the precise URL a value came from.
    public func queryURL(
        layer: ArcGISLayer,
        envelope: Envelope,
        outFields: String = "*",
        returnGeometry: Bool = true,
        maxAllowableOffset: Double? = nil
    ) -> URL {
        var components = URLComponents(url: layer.queryURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "geometry", value: envelope.queryValue),
            .init(name: "geometryType", value: "esriGeometryEnvelope"),
            .init(name: "inSR", value: "4326"),
            .init(name: "spatialRel", value: "esriSpatialRelIntersects"),
            .init(name: "outFields", value: outFields),
            .init(name: "returnGeometry", value: returnGeometry ? "true" : "false"),
            .init(name: "outSR", value: "4326"),
            .init(name: "f", value: "json"),
        ]
        // Server-side generalization. Roughly halves a parcel payload for boundaries that are
        // pixel-identical at phone zoom.
        if let maxAllowableOffset {
            components.queryItems?.append(.init(name: "maxAllowableOffset",
                                                value: String(maxAllowableOffset)))
        }
        return components.url!
    }

    /// Attribute query by `where` clause, for joining a related table once a spatial query
    /// has established the key. `value` is escaped and restricted to the characters project
    /// identifiers actually use, so a service-supplied value cannot alter the clause.
    public func query(
        layer: ArcGISLayer,
        field: String,
        equals value: String,
        and qualifier: (field: String, value: String)? = nil,
        outFields: String = "*"
    ) async throws -> (features: ArcGISFeatureSet, url: URL) {
        let escape = { (raw: String) in
            raw.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
        let safe = escape(value)
        guard !safe.isEmpty else { return (ArcGISFeatureSet(features: []), layer.queryURL) }

        // Structured rather than a caller-supplied clause fragment, so a qualifier coming from
        // the remote catalog gets exactly the same escaping as the key and cannot widen the
        // query. TxDOT needs one: its name field holds a street name only on off-system rows.
        var clause = "\(field)='\(safe)'"
        if let qualifier, !escape(qualifier.value).isEmpty {
            clause += " AND \(qualifier.field)='\(escape(qualifier.value))'"
        }

        var components = URLComponents(url: layer.queryURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "where", value: clause),
            .init(name: "outFields", value: outFields),
            .init(name: "returnGeometry", value: "false"),
            .init(name: "f", value: "json"),
        ]
        return try await send(components.url!)
    }

    public func query(
        layer: ArcGISLayer,
        envelope: Envelope,
        outFields: String = "*",
        returnGeometry: Bool = true,
        maxAllowableOffset: Double? = nil
    ) async throws -> (features: ArcGISFeatureSet, url: URL) {
        let url = queryURL(layer: layer, envelope: envelope,
                           outFields: outFields, returnGeometry: returnGeometry,
                           maxAllowableOffset: maxAllowableOffset)
        return try await send(url)
    }

    private func send(_ url: URL) async throws -> (features: ArcGISFeatureSet, url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("RoadApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ArcGISError.badStatus(http.statusCode, url: url)
        }

        // The service answers 200 with an error body, so check for that before decoding.
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(ArcGISErrorPayload.self, from: data) {
            throw ArcGISError.service(code: payload.error.code,
                                      message: payload.error.message ?? "unspecified")
        }
        do {
            return (try decoder.decode(ArcGISFeatureSet.self, from: data), url)
        } catch {
            throw ArcGISError.malformedResponse(underlying: String(describing: error))
        }
    }
}
