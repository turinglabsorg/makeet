import PhotosUI
import SwiftUI

struct ProfileAvatar: View {
    let profile: AccountProfile
    var size: CGFloat = 72
    var body: some View {
        ZStack {
            Circle().fill(Palette.soft)
            if let image = ProfileImage.decode(profile.image) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if !profile.initials.isEmpty {
                Text(verbatim: profile.initials).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Palette.accent)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.40, weight: .medium)).foregroundStyle(Palette.accent)
            }
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().strokeBorder(Palette.card, lineWidth: size > 60 ? 4 : 2))
            .accessibilityLabel(String(localized: "Foto profilo", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
    }
}

struct ProfileIdentityHeader: View {
    let profile: AccountProfile
    let email: String
    var body: some View {
        VStack(spacing: 12) {
            ProfileAvatar(profile: profile, size: 88)
            VStack(spacing: 4) {
                Text(profile.name.isEmpty ? String(localized: "Il tuo spazio", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : profile.name)
                    .font(.title2.weight(.semibold))
                if !email.isEmpty { Text(email).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.72)).textSelection(.enabled) }
            }.multilineTextAlignment(.center)
            Label(String(localized: "Account privato", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "lock.fill")
                .font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
                .padding(.horizontal, 12).padding(.vertical, 7).background(Palette.soft, in: Capsule())
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}

struct ProfileEditorView: View {
    let service: AccountProfileService
    @State private var revision: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var image: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loading = false
    @State private var photoError: String?
    @FocusState private var editingName: Bool

    init(service: AccountProfileService) {
        self.service = service
        _revision = State(initialValue: service.value.revision)
        _name = State(initialValue: service.value.name)
        _image = State(initialValue: service.value.image)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        ProfileAvatar(profile: AccountProfile(name: name, image: image), size: 120)
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            Label(String(localized: "Scegli una foto", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "camera")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.accessibilityIdentifier("chooseProfilePhoto")
                        if loading { ProgressView() }
                        if image != nil {
                            Button(String(localized: "Rimuovi foto", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { image = nil; selectedPhoto = nil; loading = false }
                                .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("removeProfilePhoto")
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Come ti chiami?", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                        TextField(String(localized: "Il tuo nome", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $name)
                            .focused($editingName)
                            .textContentType(.name).textFieldStyle(.plain).padding(16)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("profileName")
                            .onChange(of: name) { _, value in if value.count > 80 { name = String(value.prefix(80)) } }
                        Text(String(localized: "Nome e foto sono visibili solo a te e vengono salvati nel tuo account.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.footnote).foregroundStyle(Palette.ink.opacity(0.72))
                    }
                    if let error = photoError ?? service.message { Text(error).font(.callout).foregroundStyle(Palette.ink.opacity(0.72)).accessibilityIdentifier("profileError") }
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.journalBackground().foregroundStyle(Palette.ink)
                .navigationTitle(String(localized: "Il tuo profilo", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Salva", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            editingName = false
                            Task { if await service.save(name: name, image: image, revision: revision) { dismiss() } }
                        }.fontWeight(.semibold).disabled(loading || service.saving).accessibilityIdentifier("saveProfile")
                    }
                }
                .disabled(service.saving)
                .onAppear { service.message = nil }
                .task(id: selectedPhoto) {
                    guard let selectedPhoto else { return }
                    loading = true; photoError = nil
                    defer { if self.selectedPhoto == selectedPhoto { loading = false } }
                    do {
                        guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                        try Task.checkCancellation()
                        image = try ProfileImage.normalize(data)
                    } catch is CancellationError {} catch {
                        photoError = String(localized: "Non riesco a usare questa foto. Scegli un’altra immagine.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 580)
        #endif
    }
}
