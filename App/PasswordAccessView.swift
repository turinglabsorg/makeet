import SwiftUI

struct PasswordAccessView: View {
    enum Mode { case login, register, recover, enroll }
    @Environment(AccountManager.self) private var account
    @State var mode: Mode = .login
    let userID: UUID?
    @Binding var submitting: Bool
    var completed: () -> Void = {}
    @State private var identifier = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var code = ""
    @State private var requestID: String?
    @State private var message: String?
    @State private var saved = false
    private enum Field: Hashable { case identifier, username, email, password, repeated, code }
    @FocusState private var focusedField: Field?
    @State private var existing: PasswordAccessStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            if saved {
                Text(String(localized: "Credenziali salvate. Puoi usarle anche sull’altro dispositivo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                Button(String(localized: "Fine", bundle: AppLanguage.bundle, locale: AppLanguage.locale), action: completed).accessibilityIdentifier("passwordDone")
            } else if let existing, existing.enabled {
                LabeledContent(String(localized: "Nome utente", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Text(verbatim: existing.username) }.accessibilityIdentifier("passwordAccountUsername")
                Text(String(localized: "Per cambiare la password, esci e scegli Password dimenticata. Le vecchie sessioni verranno disconnesse.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            } else {
                if requestID == nil {
                    if mode == .login || mode == .recover {
                        TextField(String(localized: "Nome utente o email", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $identifier)
                            .textContentType(.username).focused($focusedField, equals: .identifier).accessibilityIdentifier("passwordIdentifier")
                    } else {
                        TextField(String(localized: "Nome utente", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $username)
                            .textContentType(.username).focused($focusedField, equals: .username).accessibilityIdentifier("passwordUsername")
                        Text(String(localized: "Da 3 a 32 caratteri: lettere senza accenti, numeri, punto, trattino o trattino basso.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption)
                        TextField(String(localized: "Email di recupero", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $email)
                            .textContentType(.emailAddress).focused($focusedField, equals: .email).accessibilityIdentifier("passwordEmail")
                    }
                    if mode != .recover { passwordFields }
                } else {
                    Text(String(localized: "Se la richiesta è valida, riceverai un codice via email. Scade tra 15 minuti. Controlla anche lo spam.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    TextField(String(localized: "Codice di verifica", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $code)
                        .textContentType(.oneTimeCode).focused($focusedField, equals: .code).accessibilityIdentifier("passwordCode")
                    if mode == .recover { passwordFields }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.red).accessibilityIdentifier("passwordError") }
                Button {
                    focusedField = nil
                    Task { await submit() }
                } label: {
                    HStack {
                        Text(actionTitle).font(.headline).foregroundStyle(.white)
                        if submitting { ProgressView().tint(.white) }
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!canSubmit || submitting || account.working)
                    .accessibilityIdentifier("passwordSubmit")
                if userID == nil && requestID == nil {
                    HStack {
                        Button(mode == .register ? String(localized: "Accedi", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Crea account", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            changeMode(mode == .register ? .login : .register)
                        }.accessibilityIdentifier("passwordToggleRegister")
                        Spacer()
                        Button(String(localized: "Password dimenticata", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { changeMode(.recover) }
                            .accessibilityIdentifier("passwordRecover")
                    }.buttonStyle(.plain).font(.subheadline)
                }
                if requestID != nil || mode == .recover {
                    Button(String(localized: "Ricomincia", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { changeMode(userID == nil ? .login : .enroll) }
                        .disabled(submitting).accessibilityIdentifier("passwordRestart")
                }
                if mode == .register {
                    Text(String(localized: "Hai già un account? Aggiungi le credenziali da Account sul dispositivo dove hai già effettuato l’accesso per conservare i tuoi progressi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.footnote)
                }
            }
        }
        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .disabled(submitting)
        #if os(iOS)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(String(localized: "Fine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { focusedField = nil } } }
        #endif
        .task { if let userID { existing = try? await account.passwordStatus(userID: userID) } }
        .onDisappear { password = ""; repeatedPassword = ""; code = "" }
    }
    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            secureField(String(localized: "Password", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $password, field: .password, identifier: "passwordValue")
            if mode != .login {
                secureField(String(localized: "Ripeti password", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $repeatedPassword, field: .repeated, identifier: "passwordRepeat")
                Text(String(localized: "Usa da 15 a 128 caratteri. Puoi usare una frase con spazi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption)
            }
        }
    }
    private func secureField(_ title: String, text: Binding<String>, field: Field, identifier: String) -> some View {
        SecureField(title, text: text).textContentType(mode == .login ? .password : .newPassword)
            .focused($focusedField, equals: field).accessibilityIdentifier(identifier).frame(minHeight: 44)
    }
    private var title: String {
        switch mode {
        case .login: String(localized: "Accedi con password", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .register: String(localized: "Crea account", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .recover: String(localized: "Recupera password", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .enroll: String(localized: "Nome utente e password", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
    private var actionTitle: String {
        if requestID != nil { return String(localized: "Conferma codice", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        return mode == .login ? String(localized: "Accedi", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Invia codice", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    private var canSubmit: Bool {
        if requestID != nil { return code.count == 8 && (mode != .recover || validNewPassword) }
        if mode == .login { return !identifier.isEmpty && !password.isEmpty }
        if mode == .recover { return !identifier.isEmpty }
        return username.count >= 3 && email.contains("@") && validNewPassword
    }
    private var validNewPassword: Bool { password.unicodeScalars.count >= 15 && password.unicodeScalars.count <= 128 && password == repeatedPassword }
    private func changeMode(_ next: Mode) {
        focusedField = nil
        mode = next; requestID = nil; password = ""; repeatedPassword = ""; code = ""; message = nil
    }
    @MainActor private func submit() async {
        guard !submitting else { return }
        submitting = true; message = nil; defer { submitting = false }
        do {
            if let requestID {
                try await account.confirmPassword(requestID: requestID, code: code, password: mode == .recover ? password : "", userID: userID)
                if userID != nil { saved = true; password = ""; repeatedPassword = ""; code = "" }
                else {
                    try await account.passwordLogin(identifier: mode == .register ? username : identifier, password: password)
                    password = ""; repeatedPassword = ""; code = ""; completed()
                }
            } else if mode == .login {
                try await account.passwordLogin(identifier: identifier, password: password)
                password = ""; completed()
            } else if mode == .recover {
                requestID = try await account.recoverPassword(identifier: identifier)
            } else {
                requestID = try await account.requestPassword(username: username, email: email, password: password, userID: userID)
            }
        } catch {
            if case AccountAPIError.response(429, _) = error {
                message = String(localized: "Troppi tentativi. Attendi e riprova.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            } else if case AccountAPIError.response(503, _) = error {
                message = String(localized: "Accesso con password temporaneamente non disponibile. Riprova più tardi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            } else {
                message = String(localized: "Controlla i dati o il codice e riprova. Il tuo archivio è conservato.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
        }
    }
}


struct PasswordAccessSheet: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var submitting = false
    var mode: PasswordAccessView.Mode = .login
    let userID: UUID?
    let completed: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                PasswordAccessView(mode: mode, userID: userID, submitting: $submitting, completed: completed)
                    .padding(16).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.journalBackground()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() }
                            .disabled(submitting || account.working).accessibilityIdentifier("passwordCancel")
                    }
                }
        }.interactiveDismissDisabled(submitting || account.working)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 550)
        #endif
    }
}
