import Foundation
import SwiftData
import Testing

@testable import SplitFree

@Suite("Sync fingerprints")
struct SyncFingerprintTests {

    /// The values below were computed from the FNV-1a specification, not from
    /// either app, and `SyncFingerprintTest.kt` asserts the same ones against
    /// the same inputs.
    ///
    /// If the two implementations ever drift apart, each app decides the other's
    /// rows have changed and pushes them back, forever - with no error, no wrong
    /// number on screen, and nothing to notice except a group that never stops
    /// syncing. That is why this is pinned to fixed values rather than to
    /// "whatever this platform computes twice in a row".
    @Test("Matches the vectors the Android app also has to produce")
    func sharedVectors() {
        #expect(SyncFingerprint.of([""]) == "cbf29ce484222325")
        #expect(SyncFingerprint.of(["Lisbon", "trip", "42"]) == "acaeb607516495a3")
        #expect(SyncFingerprint.of(["Café", "Ünïcode", "日本語"]) == "3c391f6a60531fa9")
    }

    @Test("The same contents always fingerprint the same way")
    func stable() {
        let a = SyncFingerprint.of(["Lisbon", "trip", "42"])
        let b = SyncFingerprint.of(["Lisbon", "trip", "42"])
        #expect(a == b)
    }

    @Test("A different value changes the fingerprint")
    func sensitive() {
        #expect(SyncFingerprint.of(["Lisbon", "42"]) != SyncFingerprint.of(["Lisbon", "43"]))
    }

    /// Without a separator, ["ab", "c"] and ["a", "bc"] would hash identically,
    /// and two different rosters would look like the same roster.
    @Test("Field boundaries are part of the fingerprint")
    func boundaries() {
        #expect(SyncFingerprint.of(["ab", "c"]) == "fd64a883ef221576")
        #expect(SyncFingerprint.of(["a", "bc"]) == "b6691782144715c4")
    }

    @Test("Sub-second precision is dropped, because Postgres won't return it")
    func secondResolution() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(SyncFingerprint.stamp(base) == SyncFingerprint.stamp(base.addingTimeInterval(0.4)))
        #expect(SyncFingerprint.stamp(base) != SyncFingerprint.stamp(base.addingTimeInterval(2)))
    }
}

@Suite("Join codes")
struct JoinCodeTests {

    /// A code is read aloud and typed back in. Grouping it in fives is the
    /// difference between that working and not.
    @Test("A ten character code is shown in two groups of five")
    func formatting() {
        #expect(Invite(code: "ABCDEFGHJK").formattedCode == "ABCDE-FGHJK")
    }

    @Test("Anything that is not a code character is dropped from the display")
    func formattingIgnoresPunctuation() {
        #expect(Invite(code: "abcde-fghjk").formattedCode == "ABCDE-FGHJK")
    }

    @Test("The link carries the code in the fragment, where servers never see it")
    func linkShape() {
        let url = Invite(code: "ABCDEFGHJK").url
        #expect(url.fragment == "ABCDEFGHJK")
        #expect(url.host == "splitfree.dev")
    }
}

@Suite("Invite links")
struct InviteLinkTests {

    @Test("A web link carries its token in the fragment, where servers never see it")
    func webLink() {
        let url = URL(string: "https://splitfree.dev/join#abc123")!
        #expect(SyncEngine.inviteToken(from: url) == "abc123")
    }

    @Test("Links from builds that predate splitfree.dev still resolve")
    func legacyWebLink() {
        let url = URL(string: "https://devesh-aggarwal.github.io/splitfree/join.html#abc123")!
        #expect(SyncEngine.inviteToken(from: url) == "abc123")
    }

    @Test("The custom scheme works too, for links opened inside the app")
    func customScheme() {
        #expect(SyncEngine.inviteToken(from: URL(string: "splitfree://join#abc123")!) == "abc123")
    }

    @Test("An unrelated link is not mistaken for an invite")
    func unrelated() {
        #expect(SyncEngine.inviteToken(from: URL(string: "https://example.com/join#abc")!) == nil)
        #expect(SyncEngine.inviteToken(from: URL(string: "splitfree://auth-callback#tok")!) == nil)
    }
}

@Suite("Server timestamps")
struct TimestampTests {

    /// Postgres returns six fractional digits. `ISO8601DateFormatter` accepts
    /// three, and returns nil rather than rounding, so the cursor would never
    /// advance and every sync would re-fetch the whole history.
    @Test("A Postgres timestamp with microseconds parses")
    func microseconds() throws {
        let date = try #require(SyncEngine.date(from: "2026-08-12T04:05:06.123456+00:00"))
        let expected = try #require(SyncEngine.date(from: "2026-08-12T04:05:06.123Z"))
        #expect(abs(date.timeIntervalSince(expected)) < 0.001)
    }

