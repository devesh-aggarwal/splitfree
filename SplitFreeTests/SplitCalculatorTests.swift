import Foundation
import Testing

@testable import SplitFree

/// The rule every one of these tests exists to protect: **the allocated amounts
/// must sum exactly to the total**, for every split method, every participant
/// count, and every currency precision.
@Suite("Split calculator")
struct SplitCalculatorTests {

    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    // MARK: - Equal

    @Test("An even split always sums to the total, for any group size")
    func equalSplitIsExact() {
        for total in [0, 1, 7, 100, 1000, 8450, 999_999] {
            for count in 1...12 {
                let people = ids(count)
                let allocations = SplitCalculator.equal(total: total, among: people)
                let sum = allocations.reduce(0) { $0 + $1.amountMinorUnits }
                #expect(sum == total, "total \(total) across \(count) people summed to \(sum)")
                #expect(allocations.count == count)
            }
        }
    }

    @Test("Ten dollars three ways is 3.34 / 3.33 / 3.33, not a lost cent")
    func equalSplitDistributesTheRemainder() {
        let people = ids(3)
        let amounts = SplitCalculator.equal(total: 1000, among: people).map(\.amountMinorUnits)
        #expect(amounts == [334, 333, 333])
    }

    @Test("A negative total splits symmetrically")
    func equalSplitHandlesRefunds() {
        let amounts = SplitCalculator.distributeEvenly(total: -1000, count: 3)
        #expect(amounts == [-334, -333, -333])
        #expect(amounts.reduce(0, +) == -1000)
    }

    @Test("Splitting among nobody produces nothing rather than crashing")
    func equalSplitWithNoParticipants() {
        #expect(SplitCalculator.equal(total: 500, among: []).isEmpty)
        #expect(SplitCalculator.distributeEvenly(total: 500, count: 0).isEmpty)
    }

    // MARK: - Weighted

