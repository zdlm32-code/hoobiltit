import Foundation
import RoadCore

/// Chooses which sources to ask, based on where the pin is.
///
/// The resolver stays exactly as it was — it still takes a fixed `[any RoadSource]` and runs
/// them in order. What changes is that the array is no longer a constant. This is the seam:
/// jurisdiction in, pipeline out.
///
/// Tiers run deepest first, because `RoadRecord.merge` is first-writer-wins and the most local
/// authority should not be overwritten by a national approximation:
///
/// 1. **State**, so a state route is claimed before a county source infers a municipal owner
///    for a pin that happens to fall inside city limits.
/// 2. **County**, where somebody has done the reconnaissance.
/// 3. **National**, which fills what is left — a name from TIGER, ownership if the road is on
///    the National Highway System, a bridge's build year — and is the only tier that runs
///    everywhere.
public struct PipelineFactory: Sendable {
    private let catalog: CoverageCatalog
    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(catalog: CoverageCatalog = .bundled,
                client: ArcGISClient = ArcGISClient(),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.catalog = catalog
        self.client = client
        self.now = now
    }

    public func pipeline(for jurisdiction: Jurisdiction?) -> (sources: [any RoadSource], coverage: Coverage) {
        var sources: [any RoadSource] = []
        var names: [String] = []
        var caveats: [String] = []
        var level = CoverageLevel.national
        var stateFallback: [any RoadSource] = []

        if let jurisdiction {
            // A city's own street inventory outranks the state's copy of it. TxDOT files every
            // city street for HPMS and reads them all as "city or municipal highway agency",
            // while San Antonio names the actual owner and marks 11,017 segments **Private**.
            // Running the city second would lose that on every street TxDOT also carries,
            // which is nearly all of them.
            //
            // The rule this imposes on a city profile: it must report state and county roads
            // correctly, or not map ownership at all. Both shipped cities do — San Antonio
            // writes "TxDOT", Dallas writes "State" and `dallasMaintenance` spells it out.
            //
            // Deliberately at `.county` level rather than a level of its own:
            // `CoverageLevel.Comparable` reads a hardcoded array through a force-unwrapped
            // `firstIndex`, so a case missing from it crashes on the first comparison.
            if let place = jurisdiction.placeGEOID,
               let city = catalog.profile(forPlace: place) {
                let built = self.sources(for: city)
                if !built.isEmpty {
                    sources += built
                    names.append(city.displayName)
                    city.dateCaveat.map { caveats.append($0) }
                    level = max(level, .county)
                }
            }
            // A state contributes in two places, not one. Its hand-written sources lead,
            // because they encode judgement a table cannot — ADOT's exclude a whole route
            // namespace and disambiguate two routes 2 m apart — and a state route must be
            // claimed before a county source infers a municipal owner for a pin inside city
            // limits. Its *statewide table* is a fallback and belongs below the county: ADOT's
            // HPMS names an owner for every road in Arizona, and left in the state slot it beat
            // MCDOT's answer on Maricopa's own county roads, losing the distinction between a
            // road the county accepted and one it merely maintains.
            let state = catalog.profile(forState: jurisdiction.stateFIPS)
            if let state {
                let built = self.split(state)
                sources += built.leading
                stateFallback = built.trailing
                if !built.leading.isEmpty || !built.trailing.isEmpty {
                    names.append(state.displayName)
                    state.dateCaveat.map { caveats.append($0) }
                    level = max(level, .state)
                }
            }
            if let county = catalog.profile(forCounty: jurisdiction.countyFIPS) {
                let built = self.sources(for: county)
                if !built.isEmpty {
                    sources += built
                    names.append(county.displayName)
                    county.dateCaveat.map { caveats.append($0) }
                    level = max(level, .county)
                }
            }
        }

        sources += stateFallback
        sources += nationalSources()
        let coverage = Coverage(level: level, jurisdiction: jurisdiction, profileNames: names,
                                dateCaveats: caveats, catalogCapturedOn: catalog.capturedDate)
        return (sources, coverage)
    }

    /// The tier that works everywhere, in the order their gates require.
    ///
    /// TIGER first because it names the road, and both of the others gate on having a name:
    /// the NHS will not attribute a freeway's owner to the street beside it, and NBI will not
    /// attribute a structure to a road it does not belong to.
    private func nationalSources() -> [any RoadSource] {
        [TIGERNameSource(client: client, now: now),
         NHSOwnershipSource(client: client, now: now),
         NBIBridgeSource(client: client, now: now)]
    }