    @Test("A timestamp with no fractional part parses")
    func whole() {
        #expect(SyncEngine.date(from: "2026-08-12T04:05:06Z") != nil)
    }

    @Test("A timestamp survives a round trip")
    func roundTrip() throws {
        let original = Date(timeIntervalSince1970: 1_765_432_109)
        let parsed = try #require(SyncEngine.date(from: SyncEngine.timestamp(original)))
        #expect(abs(parsed.timeIntervalSince(original)) < 0.001)
    }

    @Test("Nonsense is rejected rather than silently becoming a date")
    func rejectsGarbage() {
        #expect(SyncEngine.date(from: "-infinity") == nil)
        #expect(SyncEngine.date(from: "") == nil)
    }
}

@Suite("Expense fingerprints")
@MainActor
struct ExpenseFingerprintTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Participant.self, SpendingGroup.self, Expense.self, ExpensePayer.self,
            ExpenseShare.self, ExpenseLineItem.self, ExpenseComment.self,
            Settlement.self, RecurringRule.self, SplitTemplate.self, ActivityEntry.self,
            SyncTombstone.self,
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        ))
    }

    private func makeExpense(in context: ModelContext) -> (Expense, Participant, Participant) {
        let ana = Participant(name: "Ana")
        let ben = Participant(name: "Ben")
        context.insert(ana)
        context.insert(ben)

        let expense = Expense(title: "Dinner", amountMinorUnits: 5000, currencyCode: "USD")
        context.insert(expense)
        for (person, amount) in [(ana, 5000), (ben, 0)] where amount > 0 {
            let payer = ExpensePayer(participant: person, amountMinorUnits: amount)
            payer.expense = expense
            context.insert(payer)
        }
        for person in [ana, ben] {
            let share = ExpenseShare(participant: person, amountMinorUnits: 2500)
            share.expense = expense
            context.insert(share)
        }
        return (expense, ana, ben)
    }

    @Test("An untouched expense keeps its fingerprint, so it is not re-uploaded forever")
    func unchanged() throws {
        let context = try makeContext()
        let (expense, _, _) = makeExpense(in: context)
        let first = expense.syncFingerprint(memberID: \.id)
        let second = expense.syncFingerprint(memberID: \.id)
        #expect(first == second)
    }

    /// The point of a fingerprint over a dirty flag: an edit anywhere in the
    /// expense is detected without anyone having to remember to mark it.
    @Test("Changing the amount changes the fingerprint")
    func amountChange() throws {
        let context = try makeContext()
        let (expense, _, _) = makeExpense(in: context)
        let before = expense.syncFingerprint(memberID: \.id)
        expense.amountMinorUnits = 6000
        #expect(expense.syncFingerprint(memberID: \.id) != before)
    }

    @Test("Changing one person's share changes the fingerprint")
    func shareChange() throws {
        let context = try makeContext()
        let (expense, _, _) = makeExpense(in: context)
        let before = expense.syncFingerprint(memberID: \.id)
        expense.shareList.first?.amountMinorUnits = 3000
        #expect(expense.syncFingerprint(memberID: \.id) != before)
    }

    @Test("Reordering the same shares does not look like an edit")
    func reorderIsNotAnEdit() throws {
        let context = try makeContext()
        let (expense, _, _) = makeExpense(in: context)
        let before = expense.syncFingerprint(memberID: \.id)
        expense.shares = expense.shareList.reversed()
        #expect(expense.syncFingerprint(memberID: \.id) == before)
    }

    @Test("A group hashes to the value the Android app also produces")
    func groupVector() throws {
        let context = try makeContext()
        let ana = Participant(name: "Ana", colorIndex: 0, isCurrentUser: true)
        ana.id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        context.insert(ana)

        let group = SpendingGroup(name: "Lisbon Trip", kind: .trip, colorIndex: 2, members: [ana])
        group.id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        group.defaultCurrencyCode = "EUR"
        group.simplifyDebts = true
        context.insert(group)

        #expect(group.syncFingerprint(memberID: \.id) == "600fa776858d704f")
    }

    @Test("A group's fingerprint covers its roster, because the roster is pushed with it")
    func rosterIsPartOfTheGroup() throws {
        let context = try makeContext()
        let ana = Participant(name: "Ana")
        let ben = Participant(name: "Ben")
        context.insert(ana)
        context.insert(ben)

        let group = SpendingGroup(name: "Lisbon", members: [ana])
        context.insert(group)
        let before = group.syncFingerprint(memberID: \.id)

        group.members?.append(ben)
        #expect(group.syncFingerprint(memberID: \.id) != before)

        let renamed = group.syncFingerprint(memberID: \.id)
        ben.name = "Benedict"
        #expect(group.syncFingerprint(memberID: \.id) != renamed)
    }
}
