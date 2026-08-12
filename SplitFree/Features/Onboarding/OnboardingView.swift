import SwiftData
import SwiftUI

/// Three screens: what this is, who you are, and what currency you think in.
/// Then straight into the app.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var page = 0
    @State private var name = ""
    @State private var currencyCode = Currency.deviceDefaultCode
    @State private var isPresentingCurrency = false
    @FocusState private var isNamingFocused: Bool

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    currencyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 14) {
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? Palette.accent : Palette.separator)
                                .frame(width: index == page ? 22 : 7, height: 7)
                        }
                    }
                    .animation(Motion.snappy, value: page)

                    Button {
                        advance()
                    } label: {
                        Text(page == 2 ? "Start splitting" : "Continue")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(page == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $isPresentingCurrency) {
            CurrencyPickerSheet(selection: $currencyCode)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Palette.accentSoft)
                    .frame(width: 150, height: 150)
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(Palette.accent)
            }

            VStack(spacing: 10) {
                Text("Split anything, fairly")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)

                Text("Track shared expenses with friends, flatmates and travel companions. Everyone's balance stays exact, down to the last cent.")
                    .font(.body)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }

            VStack(spacing: 8) {
                promise(symbol: "nosign", text: String(localized: "No adverts, ever"))
                promise(symbol: "creditcard.trianglebadge.exclamationmark", text: String(localized: "No subscription, no paid tier"))
                promise(symbol: "lock.shield", text: String(localized: "Your data stays yours"))
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private func promise(symbol: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var namePage: some View {
        VStack(spacing: 22) {
            Spacer()

            Text("What should we call you?")
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.center)

            Text("This is the name your friends will see next to expenses.")
                .font(.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            TextField(text: $name) {
                Text("Your name")
            }
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($isNamingFocused)
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 0.5)
            )
            .frame(maxWidth: 340)

            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
        .onAppear { isNamingFocused = true }
    }

    private var currencyPage: some View {
        VStack(spacing: 22) {
            Spacer()

            Text("Which currency do you think in?")
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.center)

            Text("Individual expenses can be in any of 150+ currencies — this is just the one your totals are shown in.")
                .font(.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)

            Button { isPresentingCurrency = true } label: {
                HStack(spacing: 12) {
                    Text(Currency.flag(for: currencyCode))
                        .font(.title)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Currency.name(for: currencyCode))
                            .font(.headline)
                            .foregroundStyle(Palette.primaryText)
                        Text("\(currencyCode) · \(Currency.symbol(for: currencyCode))")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .padding(16)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Palette.separator, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 340)

            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    // MARK: - Actions

    private func advance() {
        Haptics.tick()
        switch page {
        case 0:
            withAnimation(Motion.smooth) { page = 1 }
        case 1:
            withAnimation(Motion.smooth) { page = 2 }
            isNamingFocused = false
        default:
            finish()
        }
    }

    private func finish() {
        let user = Ledger.currentUser(in: context)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            user.name = trimmed
            user.colorIndex = Palette.colorIndex(for: trimmed)
        }
        settings.baseCurrencyCode = currencyCode
        settings.hasCompletedOnboarding = true
        try? context.save()
        Haptics.success()
    }
}
