import AppKit
import GRDB
import MarkaCore
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case today
    case brand(String)
}

/// Marka ekranının üç bölümü (çekirdekte `BrandSection`; kısayol ve kayıt eşlemesi testli).
typealias BrandTab = BrandSection

extension BrandSection {
    var title: String {
        switch self {
        case .flow: L("Akış")
        case .todo: L("Yapılacaklar")
        case .report: L("Rapor")
        }
    }
}

/// Marka ekranının sayfaları: onay bandından ve ··· menüsünden açılır.
enum BrandSheet: Identifiable, Equatable {
    /// Onay bekleyen öneriler (terminal + uygulama içi + hafıza güncellemesi) ve klasördeki yeni dosyalar.
    case approvals(String)
    /// Bilgiler: profil, AI izinleri, kişiler, projeler.
    case info(String)
    var id: String {
        switch self {
        case .approvals(let b): "onay:" + b
        case .info(let b): "bilgi:" + b
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Uygulamanın tek durum nesnesi. Veri tabanını gözler; her yazmadan sonra `revision` artar ve görünümler yeniden okur.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var store: Store?
    private(set) var startupError: String?
    let workspaceURL: URL
    /// İçeriksiz hata günlüğü (tür + yer + zaman). Ayarlar › Veri › "Tanı bilgisini kopyala".
    let diagnostics: DiagnosticsLog
    var folders: BrandFolders?
    var engine: ChatEngine?
    /// Denetim (hesap/giriş/model listesi) Codex süreci. Çalışma alanı açılınca, kullanıcının `codex` ikilisi kurcalanmış
    /// olsa bile marka klasörleri ve uygulama verisi OS düzeyinde kapalı olan bir profille yeniden kurulur (tur çalıştırmaz).
    private(set) var codex = CodexAppServer()

    var revision = 0
    var selection: SidebarItem? = .today
    var brandTab: BrandTab = .flow
    var showTerminal = false
    var alert: AppAlert?
    /// Açılacak ayrıntı paneli (Bugün, arama ya da rapor dayanağından `open(_:)` ile). Akış/Yapılacaklar karşılayınca sıfırlar.
    var panelTarget: PanelTarget?
    var showOnboarding = false
    /// Kenar çubuğundaki "Marka adı" alanı açık (⇧⌘N, "+ Marka").
    var showNewBrand = false
    var brands: [Brand] = []
    /// Marka kimliği → onay bekleyen sayısı (kenar çubuğu). Her veri değişikliğinde yeniden okunur.
    var pendingCounts: [String: Int] = [:]
    var brandSheet: BrandSheet?
    /// ⌘F: Bugün ekranındaki arama alanına odaklanma isteği; Bugün ekranı karşılayınca sıfırlar.
    var focusSearch = false
    /// Gösterilmiş öneri dosyası hataları (dosya adı + boyut + değişiklik zamanı): aynı hata tekrar tekrar açılmaz.
    private var reportedSuggestionFailures = Set<String>()
    /// Marka klasöründe henüz eklenmemiş dosyalar (marka kimliği → dosyalar). Marka ekranı açıkken arka planda taranır;
    /// onay sayfasının "Dosyalar" grubu ve onay bandı sayısı buradan. Taranmamış markada yoktur.
    var newFiles: [String: [URL]] = [:]

    /// Marka terminali oturumları (U9): marka başına tek oturum; gizlemek/marka değiştirmek/yer değiştirmek süreci öldürmez.
    @ObservationIgnored let terminals = TerminalSessionCache<TerminalSession>()
    /// Oturum durumu değişince (kabuk bitti, yeni oturum) terminal başlığı yeniden çizilsin.
    var terminalRevision = 0

    /// Tercihler veri alanına göre yalıtılır: deneme alanı (`MARKA_WORKSPACE`) gerçek tercihleri ve Keychain kaydını
    /// paylaşmaz; ekran çizimi (`MARKA_SNAPSHOT`) tercih yazmaz. Tercihlere yalnızca bunun üzerinden erişilir.
    let preferences: PreferenceStore
    /// Bu veri alanının Anthropic anahtarı Keychain hesabı (deneme alanında gerçek hesaptan ayrı).
    var anthropicKeyAccount: String { preferences.scope.keychainAccount(ChatEngine.anthropicKeyAccount) }

    // AI ayarları (tercihler)
    var anthropicModel: String { didSet { preferences.set(anthropicModel, forKey: "anthropicModel"); pushSettings() } }
    var anthropicEffort: String { didSet { preferences.set(anthropicEffort, forKey: "anthropicEffort"); pushSettings() } }
    var codexModel: String { didSet { preferences.set(codexModel, forKey: "codexModel"); pushSettings() } }
    /// Marka terminali `sandbox-exec` ile yalıtılır (varsayılan açık; Ayarlar › Genel'den kapatılabilir).
    /// Güvenlik tercihidir: veri tabanındaki `setting` tablosunda tutulur (profilde yasak olan veri alanı), böylece
    /// yalıtımlı Codex/terminal `defaults write` ile (cfprefsd) kapatamaz. Yükleme sırasında geri yazma engellenir.
    var terminalIsolation: Bool { didSet { if !loadingSettings { try? store?.setSetting("terminalIsolation", terminalIsolation ? "1" : "0") } } }
    /// Ayarlar yükleniyor (DB'den okunuyor): `didSet` geri yazmasın.
    private var loadingSettings = false
    /// Terminal paneli alt yerine sağda açılır.
    var terminalOnSide: Bool { didSet { preferences.set(terminalOnSide ? "1" : "0", forKey: "terminalOnSide") } }
    var hasAnthropicKey = false
    var codexStatus: String = ""
    var codexAccount: CodexAppServer.Account?

    private var observer: AnyDatabaseCancellable?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let environment = ProcessInfo.processInfo.environment
        let defaultWorkspace = support.appendingPathComponent("MarkaCalismaAlani", isDirectory: true)
        workspaceURL = environment["MARKA_WORKSPACE"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultWorkspace
        preferences = PreferenceStore(scope: .resolve(workspace: workspaceURL, defaultWorkspace: defaultWorkspace,
                                                      snapshot: environment["MARKA_SNAPSHOT"] != nil))
        diagnostics = DiagnosticsLog(workspace: workspaceURL)
        // 0.2.1: model ve düşünme derinliği seçimi kalktı (plan §5); sabit varsayılanlar. Eski kayıtlı seçim yok sayılır.
        anthropicModel = PriceTable.defaultAnthropicModel
        anthropicEffort = ""
        codexModel = ""
        // Güvenlik tercihi DB'den (openWorkspace) yüklenir; buradaki değer yalnızca DB açılana kadarki varsayılandır.
        terminalIsolation = true
        terminalOnSide = preferences.string(forKey: "terminalOnSide") == "1"
        openWorkspace()
        // 0.2.1: planlı gönderim çalışmaz (plan §5). Planlar veri tabanında kalır; `DeliveryScheduler` tetiklenmez.
    }

    var foldersRoot: URL {
        if let o = ProcessInfo.processInfo.environment["MARKA_FOLDERS"] { return URL(fileURLWithPath: o, isDirectory: true) }
        return BrandFolders.defaultRoot
    }

    func openWorkspace() {
        do {
            let db = try AppDatabase.open(at: workspaceURL)
            let store = Store(database: db)
            self.store = store
            folders = BrandFolders(root: foldersRoot, store: store)
            let keyAccount = anthropicKeyAccount
            // Denetim sürecini bu çalışma alanının profiliyle yeniden kur; eskisini durdur.
            let oldCodex = codex
            let controlIsolation = BrandIsolation(workspace: workspaceURL, folders: folders!)
            codex = CodexAppServer(isolation: { _ in try controlIsolation.controlIsolation() }, controlOnly: true)
            codexAccount = nil
            Task { await oldCodex.stop() }
            engine = ChatEngine(store: store, codex: codex, folders: folders!, workspace: workspaceURL, settings: aiSettings,
                                anthropicKey: { Keychain.load(account: keyAccount) }, diagnostics: diagnostics)
            observer = DatabaseRegionObservation(tracking: .fullDatabase)
                .start(in: db.writer, onError: { _ in }, onChange: { [weak self] _ in
                    Task { @MainActor in self?.databaseChanged() }
                })
            startupError = nil
            loadTerminalIsolation(store)
            if (try? store.setting(BetaMetrics.firstLaunchKey)) == nil {
                try? store.setSetting(BetaMetrics.firstLaunchKey, ISO8601DateFormatter().string(from: Date()))
            }
            reloadBasics()
            // Ekran çizimi Keychain'e hiç dokunmaz (D1).
            hasAnthropicKey = preferences.scope.kind == .snapshot ? false : Keychain.load(account: anthropicKeyAccount)?.isEmpty == false
            if brands.isEmpty && (try? store.setting("onboarded")) == nil { showOnboarding = true }
            if let last = preferences.string(forKey: "lastBrand"), brands.contains(where: { $0.id == last }) {
                selection = .brand(last)
            }
            let backup = BackupService(workspace: workspaceURL)
            let diagnostics = diagnostics
            Task.detached(priority: .background) {
                do { try backup.autoBackupIfNeeded(database: db) } catch { diagnostics.record(error, context: "yedek.otomatik") }
            }
        } catch {
            diagnostics.record(error, context: "calisma-alani.ac")
            startupError = error.localizedDescription
        }
    }

    /// Terminal yalıtımı güvenlik tercihini DB'den yükler; eski `UserDefaults` değerini bir kez taşır.
    private func loadTerminalIsolation(_ store: Store) {
        loadingSettings = true
        defer { loadingSettings = false }
        if let saved = try? store.setting("terminalIsolation") {
            terminalIsolation = saved != "0"
        } else {
            // Eski sürüm değeri tercihlerdeydi (cfprefsd ile kurcalanabiliyordu); bir kez DB'ye taşınır.
            let legacy = preferences.string(forKey: "terminalIsolation")
            terminalIsolation = legacy != "0"
            try? store.setSetting("terminalIsolation", terminalIsolation ? "1" : "0")
            if legacy != nil { preferences.set(nil, forKey: "terminalIsolation") }
        }
    }

    func closeWorkspace() throws {
        observer?.cancel()
        observer = nil
        if let pool = store?.database.writer as? DatabasePool { try pool.close() }
        // Yalıtımlı Codex süreçlerinin profili eski çalışma alanına göre kuruldu; durdurulur.
        let old = engine
        Task { await old?.stopCodexServers() }
        store = nil
        engine = nil
    }

    private func databaseChanged() {
        revision += 1
        reloadBasics()
    }

    func reloadBasics() {
        guard let store else { return }
        brands = (try? store.brands()) ?? []
        pendingCounts = (try? store.pendingApprovalCounts()) ?? [:]
        if case .brand(let id) = selection, !brands.contains(where: { $0.id == id }) { selection = .today }
        // Arşivlenen (listeden çıkan) markanın terminal oturumu sonlanır.
        let ended = terminals.prune(keeping: Set(brands.map(\.id)))
        if !ended.isEmpty {
            ended.forEach { $0.terminate() }
            terminalRevision += 1
        }
    }

    /// Onay bandı ve kenar çubuğu sayısı: bekleyen öneriler + klasördeki eklenmemiş dosyalar (taranmışsa).
    func approvalCount(_ brandId: String) -> Int {
        (pendingCounts[brandId] ?? 0) + (newFiles[brandId]?.count ?? 0)
    }

    /// Marka klasöründeki eklenmemiş dosyaları arka planda tarar (dosyalar okunup özetle karşılaştırılır).
    func scanNewFiles(brandId: String) async {
        guard let folders else { return }
        let files = await Task.detached(priority: .utility) { (try? folders.importableFiles(brandId: brandId)) ?? [] }.value
        if !Task.isCancelled, newFiles[brandId] != files { newFiles[brandId] = files }
    }

    // MARK: Terminal oturumları (U9)

    /// Markanın süren terminal oturumu; yoksa ya da kabuk bittiyse o anki yalıtım ayarıyla yenisi başlar. Profil her yeni
    /// oturumda yeniden üretilir (sonradan eklenen markaların klasörleri de kapsansın); kurulamazsa kabuk başlatılmaz.
    func terminalSession(brand: Brand, directory: URL) throws -> TerminalSession {
        let isolated = terminalIsolation
        let brandId = brand.id
        let session = try terminals.session(for: brandId, isolated: isolated) {
            var profile: String?
            if isolated {
                guard let isolation else { throw MarkaError.ai(L("Çalışma alanı açık değil.")) }
                profile = try isolation.terminalProfile(brandId: brandId).render()
            }
            return TerminalSession(brandId: brandId, directory: directory, brandName: brand.name, profile: profile) { [weak self] in
                self?.terminals.handle(.shellExited(brandId: brandId))
                self?.terminalRevision += 1
            }
        }
        terminalRevision += 1
        return session
    }

    /// Uygulama kapanırken: çalışan terminal varsa tek soru. Onaylanırsa kabuklar sonlandırılır.
    func confirmQuit() -> Bool {
        guard let count = terminals.quitQuestionCount else { return true }
        let alert = NSAlert()
        alert.messageText = LF("%d terminalde çalışan oturum var; kapatılsın mı?", count)
        alert.informativeText = L("Kabuk ve içinde çalışan komutlar (ör. Claude oturumu) sonlanır.")
        alert.addButton(withTitle: L("Kapat"))
        alert.addButton(withTitle: L("Vazgeç"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        terminals.handle(.appQuit).forEach { $0.terminate() }
        return true
    }

    /// Marka klasöründeki `oneriler/*.json` dosyalarını bekleyen önerilere çevirir (İ7). Bozuk dosya bir kez, anlaşılır Türkçe
    /// hatayla gösterilir ve tanı kaydına içeriksiz düşer (sabit bağlam anahtarı). `settle`: yazılması sürüyor olabilecek dosyayı atla.
    func scanSuggestions(brandId: String, settle: TimeInterval = 0) {
        guard let folders else { return }
        let result = SuggestionInbox(folders: folders).scan(brandId: brandId, settle: settle)
        for f in result.failures where reportedSuggestionFailures.insert(f.fingerprint).inserted {
            diagnostics.record(f.error, context: "terminal.oneri")
            alert = AppAlert(title: L("Öneri dosyası okunamadı"),
                             message: f.fileName + "\n\n" + f.message + "\n\n"
                                + L("Dosya olduğu yerde bırakıldı; hiçbir öneri oluşturulmadı. Düzeltilip yeniden yazılınca tekrar okunur."))
        }
    }

    /// Markayı açınca ve terminal açılınca BAGLAM.md kendiliğinden yazılır (elle "Bağlamı yenile" yok). Klasör URL'si döner.
    @discardableResult
    func writeContext(brandId: String) -> URL? {
        guard let folders else { return nil }
        return perform(context: "terminal.baglam") { try folders.writeContextFile(brandId: brandId) }?.deletingLastPathComponent()
    }

    var aiSettings: AISettings {
        AISettings(anthropicModel: anthropicModel, anthropicEffort: anthropicEffort.isEmpty ? nil : anthropicEffort,
                   codexModel: codexModel.isEmpty ? nil : codexModel)
    }

    private func pushSettings() {
        let s = aiSettings
        Task { await engine?.update(settings: s) }
    }

    /// Marka terminali ve Codex için seatbelt profili üreticisi.
    var isolation: BrandIsolation? {
        folders.map { BrandIsolation(workspace: workspaceURL, folders: $0) }
    }

    var selectedBrand: Brand? {
        guard case .brand(let id) = selection else { return nil }
        return brands.first { $0.id == id }
    }

    func select(brand id: String, tab: BrandTab? = nil) {
        selection = .brand(id)
        if let tab { brandTab = tab }
        preferences.set(id, forKey: "lastBrand")
    }

    /// Bir kaydı tek yerinde açar (plan §3 "bir kavram = bir yer"): markası seçilir, bölümüne geçilir ve sağ panelde
    /// gösterilir. İş kaydı, dosya/not ve kapanmış kayıt Akış'ta; açık görev ve açık kayıt Yapılacaklar'da; rapor Rapor'da.
    func open(_ ref: RecordRef) {
        guard let store else { return }
        let found: (brandId: String, tab: BrandTab, target: PanelTarget?)? = {
            switch ref.kind {
            case .task:
                guard let t = try? store.task(ref.id) else { return nil }
                return (t.brandId, t.status.isOpen ? .todo : .flow, .task(t.id))
            case .timeEntry:
                guard let e = try? store.read({ db in try TimeEntry.fetchOne(db, key: ref.id) }),
                      let t = try? store.task(e.taskId) else { return nil }
                return (t.brandId, t.status.isOpen ? .todo : .flow, .task(t.id))
            case .source:
                guard let s = try? store.source(ref.id) else { return nil }
                return (s.brandId, .flow, .source(s.id))
            case .workLog:
                guard let d = try? store.workLogDetail(ref.id) else { return nil }
                return (d.log.brandId, .flow, .workLog(d.log.id))
            case .brandRecord:
                guard let r = try? store.read({ db in try BrandRecord.fetchOne(db, key: ref.id) }) else { return nil }
                return (r.brandId, r.isOpen ? .todo : .flow, .record(r.id))
            case .report:
                guard let r = try? store.read({ db in try Report.fetchOne(db, key: ref.id) }) else { return nil }
                return (r.brandId, .report, nil)
            case .wikiPage:
                // Bilgi sayfasının ekranı yok (0.2.1); yalnız marka açılır.
                guard let p = try? store.wikiPageDetail(ref.id).page else { return nil }
                return (p.brandId, brandTab, nil)
            }
        }()
        guard let found, brands.contains(where: { $0.id == found.brandId }) else {
            alert = AppAlert(title: L("Bulunamadı"), message: L("Bu öğe silinmiş, geri alınmış ya da markası arşivlenmiş olabilir."))
            return
        }
        select(brand: found.brandId, tab: found.tab)
        panelTarget = found.target
    }

    /// Hata yakalayan eylem sarmalayıcısı: başarısızlık kullanıcıya açık Türkçe mesajla gösterilir ve tanı günlüğüne
    /// içeriksiz kaydedilir. `context` verilmezse yer, kaynak dosyası ve satırından türetilir (ör. "WorkView:53").
    @discardableResult
    func perform<T>(title: String = L("İşlem tamamlanamadı"), context: StaticString? = nil,
                    file: StaticString = #fileID, line: UInt = #line, _ action: () throws -> T) -> T? {
        do { return try action() } catch {
            show(error: error, title: title, context: context, file: file, line: line)
            return nil
        }
    }

    func show(error: Error, title: String = L("İşlem tamamlanamadı"), context: StaticString? = nil,
              file: StaticString = #fileID, line: UInt = #line) {
        diagnostics.record(error, context: Self.contextKey(context, file: file, line: line))
        alert = AppAlert(title: title, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    /// Okuma hatası: ekran "Veriler okunamadı" durumunu gösterir; burada yalnızca tanı kaydına düşer (uyarı penceresi açılmaz).
    func recordReadFailure(_ error: Error, context: StaticString) {
        diagnostics.record(error, context: Self.contextKey(context, file: #fileID, line: #line))
    }

    /// Ekranları veri tabanından yeniden okutur ("Tekrar dene").
    func reloadViews() {
        revision += 1
        reloadBasics()
    }

    /// Sabit bağlam anahtarı. `#fileID` yalnızca "Modül/Dosya.swift" verir (geliştirici makinesindeki yol değil).
    nonisolated static func contextKey(_ context: StaticString?, file: StaticString, line: UInt) -> String {
        if let context { return context.description }
        let name = (file.description as NSString).lastPathComponent
        return (name.hasSuffix(".swift") ? String(name.dropLast(6)) : name) + ":\(line)"
    }

    func refreshCodexStatus() async {
        do {
            try await codex.start()
            codexAccount = try await codex.account()
            codexStatus = codexAccount == nil ? L("Codex kurulu, giriş yapılmamış") : L("Bağlı")
        } catch {
            codexAccount = nil
            codexStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
