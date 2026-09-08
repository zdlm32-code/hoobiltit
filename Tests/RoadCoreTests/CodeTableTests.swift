import Foundation
import Testing
@testable import RoadCore

@Suite("Coded values the agencies refuse to document")
struct CodeTableTests {
    @Test("Every ownership code Louisiana actually emits decodes")
    func louisianaCodesAllCovered() {
        // Captured live from the Ownership layer with returnDistinctValues.
        let emitted = [1, 2, 3, 4, 11, 21, 25, 26, 32, 63, 64, 66, 70, 72, 73, 74, 80]
        for code in emitted {
            #expect(CodeTables.hpmsOwnership[code] != nil, "HPMS \(code) has no name")
        }
        // 80 is "Other" — a name but not an agency, so it yields no owner rather than a
        // confident wrong one.
        #expect(CodeTables.owner(hpms: 80) == nil)
    }

    @Test("Ownership codes map to owners with the right meaning")
    func ownerMapping() {
        #expect(CodeTables.owner(hpms: 1) == .state(agency: "State highway agency"))
        #expect(CodeTables.owner(hpms: 2) == .county(agency: "County highway agency"))
        #expect(CodeTables.owner(hpms: 26) == .privateOwner)
        #expect(CodeTables.owner(hpms: 31)?.displayName == "State toll authority")
        if case .tribal = CodeTables.owner(hpms: 62) {} else { Issue.record("BIA should be tribal") }
        if case .federal = CodeTables.owner(hpms: 66) {} else { Issue.record("NPS should be federal") }
        if case .municipality = CodeTables.owner(hpms: 4) {} else { Issue.record("4 is municipal") }
    }

    @Test("An unknown code yields nothing rather than a guess")
    func unknownCodeIsSilent() {
        #expect(CodeTables.hpmsOwnership[99] == nil)
        #expect(CodeTables.owner(hpms: 99) == nil)
        #expect(CodeTables.functionalClass[19] == nil, "NY's extended scheme must not decode here")
    }

    @Test("PennDOT JURIS is decoded, and I-676 does not come back municipal")
    func penndotIsNotHPMS() {
        // The whole point. MAINT_RESPON_IND = 40 on I-676; read as HPMS that is "city or
        // municipal highway agency". JURIS = 1 is the truth: PennDOT.
        #expect(CodeTables.owner(penndot: 1) == .state(agency: "Pennsylvania Department of Transportation"))
        #expect(CodeTables.owner(hpms: 4)?.displayName == "City or municipal highway agency")
        #expect(CodeTables.owner(penndot: 1)?.displayName != CodeTables.owner(hpms: 4)?.displayName)

        if case .tollAuthority = CodeTables.owner(penndot: 2) {} else {
            Issue.record("the Turnpike Commission is not the state DOT")
        }
        #expect(CodeTables.penndotJurisdiction.keys.sorted() == [1, 2, 5, 6],
                "PennDOT emits exactly these four")
        // MAINT_RESPON_IND values must never resolve through the PennDOT table either.
        for stray in [10, 20, 30, 40, 50, 60, 70, 80] {
            #expect(CodeTables.owner(penndot: stray) == nil)
        }
    }

    @Test("TxDOT ADMIN covers every code the service emits, and is not read as HPMS")
    func txdotAdminIsComplete() {
        // The full 1...16 range, from a groupBy over all 1,027,891 statewide segments.
        for code in 1...16 {
            #expect(CodeTables.owner(txdot: code) != nil, "ADMIN \(code) decodes to nothing")
        }
        // The trap: HPMS defines nothing at 5-10 or 13-16, so reading ADMIN as HPMS would
        // drop real owners on the floor for four of Texas's sixteen codes.
        for code in [5, 6, 7, 8, 9, 10, 13, 14, 15, 16] {
            #expect(CodeTables.hpmsOwnership[code] == nil,
                    "\(code) exists in HPMS after all — the tables need re-deriving")
        }
    }

    @Test("TxDOT ADMIN maps to the owner its HSYS cross-tab proves")
    func txdotOwnerMapping() {
        // 1 covers every TxDOT-maintained system: IH, US, SH, FM, RM, SL, business routes.
        #expect(CodeTables.owner(txdot: 1) == .state(agency: "Texas Department of Transportation"))
        // 2 is CR and nothing else; 4 is LS and nothing else.
        #expect(CodeTables.owner(txdot: 2) == .county(agency: "County highway agency"))
        if case .municipality = CodeTables.owner(txdot: 4) {} else { Issue.record("4 is LS, municipal") }
        // 5, 6 and 16 are the TL rows — HWY reads TL0002, TL0011 — plus tolled state loops.
        for code in [5, 6, 16] {
            if case .tollAuthority = CodeTables.owner(txdot: code) {} else {
                Issue.record("ADMIN \(code) is a toll facility")
            }
        }
        // 3 and 7-15 are all FD. Which federal agency is unrecoverable: HWY is null on every
        // one of those 5,165 rows, so the code claims only "federal".
        for code in [3] + Array(7...15) {
            if case .federal = CodeTables.owner(txdot: code) {} else {
                Issue.record("ADMIN \(code) is HSYS FD, a federal agency")
            }
        }
        #expect(CodeTables.owner(txdot: 17) == nil)
        #expect(CodeTables.owner(txdot: 0) == nil)
    }

    @Test("Functional class covers exactly the values Louisiana publishes")
    func functionalClass() {
        #expect(CodeTables.functionalClass.keys.sorted() == [1, 2, 3, 4, 5, 6, 7])
        #expect(CodeTables.functionalClass[1] == "Interstate")
        #expect(CodeTables.functionalClass[7] == "Local")
    }

    @Test("Codes are read from every encoding the states use")
    func codeParsing() {
        #expect(CodeTables.code(.number(4)) == 4)                       // NHS
        #expect(CodeTables.code(.string("4")) == 4)                     // Louisiana
        #expect(CodeTables.code(.string("04")) == 4)                    // zero-padded
        #expect(CodeTables.code(.string("04-Municipal or City Hwy Agency")) == 4)  // Virginia
        #expect(CodeTables.code(.string("70-Interstate")) == 70)        // ADOT
        #expect(CodeTables.code(.null) == nil)
        #expect(CodeTables.code(.string("DOT-Arizona Department of Transportation")) == nil,
                "a non-numeric prefix is not a code")
    }
}
