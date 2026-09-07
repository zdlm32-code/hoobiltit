import Foundation
import RoadCore

/// Serves recorded responses from `Fixtures/`, keyed by a distinguishing part of the request
/// path. Layer ids alone are ambiguous — RIT, ATIS and ProjectStatus all publish a layer `1`
/// — so routes are matched on service *and* layer, e.g. `"RoadInformationTool/MapServer/2"`.
///
/// The payloads are real captures from the live services (see `scripts/probe.sh`), so decoding
/// is tested against the agencies' actual quirks rather than a tidied-up invention.
struct FixtureTransport: Transport {
    enum Response {
        case fixture(String)
        case status(Int)
        case body(String)
        /// Successive calls to the same path get successive entries; the last repeats.
        /// The parcel source queries one layer twice — a pin-sized box for containment, then
        /// a wider one for frontage — so path alone cannot tell them apart.
        indirect case sequence([Response])
    }

    /// Path fragment -> response. Longest matching fragment wins.
    let routes: [String: Response]

    /// Records every URL requested so tests can assert on how queries are built.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private var hits: [String: Int] = [:]
        func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; urls.append(url) }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
        /// How many times this route has been served, so a sequence can advance.
        func nextIndex(for key: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            let index = hits[key, default: 0]
            hits[key] = index + 1
            return index
        }
    }
    let log = Log()

    init(_ routes: [String: Response]) {
        self.routes = routes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        log.append(url)

        let path = url.path()
        let matched = routes
            .filter { path.contains($0.key) }
            .max { $0.key.count < $1.key.count }
        var match = matched?.value
        if case .sequence(let responses)? = match, let key = matched?.key {
            let index = log.nextIndex(for: key)
            match = responses[min(index, responses.count - 1)]
        }

        switch match {
        case .none:
            // An unmapped layer stands for a service that genuinely has nothing here.
            return (Data(#"{"features":[]}"#.utf8), http(url, 200))
        case .status(let code):
            return (Data(), http(url, code))
        case .body(let raw):
            return (Data(raw.utf8), http(url, 200))
        case .fixture(let name):
            let fixture = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
            return (try Data(contentsOf: fixture), http(url, 200))
        case .sequence:
            return (Data(#"{"features":[]}"#.utf8), http(url, 200))
        }
    }

    private func http(_ url: URL, _ code: Int) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    /// The layer id a request targeted, for assertions about query construction.
    static func layerID(of url: URL) -> Int? {
        let parts = url.pathComponents
        guard let queryIndex = parts.lastIndex(of: "query"), queryIndex > 0 else { return nil }
        return Int(parts[queryIndex - 1])
    }
}

// MARK: - Recorded scenarios

private let rit = "RoadInformationTool/MapServer/"
private let atis = "ATIS_prod_gdb/FeatureServer/"
private let bos = "BOS/Transportation/MapServer/"
private let status = "ProjectStatus/MapServer/"
private let prop = "Property/RightOfWay/MapServer/"
private let nbi = "NTAD_National_Bridge_Inventory/FeatureServer/"
private let funding = "mapped_route_export_July7/FeatureServer/"
private let rci = "RCI_Tracker/FeatureServer/"
private let parcels = "MaricopaDynamicQueryService/MapServer/3"
private let street = "IndividualService/Street/MapServer/"

extension FixtureTransport {
    /// Unincorporated, county-maintained dirt road. Municipality layer is legitimately empty.
    static var loneMountain: FixtureTransport {
        .init([rit + "7": .fixture("rit_municipality_unincorporated"),
               rit + "2": .fixture("rit_maintained_lonemountain"),
               rit + "3": .fixture("rit_subdivision_lonemountain")])
    }

    /// Inside Goodyear: municipality hits, county maintenance is empty — that empty response
    /// is the answer, not a failure.
    static var goodyear: FixtureTransport {
        .init([rit + "7": .fixture("rit_municipality_goodyear"),
               rit + "2": .fixture("rit_maintained_empty_goodyear"),
               rit + "3": .fixture("rit_subdivision_withplat")])
    }

    /// Three candidate segments in the envelope, plus a recorded plat.
    static var sunCity: FixtureTransport {
        .init([rit + "7": .fixture("rit_municipality_unincorporated"),
               rit + "2": .fixture("rit_maintained_suncity"),
               rit + "3": .fixture("rit_subdivision_withplat")])
    }

    /// A pin on I-10 at the Exit 127 interchange: the envelope returns the mainline, its
    /// ramps, and a local mirror of each, so route selection has real work to do.
    static var interstate10: FixtureTransport {
        .init([atis + "1": .fixture("atis_1_i10"),
               atis + "29": .fixture("atis_29_i10"),
               atis + "3": .fixture("atis_3_i10"),
               atis + "2": .fixture("atis_2_i10"),
               atis + "24": .fixture("atis_24_i10")])
    }

    /// A Goodyear street ATIS knows only as a non-ADOT mirror. The source must stay quiet.
    static var goodyearNonADOT: FixtureTransport {
        .init([atis + "1": .fixture("atis_1_goodyear_nonadot")])
    }

    /// McDowell Rd. Project TT0408 appears twice: as a *linear* record 401 m away whose
    /// `OnRoadName` is "78th St ... 01 Mesa", and as a *spot* record sitting on the pin. Only
    /// the spot one belongs to this road.
    static var mcDowellSpotProject: FixtureTransport {
        .init([bos + "770": .fixture("county_770_mcdowell"),
               bos + "760": .fixture("county_760_mcdowell"),
               bos + "790": .fixture("county_790_mcdowell"),
               bos + "780": .fixture("county_780_mcdowell")])
    }

    /// A pin ~206 m off the Deer Valley Road TIP line: inside the corridor radius but
    /// outside the tight one, so the name gate decides whether it counts.
    static var offCorridorProject: FixtureTransport {
        .init([bos + "770": .fixture("county_tip_offcorridor")])
    }

    /// Lone Mountain Rd: one declaration whose `RoadName` matches the segment outright.
    static var loneMountainDeclaration: FixtureTransport {
        .init([prop + "1": .fixture("decl_lonemountain"),
               prop + "0": .fixture("row_lonemountain")])
    }

    /// Williams Dr: three declarations, none named after the street. Only the subdivision
    /// the county already resolved picks the right one.
    static var williamsDeclaration: FixtureTransport {
        .init([prop + "1": .fixture("decl_williams")])
    }

    /// A structure on I-10 that carries the road under the pin.
    static var i10Bridge: FixtureTransport {
        .init([nbi + "0": .fixture("nbi_i10")])
    }

    /// Sun City: two structures within range, carrying Royal Oak Rd and 99th Ave — neither is
    /// the segment under the pin. The gate must refuse both.
    static var sunCityBridgeNoMatch: FixtureTransport {
        .init([nbi + "0": .fixture("nbi_suncity_nomatch")])
    }

    /// Programmed dollars and the exact opening date for the I-10 projects.
    static var i10Funding: FixtureTransport {
        .init([funding + "0": .fixture("funding_i10"),
               rci + "0": .fixture("rci_i10")])
    }

    /// A Goodyear residential street: the county's *maintained* layer knows nothing here, but
    /// the countywide centreline names it.
    static var goodyearStreet: FixtureTransport {
        .init([street + "1": .fixture("street_goodyear_1"),
               street + "2": .fixture("street_goodyear_2"),
               street + "3": .fixture("street_goodyear_3")])
    }

    /// A road pin in the right-of-way: containment finds nothing, frontage finds ten lots.
    static var williamsFrontage: FixtureTransport {
        .init([parcels: .sequence([.fixture("parcels_williams_empty"),
                                   .fixture("parcels_williams_frontage")])])
    }

    /// A pin that falls inside a parcel rather than on the roadway.
    static var goodyearParcel: FixtureTransport {
        .init([parcels: .fixture("parcels_goodyear_contained")])
    }

    /// Williams Dr — a county-maintained arterial carrying TIP project TT0248. The full
    /// pipeline answers here: owner, segment, capital project, and plat.
    static var williamsDrive: FixtureTransport {
        .init([rit + "7": .fixture("rit_municipality_williams"),
               rit + "2": .fixture("rit_maintained_williams"),
               rit + "3": .fixture("rit_subdivision_williams"),
               bos + "770": .fixture("county_tip_williams"),
               bos + "790": .fixture("county_mip_williams"),
               status + "1": .fixture("county_status_tt0248")])
    }
}