    /// Whether the map may draw parcel outlines here.
    public func hasParcels(_ jurisdiction: Jurisdiction?) -> Bool {
        guard let jurisdiction else { return false }
        return catalog.profile(forCounty: jurisdiction.countyFIPS)?.drawsParcels ?? false
    }

    /// The centreline drive mode should probe here.
    ///
    /// A county's own centreline beats TIGER where one is published — better naming, and a
    /// classification in words rather than a feature-class code. TIGER is the fallback
    /// precisely because the one thing this probe must never be is silent: while it read only
    /// Maricopa's centreline, drive mode outside Maricopa had nothing to compare against and
    /// fell back to re-resolving on distance alone.
    public func probe(for jurisdiction: Jurisdiction?) -> RoadNameProbe {
        let profile = jurisdiction.flatMap {
            catalog.profile(forCounty: $0.countyFIPS)?.centreline
                ?? catalog.profile(forState: $0.stateFIPS)?.centreline
        }
        guard let profile else { return RoadNameProbe(service: .national, client: client) }
        return RoadNameProbe(service: .init(url: profile.service, layers: profile.layers,
                                            nameField: profile.nameField,
                                            classificationField: profile.classificationField,
                                            minimumRadiusMeters: profile.minimumRadiusMeters ?? 0),
                             client: client)
    }

    /// The catalog may reorder or disable a compiled-in source; it cannot invent one. An id
    /// this build does not know is skipped, so a catalog published for a newer app degrades
    /// rather than crashing this one.
    ///
    /// `sourceIDs` is the whole pipeline for a `bespoke` entry, and *additional* sources for a
    /// generic one — appended after the adapter's own, so they can build on what it resolved.
    /// Texas is why: its inventory reads perfectly well through `flatInventory`, and rewriting
    /// that as bespoke to bolt on a project source would throw away a tested name join to gain
    /// nothing. A state can now have a hand-written helper without giving up the generic path.
    /// A profile's sources split into what runs before the county tier and what runs after.
    ///
    /// Only a profile marked `compiledFirst` splits: its hand-written sources lead and its
    /// generic table trails. Everything else runs as one block, exactly as before.
    private func split(_ profile: CoverageProfile) -> (leading: [any RoadSource],
                                                       trailing: [any RoadSource]) {
        guard profile.runsCompiledFirst else { return (sources(for: profile), []) }
        let compiled = (profile.sourceIDs ?? []).compactMap { self.compiled(id: $0) }
        let generic: [any RoadSource]
        switch profile.adapter {
        case .flatInventory:
            generic = [FlatInventorySource(profile: profile, client: client, now: now)].compactMap { $0 }
        case .lrsEvents:
            generic = [LRSEventSource(profile: profile, client: client, now: now)].compactMap { $0 }
        case .bespoke:
            generic = []
        }
        return (compiled, generic)
    }

    private func sources(for profile: CoverageProfile) -> [any RoadSource] {
        let compiled = (profile.sourceIDs ?? []).compactMap { self.compiled(id: $0) }
        switch profile.adapter {
        case .flatInventory:
            let own = [FlatInventorySource(profile: profile, client: client, now: now)].compactMap { $0 }
            return profile.runsCompiledFirst ? compiled + own : own + compiled
        case .lrsEvents:
            let own = [LRSEventSource(profile: profile, client: client, now: now)].compactMap { $0 }
            return profile.runsCompiledFirst ? compiled + own : own + compiled
        case .bespoke:
            return compiled
        }
    }

    /// Sources whose logic is hand-written because configuration cannot express it — deriving
    /// ownership from a layer's silence, disambiguating coincident geometry, reading a project
    /// number out of free text.
    private func compiled(id: String) -> (any RoadSource)? {
        switch id {
        case "adot.atis":         ADOTStateRouteSource(client: client, now: now)
        case "adot.funding":      ADOTFundingSource(client: client, now: now)
        case "mcdot.rit":         MCDOTRoadInfoSource(client: client, now: now)
        case "mcdot.centerline":  MaricopaStreetNameSource(probe: RoadNameProbe(service: .maricopa, client: client),
                                                   now: now)
        case "mcdot.declaration": MaricopaRoadDeclarationSource(client: client, now: now)
        case "mcdot.projects":    MaricopaCountyProjectSource(client: client, now: now)
        case "mcassessor.parcels": MaricopaParcelSource(client: client, now: now)
        case "usdot.nbi":         NBIBridgeSource(client: client, now: now)
        case "census.tiger":      TIGERNameSource(client: client, now: now)
        case "fhwa.nhs":          NHSOwnershipSource(client: client, now: now)
        case "tx.dcis":           TxDOTProjectSource(client: client, now: now)
        default:                  nil
        }
    }
}
