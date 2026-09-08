import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Arizona statewide — ADOT's HPMS tables")
struct ArizonaStatewideTests {
    let tucson = RoadQuery(latitude: 32.2226, longitude: -110.9747)

    private var adot: FixtureTransport {
        FixtureTransport([
            "FeatureServer/6": .fixture("adot_hpms_route_tucson"),
            "FeatureServer/33": .fixture("adot_hpms_33_tucson"),
            "FeatureServer/21": .fixture("adot_hpms_21_tucson"),
            "FeatureServer/0": .fixture("adot_hpms_0_tucson"),
        ])
    }

    private func source(_ transport: FixtureTransport) -> LRSEventSource {
        LRSEventSource(profile: CoverageCatalog.bundled.profile(forState: "04")!,
                       client: ArcGISClient(transport: transport), now: { fixedNow })!
    }

    @Test("A Tucson street is named by the city that owns it")
    func namesTheOwningCity() async throws {
        let fragment = try await source(adot).fetch(tucson)
        // Tucson publishes no street data of its own, and neither do Mesa, Chandler, Gilbert,
        // Scottsdale or Peoria. ADOT names all of them.
        #expect(fragment.owner?.value == .municipality(name: "Tucson", fullName: "Tucson"))
    }

    // MARK: - The ownership vocabulary

    @Test("An owner is read as the body it names, at the level its code gives")
    func ownershipDecoding() {
        #expect(CodeTables.owner(adot: "PHX-Phoenix (4)")
                == .municipality(name: "Phoenix", fullName: "Phoenix"))
        #expect(CodeTables.owner(adot: "MMA-Maricopa County DOT (2)")
                == .county(agency: "Maricopa County DOT"))
        // No trailing code at all on the state's own roads.
        #expect(CodeTables.owner(adot: "DOT-Arizona Department of Transportation")
                == .state(agency: "Arizona Department of Transportation"))
        if case .federal(let agency) = CodeTables.owner(adot: "PNF-Prescott NF (64)") {
            #expect(agency == "Prescott NF")
        } else { Issue.record("code 64 is the Forest Service") }
    }

    @Test("Private and gated roads are read as private, whatever code they carry")
    func privateRoads() {
        // 21,600 segments. ADOT files these under HPMS 80, "Other", which decodes to nothing —
        // so the name has to be trusted over the code here.
        #expect(CodeTables.owner(adot: "PRI-Private (unrestricted to Public) (80)") == .privateOwner)
        // 10,213 more behind a gate.
        #expect(CodeTables.owner(adot: "OAG-Owners Association - Gated (26)") == .privateOwner)
    }

    @Test("An admission of ignorance is not an owner")
    func placeholders() {
        #expect(CodeTables.owner(adot: "TBD-To be determined after 2013 ()") == nil)
        #expect(CodeTables.owner(adot: "UNK-Unknown (yet Fed FC) (80)") == nil)
        // 468 segments platted but never built. Not an owner, and not worth guessing at.
        #expect(CodeTables.owner(adot: "NBY-Not Built Yet - platted roads ()") == nil)
        #expect(CodeTables.owner(adot: nil) == nil)
        #expect(CodeTables.owner(adot: "") == nil)
    }

    // MARK: - Ordering, which is the whole point

    @Test("The statewide table runs behind the county, not beside the state")
    func fallbackOrder() {
        let maricopa = Jurisdiction(stateFIPS: "04", countyFIPS: "04013",
                                    countyName: "Maricopa County", placeName: "Goodyear city")
        let ids = PipelineFactory().pipeline(for: maricopa).sources.map(\.id)
        let atis = ids.firstIndex(of: "adot.atis")
        let mcdot = ids.firstIndex(of: "mcdot.rit")
        let hpms = ids.firstIndex(of: "az.adot")
        // ADOT's hand-written source leads, because a pin on I-10 sits inside Goodyear's
        // limits and the state must claim it before MCDOT infers a municipal owner.
        #expect(atis != nil && mcdot != nil && atis! < mcdot!)
        // The statewide table trails, because it names an owner for *every* road in Arizona
        // and in the state slot it beat MCDOT on Maricopa's own county roads — losing the
        // difference between a road the county accepted and one it maintains as a courtesy.
        #expect(hpms != nil && mcdot! < hpms!)
    }

    @Test("A county with no profile of its own still reaches the statewide table")
    func uncoveredCounty() {
        let pima = Jurisdiction(stateFIPS: "04", countyFIPS: "04019", countyName: "Pima County",
                                placeName: "Tucson city")
        let ids = PipelineFactory().pipeline(for: pima).sources.map(\.id)
        #expect(ids.contains("az.adot"))
        #expect(!ids.contains("mcdot.rit"), "Maricopa's sources are not Pima's")
    }
}
