import SwiftUI
import StoreKit

struct PlusView: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var signingInWithPassword = false
    private var policyLanguage: String { ["it", "en", "fr", "de", "es"].contains(AppLanguage.code) ? AppLanguage.code : "en" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Palette.accent)
                    Text("Makeet Plus").font(.largeTitle.weight(.semibold))
                    Text(String(localized: "Abitudini, statistiche e pianificazione sul dispositivo sono gratis. Plus aggiunge la sincronizzazione privata tra i tuoi dispositivi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.body)
                    if let store = account.subscription {
                        if store.hasPlus {
                            Label(String(localized: "Makeet Plus è attivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "checkmark.seal.fill").font(.headline)
                        } else if store.entitlement?.billingEnabled == false {
                            Text(String(localized: "Gli abbonamenti saranno disponibili al lancio. Durante questa anteprima puoi provare tutte le funzioni.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).journalCard()
                        } else {
                            ForEach(store.products) { product in
                                Button { Task { await store.purchase(product) } } label: {
                                    HStack {
                                        Text(product.id == SubscriptionStore.monthly ? String(localized: "Mensile", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Annuale", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                        Spacer()
                                        Text(product.displayPrice).fontWeight(.semibold)
                                    }.padding(18).frame(maxWidth: .infinity).background(Palette.soft, in: RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain).accessibilityIdentifier("purchase-\(product.id)")
                            }
                            Text(String(localized: "Il piano annuale addebita l’intero importo ogni anno. L’abbonamento si rinnova automaticamente; puoi annullarlo nelle impostazioni dell’App Store.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                        }
                        if store.working { ProgressView() }
                        if let message = store.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("subscriptionMessage") }
                        Button(String(localized: "Riprova", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await store.load() } }.disabled(store.working)
                        Button(String(localized: "Ripristina acquisti", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await store.restore() } }.disabled(store.working)
                    } else {
                        Text(String(localized: "Accedi con Apple o Google per collegare Plus al tuo account. Puoi continuare a usare tutte le funzioni locali senza registrarti.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        AccountSignInButtons { signingInWithPassword = true }
                    }
                    Link(String(localized: "Gestisci abbonamento", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    Link(String(localized: "Informativa privacy", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: URL(string: "https://makeet.app/\(policyLanguage)/privacy")!)
                    Link(String(localized: "Condizioni d’uso", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: URL(string: "https://makeet.app/\(policyLanguage)/terms")!)
                    Text(String(localized: "Anche se Plus scade, i dati già presenti restano consultabili, modificabili ed esportabili. Account e cancellazione restano sempre accessibili.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 540).disabled(account.subscription?.working == true)
            }.journalBackground().navigationTitle("Makeet Plus")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Fine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() }.accessibilityIdentifier("plusDone") } }
                .task { await account.subscription?.load() }
        }
        .sheet(isPresented: $signingInWithPassword) { PasswordAccessSheet(userID: nil) { signingInWithPassword = false } }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}
