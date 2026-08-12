import Foundation
import SwiftData

/// CSV export. Everything you put into SplitFree can be taken back out —
/// no account, no export tier, no lock-in.
@MainActor
enum GroupExporter {

    static func csv(for group: SpendingGroup) -> String {
        var rows: [[String]] = [[
            String(localized: "Date"),
            String(localized: "Description"),
            String(localized: "Category"),
            String(localized: "Currency"),
            String(localized: "Amount"),
            String(localized: "Paid by"),
            String(localized: "Split method"),
            String(localized: "Notes"),
        ]]

        let members = group.memberList
        rows[0].append(contentsOf: members.map(\.fullName))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        for entry in group.timeline.reversed() {
            switch entry {
            case .expense(let expense):
                var row = [
                    formatter.string(from: expense.date),
                    expense.displayTitle,
                    expense.category.title,
                    expense.currencyCode,
                    decimalString(expense.amountMinorUnits, currencyCode: expense.currencyCode),
                    expense.payerList.compactMap { $0.participant?.fullName }.joined(separator: " + "),
                    expense.splitMethod.title,
                    expense.notes,
                ]
                // One column per member holding their net position on this row:
                // positive means they're up, negative means they owe.
                for member in members {
                    row.append(decimalString(expense.net(for: member), currencyCode: expense.currencyCode))
                }
                rows.append(row)

            case .settlement(let settlement):
                var row = [
                    formatter.string(from: settlement.date),
                    String(localized: "Payment"),
                    settlement.method.title,
                    settlement.currencyCode,
                    decimalString(settlement.amountMinorUnits, currencyCode: settlement.currencyCode),
                    settlement.fromParticipant?.fullName ?? "",
                    String(localized: "Settle up"),
                    settlement.notes,
                ]
                for member in members {
                    row.append(decimalString(settlement.net(for: member), currencyCode: settlement.currencyCode))
                }
                rows.append(row)
            }
        }

        // Closing balances so the file stands on its own.
        let sheet = BalanceEngine.balanceSheet(
            expenses: group.expenseList,
            settlements: group.settlementList,
            simplify: false
        )
        rows.append([])
        rows.append([String(localized: "Closing balances")])
        for member in members {
            let position = sheet.position(for: member.id)
            for code in position.nonZeroCurrencies {
                rows.append([
                    "", member.fullName, "", code,
                    decimalString(position.amount(in: code), currencyCode: code),
                ])
            }
            if position.isSettled {
                rows.append(["", member.fullName, "", "", "0"])
            }
        }

        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }

    /// Every expense across every group, for a full backup.
    static func csvForEverything(in context: ModelContext) -> String {
        var rows: [[String]] = [[
            String(localized: "Date"),
            String(localized: "Group"),
            String(localized: "Description"),
            String(localized: "Category"),
            String(localized: "Currency"),
            String(localized: "Amount"),
            String(localized: "Paid by"),
            String(localized: "Your share"),
            String(localized: "Your net"),
            String(localized: "Notes"),
        ]]

        let user = Ledger.currentUser(in: context)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        for expense in Ledger.allExpenses(in: context) {
            rows.append([
                formatter.string(from: expense.date),
                expense.group?.displayName ?? "",
                expense.displayTitle,
                expense.category.title,
                expense.currencyCode,
                decimalString(expense.amountMinorUnits, currencyCode: expense.currencyCode),
                expense.payerList.compactMap { $0.participant?.fullName }.joined(separator: " + "),
                decimalString(expense.amountOwed(by: user), currencyCode: expense.currencyCode),
                decimalString(expense.net(for: user), currencyCode: expense.currencyCode),
                expense.notes,
            ])
        }

        for settlement in Ledger.allSettlements(in: context) {
            rows.append([
                formatter.string(from: settlement.date),
                settlement.group?.displayName ?? "",
                settlement.summary,
                String(localized: "Payment"),
                settlement.currencyCode,
                decimalString(settlement.amountMinorUnits, currencyCode: settlement.currencyCode),
                settlement.fromParticipant?.fullName ?? "",
                "",
                decimalString(settlement.net(for: user), currencyCode: settlement.currencyCode),
                settlement.notes,
            ])
        }

        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }

    /// Writes a CSV to a temporary file so it can be shared as a real document.
    static func writeTemporaryFile(named name: String, contents: String) -> URL? {
        let safe = name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = safe.isEmpty ? "SplitFree.csv" : "\(safe).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            // A BOM makes Excel open UTF-8 correctly on Windows.
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(contentsOf: Array(contents.utf8))
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Formats minor units without a currency symbol, so spreadsheets treat the
    /// column as a number.
    private static func decimalString(_ minorUnits: Int, currencyCode: String) -> String {
        let digits = Currency.fractionDigits(for: currencyCode)
        if digits == 0 { return String(minorUnits) }
        let sign = minorUnits < 0 ? "-" : ""
        let magnitude = abs(minorUnits)
        let divisor = Int(pow(10.0, Double(digits)))
        let whole = magnitude / divisor
        let fraction = magnitude % divisor
        return "\(sign)\(whole).\(String(format: "%0\(digits)d", fraction))"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
