import Foundation
import Testing
@testable import RoadCore

private let source = Provenance(sourceID: "test", sourceName: "Test DOT",
                                url: URL(string: "https://example.org/q")!,
                                fetchedAt: Date(timeIntervalSince1970: 1_757_000_000),
                                isBundled: false)

private func record(_ owner: RoadOwner?) -> RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
    record.owner = owner.map { Attributed($0, provenance: source) }
    return record
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Noon UTC on 1 September 2026, plus `n` days.
private func day(_ n: Int, hour: Int = 12) -> Date {
    Date(timeIntervalSince1970: 1_788_220_800 + Double(n) * 86_400 + Double(hour) * 3_600)
}

private func answered(onDays days: [Int], owner: RoadOwner? = .state(agency: "TxDOT")) -> ReviewPrompt {
    var prompt = ReviewPrompt()
    for n in days { prompt.note(record(owner), on: day(n), calendar: utc) }
    return prompt
}

@Suite("When the app may ask for a rating")
struct ReviewPromptTests {
    @Test("A brand-new user is never asked")
    func freshInstall() {
        #expect(!ReviewPrompt().shouldAsk(appVersion: "1.0.1", isDriving: false))
    }

    @Test("Answers on three different days earn the ask")
    func threeDays() {
        #expect(answered(onDays: [0, 2, 5]).shouldAsk(appVersion: "1.0.1", isDriving: false))
    }

    @Test("Many lookups in one sitting count as one day")
    func oneBusyDay() {
        // Someone exploring the map on day one drops twenty pins; that is one day of use,
        // not twenty, and the ask should wait for them to come back.
        var prompt = ReviewPrompt()
        for hour in 0..<20 { prompt.note(record(.county(agency: "MCDOT")), on: day(0, hour: hour % 24), calendar: utc) }
        prompt.note(record(.county(agency: "MCDOT")), on: day(1), calendar: utc)
        #expect(!prompt.shouldAsk(appVersion: "1.0.1", isDriving: false))
    }

    @Test("An empty or undetermined answer does not count")
    func emptyAnswers() {
        #expect(!answered(onDays: [0, 1, 2], owner: nil).shouldAsk(appVersion: "1.0.1", isDriving: false))
        #expect(!answered(onDays: [0, 1, 2], owner: .undetermined).shouldAsk(appVersion: "1.0.1", isDriving: false))
    }

    @Test("Unmaintained and private roads are real answers")
    func negativeAnswersCount() {
        // A Class VI road coming back "not publicly maintained" is the app at its best.
        #expect(answered(onDays: [0, 1, 2], owner: .notPubliclyMaintained).shouldAsk(appVersion: "1.0.1", isDriving: false))
        #expect(answered(onDays: [0, 1, 2], owner: .privateOwner).shouldAsk(appVersion: "1.0.1", isDriving: false))
    }

    @Test("Never while driving")
    func notWhileDriving() {
        #expect(!answered(onDays: [0, 1, 2]).shouldAsk(appVersion: "1.0.1", isDriving: true))
    }

    @Test("Asked once per version, and again after an update")
    func oncePerVersion() {
        var prompt = answered(onDays: [0, 1, 2])
        prompt.markAsked(appVersion: "1.0.1")
        #expect(!prompt.shouldAsk(appVersion: "1.0.1", isDriving: false))
        #expect(prompt.shouldAsk(appVersion: "1.1", isDriving: false))
    }

    @Test("Only the most recent days are kept, and state round-trips through JSON")
    func persistence() throws {
        let prompt = answered(onDays: [0, 1, 2, 3, 4, 5, 6])
        #expect(prompt.answeredDays == ["2026-09-05", "2026-09-06", "2026-09-07"])
        let decoded = try JSONDecoder().decode(ReviewPrompt.self, from: JSONEncoder().encode(prompt))
        #expect(decoded == prompt)
    }
}
