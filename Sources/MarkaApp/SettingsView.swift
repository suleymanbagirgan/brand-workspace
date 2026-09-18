import AppKit
import MarkaCore
import SwiftUI

/// Ayarlar: iki sekme (plan §4). *Genel*: Claude anahtarı, Codex girişi, terminal yalıtımı. *Veri*: konum, yedekler,
/// arşivlenmiş markalar, eski görev listesini içe aktarma, tanı bilgisi. Form/liste denetimi yok: düz satırlar, ekran
/// çiziminde de aynı görünür.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label(L("Genel"), systemImage: "gearshape") }
            DataSettings().tabItem { Label(L("Veri"), systemImage: "externaldrive") }
        }
        .frame(width: 620, height: 540)
    }
}

/// Ayarlar bölümü: başlık (sağında isteğe bağlı tek metin eylemi, Bilgiler'deki "Ekle" gibi) + içerik; kutu yok,
/// bölümler boşlukla ayrılır.
struct SettingsSection<Content: View>: View {
    let title: String
    var action: String? = nil
    var perform: (() -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Design.Font.section).accessibilityAddTraits(.isHeader)
                Spacer()
                if let action, let perform {
                    Button(action, action: perform).buttonStyle(.text)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Satır: solda içerik, sağda eylemi (U9: her zaman görünür; üzerine gelince gizlenen eylem yok).
struct ActionRow<Content: View, Actions: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            content
            Spacer(minLength: Design.Space.s)
            actions
        }
        .padding(.vertical, Design.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Parola alanı. Ekran çiziminde (`SecureField` AppKit denetimi) `InputField` gibi çerçeveli yer tutucu çizilir.
struct SecureInputField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    @Binding var text: String
    var body: some View {
        if isSnapshot {
            InputField(title: title, text: .constant(""))
        } else {
            SecureField(title, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Genel

struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var keyInput = ""
    @State private var verifying = false
    @State private var keyStatus = ""
    @State private var waitingLogin = false
    @State private var loginPoll: Task<Void, Never>?

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: Design.Space.l) {
                claude
                codex
                terminal
            }
            .padding(Design.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            // Ekran çizimi Codex sürecini başlatmaz.
            if !isSnapshot { await app.refreshCodexStatus() }
        }
        .onDisappear { loginPoll?.cancel() }
    }

    private var claude: some View {
        SettingsSection(title: "Claude") {
            if app.hasAnthropicKey {
                // Anahtar kaydedilirken doğrulandı; yeniden doğrulamak için kaldırıp yeniden eklenir (tek yol).
                HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                    Text(L("API anahtarı kayıtlı"))
                    Spacer()
                    Button(L("Kaldır")) {
                        Keychain.delete(account: app.anthropicKeyAccount)
                        app.hasAnthropicKey = false
                        keyStatus = ""
                    }
                    .buttonStyle(.text)
                }
            } else {
                HStack(spacing: Design.Space.s) {
                    SecureInputField(title: L("API anahtarı (sk-ant-…)"), text: $keyInput)
                        .onSubmit { if !keyInput.isEmpty { verify(keyInput) } }
                    // Sekmenin tek birincil düğmesi.
                    Button(L("Kaydet ve doğrula")) { verify(keyInput) }
                        .buttonStyle(.borderedProminent)
                        .disabled(keyInput.isEmpty || verifying)
                }
            }
            if !keyStatus.isEmpty { Text(keyStatus).captionStyle().fixedSize(horizontal: false, vertical: true) }
            Text(L("Yalnız rapor özetinde, izin verdiğin markalarda kullanılır. Anahtar Keychain'de durur; kullanım başına ücretlidir."))
                .captionStyle().fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codex: some View {
        SettingsSection(title: "Codex") {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                Text(codexStatusText).lineLimit(2)
                Spacer()
                // Tek düğme: girişe göre "Giriş yap" ya da "Çıkış yap".
                Button(app.codexAccount == nil ? L("Giriş yap") : L("Çıkış yap")) {
                    if app.codexAccount == nil { login() } else { logout() }
                }
                .buttonStyle(.text)
                .disabled(waitingLogin)
            }
            if waitingLogin {
                Text(L("Tarayıcıda girişi tamamla; bu satır kendiliğinden güncellenir.")).captionStyle()
            }
            Text(L("Bilgisayarındaki codex aracı kendi ChatGPT girişinle kullanılır; uygulama giriş bilgini saklamaz."))
                .captionStyle().fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codexStatusText: String {
        if let a = app.codexAccount {
            return LF("Giriş yapıldı: %@", a.email ?? a.type) + (a.planType.map { " (\($0))" } ?? "")
        }
        return app.codexStatus.isEmpty ? L("Durum bilinmiyor") : app.codexStatus
    }

    private var terminal: some View {
        @Bindable var app = app
        return SettingsSection(title: L("Terminal")) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                CheckBox(isOn: $app.terminalIsolation, label: L("Marka yalıtımı"))
                Text(L("Marka yalıtımı")).onTapGesture { app.terminalIsolation.toggle() }
            }
            Text(L("Açıkken her markanın terminali diğer markaların klasörlerini ve uygulama verisini okuyamaz, yazamaz. Değişiklik yeni açılan oturumlarda geçerlidir; açık oturumlar başladıkları ayarla sürer."))
                .captionStyle().fixedSize(horizontal: false, vertical: true)
        }
    }

    func verify(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        verifying = true
        keyStatus = L("Doğrulanıyor…")
        Task {
            defer { verifying = false }
            do {
                try await AnthropicClient(apiKey: key, model: app.anthropicModel).verifyKey()
                try Keychain.save(key, account: app.anthropicKeyAccount)
                app.hasAnthropicKey = true
                keyInput = ""
                keyStatus = L("Anahtar geçerli ve Keychain'e kaydedildi.")
            } catch {
                app.diagnostics.record(error, context: "ai.anthropic.dogrula")
                keyStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func logout() {
        Task {
            try? await app.codex.logout()
            // Yalıtımlı marka süreçleri girişi bellekte tutar; çıkıştan sonra çalışmaya devam etmesinler.
            await app.engine?.stopCodexServers()
            await app.refreshCodexStatus()
        }
    }

    /// Tarayıcıda ChatGPT girişini başlatır; giriş tamamlanana kadar (en çok 3 dakika) durum 3 saniyede bir yenilenir.
    func login() {
        loginPoll?.cancel()
        loginPoll = Task {
            do {
                try await app.codex.start()
                let url = try await app.codex.startChatGPTLogin()
                NSWorkspace.shared.open(url)
                waitingLogin = true
                defer { waitingLogin = false }
                for _ in 0..<60 {
                    try await Task.sleep(for: .seconds(3))
                    await app.refreshCodexStatus()
                    if app.codexAccount != nil { break }
                }
            } catch is CancellationError {
            } catch {
                app.show(error: error, title: L("Codex girişi başlatılamadı"), context: "ai.codex.giris")
            }
        }
    }
}

// MARK: - Veri

struct DataSettings: View {
    @Environment(AppModel.self) private var app
    /// Yedek listesi her çizimde klasörden okunur (ekran çiziminde `onAppear` çalışmaz); yedek alınınca artar.
    @State private var backupsRevision = 0
    @State private var restoreTarget: BackupInfo?
    @State private var importing = false
    @State private var copied = false

    var service: BackupService { BackupService(workspace: app.workspaceURL) }

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: Design.Space.l) {
                location
                backupSection
                archived
                importAndDiagnostics
            }
            .padding(Design.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(L("Yedekten geri yüklensin mi?"), isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } })) {
            Button(L("Geri yükle"), role: .destructive) { restore() }
        } message: {
            Text(L("Mevcut veri önce ayrı bir yedeğe alınır, sonra seçtiğin yedek yüklenir."))
        }
    }

    private var location: some View {
        SettingsSection(title: L("Konum"), action: L("Finder'da göster")) {
            try? FileManager.default.createDirectory(at: app.foldersRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([app.workspaceURL, app.foldersRoot])
        } content: {
            path(L("Veri"), app.workspaceURL)
            path(L("Marka klasörleri"), app.foldersRoot)
            if app.preferences.scope.kind == .trial {
                Text(L("Deneme veri alanı: tercihler ve API anahtarı bu alana özeldir.")).captionStyle()
            }
        }
    }

    private func path(_ title: String, _ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(title).foregroundStyle(.secondary).frame(width: InfoKeyRow.keyWidth, alignment: .leading)
            Text((url.path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private var backupSection: some View {
        let _ = backupsRevision
        let backups = service.listBackups()
        return SettingsSection(title: L("Yedekler"), action: L("Şimdi yedekle")) {
            guard let db = app.store?.database else { return }
            app.perform(context: "yedek.elle") { try service.createBackup(database: db, reason: "manual") }
            backupsRevision += 1
        } content: {
            if backups.isEmpty { EmptyStateView(message: L("Henüz yedek yok.")) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(backups) { b in
                    ActionRow {
                        Text(b.manifest.createdAt, format: .dateTime.day().month().year().hour().minute())
                        Text(reason(b.manifest.reason)).captionStyle()
                    } actions: {
                        Button(L("Geri yükle…")) { restoreTarget = b }.buttonStyle(.text)
                    }
                }
            }
            Text(L("Her gün ilk açılışta otomatik yedek alınır, son 14'ü saklanır. Geri yüklemeden önce mevcut veri ayrıca yedeklenir."))
                .captionStyle().fixedSize(horizontal: false, vertical: true)
        }
    }

    private var archived: some View {
        let _ = app.revision
        let list = (try? app.store?.archivedBrands()) ?? []
        return SettingsSection(title: L("Arşivlenmiş markalar")) {
            if list.isEmpty {
                EmptyStateView(message: L("Arşivlenmiş marka yok."))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { b in
                        ActionRow {
                            Text(b.name)
                        } actions: {
                            Button(L("Arşivden çıkar")) {
                                if app.perform(context: "marka.arsivden-cikar", { try app.store?.setBrandArchived(b.id, archived: false) }) != nil {
                                    app.reloadBasics()
                                }
                            }
                            .buttonStyle(.text)
                        }
                    }
                }
            }
        }
    }

    private var importAndDiagnostics: some View {
        Group {
            // Aktarım bu bölümde yerinde açılır (ayrı sayfa ya da geri düğmesi yok).
            SettingsSection(title: L("İçe aktarım"), action: importing ? L("Kapat") : L("Eski görev listesini içe aktar…")) {
                importing.toggle()
            } content: {
                if importing {
                    JoiImportView()
                } else {
                    Text(L("Eski görev listendeki görevler, son tarihler ve süre kayıtları markalara aktarılır."))
                        .captionStyle().fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsSection(title: L("Tanı bilgisi"), action: copied ? L("Panoya kopyalandı") : L("Tanı bilgisini kopyala")) { copyDiagnostics() } content: {
                Text(L("Sorun bildirmek için: sürüm, macOS, kayıt sayıları, son hataların türü ve beta ölçümleri. Marka adı, içerik ve dosya yolu içermez; hiçbir yere kendiliğinden gönderilmez."))
                    .captionStyle().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func copyDiagnostics() {
        let codex: DiagnosticSnapshot.CodexState = app.codexAccount != nil ? .girisli
            : (app.codexStatus == L("Codex kurulu, giriş yapılmamış") ? .girissiz : .bilinmiyor)
        let snapshot = DiagnosticSnapshot.collect(store: app.store, log: app.diagnostics,
                                                  anthropicKeyPresent: app.hasAnthropicKey, codex: codex)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticReport.render(snapshot, now: Date()), forType: .string)
        copied = true
    }

    func reason(_ r: String) -> String {
        switch r {
        case "auto": L("otomatik")
        case "manual": L("elle")
        case "pre-restore": L("geri yükleme öncesi")
        default: r
        }
    }

    func restore() {
        guard let target = restoreTarget, let db = app.store?.database else { return }
        app.perform(title: L("Geri yükleme başarısız"), context: "yedek.geri-yukle") {
            try service.restore(backup: target.url, current: db) { try app.closeWorkspace() }
        }
        app.openWorkspace()
        backupsRevision += 1
    }
}
