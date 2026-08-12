import AuthenticationServices
import CryptoKit
import SwiftData
import SwiftUI

/// Creating an account, which is optional and always has been.
///
/// The screen leads with what signing in is *for* rather than with a form,
/// because most people arriving here have been using the app happily without an
/// account and deserve to know what changes before they hand over an email.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync

    @State private var email = ""
    @State private var code = ""
    @State private var stage: Stage = .choosing
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var appleNonce: String?
    @FocusState private var focus: Field?

    private enum Stage { case choosing, awaitingCode }
    private enum Field { case email, code }

    var body: some View {
        NavigationStack {
            Form {
                explanation

                if stage == .choosing {
                    emailSection
                    providerSection
                } else {
                    codeSection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.negative)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Sign in"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .disabled(isWorking)
            .onOpenURL { url in Task { await completeOAuth(url) } }
        }
    }

    // MARK: Sections

    private var explanation: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("An account is only for sharing")
                    .font(.headline)
                Text("""
                     Nothing changes for the groups you keep to yourself. Signing \
                     in lets you share a specific group with a friend, so their \
                     phone and yours stay in step.
                     """)
                Text("A shared group is stored on SplitFree's server so your friend's phone can reach it. Groups you don't share never leave this device.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.vertical, 4)
        }
    }

    private var emailSection: some View {
        Section {
            TextField(String(localized: "you@example.com"), text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.go)
                .onSubmit { Task { await sendCode() } }

            Button {
                Task { await sendCode() }
            } label: {
                HStack {
                    Text("Email me a code")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(!isPlausibleEmail)
        } header: {
            Text("With your email")
        } footer: {
            Text("We send a six-digit code. There's no password to forget.")
        }
    }

    private var providerSection: some View {
        Section {
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonce()
                appleNonce = nonce
                request.requestedScopes = [.email, .fullName]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                Task { await completeApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
            .listRowInsets(EdgeInsets())

            Button {
                Task { await startGoogle() }
            } label: {
                Label(String(localized: "Continue with Google"), systemImage: "globe")
            }
        } header: {
            Text("Or")
        }
    }

    private var codeSection: some View {
        Section {
            TextField(String(localized: "123456"), text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
                .focused($focus, equals: .code)

            Button {
                Task { await verifyCode() }
            } label: {
                HStack {
                    Text("Sign in")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(code.count < 6)

            Button(String(localized: "Use a different email")) {
                stage = .choosing
                code = ""
                errorMessage = nil
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("Check your email")
        } footer: {
            Text(String(format: String(localized: "We sent a code to %@.", comment: "Email address"), email))
        }
        .onAppear { focus = .code }
    }

    private var isPlausibleEmail: Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !email.hasSuffix(".")
    }

    // MARK: Actions

    private func sendCode() async {
        await perform {
            try await SupabaseClient.shared.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces))
            stage = .awaitingCode
        }
    }

    private func verifyCode() async {
        await perform {
            _ = try await SupabaseClient.shared.verifyEmailCode(
                email: email.trimmingCharacters(in: .whitespaces),
                code: code
            )
            await finishSignIn()
        }
    }

    private func completeApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // Cancelling is not a failure worth shouting about.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = String(localized: "Apple didn't return a usable sign-in.")
                return
            }
            await perform {
                _ = try await SupabaseClient.shared.signInWithApple(idToken: token, nonce: appleNonce)
                // Apple only sends the name on the very first authorisation, so
                // it is used now or never.
                if let name = credential.fullName?.formatted(), !name.isEmpty {
                    Ledger.currentUser(in: context).name = name
                }
                await finishSignIn()
            }
        }
    }

    private func startGoogle() async {
        guard let url = SupabaseClient.shared.oauthURL(provider: "google") else {
            errorMessage = String(localized: "This build isn't set up for syncing.")
            return
        }
        await UIApplication.shared.open(url)
    }

    private func completeOAuth(_ url: URL) async {
        guard url.scheme == "splitfree", url.host == "auth-callback" else { return }
        await perform {
            _ = try await SupabaseClient.shared.completeOAuth(callback: url)
            await finishSignIn()
        }
    }

    private func finishSignIn() async {
        await sync.refreshAccountState()
        await sync.syncNow(context: context)
        Haptics.success()
        dismiss()
    }

    private func perform(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    // MARK: Apple nonce

    /// Apple signs the hash of this value into the identity token, and Supabase
    /// checks it. It is what stops a token intercepted from another app from
    /// being replayed against this one.
    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
