import Foundation

/// A stable hash of a row's syncable contents.
///
/// Swift's own `hashValue` is seeded per process, so it changes every launch and
/// is useless for deciding what has already been uploaded. This is FNV-1a over a
/// canonical string, which gives the same answer on every launch and on both
/// platforms - the Android app computes the identical value from the identical
/// fields, so a group that round-trips between an iPhone and a Pixel doesn't
/// re-upload itself forever.
enum SyncFingerprint {
    static func of(_ parts: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "\u{1}").utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// Dates are truncated to the second. Sub-second precision does not survive
    /// the round trip through Postgres, and keeping it would make every row look
    /// permanently changed. Truncated rather than rounded so it matches Kotlin's
    /// integer division on the other side.
    static func stamp(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }
}

extension SpendingGroup {
    /// Includes the roster, because a member added or renamed is a change to the
    /// group as far as the server is concerned - the whole roster is pushed with
    /// it, so the whole roster has to be part of what marks it dirty.
    func syncFingerprint(memberID: (Participant) -> UUID) -> String {
        var parts = [
            name,
            kindRaw,
            String(colorIndex),
            defaultCurrencyCode,
            simplifyDebts ? "1" : "0",
            notes,
            isArchived ? "1" : "0",
            isDirect ? "1" : "0",
        ]
        for person in memberList {
            parts.append(memberID(person).uuidString.lowercased())
            parts.append(person.fullName)
            parts.append(String(person.colorIndex))
        }
        return SyncFingerprint.of(parts)
    }
}

/// Anything that points at one person and carries an amount.
private protocol ParticipantHolder { var participant: Participant? { get } }
extension ExpensePayer: ParticipantHolder {}
extension ExpenseShare: ParticipantHolder {}

/// The sort key for allocations: who it belongs to, not which local row holds
/// it. Empty for an allocation whose person has been deleted, which sorts first
/// and is stable.
private func memberIDString(_ holder: ParticipantHolder, _ memberID: (Participant) -> UUID) -> String {
    holder.participant.map { memberID($0).uuidString.lowercased() } ?? ""
}

extension Expense {
    func syncFingerprint(memberID: (Participant) -> UUID) -> String {
        var parts = [
            title,
            notes,
            String(amountMinorUnits),
            currencyCode,
            SyncFingerprint.stamp(date),
            categoryRaw,
            splitMethodRaw,
            String(taxMinorUnits),
            String(tipMinorUnits),
            baseCurrencyCode,
            String(format: "%.6f", exchangeRateToBase),
        ]
        // Sorted by member id, not by row id. Row ids are local: an expense
        // that came down from the server gets fresh payer rows with ids this
        // device invented, and Android invented different ones. Sorting on them
        // would make the two platforms hash the same expense differently and
        // push it back and forth forever.
        for payer in payerList.sorted(by: { memberIDString($0, memberID) < memberIDString($1, memberID) }) {
            parts.append(payer.participant.map { memberID($0).uuidString.lowercased() } ?? "")
            parts.append(String(payer.amountMinorUnits))
        }
        for share in shareList.sorted(by: { memberIDString($0, memberID) < memberIDString($1, memberID) }) {
            parts.append(share.participant.map { memberID($0).uuidString.lowercased() } ?? "")
            parts.append(String(share.amountMinorUnits))
            parts.append(String(format: "%.6f", share.weight))
        }
        for item in lineItemList {
            parts.append(item.id.uuidString.lowercased())
            parts.append(item.name)
            parts.append(String(item.amountMinorUnits))
            parts.append(String(item.quantity))
            parts.append(item.assigneeList.map { memberID($0).uuidString.lowercased() }.sorted().joined(separator: ","))
        }
        return SyncFingerprint.of(parts)
    }
}

extension Settlement {
    func syncFingerprint(memberID: (Participant) -> UUID) -> String {
        SyncFingerprint.of([
            fromParticipant.map { memberID($0).uuidString.lowercased() } ?? "",
            toParticipant.map { memberID($0).uuidString.lowercased() } ?? "",
            String(amountMinorUnits),
            currencyCode,
            SyncFingerprint.stamp(date),
            methodRaw,
            notes,
            baseCurrencyCode,
            String(format: "%.6f", exchangeRateToBase),
        ])
    }
}
