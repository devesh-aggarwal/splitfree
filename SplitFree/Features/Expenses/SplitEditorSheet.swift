import SwiftData
import SwiftUI

/// Chooses how a bill is divided.
///
/// The method picker is a row of pills across the top; below it, one control per
/// person appropriate to the method. Whatever you type, the resolved amount for
/// each person is shown next to their name and a banner at the bottom tells you
/// whether it adds up. There is never a moment where you can't see the answer.
struct SplitEditorSheet: View {
    @Bindable var draft: ExpenseDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showsSaveTemplate = false
    @State private var templateName = ""
    @FocusState private var isEditingValue: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    methodPicker
                    explanation
                    peopleList
                    quickActions
                    if !draft.templates.isEmpty {
                        savedSplits
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle(Text("Split"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button {
                            templateName = draft.title.isEmpty ? String(localized: "My split") : draft.title
                            showsSaveTemplate = true
                        } label: {
                            Label("Save as a default split", systemImage: "bookmark")
                        }
                        .disabled(draft.validationIssue != nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").fontWeight(.semibold) }
                        .disabled(draft.validationIssue != nil)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button {
                            isEditingValue = false
                            UIApplication.dismissKeyboard()
                        } label: { Text("Done") }
                    }
                }
            }
            .alert(Text("Save this split"), isPresented: $showsSaveTemplate) {
                TextField(text: $templateName) { Text("Name") }
                Button { saveTemplate() } label: { Text("Save") }
                Button(role: .cancel) {} label: { Text("Cancel") }
            } message: {
                Text("You can reuse it for future expenses in this group.")
            }
        }
    }

    // MARK: - Method picker

    private var methodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SplitMethod.allCases) { method in
                    ChipButton(
                        title: method.title,
                        systemImage: method.symbol,
                        isSelected: draft.splitMethod == method
                    ) {
                        withAnimation(Motion.snappy) { draft.splitMethod = method }
                        Haptics.selectionChanged()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var explanation: some View {
        InfoBanner(symbol: "info.circle.fill", text: draft.splitMethod.explanation)
    }

    // MARK: - People

    private var peopleList: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(draft.candidates.enumerated()), id: \.element.id) { index, person in
                    personRow(person)
                    if index < draft.candidates.count - 1 {
                        Divider().overlay(Palette.separator).padding(.leading, 62)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func personRow(_ person: Participant) -> some View {
        let isIncluded = draft.isIncluded(person)
        let allocated = draft.allocatedAmount(for: person.id)

        HStack(spacing: 12) {
            Button {
                withAnimation(Motion.quick) { draft.toggleInclusion(person) }
                Haptics.selectionChanged()
            } label: {
                HStack(spacing: 12) {
                    AvatarView(participant: person, size: 38)
                        .opacity(isIncluded ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.isCurrentUser ? String(localized: "You") : person.fullName)
                            .font(Typography.rowTitle)
                            .foregroundStyle(isIncluded ? Palette.primaryText : Palette.tertiaryText)
                        if isIncluded {
                            Text(Money(minorUnits: allocated, currencyCode: draft.currencyCode).formatted())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.secondaryText)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        } else {
                            Text("Not included")
                                .font(.caption)
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if isIncluded {
                control(for: person)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(Palette.separator)
                    .onTapGesture {
                        withAnimation(Motion.quick) { draft.toggleInclusion(person) }
                    }
            }
        }
        .padding(Metrics.cardPadding)
        .animation(Motion.quick, value: allocated)
    }

    @ViewBuilder
    private func control(for person: Participant) -> some View {
        switch draft.splitMethod {
        case .equal:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21))
                .foregroundStyle(Palette.accent)

        case .itemized:
            Text(itemCountText(for: person))
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

        case .exact:
            HStack(spacing: 6) {
                InlineMoneyField(
                    minorUnits: Binding(
                        get: { Int(draft.splitValues[person.id] ?? 0) },
                        set: { draft.splitValues[person.id] = Double($0) }
                    ),
                    currencyCode: draft.currencyCode
                )
                .focused($isEditingValue)

                Button {
                    withAnimation(Motion.quick) { draft.assignRemainder(to: person.id) }
                    Haptics.snap()
                } label: {
                    Image(systemName: "arrow.down.right.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Assign the rest to \(person.fullName)"))
            }

        case .percent:
            NumericField(
                value: Binding(
                    get: { draft.splitValues[person.id] ?? 0 },
                    set: { draft.splitValues[person.id] = $0 }
                ),
                suffix: "%",
                width: 96
            )
            .focused($isEditingValue)

        case .shares:
            Stepper(
                value: Binding(
                    get: { draft.splitValues[person.id] ?? 1 },
                    set: { draft.splitValues[person.id] = max(0, $0) }
                ),
                in: 0...99,
                step: 1
            ) {
                Text("\(Int(draft.splitValues[person.id] ?? 1))")
                    .font(Typography.money(17, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 22)
            }
            .labelsHidden()
            .fixedSize()
            .overlay(alignment: .leading) {
                Text("\(Int(draft.splitValues[person.id] ?? 1))×")
                    .font(Typography.money(15, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .monospacedDigit()
                    .offset(x: -30)
            }

        case .adjustment:
            HStack(spacing: 4) {
                Text(Int(draft.splitValues[person.id] ?? 0) < 0 ? "−" : "+")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.secondaryText)
                InlineMoneyField(
                    minorUnits: Binding(
                        get: { abs(Int(draft.splitValues[person.id] ?? 0)) },
                        set: { newValue in
                            let sign: Double = (draft.splitValues[person.id] ?? 0) < 0 ? -1 : 1
                            draft.splitValues[person.id] = Double(newValue) * sign
                        }
                    ),
                    currencyCode: draft.currencyCode
                )
                .focused($isEditingValue)

                Button {
                    draft.splitValues[person.id] = -(draft.splitValues[person.id] ?? 0)
                    Haptics.tick()
                } label: {
                    Image(systemName: "plusminus.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Flip the sign"))
            }
        }
    }

    private func itemCountText(for person: Participant) -> String {
        let count = draft.lineItems.filter { $0.assigneeIDs.contains(person.id) || $0.assigneeIDs.isEmpty }.count
        return String(localized: "^[\(count) item](inflect: true)", comment: "Item count")
    }

    // MARK: - Quick actions

    @ViewBuilder
    private var quickActions: some View {
        switch draft.splitMethod {
        case .percent:
            HStack(spacing: 10) {
                Button {
                    withAnimation(Motion.snappy) { draft.balancePercentages() }
                    Haptics.snap()
                } label: {
                    Label("Even it out", systemImage: "equal.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
        case .exact:
            HStack(spacing: 10) {
                Button {
                    withAnimation(Motion.snappy) { splitRemainingEvenly() }
                    Haptics.snap()
                } label: {
                    Label("Split the rest evenly", systemImage: "equal.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
        case .itemized:
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Label("Edit the items", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
        default:
            EmptyView()
        }
    }

    private var savedSplits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved splits")
                .font(Typography.overline)
                .textCase(.uppercase)
                .foregroundStyle(Palette.tertiaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draft.templates) { template in
                        Button {
                            withAnimation(Motion.snappy) {
                                SplitTemplateApplier.apply(template, to: draft)
                            }
                            template.useCount += 1
                            template.lastUsedAt = Date()
                            Haptics.success()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.primaryText)
                                Text(template.summary)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                                    .strokeBorder(Palette.separator, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.separator)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total")
                        .font(Typography.overline)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.tertiaryText)
                    Text(Money(minorUnits: draft.amountMinorUnits, currencyCode: draft.currencyCode).formatted())
                        .font(Typography.money(20, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                }
                Spacer()
                statusPill
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let issue = draft.validationIssue, issue != .negativeTotal {
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.negative)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.negativeSoft, in: Capsule())
                .transition(.opacity.combined(with: .scale))
        } else {
            Label("Adds up exactly", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.positive)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.positiveSoft, in: Capsule())
                .transition(.opacity.combined(with: .scale))
        }
    }

    // MARK: - Actions

    /// Leaves already-typed amounts alone and spreads whatever's left over the
    /// people still on zero - or over everyone if all are set.
    private func splitRemainingEvenly() {
        let ids = Array(draft.includedIDs)
        guard !ids.isEmpty else { return }
        let untouched = ids.filter { (draft.splitValues[$0] ?? 0) == 0 }
        let targets = untouched.isEmpty ? ids : untouched
        let assigned = ids.filter { !targets.contains($0) }
            .reduce(0) { $0 + Int((draft.splitValues[$1] ?? 0).rounded()) }
        let remaining = draft.amountMinorUnits - assigned
        let parts = SplitCalculator.distributeEvenly(total: remaining, count: targets.count)
        for (id, part) in zip(targets, parts) {
            draft.splitValues[id] = Double(part)
        }
    }

    private func saveTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let template = SplitTemplate(name: name, splitMethod: draft.splitMethod, group: draft.group)
        template.plan = RecurringSplitPlan(
            payers: draft.payerAllocations.map {
                RecurringSplitPlan.Entry(
                    participantID: $0.participant.id,
                    amountMinorUnits: $0.amountMinorUnits,
                    weight: 0
                )
            },
            shares: draft.allocations.map {
                RecurringSplitPlan.Entry(
                    participantID: $0.participantID,
                    amountMinorUnits: $0.amountMinorUnits,
                    weight: $0.weight
                )
            }
        )
        context.insert(template)
        try? context.save()
        Haptics.success()
    }
}

extension ExpenseDraft {
    /// Saved splits that apply here: this group's, plus any global ones.
    var templates: [SplitTemplate] {
        (group?.templateList ?? []).sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }
}

/// Replays a saved split onto a draft.
@MainActor
enum SplitTemplateApplier {
    static func apply(_ template: SplitTemplate, to draft: ExpenseDraft) {
        let plan = template.plan
        let known = Set(draft.candidates.map(\.id))
        let shareIDs = plan.shares.map(\.participantID).filter { known.contains($0) }
        guard !shareIDs.isEmpty else { return }

        draft.splitMethod = template.splitMethod
        draft.includedIDs = Set(shareIDs)

        switch template.splitMethod {
        case .equal, .itemized:
            for id in shareIDs { draft.splitValues[id] = 1 }
        case .percent, .shares, .adjustment:
            for entry in plan.shares where known.contains(entry.participantID) {
                draft.splitValues[entry.participantID] = entry.weight
            }
        case .exact:
            // Exact amounts from a different total don't transfer meaningfully,
            // so scale them to the current total instead of copying blindly.
            let plannedTotal = plan.shares.reduce(0) { $0 + $1.amountMinorUnits }
            if plannedTotal > 0 && draft.amountMinorUnits > 0 {
                let weights = plan.shares
                    .filter { known.contains($0.participantID) }
                    .map { (id: $0.participantID, weight: Double($0.amountMinorUnits)) }
                for allocation in SplitCalculator.weighted(total: draft.amountMinorUnits, weights: weights) {
                    draft.splitValues[allocation.participantID] = Double(allocation.amountMinorUnits)
                }
            } else {
                for entry in plan.shares where known.contains(entry.participantID) {
                    draft.splitValues[entry.participantID] = Double(entry.amountMinorUnits)
                }
            }
        }

        // Restore the payer too, when they're still around.
        let payerIDs = plan.payers.map(\.participantID).filter { known.contains($0) }
        if payerIDs.count == 1 {
            draft.usesMultiplePayers = false
            draft.singlePayerID = payerIDs[0]
        } else if payerIDs.count > 1 {
            draft.usesMultiplePayers = true
            draft.multiplePayerAmounts = Dictionary(
                plan.payers
                    .filter { known.contains($0.participantID) }
                    .map { ($0.participantID, $0.amountMinorUnits) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
}
