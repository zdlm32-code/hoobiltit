import Foundation
import RoadCore
import RoadSources
import RoadStore

// usage: roadlookup <longitude> <latitude>   (defaults to the Lone Mountain Rd test pin)
let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
let (lon, lat) = args.count >= 2 ? (args[0], args[1]) : (-112.528617, 33.767648)

// --cache exercises the SwiftData store across runs, so a repeat lookup can be seen to skip
// the network entirely.
let cache: (any FragmentCache)? = CommandLine.arguments.contains("--cache")
    ? try? SwiftDataFragmentCache()
    : nil

// The pipeline is chosen by where the pin is, exactly as the app chooses it, so this tool
// exercises national coverage rather than a hardcoded Arizona pipeline.
let jurisdiction = await JurisdictionLocator().locate(Coordinate(latitude: lat, longitude: lon))
let built = PipelineFactory().pipeline(for: jurisdiction)
let resolver = RoadResolver(sources: built.sources, cache: cache)
var record = await resolver.resolve(RoadQuery(latitude: lat, longitude: lon))
record.coverage = built.coverage

func show(_ label: String, _ value: String?, _ attributed: (any AttributedDescribing)?) {
    guard let value else { return }
    let tag = attributed.map { " [\($0.sourceName), \($0.confidence.rawValue)]" } ?? ""
    print("  \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)\(tag)")
}

print("\npin \(lat), \(lon)")
if let coverage = record.coverage {
    let place = coverage.jurisdiction?.description ?? "jurisdiction unknown"
    let via = coverage.profileNames.isEmpty ? "national tier only"
                                            : coverage.profileNames.joined(separator: ", ")
    print("  \("coverage".padding(toLength: 22, withPad: " ", startingAt: 0)) "
          + "\(coverage.level.rawValue) — \(place) — \(via)")
}
let ymd = { (d: Date) -> String in CalendarDate.medium(d) }
show("owner", record.owner?.value.displayName, record.owner)
show("route", record.routeDesignation?.value, record.routeDesignation)
show("jurisdiction", record.jurisdiction?.value, record.jurisdiction)
show("segment", record.segmentName?.value, record.segmentName)
show("classification", record.classification?.value, record.classification)
show("between", record.crossStreets?.value, record.crossStreets)
show("maint. district", record.maintenanceDistrict?.value, record.maintenanceDistrict)
show("supervisor district", record.supervisorDistrict.map { String($0.value) }, record.supervisorDistrict)
if let s = record.surface {
    let v = s.value
    let parts = [v.type,
                 (v.depthInches ?? 0) > 0 ? "\(v.depthInches!)\" over \(v.baseType ?? "unknown base")" : nil,
                 v.laneCount.map { "\($0) lanes" }, v.conditionRating.map { "condition \($0.lowercased())" }]
    show("surface", parts.compactMap { $0 }.joined(separator: ", "), s)
}
show("last constructed", record.yearLastConstruction.map { ymd($0.value) }, record.yearLastConstruction)
show("last improved", record.yearLastImprovement.map { ymd($0.value) }, record.yearLastImprovement)
if let p = record.project {
    show("project", [p.value.projectNumber, p.value.title].compactMap { $0 }.first, p)
    show("  title", p.value.projectNumber == nil ? nil : p.value.title, nil)
    show("  phase", p.value.phase, nil)
    show("  location", p.value.location, nil)
    show("  detail", p.value.detail.map { $0.replacingOccurrences(of: "\n\n", with: " / ") }, nil)
}
if let i = record.lastKnownImprovement {
    show("last improvement", [i.value.projectNumber, i.value.title].compactMap { $0 }.first, i)
    show("  detail", i.value.detail, nil)
}
if let b = record.bridge {
    let v = b.value
    let years = [v.yearBuilt.map { "built \($0)" }, v.yearReconstructed.map { "reconstructed \($0)" }]
        .compactMap { $0 }.joined(separator: ", ")
    show("structure", [v.crosses.map { "over \($0)" }, years.isEmpty ? nil : years].compactMap { $0 }.joined(separator: " — "), b)
    show("  owner", v.ownerDescription, nil)
}
if let f = record.funding {
    let v = f.value
    let parts = [v.programmedAmount.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) },
                 v.fiscalYear, v.leadAgency.map { "lead \($0)" },
                 v.inServiceDate.map { "opened \(ymd($0))" }].compactMap { $0 }
    show("programmed cost", parts.joined(separator: ", "), f)
}
if let pc = record.parcel {
    let v = pc.value
    show(v.containsPin ? "parcel (contains pin)" : "parcel (adjacent)", v.apn, pc)
    show("  owner", v.ownerName, nil)
    show("  address", v.address, nil)
    show("  subdivision", v.subdivisionName.map { n in v.recorderNumber.map { "\(n) (plat \($0))" } ?? n }, nil)
    if let r = v.constructionYearRange {
        show("  buildings built", "\(r.lowerBound)\u{2013}\(r.upperBound)", nil)
    } else if let y = v.constructionYear {
        show("  built", String(y), nil)
    }
}
if let d = record.declaration {
    show("declared public road", ymd(d.value.effectiveDate), d)
    show("  road file", d.value.roadFileNumber, nil)
    show("  document", d.value.documentURL?.absoluteString, nil)
}
if let a = record.acquisition {
    show("row acquired by", a.value.method, a)
    show("  document", a.value.recorderURL?.absoluteString, nil)
}
if let plat = record.plat {
    show("platted as", plat.value.subdivisionName, plat)
    show("  plat book-page", plat.value.recorderNumber, nil)
    show("  plat document", plat.value.recorderURL?.absoluteString, nil)
}
if let a = record.annexation?.value {
    show("annexed by ord.", a.ordinance, record.annexation)
    show("  ordinance PDF", a.ordinanceURL?.absoluteString, nil)
}
if CommandLine.arguments.contains("--request") {
    let agency = record.owner.flatMap { AgencyDirectory.bundled.agency(for: $0.value) }
    print("\n--- public records request ---")
    print(RecordsRequest.draft(for: record, agency: agency))
    print("--- end ---")
}
if let explanation = record.coverage?.explanation(for: record) {
    print("\n  \(explanation)")
}
print("\n  notes")
for note in record.notes {
    print("    \(note.outcome.rawValue): \(note.sourceName) — \(note.detail ?? "")")
}
print("")
