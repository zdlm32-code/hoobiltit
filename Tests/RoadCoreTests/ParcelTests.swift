import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func parcels(_ transport: FixtureTransport) -> MaricopaParcelSource {
    MaricopaParcelSource(client: ArcGISClient(transport: transport), now: { fixedNow })
}

@Suite("Assessor parcels — the land beside the road")
struct ParcelSourceTests {
    let williams = RoadQuery(latitude: 33.689441, longitude: -112.317668)
    let goodyear = RoadQuery(latitude: 33.4386, longitude: -112.4118)

    @Test("Falls back to frontage when the pin is in the right-of-way")
    func frontageFallback() async throws {
        // A road pin sits between parcels, so containment returns nothing. Without the
        // fallback this source would be silent on exactly the pins the app is built for.
        let fragment = try await parcels(.williamsFrontage).fetch(williams)
        let parcel = try #require(fragment.parcel?.value)

        #expect(parcel.containsPin == false)
        #expect(fragment.parcel?.confidence == .spatial)
        #expect(parcel.apn.contains("-"))
    }

    @Test("Reports a build-year range across the frontage, not one neighbour's year")
    func frontageYearRange() async throws {
        let parcel = try #require(try await parcels(.williamsFrontage).fetch(williams).parcel?.value)
        let range = try #require(parcel.constructionYearRange)

        #expect(range.lowerBound == 2008)
        #expect(range.upperBound == 2009)
        // The county declared this road a public road in May 2009 — the frontage brackets it.
    }

    @Test("Carries the plat identifiers, so the Assessor can corroborate MCDOT")
    func platCrossReference() async throws {
        let parcel = try #require(try await parcels(.williamsFrontage).fetch(williams).parcel?.value)
        #expect(parcel.subdivisionName == "CROSSRIVER UNIT 8")
        #expect(parcel.recorderNumber == "706-34")
    }

    @Test("Says so plainly when the pin really is inside a parcel")
    func containment() async throws {
        let fragment = try await parcels(.goodyearParcel).fetch(goodyear)
        let parcel = try #require(fragment.parcel?.value)

        #expect(parcel.containsPin)
        #expect(fragment.parcel?.confidence == .direct)
        #expect(parcel.constructionYear == 2025)
        #expect(parcel.ownerName?.isEmpty == false)
    }

    @Test("Summaries never claim the parcel owner owns the road")
    func summaryIsHonestAboutAdjacency() async throws {
        let adjacent = try #require(try await parcels(.williamsFrontage).fetch(williams).parcel?.value)
        #expect(MaricopaParcelSource.summary(adjacent).hasPrefix("Nearest parcel"))

        let containing = try #require(try await parcels(.goodyearParcel).fetch(goodyear).parcel?.value)
        #expect(MaricopaParcelSource.summary(containing).hasPrefix("The pin falls inside"))
    }

    @Test("Treats the vacant-land year sentinel as no year")
    func yearSentinel() {
        // CONST_YEAR is a string and vacant parcels carry "0".
        #expect(MaricopaParcelSource.year(from: .string("0")) == nil)
        #expect(MaricopaParcelSource.year(from: .string("")) == nil)
        #expect(MaricopaParcelSource.year(from: .null) == nil)
        #expect(MaricopaParcelSource.year(from: .string("2008")) == 2008)
        #expect(MaricopaParcelSource.year(from: .number(1954)) == 1954)
    }

    @Test("Converts land size from square feet to acres")
    func landSize() async throws {
        let parcel = try #require(try await parcels(.goodyearParcel).fetch(goodyear).parcel?.value)
        let acres = try #require(parcel.landSizeAcres)
        // 568,271 sq ft ≈ 13 acres.
        #expect(acres > 12 && acres < 14)
    }
}
