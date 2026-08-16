import Foundation
import SwiftData

/// Moves shared groups between this device and the server.
///
/// The shape is deliberately dull: push what changed here, pull what changed
/// there, resolve ties by the server clock. The device stays the thing you read
/// and write, so every screen works with the network off and sync is something
/// that happens afterwards rather than something the UI waits on.
///
/// Only groups with `isShared` are touched. Everything else stays on the phone,
/// which is what keeps the local-only promise true for people who never sign in.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case unavailable
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .unavailable
    private(set) var lastSyncedAt: Date?
    /// True once this device has an identity, which happens the first time it
    /// shares or joins something.
    private(set) var hasIdentity = false

    private let client: SupabaseClient
    private let defaults: UserDefaults
    private var inFlight = false

    private static let cursorKey = "sync.cursor"
    private static let lastSyncedKey = "sync.lastSyncedAt"

    init(client: SupabaseClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        self.lastSyncedAt = defaults.object(forKey: Self.lastSyncedKey) as? Date
    }

    /// The server time of the last successful pull. Everything changed after it
    /// is what the next pull asks for.
    private var cursor: Date? {
        get { defaults.object(forKey: Self.cursorKey) as? Date }
        set { defaults.set(newValue, forKey: Self.cursorKey) }
    }

    // MARK: - Account

    func refreshState() async {
        guard SupabaseConfig.isConfigured else {
            status = .unavailable
            hasIdentity = false
            return
        }
        _ = await client.restoreSession()
        hasIdentity = await client.isSignedIn
        status = .idle
    }

    /// Makes sure there is an identity before doing something that needs one.
    ///
    /// Sharing and joining call this. The UI never does, which is the point:
    /// there is no screen, and nobody is asked for anything.
    private func ensureIdentity() async throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseError.notConfigured }
        try await client.signInAnonymously()
        hasIdentity = true
    }

    // MARK: - Sync

    /// Runs a full cycle. Safe to call from anywhere; overlapping calls collapse
    /// into the one already running.
    func syncNow(context: ModelContext) async {
        guard SupabaseConfig.isConfigured else { status = .unavailable; return }
        // Nothing shared from this device yet, so there is nothing to sync and
        // no reason to create an identity.
        guard await client.isSignedIn else { return }
        guard !inFlight else { return }

        inFlight = true
        status = .syncing
        defer { inFlight = false }

        do {
            try await pushTombstones(context: context)
            try await pushChanges(context: context)
            try await pull(context: context)

            let now = Date()
            lastSyncedAt = now
            defaults.set(now, forKey: Self.lastSyncedKey)
            status = .idle
        } catch let error as SupabaseError {
            status = .failed(error.localizedDescription)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Turns a local group into a shared one and uploads it, keeping every id the
    /// device already uses so its expenses stay attached to the right people.
    func shareGroup(_ group: SpendingGroup, context: ModelContext) async throws {
        try await ensureIdentity()

        let members = group.memberList.map { person in
            [
                "member_id": memberID(for: person, in: group).uuidString.lowercased(),
                "display_name": person.fullName,
                "color_index": person.colorIndex,
                "is_me": person.isCurrentUser,
            ] as [String: Any]
        }

        _ = try await client.rpc("adopt_local_group", arguments: [
            "p_group_id": group.id.uuidString.lowercased(),
            "p_name": group.name,
            "p_kind": group.kind.rawValue,
            "p_color_index": group.colorIndex,
            "p_currency_code": group.defaultCurrencyCode,
            "p_simplify_debts": group.simplifyDebts,
            "p_members": members,
            "p_is_direct": group.isDirect,
        ])

        group.isShared = true
        group.updatedAt = Date()
        group.syncedFingerprint = ""
        // Everything inside it now needs uploading, whenever it was last edited.
        for expense in group.expenseList { expense.syncedFingerprint = "" }
        for settlement in group.settlementList { settlement.syncedFingerprint = "" }
        try? context.save()

        await syncNow(context: context)
    }

    // MARK: - Invites

    /// What an invite link points at, shown before anyone commits to joining.
    struct InvitePreview {
        var groupID: UUID
        var groupName: String
        var groupKind: GroupKind
        var memberCount: Int
        /// The name of the slot being handed over, when the inviter reserved one.
        var claimsMemberName: String?
        var alreadyMember: Bool
    }

    func createInvite(for group: SpendingGroup, claiming member: Participant?) async throws -> Invite {
        try await ensureIdentity()
        var arguments: [String: Any] = ["p_group_id": group.id.uuidString.lowercased()]
        if let member {
            arguments["p_member_id"] = memberID(for: member, in: group).uuidString.lowercased()
        }
        let data = try await client.rpc("create_invite", arguments: arguments)
        guard let code = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? String
        else { throw SupabaseError.decoding("create_invite") }
        return Invite(code: code)
    }

    func previewInvite(token: String) async throws -> InvitePreview {
        try await ensureIdentity()
        let data = try await client.rpc("preview_invite", arguments: ["p_token": token])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groupID = (json["group_id"] as? String).flatMap(UUID.init(uuidString:))
        else { throw SupabaseError.decoding("preview_invite") }

        return InvitePreview(
            groupID: groupID,
            groupName: json["group_name"] as? String ?? "",
            groupKind: GroupKind(rawValue: json["group_kind"] as? String ?? "") ?? .other,
            memberCount: Self.int(json["member_count"]),
            claimsMemberName: json["claims_member_name"] as? String,
            alreadyMember: json["already_member"] as? Bool ?? false
        )
    }

    @discardableResult
    func redeemInvite(token: String, context: ModelContext) async throws -> UUID {
        try await ensureIdentity()
        let data = try await client.rpc("redeem_invite", arguments: [
            "p_token": token,
            "p_display_name": Ledger.currentUser(in: context).fullName,
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groupID = (json["group_id"] as? String).flatMap(UUID.init(uuidString:))
        else { throw SupabaseError.decoding("redeem_invite") }

        // The group and everything in it arrive on the next pull. Reaching for
        // it here rather than waiting for a timer is what makes joining feel
        // like the group appeared instantly.
        await syncNow(context: context)
        return groupID
    }

    /// Pulls the token out of a link, whichever form it arrived in.
    nonisolated static func inviteToken(from url: URL) -> String? {
        if url.scheme == "splitfree", url.host == "join" {
            return url.fragment ?? url.lastPathComponent
        }
        // splitfree.dev is the current home; github.io links from older
        // builds keep working for as long as the old page redirects.
        if url.host == "splitfree.dev" || url.host?.hasSuffix("github.io") == true,
           url.path.contains("/join") {
            return url.fragment
        }
        return nil
    }

    // MARK: - Push

    private func pushTombstones(context: ModelContext) async throws {
        let pending = ((try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? [])
            .filter { !$0.isPushed }
        guard !pending.isEmpty else { return }

        for tombstone in pending {
            do {
                _ = try await client.rpc("mark_deleted", arguments: [
                    "p_entity": tombstone.entityRaw,
                    "p_id": tombstone.entityID.uuidString.lowercased(),
                    "p_group_id": tombstone.groupID?.uuidString.lowercased() as Any,
                ])
                tombstone.isPushed = true
            } catch SupabaseError.http(let code, _) where (400..<500).contains(code) {
                // The server will not accept this tombstone and never will -
                // the row was never uploaded, or the group is gone. Retrying it
                // on every sync forever helps nobody.
                tombstone.isPushed = true
            }
        }
        try? context.save()

        // Keep pushed tombstones for a month so a late edit to something you
        // deleted can be recognised and ignored rather than resurrecting it.
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        for tombstone in pending where tombstone.isPushed && tombstone.deletedAt < cutoff {
            context.delete(tombstone)
        }
        try? context.save()
    }

    private func pushChanges(context: ModelContext) async throws {
        let groups = ((try? context.fetch(FetchDescriptor<SpendingGroup>())) ?? [])
            .filter(\.isShared)
        guard !groups.isEmpty else { return }

        var groupRows: [[String: Any]] = []
        var memberRows: [[String: Any]] = []
        var pushedGroups: [SpendingGroup] = []

        for group in groups where group.syncFingerprint(memberID: serverIDs(in: group)) != group.syncedFingerprint {
            groupRows.append([
                "id": group.id.uuidString.lowercased(),
                "name": group.name,
                "kind": group.kind.rawValue,
                "color_index": group.colorIndex,
                "default_currency_code": group.defaultCurrencyCode,
                "simplify_debts": group.simplifyDebts,
                "notes": group.notes,
                "is_archived": group.isArchived,
                "is_direct": group.isDirect,
            ])
            pushedGroups.append(group)
        }

        // The roster travels with its group. It is small, and sending it whole
        // avoids having to track which individual member rows changed.
        for group in pushedGroups {
            for person in group.memberList {
                memberRows.append([
                    "group_id": group.id.uuidString.lowercased(),
                    "member_id": memberID(for: person, in: group).uuidString.lowercased(),
                    "display_name": person.fullName,
                    "color_index": person.colorIndex,
                ])
            }
        }

        if !groupRows.isEmpty {
            try await client.upsert(table: "groups", rows: groupRows, onConflict: "id")
        }
        if !memberRows.isEmpty {
            try await client.upsert(table: "group_members", rows: memberRows, onConflict: "group_id,member_id")
        }
        for group in pushedGroups {
            group.syncedFingerprint = group.syncFingerprint(memberID: serverIDs(in: group))
        }

        // Expenses
        var expenseRows: [[String: Any]] = []
        var pushedExpenses: [(Expense, SpendingGroup)] = []
        for group in groups {
            for expense in group.expenseList
            where expense.syncFingerprint(memberID: serverIDs(in: group)) != expense.syncedFingerprint {
                guard let row = expenseRow(expense, in: group) else { continue }
                expenseRows.append(row)
                pushedExpenses.append((expense, group))
            }
        }
        if !expenseRows.isEmpty {
            try await client.upsert(table: "expenses", rows: expenseRows, onConflict: "id")
        }
        for (expense, group) in pushedExpenses {
            expense.syncedFingerprint = expense.syncFingerprint(memberID: serverIDs(in: group))
        }

        // Settlements
        var settlementRows: [[String: Any]] = []
        var pushedSettlements: [(Settlement, SpendingGroup)] = []
        for group in groups {
            for settlement in group.settlementList
            where settlement.syncFingerprint(memberID: serverIDs(in: group)) != settlement.syncedFingerprint {
                guard let from = settlement.fromParticipant,
                      let to = settlement.toParticipant,
                      settlement.amountMinorUnits > 0
                else { continue }
                settlementRows.append([
                    "id": settlement.id.uuidString.lowercased(),
                    "group_id": group.id.uuidString.lowercased(),
                    "from_member_id": memberID(for: from, in: group).uuidString.lowercased(),
                    "to_member_id": memberID(for: to, in: group).uuidString.lowercased(),
                    "amount_minor_units": settlement.amountMinorUnits,
                    "currency_code": settlement.currencyCode,
                    "date": Self.timestamp(settlement.date),
                    "method": settlement.method.rawValue,
                    "notes": settlement.notes,
                    "base_currency_code": settlement.baseCurrencyCode,
                    "exchange_rate_to_base": settlement.exchangeRateToBase,
                ])
                pushedSettlements.append((settlement, group))
            }
        }
        if !settlementRows.isEmpty {
            try await client.upsert(table: "settlements", rows: settlementRows, onConflict: "id")
        }
        for (settlement, group) in pushedSettlements {
            settlement.syncedFingerprint = settlement.syncFingerprint(memberID: serverIDs(in: group))
        }

        try? context.save()
    }

    /// Builds the row for an expense, or nil if it would violate the invariant
    /// the database enforces.
    ///
    /// Refusing to send a split that doesn't add up is better than letting the
    /// server reject the whole batch: one malformed expense would otherwise stop
    /// every other expense in the same push from ever landing.
    private func expenseRow(_ expense: Expense, in group: SpendingGroup) -> [String: Any]? {
        let payers = expense.payerList.compactMap { payer -> [String: Any]? in
            guard let person = payer.participant else { return nil }
            return [
                "participantId": memberID(for: person, in: group).uuidString.lowercased(),
                "amountMinorUnits": payer.amountMinorUnits,
            ]
        }
        let shares = expense.shareList.compactMap { share -> [String: Any]? in
            guard let person = share.participant else { return nil }
            return [
                "participantId": memberID(for: person, in: group).uuidString.lowercased(),
                "amountMinorUnits": share.amountMinorUnits,
                "weight": share.weight,
            ]
        }

        let payerTotal = payers.reduce(0) { $0 + (($1["amountMinorUnits"] as? Int) ?? 0) }
        let shareTotal = shares.reduce(0) { $0 + (($1["amountMinorUnits"] as? Int) ?? 0) }
        guard expense.amountMinorUnits > 0,
              payerTotal == expense.amountMinorUnits,
              shareTotal == expense.amountMinorUnits
        else { return nil }

        let items = expense.lineItemList.map { item -> [String: Any] in
            [
                "id": item.id.uuidString.lowercased(),
                "name": item.name,
                "amountMinorUnits": item.amountMinorUnits,
                "quantity": item.quantity,
                "sortOrder": item.sortOrder,
                "assignees": item.assigneeList.map { memberID(for: $0, in: group).uuidString.lowercased() },
            ]
        }

        return [
            "id": expense.id.uuidString.lowercased(),
            "group_id": group.id.uuidString.lowercased(),
            "title": expense.title,
            "notes": expense.notes,
            "amount_minor_units": expense.amountMinorUnits,
            "currency_code": expense.currencyCode,
            "date": Self.timestamp(expense.date),
            "category": expense.category.rawValue,
            "split_method": expense.splitMethod.rawValue,
            "tax_minor_units": expense.taxMinorUnits,
            "tip_minor_units": expense.tipMinorUnits,
            "base_currency_code": expense.baseCurrencyCode,
            "exchange_rate_to_base": expense.exchangeRateToBase,
            "payers": payers,
            "shares": shares,
            "items": items,
        ]
    }

    // MARK: - Pull

    private func pull(context: ModelContext) async throws {
        let since = cursor.map(Self.timestamp) ?? "-infinity"
        let data = try await client.rpc("pull_changes", arguments: ["since": since])

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseError.decoding("pull_changes")
        }

        let myUserID = await client.userID

        // Order matters: groups before members before the rows that reference
        // them, so nothing arrives pointing at something that isn't there yet.
        applyGroups(payload["groups"] as? [[String: Any]] ?? [], context: context)
        applyMembers(payload["members"] as? [[String: Any]] ?? [], myUserID: myUserID, context: context)
        applyExpenses(payload["expenses"] as? [[String: Any]] ?? [], context: context)
        applySettlements(payload["settlements"] as? [[String: Any]] ?? [], context: context)

        try? context.save()

        if let serverTime = (payload["server_time"] as? String).flatMap(Self.date(from:)) {
            cursor = serverTime
        }
    }

    private func applyGroups(_ rows: [[String: Any]], context: ModelContext) {
        for row in rows {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) else { continue }
            let existing = fetchGroup(id, context: context)

            if row["deleted_at"] is String {
                if let existing { context.delete(existing) }
                continue
            }
            guard !isDeletedLocally(id, context: context) else { continue }

            let group = existing ?? {
                let fresh = SpendingGroup(name: "")
                fresh.id = id
                context.insert(fresh)
                return fresh
            }()

            // A local edit that hasn't been pushed yet wins for now; the next
            // push sends it and the server decides the final order.
            guard group.syncFingerprint(memberID: serverIDs(in: group)) == group.syncedFingerprint else { continue }

            group.name = row["name"] as? String ?? group.name
            group.kindRaw = row["kind"] as? String ?? group.kindRaw
            group.colorIndex = row["color_index"] as? Int ?? group.colorIndex
            group.defaultCurrencyCode = row["default_currency_code"] as? String ?? group.defaultCurrencyCode
            group.simplifyDebts = row["simplify_debts"] as? Bool ?? group.simplifyDebts
            group.notes = row["notes"] as? String ?? group.notes
            group.isArchived = row["is_archived"] as? Bool ?? group.isArchived
            group.isDirect = row["is_direct"] as? Bool ?? group.isDirect
            group.isShared = true
            if let stamp = (row["updated_at"] as? String).flatMap(Self.date(from:)) {
                group.updatedAt = stamp
            }
            group.syncedFingerprint = group.syncFingerprint(memberID: serverIDs(in: group))
        }
    }

    private func applyMembers(_ rows: [[String: Any]], myUserID: String?, context: ModelContext) {
        let me = Ledger.currentUser(in: context)

        for row in rows {
            guard let groupID = (row["group_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let memberID = (row["member_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let group = fetchGroup(groupID, context: context)
            else { continue }

            let userID = row["user_id"] as? String

            // This slot is me. Record which id the group uses for me instead of
            // making a second copy of myself.
            if let userID, let myUserID, userID == myUserID {
                group.myMemberIDRaw = memberID.uuidString
                if !group.memberList.contains(where: { $0.id == me.id }) {
                    group.members?.append(me)
                }
                if me.remoteUserID == nil { me.remoteUserID = userID }
                continue
            }

            if row["deleted_at"] is String {
                group.members?.removeAll { $0.id == memberID }
                continue
            }

            let person = fetchParticipant(memberID, context: context) ?? {
                let fresh = Participant(name: row["display_name"] as? String ?? "")
                fresh.id = memberID
                fresh.colorIndex = row["color_index"] as? Int ?? 0
                context.insert(fresh)
                return fresh
            }()
            person.remoteUserID = userID
            if person.name.isEmpty, let name = row["display_name"] as? String { person.name = name }

            if !group.memberList.contains(where: { $0.id == person.id }) {
                group.members?.append(person)
            }
        }
    }

    private func applyExpenses(_ rows: [[String: Any]], context: ModelContext) {
        for row in rows {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) else { continue }
            let existing = fetchExpense(id, context: context)

            if row["deleted_at"] is String {
                if let existing { context.delete(existing) }
                continue
            }
            guard !isDeletedLocally(id, context: context) else { continue }
            guard let groupID = (row["group_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let group = fetchGroup(groupID, context: context)
            else { continue }

            let expense = existing ?? {
                let fresh = Expense()
                fresh.id = id
                context.insert(fresh)
                return fresh
            }()
            guard expense.syncedFingerprint.isEmpty
                    || expense.syncFingerprint(memberID: serverIDs(in: group)) == expense.syncedFingerprint
            else { continue }

            expense.group = group
            expense.title = row["title"] as? String ?? ""
            expense.notes = row["notes"] as? String ?? ""
            expense.amountMinorUnits = Self.int(row["amount_minor_units"])
            expense.currencyCode = row["currency_code"] as? String ?? "USD"
            expense.categoryRaw = row["category"] as? String ?? ExpenseCategory.general.rawValue
            expense.splitMethodRaw = row["split_method"] as? String ?? SplitMethod.equal.rawValue
            expense.taxMinorUnits = Self.int(row["tax_minor_units"])
            expense.tipMinorUnits = Self.int(row["tip_minor_units"])
            expense.baseCurrencyCode = row["base_currency_code"] as? String ?? expense.currencyCode
            expense.exchangeRateToBase = (row["exchange_rate_to_base"] as? Double) ?? 1
            if let date = (row["date"] as? String).flatMap(Self.date(from:)) { expense.date = date }

            rebuildAllocations(of: expense, from: row, in: group, context: context)

            if let stamp = (row["updated_at"] as? String).flatMap(Self.date(from:)) {
                expense.updatedAt = stamp
            }
            expense.syncedFingerprint = expense.syncFingerprint(memberID: serverIDs(in: group))
        }
    }

    /// Replaces an expense's payers, shares and line items with what the server
    /// sent. They are rebuilt rather than merged: a person removed from the
    /// split upstream has no row to match against, and merging would leave them
    /// behind with a stale share.
    private func rebuildAllocations(
        of expense: Expense,
        from row: [String: Any],
        in group: SpendingGroup,
        context: ModelContext
    ) {
        for payer in expense.payerList { context.delete(payer) }
        for share in expense.shareList { context.delete(share) }
        for item in expense.lineItemList { context.delete(item) }
        expense.payers = []
        expense.shares = []
        expense.lineItems = []

        for entry in row["payers"] as? [[String: Any]] ?? [] {
            guard let person = participant(forMemberID: entry["participantId"], in: group, context: context)
            else { continue }
            let payer = ExpensePayer(participant: person, amountMinorUnits: Self.int(entry["amountMinorUnits"]))
            payer.expense = expense
            context.insert(payer)
        }
        for entry in row["shares"] as? [[String: Any]] ?? [] {
            guard let person = participant(forMemberID: entry["participantId"], in: group, context: context)
            else { continue }
            let share = ExpenseShare(
                participant: person,
                amountMinorUnits: Self.int(entry["amountMinorUnits"]),
                weight: (entry["weight"] as? Double) ?? 0
            )
            share.expense = expense
            context.insert(share)
        }
        for entry in row["items"] as? [[String: Any]] ?? [] {
            let item = ExpenseLineItem(
                name: entry["name"] as? String ?? "",
                amountMinorUnits: Self.int(entry["amountMinorUnits"]),
                quantity: Self.int(entry["quantity"], default: 1),
                sortOrder: Self.int(entry["sortOrder"]),
                assignees: (entry["assignees"] as? [String] ?? []).compactMap {
                    participant(forMemberID: $0, in: group, context: context)
                }
            )
            if let id = (entry["id"] as? String).flatMap(UUID.init(uuidString:)) { item.id = id }
            item.expense = expense
            context.insert(item)
        }
    }

    private func applySettlements(_ rows: [[String: Any]], context: ModelContext) {
        for row in rows {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) else { continue }
            let existing = fetchSettlement(id, context: context)

            if row["deleted_at"] is String {
                if let existing { context.delete(existing) }
                continue
            }
            guard !isDeletedLocally(id, context: context) else { continue }
            guard let groupID = (row["group_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let group = fetchGroup(groupID, context: context),
                  let from = participant(forMemberID: row["from_member_id"], in: group, context: context),
                  let to = participant(forMemberID: row["to_member_id"], in: group, context: context)
            else { continue }

            let settlement = existing ?? {
                let fresh = Settlement(
                    from: from,
                    to: to,
                    amountMinorUnits: 0,
                    currencyCode: "USD",
                    group: group
                )
                fresh.id = id
                context.insert(fresh)
                return fresh
            }()
            guard settlement.syncedFingerprint.isEmpty
                    || settlement.syncFingerprint(memberID: serverIDs(in: group)) == settlement.syncedFingerprint
            else { continue }

            settlement.group = group
            settlement.fromParticipant = from
            settlement.toParticipant = to
            settlement.amountMinorUnits = Self.int(row["amount_minor_units"])
            settlement.currencyCode = row["currency_code"] as? String ?? "USD"
            settlement.methodRaw = row["method"] as? String ?? PaymentMethod.cash.rawValue
            settlement.notes = row["notes"] as? String ?? ""
            settlement.baseCurrencyCode = row["base_currency_code"] as? String ?? settlement.currencyCode
            settlement.exchangeRateToBase = (row["exchange_rate_to_base"] as? Double) ?? 1
            if let date = (row["date"] as? String).flatMap(Self.date(from:)) { settlement.date = date }
            if let stamp = (row["updated_at"] as? String).flatMap(Self.date(from:)) {
                settlement.updatedAt = stamp
            }
            settlement.syncedFingerprint = settlement.syncFingerprint(memberID: serverIDs(in: group))
        }
    }

    // MARK: - Identity

    /// Curried form of `memberID(for:in:)`, for the fingerprint extensions.
    /// Each of them hashes the *server's* view of who someone is, so a group you
    /// joined under a slot somebody else made still fingerprints consistently.
    private func serverIDs(in group: SpendingGroup) -> (Participant) -> UUID {
        { [self] person in memberID(for: person, in: group) }
    }

    /// The id the server uses for this person inside this group.
    func memberID(for participant: Participant, in group: SpendingGroup) -> UUID {
        if participant.isCurrentUser, let mine = UUID(uuidString: group.myMemberIDRaw) {
            return mine
        }
        return participant.id
    }

    private func participant(
        forMemberID raw: Any?,
        in group: SpendingGroup,
        context: ModelContext
    ) -> Participant? {
        guard let id = (raw as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        if let mine = UUID(uuidString: group.myMemberIDRaw), mine == id {
            return Ledger.currentUser(in: context)
        }
        return fetchParticipant(id, context: context)
    }

    // MARK: - Lookups

    private func fetchGroup(_ id: UUID, context: ModelContext) -> SpendingGroup? {
        try? context.fetch(FetchDescriptor<SpendingGroup>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchParticipant(_ id: UUID, context: ModelContext) -> Participant? {
        try? context.fetch(FetchDescriptor<Participant>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchExpense(_ id: UUID, context: ModelContext) -> Expense? {
        try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchSettlement(_ id: UUID, context: ModelContext) -> Settlement? {
        try? context.fetch(FetchDescriptor<Settlement>(predicate: #Predicate { $0.id == id })).first
    }

    /// Guards against a row you deleted coming back because someone else touched
    /// it before your tombstone reached the server.
    private func isDeletedLocally(_ id: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SyncTombstone>(predicate: #Predicate { $0.entityID == id })
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    // MARK: - Helpers

    /// `nonisolated(unsafe)` rather than `nonisolated`: `ISO8601DateFormatter`
    /// is not `Sendable`, but its formatting and parsing methods are documented
    /// as thread-safe and this instance is never mutated after creation. The
    /// alternative is allocating a formatter per row, which a large pull would
    /// do thousands of times for no benefit.
    private nonisolated(unsafe) static let outbound: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    nonisolated static func timestamp(_ date: Date) -> String { outbound.string(from: date) }

    /// Parses a Postgres `timestamptz`, which arrives with up to six fractional
    /// digits - more than `ISO8601DateFormatter` will accept.
    nonisolated static func date(from string: String) -> Date? {
        var value = string
        if let dot = value.firstIndex(of: "."),
           let end = value[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = value[value.index(after: dot)..<end]
            if fraction.count > 3 {
                let trimmed = fraction.prefix(3)
                value.replaceSubrange(value.index(after: dot)..<end, with: trimmed)
            }
        }
        if let date = outbound.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        plain.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = plain.date(from: value) { return date }

        // Postgres omits the offset entirely for `-infinity` and friends.
        return nil
    }

    private nonisolated static func int(_ value: Any?, default fallback: Int = 0) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String, let int = Int(string) { return int }
        return fallback
    }
}