    @Test("Weighted splits sum exactly, with the leftover going to the largest remainders")
    func weightedSplitIsExact() {
        let people = ids(3)
        let weights = [
            (id: people[0], weight: 1.0),
            (id: people[1], weight: 1.0),
            (id: people[2], weight: 1.0),
        ]
        let allocations = SplitCalculator.weighted(total: 1000, weights: weights)
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 1000)
        #expect(allocations.map(\.amountMinorUnits) == [334, 333, 333])
    }

    @Test("Shares divide in the stated proportion")
    func sharesProportion() {
        let people = ids(2)
        let allocations = SplitCalculator.weighted(
            total: 900,
            weights: [(id: people[0], weight: 2), (id: people[1], weight: 1)]
        )
        #expect(allocations.map(\.amountMinorUnits) == [600, 300])
    }

    @Test("Percentages that don't divide cleanly still sum to the total")
    func percentagesStayExact() {
        let people = ids(3)
        let allocations = SplitCalculator.weighted(
            total: 10_000,
            weights: [
                (id: people[0], weight: 33.33),
                (id: people[1], weight: 33.33),
                (id: people[2], weight: 33.34),
            ]
        )
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 10_000)
    }

    @Test("All-zero weights allocate nothing instead of dividing by zero")
    func zeroWeights() {
        let people = ids(3)
        let allocations = SplitCalculator.weighted(
            total: 1000,
            weights: people.map { (id: $0, weight: 0.0) }
        )
        #expect(allocations.allSatisfy { $0.amountMinorUnits == 0 })
    }

    // MARK: - Adjustment

    @Test("Plus/minus adds personal extras on top of an even split of the rest")
    func adjustmentSplit() {
        let people = ids(3)
        // A $30 bill where one person had a $6 dessert: the other $24 splits
        // three ways at $8 each, and the dessert lands on them alone.
        let allocations = SplitCalculator.adjustment(
            total: 3000,
            entries: [
                (id: people[0], adjustment: 600),
                (id: people[1], adjustment: 0),
                (id: people[2], adjustment: 0),
            ]
        )
        #expect(allocations.map(\.amountMinorUnits) == [1400, 800, 800])
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 3000)
    }

    @Test("Adjustments always reconcile to the total, even when they exceed it")
    func adjustmentAlwaysSumsToTotal() {
        let people = ids(2)
        let allocations = SplitCalculator.adjustment(
            total: 1000,
            entries: [(id: people[0], adjustment: 1500), (id: people[1], adjustment: 0)]
        )
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 1000)
    }

    // MARK: - Itemized

    @Test("Itemizing charges each person for what they had, plus a share of tax and tip")
    func itemizedSplit() {
        let ana = UUID()
        let ben = UUID()
        let items = [
            SplitCalculator.ItemAssignment(amountMinorUnits: 2000, participantIDs: [ana]),
            SplitCalculator.ItemAssignment(amountMinorUnits: 1000, participantIDs: [ben]),
        ]
        // 30.00 of items + 3.00 tax + 3.00 tip = 36.00; extras split 2:1.
        let allocations = SplitCalculator.itemized(
            total: 3600,
            items: items,
            taxMinorUnits: 300,
            tipMinorUnits: 300,
            fallbackParticipants: [ana, ben]
        )
        let byID = Dictionary(uniqueKeysWithValues: allocations.map { ($0.participantID, $0.amountMinorUnits) })
        #expect(byID[ana] == 2400)
        #expect(byID[ben] == 1200)
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 3600)
    }

    @Test("An unassigned item is shared by everyone")
    func itemizedFallsBackToEveryone() {
        let people = ids(3)
        let items = [SplitCalculator.ItemAssignment(amountMinorUnits: 900, participantIDs: [])]
        let allocations = SplitCalculator.itemized(
            total: 900,
            items: items,
            taxMinorUnits: 0,
            tipMinorUnits: 0,
            fallbackParticipants: people
        )
        #expect(allocations.allSatisfy { $0.amountMinorUnits == 300 })
    }

    @Test("Itemized amounts reconcile even when the receipt's own arithmetic is off")
    func itemizedReconcilesAgainstTotal() {
        let people = ids(2)
        let items = [
            SplitCalculator.ItemAssignment(amountMinorUnits: 1000, participantIDs: [people[0]]),
            SplitCalculator.ItemAssignment(amountMinorUnits: 1000, participantIDs: [people[1]]),
        ]
        // The stated total is 5 cents more than the lines add up to.
        let allocations = SplitCalculator.itemized(
            total: 2005,
            items: items,
            taxMinorUnits: 0,
            tipMinorUnits: 0,
            fallbackParticipants: people
        )
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 2005)
    }

    // MARK: - Validation

    @Test("Exact amounts that don't add up are reported, with the shortfall")
    func exactValidation() {
        let people = ids(2)
        let entries = [
            SplitCalculator.Entry(participantID: people[0], isIncluded: true, value: 500),
            SplitCalculator.Entry(participantID: people[1], isIncluded: true, value: 400),
        ]
        let issue = SplitCalculator.validate(method: .exact, total: 1000, currencyCode: "USD", entries: entries)
        #expect(issue == .amountsDontAddUp(remainder: 100, currencyCode: "USD"))
    }

    @Test("Percentages within a rounding hair of 100 are accepted")
    func percentValidationTolerance() {
        let people = ids(3)
        let entries = people.map {
            SplitCalculator.Entry(participantID: $0, isIncluded: true, value: 33.333)
        }
        #expect(SplitCalculator.validate(method: .percent, total: 1000, currencyCode: "USD", entries: entries) == nil)
    }

    @Test("A split with nobody in it is rejected")
    func noOneSelected() {
        let entries = [SplitCalculator.Entry(participantID: UUID(), isIncluded: false, value: 1)]
        #expect(SplitCalculator.validate(method: .equal, total: 1000, currencyCode: "USD", entries: entries) == .noOneSelected)
    }

    // MARK: - Resolve

    @Test("Every split method resolves to amounts that sum to the total")
    func resolveIsAlwaysExact() {
        let people = ids(4)
        let total = 12_345

        for method in [SplitMethod.equal, .percent, .shares, .itemized] {
            let entries = people.map { id in
                SplitCalculator.Entry(
                    participantID: id,
                    isIncluded: true,
                    value: method == .percent ? 25 : 1
                )
            }
            let allocations = SplitCalculator.resolve(
                method: method,
                total: total,
                currencyCode: "USD",
                entries: entries,
                items: [],
                taxMinorUnits: 0,
                tipMinorUnits: 0
            )
            let sum = allocations.reduce(0) { $0 + $1.amountMinorUnits }
            #expect(sum == total, "\(method) summed to \(sum)")
        }
    }

    @Test("Excluded people get nothing")
    func resolveRespectsInclusion() {
        let people = ids(3)
        var entries = people.map { SplitCalculator.Entry(participantID: $0, isIncluded: true, value: 1) }
        entries[2].isIncluded = false

        let allocations = SplitCalculator.resolve(
            method: .equal,
            total: 1000,
            currencyCode: "USD",
            entries: entries
        )
        #expect(allocations.count == 2)
        #expect(!allocations.contains { $0.participantID == people[2] })
        #expect(allocations.reduce(0) { $0 + $1.amountMinorUnits } == 1000)
    }
}
