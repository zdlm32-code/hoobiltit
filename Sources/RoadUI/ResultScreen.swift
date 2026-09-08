import SwiftUI
import RoadCore
#if os(iOS)
import UIKit
#endif

/// The full answer for one pin, organised around the three questions the app exists to ask —
/// and honest about the one it usually cannot answer.
///
/// Dates are never fused. A plat date, a county road declaration, an ADOT construction date
/// and a bridge's build year are four different facts from four different records, and the
/// screen shows whichever exist as separate labelled rows rather than inventing a single
/// "built in YYYY" the data cannot support.
public struct ResultScreen: View {
    let record: RoadRecord
    let placeName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var copiedRequest = false
    /// Rendered once when the screen appears rather than on every body evaluation.
    @State private var share: RoadShare?

    private var agency: Agency? {
        record.owner.flatMap { AgencyDirectory.bundled.agency(for: $0.value) }
    }

    public var body: some View {
        NavigationStack {
            List {
                if record.isEmpty { nothingFound }
                whoseRoad
                when
                structure
                whatProject
                workHistory
                land
                paperTrail
                fallback
                whereThisCameFrom
            }
            .navigationTitle(record.segmentName?.value ?? record.routeDesignation?.value ?? "Road")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let share {
                            ShareLink(item: share,
                                      preview: SharePreview(shareContent.roadName ?? "This road")) {
                                Label("Share the card", systemImage: "photo")
                            }
                        }
                        // The same answer as a file: greppable, pastes into an email, and it is
                        // the form somebody actually filing something wants.
                        ShareLink(item: RoadReportFile(name: fileName, text: reportText),
                                  preview: SharePreview(fileName)) {
                            Label("Share the full report", systemImage: "doc.text")
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task {
                let content = shareContent
                guard let png = ShareCard.png(content) else { return }
                share = RoadShare(png: png, text: ShareCard.text(content))
            }
        }
    }

    /// The same plain-string projection the drive card and the Live Activity use, so a shared
    /// image cannot disagree with what the app showed on screen.
    private var shareContent: DriveCardContent {
        DriveCardContent(record: record, placeName: placeName)
    }

    private var reportText: String { ReportDocument.text(for: record, placeName: placeName) }

    /// A filename somebody can find again, not "document.txt".
    private var fileName: String {
        let name = shareContent.roadName ?? "road"
        return name.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - Provenance

    /// One row per source: what it gave, how firmly, when it was asked, and a link to the exact
    /// query. `Provenance` has always documented that the fetch time must be disclosed; this is
    /// the first screen that does it, and the first that lets a claim be re-run.
    private var whereThisCameFrom: some View {
        Section {
            ForEach(record.receipts) { SourceReceiptRow(receipt: $0) }
        } header: {
            Text("Where this came from")
        } footer: {
            Text("Every source the app asked, including the ones with nothing to say \u{2014} a "
                 + "partial answer is the normal outcome here. Opening a query re-runs the exact "
                 + "request behind a value.")
        }
    }

    // MARK: - Nothing found

    /// A wholly unresolved road used to open a report consisting of an empty section and a
    /// records request, which reads as a broken screen rather than an answer.
    private var nothingFound: some View {
        Section {
            Text("No public source identified a road at this point.")
                .font(.subheadline)
            Text("The sources consulted are listed below, including the ones that had nothing "
                 + "to say. A records request is still the way to ask.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// What the app could bring to bear here. The smaller cards already explain a thin answer;
    /// the screen meant to be exhaustive did not.
    @ViewBuilder
    private var coverageNote: some View {
        if let coverage = record.coverage {
            if let explanation = coverage.explanation(for: record) {
                Text(explanation).font(.footnote).foregroundStyle(.secondary)
            }
            if !coverage.profileNames.isEmpty {
                Text("Consulted: " + coverage.profileNames.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if let captured = coverage.catalogCapturedOn {
                Text("Coverage list checked \(CalendarDate.medium(captured))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - The structure you are on

    /// The National Bridge Inventory record, which the app has always fetched in full and shown
    /// two integers from. It is the oldest construction date available anywhere — some Maricopa
    /// structures go back to 1927 — and it separates original construction from reconstruction,
    /// which no other source does.
    @ViewBuilder
    private var structure: some View {
        if let bridge = record.bridge {
            let value = bridge.value
            Section("The structure here") {
                if let carries = value.carries {
                    LabelledValue(label: "Carries", value: carries, attributed: bridge)
                }
                if let crosses = value.crosses {
                    LabelledValue(label: "Over", value: crosses, attributed: nil)
                }
                if let number = value.structureNumber {
                    LabelledValue(label: "Structure number", value: number, attributed: nil)
                }
                if let owner = value.ownerDescription {
                    LabelledValue(label: "Structure owner", value: owner, attributed: nil)
                }
                if let traffic = value.averageDailyTraffic {
                    LabelledValue(label: "Traffic across it",
                                  value: "\(traffic.formatted(.number)) vehicles a day"
                                         + (value.trafficCountYear.map { " (\($0))" } ?? ""),
                                  attributed: nil)
                }
            }
        }
    }

    // MARK: - Whose road

    private var whoseRoad: some View {
        Section("Whose road") {
            if let placeName {
                Text(placeName).font(.subheadline).foregroundStyle(.secondary)
            }
            if let owner = record.owner {
                LabelledValue(label: "Maintained by", value: owner.value.displayName, attributed: owner)
                if owner.value.isCourtesyMaintained {
                    // The distinction the data makes and v1 flattened.
                    Text("The county maintains this road but has not accepted it into its system. "
                         + "That usually means it was built by a developer, so the recorded plat "
                         + "below is the better answer to who built it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let jurisdiction = record.jurisdiction {
                LabelledValue(label: "Jurisdiction", value: jurisdiction.value, attributed: jurisdiction)
            }
            // "This street is also US-60" was lost: the designation was only ever used as a
            // fallback for a missing name, never shown alongside one.
            if let designation = record.routeDesignation,
               designation.value != record.segmentName?.value {
                LabelledValue(label: "Also known as", value: designation.value, attributed: designation)
            }
            if let traffic = record.trafficCount {
                LabelledValue(label: "Traffic",
                              value: "\(traffic.value.formatted(.number)) vehicles a day",
                              attributed: traffic)
            }
            if let classification = record.classification {
                LabelledValue(label: "Classification", value: classification.value, attributed: classification)
            }
            if let crossStreets = record.crossStreets {
                LabelledValue(label: "Between", value: crossStreets.value, attributed: crossStreets)
            }
            if let district = record.maintenanceDistrict {
                LabelledValue(label: "Maintenance district", value: district.value, attributed: district)
            }
            if let district = record.supervisorDistrict {
                LabelledValue(label: "Supervisor district",
                              value: "District \(district.value)", attributed: district)
            }
            coverageNote
        }
    }

    // MARK: - When

    @ViewBuilder
    private var when: some View {
        let rows = dateRows
        if !rows.isEmpty || record.surface != nil {
            Section {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    LabelledValue(label: row.label, value: row.value, attributed: row.source)
                }
                if let surface = record.surface {
                    LabelledValue(label: "Surface", value: describe(surface.value), attributed: surface)
                }
            } header: {
                Text("When")
            } footer: {
                if rows.count > 1 {
                    Text("These are separate records, not one date. A road can be declared, "
                         + "constructed, resurfaced and rebuilt in different years.")
                }
            }
        }
    }

    private struct DateRow {
        let label: String
        let value: String
        let source: (any AttributedDescribing)?
    }

    private var dateRows: [DateRow] {
        var rows: [DateRow] = []
        if let declaration = record.declaration {
            rows.append(DateRow(label: "Declared a public road",
                                value: CalendarDate.medium(declaration.value.effectiveDate),
                                source: declaration))
        }
        if let platted = record.plattedDate {
            rows.append(DateRow(label: "Platted",
                                value: CalendarDate.medium(platted.value),
                                source: platted))
        }
        if let built = record.yearLastConstruction {
            rows.append(DateRow(label: "Last constructed",
                                value: CalendarDate.medium(built.value),
                                source: built))
        }
        if let improved = record.yearLastImprovement {
            rows.append(DateRow(label: "Last improved",
                                value: CalendarDate.medium(improved.value),
                                source: improved))
        }
        if let bridge = record.bridge, let year = bridge.value.yearBuilt {
            rows.append(DateRow(label: "Bridge built", value: String(year), source: bridge))
            if let rebuilt = bridge.value.yearReconstructed, rebuilt > 0 {
                rows.append(DateRow(label: "Bridge reconstructed", value: String(rebuilt), source: bridge))
            }
        }
        return rows
    }

    // MARK: - What project

    @ViewBuilder
    private var whatProject: some View {
        if record.project != nil || record.lastKnownImprovement != nil || record.funding != nil {
            Section("What project") {
                if let project = record.project {
                    projectRows("Built under", project)
                }
                if let improvement = record.lastKnownImprovement {
                    projectRows("Most recent work", improvement)
                }
                if let funding = record.funding {
                    LabelledValue(label: "Programmed cost",
                                  value: describe(funding.value), attributed: funding)
                }
                // This used to say flatly that no public source publishes cost or contractor
                // anywhere. That was true of the fourteen state DOTs checked at the time and
                // is false in Texas, whose construction register carries both — so the claim
                // is now made only where it still holds.
                if record.funding?.value.programmedAmount != nil {
                    Text("This is the agency's *estimated* construction cost, not the amount "
                         + "the contract was finally awarded or paid out. The request below is "
                         + "how you get the awarded figure.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Most agencies publish no contractor and no award amount for a road "
                         + "segment: that held for Maricopa County, and of fourteen state DOTs "
                         + "checked only Texas carries construction cost. The request below is "
                         + "how you get it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func projectRows(_ label: String, _ project: Attributed<ProjectReference>) -> some View {
        LabelledValue(label: label, value: SegmentCard.describe(project.value), attributed: project)
        if let type = project.value.projectType {
            Text(type).font(.caption).foregroundStyle(.secondary)
        }
        if let location = project.value.location {
            // The agency's own description of the extent — often more exact than the cross
            // streets the app derives.
            Text(location).font(.caption).foregroundStyle(.secondary)
        }
        if let phase = project.value.phase {
            Text(phase).font(.caption).foregroundStyle(.secondary)
        }
        if let detail = project.value.detail {
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - Work on this road

    /// The full register, where an agency publishes one.
    ///
    /// Deliberately below "What project", which answers the question in one line. This is the
    /// evidence behind that line, and for a Texas highway it can run to twenty-odd jobs across
    /// fifty years, so it is a list rather than a sentence.
    @ViewBuilder
    private var workHistory: some View {
        if let works = record.works?.value, !works.isEmpty {
            let done = works.filter { !$0.isPlanned }
            let planned = works.filter(\.isPlanned)
            if !done.isEmpty {
                Section("Work on this road") {
                    ForEach(Array(done.enumerated()), id: \.offset) { _, work in
                        workRow(work)
                    }
                    Text("Dates are when the contract was let, not when work finished. A "
                         + "project is drawn along the whole control section, so a job may "
                         + "have been done elsewhere on this stretch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !planned.isEmpty {
                Section("Planned") {
                    ForEach(Array(planned.enumerated()), id: \.offset) { _, work in
                        workRow(work)
                    }
                    Text("Not yet let. Planned work slips and is sometimes cancelled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func workRow(_ work: RoadWork) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(work.title).font(.body)
                Spacer()
                if let year = work.letDate.map({ CalendarDate.year($0) }) {
                    Text(String(year)).font(.body).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let cost = work.cost {
                Text(cost.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let contractor = work.contractor {
                Text("Built by \(contractor)").font(.caption)
            }
            if let location = work.location {
                Text(location).font(.caption).foregroundStyle(.secondary)
            }
            if let detail = work.detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            if let number = work.projectNumber {
                Text("Project \(number)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - The land beside it

    @ViewBuilder
    private var land: some View {
        if let parcel = record.parcel {
            let value = parcel.value
            Section {
                LabelledValue(label: value.containsPin ? "Parcel (contains the pin)"
                                                       : "Parcel fronting this road",
                              value: value.apn, attributed: parcel)
                if let owner = value.ownerName {
                    LabelledValue(label: "Owner of that parcel", value: owner, attributed: nil)
                }
                if let address = value.address {
                    Text(address).font(.footnote).foregroundStyle(.secondary)
                }
                if let range = value.constructionYearRange {
                    LabelledValue(label: "Buildings alongside built",
                                  value: "\(range.lowerBound)\u{2013}\(range.upperBound)",
                                  attributed: nil)
                } else if let year = value.constructionYear {
                    LabelledValue(label: "Building on it built", value: String(year), attributed: nil)
                }
                if let acres = value.landSizeAcres {
                    LabelledValue(label: "Land size",
                                  value: acres.formatted(.number.precision(.fractionLength(0...2))) + " acres",
                                  attributed: nil)
                }
                if let corroboration = platCorroboration {
                    Label(corroboration, systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("The land beside it")
            } footer: {
                Text(value.containsPin
                     ? "Assessor records for the parcel under the pin. A building's year is not the road's year."
                     : "A road runs in the right-of-way between parcels, so this is the land the "
                       + "road passes, not land the road sits on \u{2014} and its owner is not the "
                       + "road's owner. Where the buildings went up still brackets when a "
                       + "developer-built street was laid out.")
            }
        }
    }

    /// The Assessor and MCDOT keep the plat identifier independently. When they agree it is
    /// worth saying, because most of this app's answers rest on a single source.
    private var platCorroboration: String? {
        guard let parcelPlat = record.parcel?.value.recorderNumber,
              let recordedPlat = record.plat?.value.recorderNumber,
              parcelPlat == recordedPlat
        else { return nil }
        return "The Assessor and MCDOT agree this is plat \(recordedPlat)."
    }

    // MARK: - Paper trail

    @ViewBuilder
    private var paperTrail: some View {
        if record.plat != nil || record.declaration != nil
            || record.acquisition != nil || record.annexation != nil {
            Section {
                if let plat = record.plat {
                    LabelledValue(label: "Subdivision", value: plat.value.subdivisionName, attributed: plat)
                    documentLink(plat.value.recorderURL,
                                 plat.value.recorderNumber.map { "Recorded plat \($0)" } ?? "Recorded plat")
                }
                if let declaration = record.declaration {
                    if let file = declaration.value.roadFileNumber {
                        LabelledValue(label: "County road file", value: file, attributed: declaration)
                    }
                    documentLink(declaration.value.documentURL, "Recorded road declaration")
                }
                if let declaration = record.declaration,
               declaration.value.roadName != record.segmentName?.value,
               !declaration.value.roadName.isEmpty {
                // The county's road file can name the road differently from the centreline.
                LabelledValue(label: "Named in the road file as",
                              value: declaration.value.roadName, attributed: declaration)
            }
            if let acquisition = record.acquisition {
                    LabelledValue(label: "Acquired by", value: acquisition.value.method, attributed: acquisition)
                    if let width = acquisition.value.widthFeet, width > 0 {
                        // The width of the strip the public actually owns — resolved from the
                        // county's right-of-way layer and, until now, shown nowhere.
                        LabelledValue(label: "Right of way",
                                      value: "\(width.formatted(.number.precision(.fractionLength(0...1)))) ft wide",
                                      attributed: nil)
                    }
                    documentLink(acquisition.value.recorderURL,
                                 acquisition.value.recorderNumber.map { "Recorded document \($0)" }
                                     ?? "Recorded document")
                }
                if let annexation = record.annexation {
                    if let ordinance = annexation.value.ordinance {
                        let date = annexation.value.ordinanceDate
                            .map { " (\(CalendarDate.medium($0)))" } ?? ""
                        LabelledValue(label: "Annexed by ordinance",
                                      value: ordinance + date, attributed: annexation)
                    }
                    documentLink(annexation.value.ordinanceURL, "Annexation ordinance")
                }
            } header: {
                Text("The paper trail")
            } footer: {
                Text("These open the county's recording system in your browser.")
            }
        }
    }

    @ViewBuilder
    private func documentLink(_ url: URL?, _ title: String) -> some View {
        if let url {
            Link(destination: url) { Label(title, systemImage: "doc.text") }
        }
    }

    // MARK: - Fallback

    private var fallback: some View {
        Section {
            if let agency {
                Text("Send this to \(agency.name).").font(.subheadline)
                if let url = agency.requestURL {
                    Link(destination: url) { Label("Open the request form", systemImage: "arrow.up.right.square") }
                }
                if let email = agency.email {
                    Text(email).font(.footnote).textSelection(.enabled)
                }
                if let phone = agency.phone {
                    Text(phone).font(.footnote).textSelection(.enabled)
                }
            } else {
                Text("No contact route is bundled for this agency. The request text below is "
                     + "still valid — send it to whoever maintains the road.")
                    .font(.subheadline)
            }

            Text(RecordsRequest.draft(for: record, agency: agency))
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)

            Button {
                copyRequest()
            } label: {
                Label(copiedRequest ? "Copied" : "Copy request", systemImage: copiedRequest ? "checkmark" : "doc.on.doc")
            }

            ShareLink(item: RecordsRequest.draft(for: record, agency: agency),
                      preview: SharePreview("Records request")) {
                Label("Send the request", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Ask for the rest")
        } footer: {
            // The one deliberate exception to the rule that a shared artefact carries no
            // coordinate. The letter cites the pin to six decimal places because an agency has
            // to know which stretch of road is being asked about — and unlike a card handed to a
            // group chat, this one is addressed to a named public office.
            Text("This letter includes the exact coordinate, because the agency needs it to "
                 + "find the segment. Agency contact details are bundled with the app, checked "
                 + CalendarDate.medium(AgencyDirectory.bundled.capturedOn)
                 + ". Verify before relying on them.")
        }
    }

    private func copyRequest() {
        #if os(iOS)
        UIPasteboard.general.string = RecordsRequest.draft(for: record, agency: agency)
        #endif
        copiedRequest = true
    }

    // MARK: - Sources


    // MARK: - Formatting

    /// The full build-up. `SegmentCard` has a shorter version for the compact card; this one is
    /// meant to leave nothing out, including the base depth and the width, which nothing showed.
    private func describe(_ surface: SurfaceDescription) -> String {
        var parts = [surface.type]
        if let depth = surface.depthInches, depth > 0 {
            let inches = depth.formatted(.number.precision(.fractionLength(0...1)))
            var layer = "\(inches)\u{2033}"
            if let base = surface.baseType {
                let baseDepth = surface.baseDepthInches
                    .flatMap { $0 > 0 ? $0.formatted(.number.precision(.fractionLength(0...1))) : nil }
                layer += " over \(baseDepth.map { "\($0)\u{2033} " } ?? "")\(base)"
            }
            parts.append(layer)
        }
        if let lanes = surface.laneCount { parts.append("\(lanes) lanes") }
        if let width = surface.widthFeet, width > 0 {
            parts.append("\(width.formatted(.number.precision(.fractionLength(0...1)))) ft wide")
        }
        // Prefer the agency's own words over the raw index.
        if let rating = surface.conditionRating {
            parts.append("condition \(rating.lowercased())")
        } else if let index = surface.conditionIndex {
            parts.append("condition \(Int(index.rounded()))/100")
        }
        return parts.joined(separator: ", ")
    }

    /// Everything the funding record carries, including its own project number — which is not
    /// always the same as the construction project's — and the agency region.
    private func describe(_ funding: ProjectFunding) -> String {
        var parts: [String] = []
        if let amount = funding.programmedAmount {
            parts.append(amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
        }
        if let year = funding.fiscalYear { parts.append(year) }
        if let agency = funding.leadAgency { parts.append("lead agency \(agency)") }
        if let region = funding.region { parts.append("region \(region)") }
        if let number = funding.projectNumber { parts.append("programme no. \(number)") }
        if let opened = funding.inServiceDate {
            parts.append("opened \(CalendarDate.medium(opened))")
        }
        // Kept beside the estimate rather than replacing it: they answer different questions,
        // and on a job still under way the spend is a running total, not a final figure.
        if let spent = funding.actualSpend {
            parts.append("spent so far "
                + spent.formatted(.currency(code: "USD").precision(.fractionLength(0))))
        }
        if let contractor = funding.contractor { parts.append("built by \(contractor)") }
        return parts.isEmpty ? "Programmed" : parts.joined(separator: ", ")
    }
}
