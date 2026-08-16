import SwiftUI

// MARK: - Avatars

/// A person's avatar: their photo if they have one, otherwise coloured initials.
struct AvatarView: View {
    var participant: Participant
    var size: CGFloat = Metrics.avatarMedium
    var showsRing: Bool = false

    private var backgroundColor: Color {
        Palette.avatarColor(participant.colorIndex)
    }

    var body: some View {
        ZStack {
            if let data = participant.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                backgroundColor
                Text(participant.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsRing {
                Circle().strokeBorder(Palette.accent, lineWidth: 2.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Overlapping avatars with a "+N" cap - the group row's at-a-glance roster.
struct AvatarStack: View {
    var participants: [Participant]
    var size: CGFloat = Metrics.avatarSmall
    var maxVisible: Int = 4

    private var visible: [Participant] { Array(participants.prefix(maxVisible)) }
    private var overflow: Int { max(0, participants.count - maxVisible) }

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(visible) { participant in
                AvatarView(participant: participant, size: size)
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
            }
            if overflow > 0 {
                ZStack {
                    Circle().fill(Palette.surfaceSunken)
                    Text("+\(overflow)")
                        .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            participants.count == 1
                ? participants[0].fullName
                : String(localized: "^[\(participants.count) person](inflect: true)", comment: "Member count")
        )
    }
}

/// The rounded square that carries an expense's category.
struct CategoryBadge: View {
    var category: ExpenseCategory
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(category.color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(category.color)
            }
            .accessibilityHidden(true)
    }
}

/// Group identity tile - cover photo if set, otherwise a tinted glyph.
struct GroupBadge: View {
    var group: SpendingGroup
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let data = group.coverImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [group.tint.opacity(0.9), group.tint.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: group.kind.symbol)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Containers

/// The app's standard card. One radius, one shadow, used everywhere.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.045), radius: 12, x: 0, y: 4)
    }
}

/// A titled section with optional trailing action.
struct SectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Money

/// A balance rendered with the right colour and the right words.
struct BalanceLabel: View {
    var minorUnits: Int
    var currencyCode: String
    var font: Font = Typography.rowMoney
    /// Shows "you owe" / "owes you" above the figure.
    var showsCaption: Bool = false
    var settledText: String = String(localized: "settled up")

    private var color: Color { .forBalance(minorUnits) }

    private var caption: String {
        if minorUnits > 0 { return String(localized: "you get back") }
        if minorUnits < 0 { return String(localized: "you owe") }
        return settledText
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if showsCaption {
                Text(caption)
                    .font(Typography.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryText)
                    .tracking(0.4)
            }
            if minorUnits == 0 && !showsCaption {
                Text(settledText)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.neutral)
            } else {
                Text(Money(minorUnits: abs(minorUnits), currencyCode: currencyCode).formatted())
                    .moneyStyle(font, color: color)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let amount = Money(minorUnits: abs(minorUnits), currencyCode: currencyCode).formatted()
        if minorUnits > 0 {
            return String(format: String(localized: "You get back %@", comment: "Accessibility"), amount)
        }
        if minorUnits < 0 {
            return String(format: String(localized: "You owe %@", comment: "Accessibility"), amount)
        }
        return settledText
    }
}

// MARK: - Controls

/// The app's filled call to action.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var isProminent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(isProminent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)))
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Compact bordered button used in headers and toolbars.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// A selectable pill - split methods, category filters, date ranges.
struct ChipButton: View {
    var title: String
    var systemImage: String?
    var isSelected: Bool
    var tint: Color = Palette.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Palette.secondaryText)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.surfaceSunken))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A row that reads as tappable without pretending to be a button.
struct DisclosureRow<Leading: View, Content: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            leading
            content
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Empty & loading states

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.accentSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 2)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, Metrics.screenPadding)
    }
}

/// A subtle badge for states worth calling out without alarming anyone.
struct InfoBanner: View {
    var symbol: String
    var text: String
    var tint: Color = Palette.categoryBlue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous))
    }
}

// MARK: - Modifiers

/// Set by any pushed screen that has its own primary action, so the global
/// floating "add expense" button gets out of the way instead of hovering over
/// a detail view's own buttons.
struct HidesFloatingActionKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Standard screen chrome: app background, edge padding, large title.
    func screenBackground() -> some View {
        self.background(Palette.background.ignoresSafeArea())
    }

    func hidesFloatingAction() -> some View {
        self.preference(key: HidesFloatingActionKey.self, value: true)
    }

    /// Makes a whole row tappable with a press highlight, without the button look.
    func tappableRow(action: @escaping () -> Void) -> some View {
        Button(action: action) { self }
            .buttonStyle(RowButtonStyle())
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.primaryText.opacity(configuration.isPressed ? 0.05 : 0))
            )
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
