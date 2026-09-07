import Foundation
import Testing
@testable import RoadCore

private func input(probed: String? = "williamsdr", last: String? = "williamsdr",
                   county: String? = "04013", lastCounty: String? = "04013",
                   metres: Double? = 50, hasAnswer: Bool = true) -> DriveTrigger.Input {
    .init(probedRoad: probed, lastProbedRoad: last, countyFIPS: county,
          lastCountyFIPS: lastCounty, metresSinceLastResolve: metres,
          hasStandingAnswer: hasAnswer)
}

@Suite("When a moving car deserves a fresh answer")
struct DriveTriggerTests {
    @Test("Staying on the same road in the same county asks nothing")
    func steadyState() {
        // The whole point of the probe: driving a long straight road must not re-ask every
        // agency the same question every 25 metres.
        #expect(!DriveTrigger.shouldResolve(input()))
    }

    @Test("A new road name resolves")
    func turningOntoAnotherStreet() {
        #expect(DriveTrigger.shouldResolve(input(probed: "bullardave")))
    }

    @Test("Crossing a county line resolves even though the road is the same")
    func crossingACountyLine() {
        // The bug that going national introduces and that nothing in the Maricopa-era tests
        // could catch: a road keeps its name across the line and changes its owner. Drive
        // I-10 from Maricopa into Pinal and the card would otherwise still credit MCDOT.
        #expect(DriveTrigger.shouldResolve(
            input(probed: "i10", last: "i10", county: "04021", lastCounty: "04013", metres: 40)))
    }

    @Test("Crossing a state line resolves, which is where the pipeline changes entirely")
    func crossingAStateLine() {
        // Arizona into California on I-10: different DOT, different adapter, and California
        // publishes almost nothing — so the answer legitimately gets thinner, and must.
        #expect(DriveTrigger.shouldResolve(
            input(probed: "i10", last: "i10", county: "06065", lastCounty: "04012", metres: 30)))
    }

    @Test("The first fix of a drive has no county to compare against and still resolves")
    func firstFix() {
        #expect(DriveTrigger.shouldResolve(
            input(probed: nil, last: nil, county: "04013", lastCounty: nil,
                  metres: nil, hasAnswer: false)))
    }

    @Test("An unnameable road does not veto the lookup")
    func probeSilenceDoesNotBlock() {
        // Letting the probe's silence block resolution is what once left drive mode stuck on
        // "Looking…" on any road the centreline did not know.
        #expect(DriveTrigger.shouldResolve(input(probed: nil, last: nil, hasAnswer: false)))
        // But with an answer already on screen and the car barely moved, silence is not a
        // reason to ask again.
        #expect(!DriveTrigger.shouldResolve(input(probed: nil, last: nil, hasAnswer: true)))
    }

    @Test("A long stretch refreshes even with nothing else changing")
    func staleness() {
        #expect(!DriveTrigger.shouldResolve(input(metres: DriveTrigger.staleDistanceMeters - 1)))
        #expect(DriveTrigger.shouldResolve(input(metres: DriveTrigger.staleDistanceMeters + 1)))
    }

    @Test("A failed jurisdiction lookup is not mistaken for leaving the county")
    func nilCountyIsNotACrossing() {
        // TIGERweb being briefly unreachable must not read as having crossed a line, or a
        // patchy connection would trigger a full resolve on every fix.
        #expect(!DriveTrigger.shouldResolve(input(county: nil, lastCounty: "04013")))
    }
}
