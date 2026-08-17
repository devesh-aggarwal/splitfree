import SwiftData
import SwiftUI

/// The full record of one expense: what it was, who paid, who owes what, the
/// receipt, and the conversation about it.
struct ExpenseDetailView: View {
    @Bindable var expense: Expense

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingEditor = false
    @State private var showsReceipt = false
    @State private var showsDeleteConfirmation = false
    @State private var commentText = ""
    @FocusState private var isCommenting: Bool

    private var user: Participant { Ledger.currentUser(in: context) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    breakdownCard
                    if !expense.lineItemList.isEmpty {
                        itemsCard.id("items")
                    }
                    if let data = expense.receiptImageData, let image = UIImage(data: data) {
                        receiptCard(image)
                    }
                    if !expense.notes.isEmpty {
                        notesCard
                    }
                    commentsCard
                    Color.clear.frame(height: 20)
                }
                .padding(Metrics.screenPadding)
            }
            #if DEBUG
            // The screenshot wants the line items and tax in frame, not the
            // header they sit beneath.
            .task {
                guard DemoData.opensItemizedExpense else { return }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(nil) { proxy.scrollTo("items", anchor: .top) }
            }
            #endif
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(Text("Expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Close") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { isPresentingEditor = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                ExpenseEditorView(context: ExpenseEditorContext(mode: .edit(expense)))
            }
            .fullScreenCover(isPresented: $showsReceipt) {
                if let data = expense.receiptImageData, let image = UIImage(data: data) {
                    ReceiptViewer(image: image)
                }
            }
            .confirmationDialog(
                Text("Delete this expense?"),
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    Ledger.delete(expense: expense, in: context)
                    try? context.save()
                    Haptics.warning()
                    dismiss()
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card(padding: 20) {
            VStack(spacing: 12) {
                CategoryBadge(category: expense.category, size: 56)

                Text(expense.displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(expense.total.formatted())
                    .font(Typography.titleMoney)
                    .foregroundStyle(Palette.primaryText)
                    .monospacedDigit()

                HStack(spacing: 6) {
                    Text(expense.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    if let group = expense.group {
                        Text("·")
                        Text(group.displayName)
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)

                if expense.currencyCode != expense.baseCurrencyCode {
                    Text(
                        String(
                            format: String(localized: "≈ %@ at the rate when this was added", comment: "Converted amount"),
                            Money(
                                minorUnits: expense.amountInBaseMinorUnits,
                                currencyCode: expense.baseCurrencyCode
                            ).formatted()
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(Palette.tertiaryText)
                }

                personalImpactPill
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var personalImpactPill: some View {
        let net = expense.net(for: user)
        return Text(Ledger.personalImpact(of: expense, for: user))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.forBalance(net))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.softForBalance(net), in: Capsule())
    }

    // MARK: - Breakdown

    private var breakdownCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(String(localized: "Who paid"))
                ForEach(expense.payerList.filter { $0.amountMinorUnits != 0 }, id: \.id) { payer in
                    if let person = payer.participant {
                        HStack(spacing: 10) {
                            AvatarView(participant: person, size: 32)
                            Text(person.displayName)
                                .font(Typography.rowSubtitle)
                                .foregroundStyle(Palette.primaryText)
                            Spacer()
                            Text(Money(minorUnits: payer.amountMinorUnits, currencyCode: expense.currencyCode).formatted())
                                .font(Typography.rowMoney)
                                .foregroundStyle(Palette.primaryText)
                                .monospacedDigit()
                        }
                    }
                }

                Divider().overlay(Palette.separator)

                SectionHeader(
                    String(localized: "Who owes"),
                    subtitle: String(format: String(localized: "Split %@", comment: "Split method"), expense.splitMethod.title.lowercased())
                )
                ForEach(expense.shareList.sorted { $0.amountMinorUnits > $1.amountMinorUnits }, id: \.id) { share in
                    if let person = share.participant {
                        HStack(spacing: 10) {
                            AvatarView(participant: person, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.displayName)
                                    .font(Typography.rowSubtitle)
                                    .foregroundStyle(Palette.primaryText)
                                if let detail = weightDetail(for: share) {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.tertiaryText)
                                }
                            }
                            Spacer()
                            Text(Money(minorUnits: share.amountMinorUnits, currencyCode: expense.currencyCode).formatted())
                                .font(Typography.rowMoney)
                                .foregroundStyle(Palette.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    /// Shows the original intent behind a share: "40%", "2 shares", "+$6.00".
    private func weightDetail(for share: ExpenseShare) -> String? {
        switch expense.splitMethod {
        case .percent:
            return String(format: "%.4g%%", share.weight)
        case .shares:
            return String(
                localized: "^[\(Int(share.weight)) share](inflect: true)",
                comment: "Share count"
            )
        case .adjustment:
            guard share.weight != 0 else { return nil }
            let money = Money(minorUnits: abs(Int(share.weight)), currencyCode: expense.currencyCode)
            return (share.weight > 0 ? "+" : "−") + money.formatted()
        case .equal, .exact, .itemized:
            return nil
        }
    }

    // MARK: - Items

    private var itemsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(String(localized: "Items"))
                ForEach(expense.lineItemList, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                                .font(Typography.rowSubtitle)
                                .foregroundStyle(Palette.primaryText)
                            Spacer()
                            Text(Money(minorUnits: item.lineTotalMinorUnits, currencyCode: expense.currencyCode).formatted())
                                .font(Typography.rowMoney)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        if item.assigneeList.isEmpty {
                            Text("Shared by everyone")
                                .font(.caption2)
                                .foregroundStyle(Palette.tertiaryText)
                        } else {
                            AvatarStack(participants: item.assigneeList, size: 20, maxVisible: 6)
                        }
                    }
                }

                if expense.taxMinorUnits != 0 || expense.tipMinorUnits != 0 {
                    Divider().overlay(Palette.separator)
                    if expense.taxMinorUnits != 0 {
                        summaryLine(String(localized: "Tax"), expense.taxMinorUnits)
                    }
                    if expense.tipMinorUnits != 0 {
                        summaryLine(String(localized: "Tip"), expense.tipMinorUnits)
                    }
                }
            }
        }
    }

    private func summaryLine(_ label: String, _ amount: Int) -> some View {
        HStack {
            Text(label)
                .font(Typography.rowSubtitle)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(Money(minorUnits: amount, currencyCode: expense.currencyCode).formatted())
                .font(Typography.rowMoney)
                .foregroundStyle(Palette.primaryText)
        }
    }

    // MARK: - Receipt & notes

    private func receiptCard(_ image: UIImage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(String(localized: "Receipt"))
                Button { showsReceipt = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(String(localized: "Notes"))
                Text(expense.notes)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.primaryText)
            }
        }
    }

    // MARK: - Comments

    private var commentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(String(localized: "Comments"))

                if expense.commentList.isEmpty {
                    Text("No comments yet.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                } else {
                    ForEach(expense.commentList, id: \.id) { comment in
                        HStack(alignment: .top, spacing: 10) {
                            if let author = comment.author {
                                AvatarView(participant: author, size: 28)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(comment.author?.displayName ?? String(localized: "Someone"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.primaryText)
                                    Text(comment.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundStyle(Palette.tertiaryText)
                                }
                                Text(comment.text)
                                    .font(Typography.rowSubtitle)
                                    .foregroundStyle(Palette.primaryText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(text: $commentText, axis: .vertical) {
                        Text("Add a comment")
                    }
                    .font(Typography.rowSubtitle)
                    .lineLimit(1...4)
                    .focused($isCommenting)
                    .padding(10)
                    .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous))

                    Button { addComment() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(commentText.isEmpty ? Palette.separator : Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let comment = ExpenseComment(text: trimmed, author: user)
        comment.expense = expense
        context.insert(comment)

        Ledger.log(
            .commentAdded,
            headline: String(
                format: String(localized: "You commented on %@", comment: "Expense title"),
                expense.displayTitle
            ),
            detail: trimmed,
            expenseID: expense.id,
            groupID: expense.group?.id,
            groupName: expense.group?.name ?? "",
            in: context
        )

        try? context.save()
        commentText = ""
        isCommenting = false
        Haptics.tick()
    }
}

/// Pinch-to-zoom receipt viewer.
struct ReceiptViewer: View {
    var image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = max(1, value.magnification) }
                        .onEnded { _ in
                            if scale < 1.05 {
                                withAnimation(Motion.snappy) {
                                    scale = 1
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = value.translation
                        }
                        .onEnded { _ in
                            if scale <= 1 {
                                withAnimation(Motion.snappy) { offset = .zero }
                            }
                        }
                )
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(Metrics.screenPadding)
        }
    }
}
