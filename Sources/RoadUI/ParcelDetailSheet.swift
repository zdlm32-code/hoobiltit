import SwiftUI
import RoadCore

/// What a tapped parcel says about itself.
///
/// Separate from the road report on purpose: this is a neighbouring lot the user asked about,
/// not the answer to who built the road. Nothing here should read as if it were.
struct ParcelDetailSheet: View {
    let apn: String
    let parcel: ParcelReference?
    let isLoading: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking up \(apn)\u{2026}").foregroundStyle(.secondary)
                    }
                } else if let parcel {
                    Section {
                        if let owner = parcel.ownerName {
                            LabelledValue(label: "Owner", value: owner, attributed: nil)
                        }
                        if let address = parcel.address {
                            LabelledValue(label: "Address", value: address, attributed: nil)
                        }
                        if let year = parcel.constructionYear {
                            LabelledValue(label: "Building built", value: String(year), attributed: nil)
                        }
                        if let acres = parcel.landSizeAcres {
                            LabelledValue(label: "Land size",
                                          value: acres.formatted(.number.precision(.fractionLength(0...2))) + " acres",
                                          attributed: nil)
                        }
                    } header: {
                        Text("Parcel \(parcel.apn)")
                    } footer: {
                        Text("Maricopa County Assessor. A building's year is not the road's year, "
                             + "and this owner owns the lot, not the street.")
                    }

                    if parcel.subdivisionName != nil || parcel.recorderNumber != nil {
                        Section("Plat") {
                            if let name = parcel.subdivisionName {
                                LabelledValue(label: "Subdivision", value: name, attributed: nil)
                            }
                            if let number = parcel.recorderNumber {
                                LabelledValue(label: "Recorded plat", value: number, attributed: nil)
                            }
                        }
                    }
                } else {
                    Text("No assessor record came back for \(apn).")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Parcel")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
