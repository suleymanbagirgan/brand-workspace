import AppKit
import GRDB
import MarkaCore
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case today
    /// "Biz kimiz": şirket, hizmetler, ekip, şema (çalışma alanı seviyesi, markaya bağlı değil).
    case company
    case brand(String)
}

/// Marka ekranının bölümleri (çekirdekte `BrandSection`; kısayol ve kayıt eşlemesi testli).
typealias BrandTab = BrandSection

extension BrandSection {
    /// Kendi şirketimizde "Marka Bilgileri" sekmesi "Şirket" olur (Biz, Hizmetler, Ekip, Şema, Yetenekler).
    func title(for brand: Brand) -> String { self == .info && brand.isOwn ? L("Şirket") : title }

    var title: String {
        switch self {
        case .flow: L("Özet")
        case .todo: L("Görevler")
        case .files: L("Dosyalar")
        case .info: L("Marka Bilgileri")
        case .finance: L("Finans")
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
    /// Açılış hatası veri alanı kilidinden (ikinci süreç, H1-09): ayrı "Uygulama zaten açık" ekranı, yedek önerisi yok.
    private(set) var startupLocked = false
    let workspaceURL: URL
    /// İçeriksiz hata günlüğü (tür + yer + zaman). Ayarlar › Veri › "Tanı bilgisini kopyala".
    let diagnostics: DiagnosticsLog
    var folders: BrandFolders?
    var engine: ChatEngine?
    #if !MAS
    /// Denetim (hesap/giriş/model listesi) Codex süreci. Çalışma alanı açılınca, kullanıcının `codex` ikilisi kurcalanmış
    /// olsa bile marka klasörleri ve uygulama verisi OS düzeyinde kapalı olan bir profille yeniden kurulur (tur çalıştırmaz).
    private(set) var codex = CodexAppServer()
    #endif

    var revision = 0
    var selection: SidebarItem? = .today
    var brandTab: BrandTab = .flow { didSet { preferences.set(brandTab.rawValue, forKey: "lastTab") } }
    /// Başka bölümden "Görev ekle": Görevler açılır ve ekleme alanı odaklanır.
    var addTaskRequested = false
    /// Komut paleti açık (⌘K).
    var showPalette = false
    /// 0.3.0: terminal merkezde; varsayılan açık (⌘J gizler, oturum sürer).
    /// Görevler listesinde tamamlananlar (Hatırlatıcılar kalıbı: varsayılan gizli; ⇧⌘H).
    var showCompletedTasks = false { didSet { preferences.set(showCompletedTasks ? "1" : "0", forKey: "showCompletedTasks") } }
    /// Menü çubuğu simgesi (isteğe bağlı, varsayılan kapalı; Ayarlar › Genel). Pencere kapansa da uygulama yaşar.
    var showMenuBarExtra = false { didSet { preferences.set(showMenuBarExtra ? "1" : "0", forKey: "menuBarExtra") } }
    /// Uygulama görünümü: "system" (Mac'in ayarı), "light", "dark". Varsayılan "system" (U-48; kayıtlı tercih korunur); Görünüm menüsü ve Ayarlar'dan değişir.
    var appearance: String = "system" {
        didSet { preferences.set(appearance, forKey: "appearance"); Self.applyAppearance(appearance) }
    }
    static func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
    /// Çalışan zamanlayıcı (varsa) ve görevi; saniyede bir `now` güncellenir (yalnız sayaç çalışırken).
    var runningTimer: TimeEntry?
    var runningTask: WorkTask?
    var now = Date()
    private var ticker: Timer?
    /// Çentik penceresi (çentiği olan ekranda sayaç çalışırken görünür). Ayarlar › Genel'den kapatılır.
    var showNotchTimer = true { didSet { preferences.set(showNotchTimer ? "1" : "0", forKey: "notchTimer") } }
    /// Çentik adası bu sayaç için gizlendi (yeni sayaç başlayınca ya da menü çubuğu panelinden geri açılır).
    var notchDismissed = false
    var elapsed: TimeInterval { runningTimer.map { max(0, now.timeIntervalSince($0.startedAt)) } ?? 0 }

    /// Veri tabanındaki çalışan sayacı yükler (uygulama kapanıp açılsa da sayaç sürer).
    func syncTimer() {
        let entry: TimeEntry? = read(or: nil, context: "zamanlayici.oku") { try $0.runningTimer() }
        runningTimer = entry
        runningTask = entry.flatMap { e in read(or: nil, context: "zamanlayici.gorev") { try $0.task(e.taskId) } }
        ticker?.invalidate(); ticker = nil
        if entry != nil {
            now = Date()
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.now = Date() }
            }
        }
    }

    /// Sayaç başlatılırken sessizce olanı söyleyen kısa bildirim (H1-08, U-19): durdurulan başka sayaç (marka · görev · süre)
    /// ve "Sürüyor"a geçen görev aynı satırda. Uygulama içi; sistem bildirim izni gerekmez. Birkaç saniye sonra kendiliğinden kapanır.
    struct TimerNotice: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }
    var timerNotice: TimerNotice?
    private var timerNoticeDismiss: Task<Void, Never>?

    func startTimer(_ taskId: String) {
        notchDismissed = false
        let handoff = perform(title: L("Zamanlayıcı başlatılamadı"), context: "sayac.baslat") {
            try store?.startTimerReportingHandoff(taskId: taskId)
        }
        syncTimer()
        if let handoff = handoff ?? nil, handoff.isWorthTelling { showTimerNotice(Self.noticeText(handoff)) }
    }

    static func noticeText(_ h: TimerHandoff) -> String {
        var parts: [String] = []
        if h.movedToInProgress { parts.append(LF("%1$@ → %2$@", h.taskTitle, TaskStatus.inProgress.title)) }
        if let s = h.stopped {
            parts.append(LF("%1$@ · %2$@ sayacı durdu. Süre: %3$@", s.brandName, s.taskTitle, DurationFormat.short(s.seconds)))
        }
        return parts.joined(separator: "  ·  ")
    }

    func showTimerNotice(_ text: String) {
        let notice = TimerNotice(text: text)
        timerNotice = notice
        AccessibilityNotification.Announcement(text).post()
        timerNoticeDismiss?.cancel()
        timerNoticeDismiss = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self?.timerNotice?.id == notice.id else { return }
            self?.timerNotice = nil
        }
    }

    func stopTimer() {
        _ = perform(title: L("Zamanlayıcı durdurulamadı"), context: "sayac.durdur") { try store?.stopTimer() }
        syncTimer()
    }

    /// Marka başına yapay zekâ sohbeti ve "Yapay zekâya sor" ile gelen bekleyen soru.
    var chats: [String: ChatModel] = [:]
    /// H2-02 (U-11): istem yalnız sağlayıcı hazırken ve yalnız sorulduğu markada tüketilir; aksi hâlde gönderilmeden silinir.
    var pendingChat = PendingPromptSlot()
    /// Asistan paneli açık mı. Kullanıcının bilinçli açma/kapama seçimi tercihe yazılır; açılış varsayılanı (`applyAssistantDefault`) yazılmaz.
    var showAssistant = false { didSet { if !applyingAssistantDefault { preferences.set(showAssistant ? "1" : "0", forKey: "showAssistant") } } }
    @ObservationIgnored private var applyingAssistantDefault = false
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

    /// Tercihler veri alanına göre yalıtılır: deneme alanı (`MARKA_WORKSPACE`) gerçek tercihleri ve Keychain kaydını
    /// paylaşmaz; ekran çizimi (`MARKA_SNAPSHOT`) tercih yazmaz. Tercihlere yalnızca bunun üzerinden erişilir.
    let preferences: PreferenceStore
    /// Bu veri alanının Anthropic anahtarı Keychain hesabı (deneme alanında gerçek hesaptan ayrı).
    var anthropicKeyAccount: String { preferences.scope.keychainAccount(ChatEngine.anthropicKeyAccount) }

    // AI ayarları (tercihler)
    var anthropicModel: String { didSet { preferences.set(anthropicModel, forKey: "anthropicModel"); pushSettings() } }
    var anthropicEffort: String { didSet { preferences.set(anthropicEffort, forKey: "anthropicEffort"); pushSettings() } }
    /// Yanıt uzunluğu (E-20): Kısa / Normal / Ayrıntılı; kayıt yoksa Normal.
    var responseLength: ResponseLength { didSet { preferences.set(responseLength.rawValue, forKey: "responseLength"); pushSettings() } }
    #if !MAS
    var codexModel: String { didSet { preferences.set(codexModel, forKey: "codexModel"); pushSettings() } }
    /// Bu Mac'teki model (E-11): yalnız `LocalModelPreferences` doğrulayarak yazar (geri döngü dışı adres tercihe girmez).
    private(set) var localModel: LocalModelPreferences.Value? { didSet { pushSettings() } }
    #endif
    /// Marka terminali `sandbox-exec` ile yalıtılır (varsayılan açık; Ayarlar › Genel'den kapatılabilir).
    /// Güvenlik tercihidir: veri tabanındaki `setting` tablosunda tutulur (profilde yasak olan veri alanı), böylece
    /// yalıtımlı Codex/terminal `defaults write` ile (cfprefsd) kapatamaz. Yükleme sırasında geri yazma engellenir.
    /// Ayarlar yükleniyor (DB'den okunuyor): `didSet` geri yazmasın.
    /// Terminal sütununun genişliği (sürüklenir, hatırlanır). Tasarım teslimi: 315–600, varsayılan 390.
    var terminalWidth: CGFloat {
        didSet { preferences.set(String(Int(terminalWidth)), forKey: "terminalWidth") }
    }
    static let terminalWidthRange: ClosedRange<CGFloat> = 315...600
    var hasAnthropicKey = false
    #if !MAS
    var codexStatus: String = ""
    var codexAccount: CodexAppServer.Account?
    #endif
    /// Codex bağlı mı (girişli). MAS derlemesinde Codex yok: her zaman `false`.
    var codexConnected: Bool {
        #if !MAS
        return codexAccount != nil
        #else
        return false
        #endif
    }

    private var observer: AnyDatabaseCancellable?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let defaultWorkspace = support.appendingPathComponent("MarkaCalismaAlani", isDirectory: true)
        workspaceURL = DevHook.value("MARKA_WORKSPACE").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultWorkspace
        preferences = PreferenceStore(scope: .resolve(workspace: workspaceURL, defaultWorkspace: defaultWorkspace,
                                                      snapshot: DevHook.value("MARKA_SNAPSHOT") != nil))
        diagnostics = DiagnosticsLog(workspace: workspaceURL)
        // 0.2.1: model ve düşünme derinliği seçimi kalktı (plan §5); sabit varsayılanlar. Eski kayıtlı seçim yok sayılır.
        anthropicModel = PriceTable.defaultAnthropicModel
        anthropicEffort = ""
        responseLength = preferences.string(forKey: "responseLength").flatMap(ResponseLength.init(rawValue:)) ?? .normal
        #if !MAS
        codexModel = ""
        localModel = LocalModelPreferences.load(preferences)
        #endif
        // Güvenlik tercihi DB'den (openWorkspace) yüklenir; buradaki değer yalnızca DB açılana kadarki varsayılandır.
        // Başlatma: önceki durum geri yüklenir (HIG): terminal açık/kapalı, açık bölüm.
        // H2-02 (U-34): seçim yoksa sağlayıcı bilinene kadar kapalı; anahtar okununca `applyAssistantDefault` yeniden karar verir.
        applyingAssistantDefault = true
        showAssistant = AssistantPanelDefault.isOpen(savedChoice: preferences.string(forKey: "showAssistant"), providerConnected: false)
        applyingAssistantDefault = false
        showCompletedTasks = preferences.string(forKey: "showCompletedTasks") == "1"
        showMenuBarExtra = preferences.string(forKey: "menuBarExtra") == "1"
        if let saved = preferences.string(forKey: "appearance") { appearance = saved }   // kayıt yoksa varsayılan "system" (U-48)
        showNotchTimer = preferences.string(forKey: "notchTimer") != "0"
        if let t = preferences.string(forKey: "lastTab"), let tab = BrandTab(rawValue: t) { brandTab = tab }
        // Geliştirme: `MARKA_SEKME=flow|todo|files|info|finance|report|bugun` ile açılış bölümünü seçer (ekran doğrulaması için).
        if let t = DevHook.value("MARKA_SEKME"), let tab = BrandTab(rawValue: t) { brandTab = tab }
        terminalWidth = preferences.string(forKey: "terminalWidth").flatMap { Double($0) }.map { CGFloat($0) } ?? 390
        terminalWidth = min(max(terminalWidth, Self.terminalWidthRange.lowerBound), Self.terminalWidthRange.upperBound)
        observeDayChanges()
        openWorkspace()
        // 0.2.1: planlı gönderim çalışmaz (plan §5). Planlar veri tabanında kalır; `DeliveryScheduler` tetiklenmez.
    }

    // MARK: Gün / saat dilimi değişimi (H1-02, U-25)
    private var dayObservers: [NSObjectProtocol] = []

    /// Gece yarısı, saat dilimi ya da sistem saati değişince `revision` artar: "Bugün" ve tarih gösteren ekranlar yeniden çizilir.
    private func observeDayChanges() {
        let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange]
        dayObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dayChanged() }
            }
        }
    }

    func dayChanged() {
        now = Date()
        revision += 1
        // Uygulama gece yarısını geçerek açık kaldıysa o günün otomatik yedeği de alınır (karar `BackupSchedule`'da).
        guard let db = store?.database else { return }
        let backup = BackupService(workspace: workspaceURL)
        let diagnostics = diagnostics
        Task.detached(priority: .background) {
            do { try backup.autoBackupIfNeeded(database: db) } catch { diagnostics.record(error, context: "yedek.otomatik") }
        }
    }

    var foldersRoot: URL {
        if let o = DevHook.value("MARKA_FOLDERS") { return URL(fileURLWithPath: o, isDirectory: true) }
        return BrandFolders.defaultRoot
    }

    /// Bu çalışma alanını açık tutan kilit (ikinci bir süreç aynı veri alanını açamasın).
    private var workspaceLock: WorkspaceLock?

    func openWorkspace() {
        do {
            if workspaceLock == nil {
                // Alınamazsa tipli `WorkspaceLockError` atılır; aşağıda metinden değil tipinden ayırt edilir.
                workspaceLock = try WorkspaceLock.lock(directory: workspaceURL)
            }
            let db = try AppDatabase.open(at: workspaceURL)
            let store = Store(database: db)
            self.store = store
            // U-45: 7 günden eski geçici rapor PDF'leri silinir (yalnız ürünün kendi "Gecici" klasöründeki "… rapor vN.pdf").
            let geciciKlasor = workspaceURL.appendingPathComponent(GeciciRaporTemizligi.folderName, isDirectory: true)
            DispatchQueue.global(qos: .utility).async { GeciciRaporTemizligi.clean(directory: geciciKlasor) }
            folders = BrandFolders(root: foldersRoot, store: store)
            let keyAccount = anthropicKeyAccount
            #if !MAS
            // Denetim sürecini bu çalışma alanının profiliyle yeniden kur; eskisini durdur.
            let oldCodex = codex
            let controlIsolation = BrandIsolation(workspace: workspaceURL, folders: folders!)
            codex = CodexAppServer(isolation: { _ in try controlIsolation.controlIsolation() }, controlOnly: true, diagnostics: diagnostics)
            codexAccount = nil
            Task { await oldCodex.stop() }
            engine = ChatEngine(store: store, codex: codex, folders: folders!, workspace: workspaceURL, settings: aiSettings,
                                anthropicKey: { Keychain.load(account: keyAccount) }, diagnostics: diagnostics)
            #else
            engine = ChatEngine(store: store, folders: folders!, workspace: workspaceURL, settings: aiSettings,
                                anthropicKey: { Keychain.load(account: keyAccount) }, diagnostics: diagnostics)
            #endif
            observer = DatabaseRegionObservation(tracking: .fullDatabase)
                .start(in: db.writer, onError: { [diagnostics] error in diagnostics.record(error, context: "veritabani.gozlem") }, onChange: { [weak self] _ in
                    Task { @MainActor in self?.databaseChanged() }
                })
            startupError = nil
            startupLocked = false
            if diagnostics.value(or: nil, context: "olcum.ilk-acilis", { try store.setting(BetaMetrics.firstLaunchKey) }) == nil {
                diagnostics.attempt(context: "olcum.ilk-acilis") {
                    try store.setSetting(BetaMetrics.firstLaunchKey, ISO8601DateFormatter().string(from: Date()))
                }
            }
            reloadBasics()
            syncTimer()
            // Ekran çizimi Keychain'e hiç dokunmaz (D1).
            hasAnthropicKey = preferences.scope.kind == .snapshot ? false : Keychain.load(account: anthropicKeyAccount)?.isEmpty == false
            applyAssistantDefault()
            if brands.isEmpty && diagnostics.value(or: nil, context: "ilk-acilis.oku", { try store.setting("onboarded") }) == nil { showOnboarding = true }
            if let last = preferences.string(forKey: "lastBrand"), brands.contains(where: { $0.id == last }) {
                selection = .brand(last)
            }
            if DevHook.value("MARKA_SEKME") == "sirket" { openStudio() }
            // Geliştirme (`MARKA_SEKME` verilmişse): ilk markayı aç; `bugun` ise Bugün'de kal.
            if let t = DevHook.value("MARKA_SEKME"), t != "bugun", t != "sirket", let first = brands.first {
                selection = .brand(first.id)
                // `MARKA_PANEL=1`: bölümdeki ilk kaydın ayrıntı panelini aç (ekran doğrulaması için).
                if DevHook.value("MARKA_PANEL") == "onay" { brandSheet = .approvals(first.id) }
                // Geliştirme: `MARKA_ZAMANLAYICI=1` ilk açık görevde zamanlayıcıyı başlatır (çentik/menü çubuğu doğrulaması için).
                if DevHook.value("MARKA_ZAMANLAYICI") == "1",
                   let task = (try? store.tasks(brandId: first.id, statuses: [.todo, .inProgress]))?.first {
                    _ = try? store.startTimer(taskId: task.id, at: Date().addingTimeInterval(-754))
                    syncTimer()
                }
                if DevHook.value("MARKA_PANEL") == "1" {
                    switch BrandTab(rawValue: t) {
                    case .todo: panelTarget = (try? store.todo(brandId: first.id))?.first.map(PanelTarget.init)
                    case .flow: panelTarget = (try? store.flow(brandId: first.id))?.first.map(PanelTarget.init)
                    default: break
                    }
                }
            }
            let backup = BackupService(workspace: workspaceURL)
            let diagnostics = diagnostics
            Task.detached(priority: .background) {
                do { try backup.autoBackupIfNeeded(database: db) } catch { diagnostics.record(error, context: "yedek.otomatik") }
            }
        } catch {
            diagnostics.record(error, context: "calisma-alani.ac")
            startupLocked = error is WorkspaceLockError
            startupError = error.localizedDescription
        }
    }


    func closeWorkspace() throws {
        observer?.cancel()
        observer = nil
        if let pool = store?.database.writer as? DatabasePool { try pool.close() }
        #if !MAS
        // Yalıtımlı Codex süreçlerinin profili eski çalışma alanına göre kuruldu; durdurulur.
        let old = engine
        Task { await old?.stopCodexServers() }
        #endif
        store = nil
        engine = nil
    }

    private func databaseChanged() {
        revision += 1
        reloadBasics()
    }

    func reloadBasics() {
        guard let store else { return }
        brands = diagnostics.value(or: [], context: "markalar.oku") { try store.brands() }
        pendingCounts = diagnostics.value(or: [:], context: "onay.sayac") { try store.pendingApprovalCounts() }
        if case .brand(let id) = selection, !brands.contains(where: { $0.id == id }) { selection = .today }
    }

    /// Onay bandı ve kenar çubuğu sayısı: bekleyen öneriler + klasördeki eklenmemiş dosyalar (taranmışsa).
    func approvalCount(_ brandId: String) -> Int {
        (pendingCounts[brandId] ?? 0) + (newFiles[brandId]?.count ?? 0)
    }

    /// Marka klasöründeki eklenmemiş dosyaları arka planda tarar (dosyalar okunup özetle karşılaştırılır).
    func scanNewFiles(brandId: String) async {
        guard let folders else { return }
        let diagnostics = diagnostics
        let files = await Task.detached(priority: .utility) {
            diagnostics.value(or: [], context: "klasor.tara") { try folders.importableFiles(brandId: brandId) }
        }.value
        if !Task.isCancelled, newFiles[brandId] != files { newFiles[brandId] = files }
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

    /// BAGLAM.md'yi tazeler: yalnız markanın Codex izni varsa yazılır (Y1); izin yoksa hiçbir şey yazılmaz, klasör de oluşturulmaz.
    func writeContext(brandId: String) {
        guard let folders else { return }
        _ = perform(context: "terminal.baglam") { try folders.writeContextFile(brandId: brandId) }
    }

    /// "Klasörü Finder'da göster": kullanıcı açıkça istediği için klasör oluşturulur; BAGLAM.md yine yalnız Codex izniyle yazılır.
    func revealFolder(brandId: String) -> URL? {
        guard let folders else { return nil }
        writeContext(brandId: brandId)
        return perform(context: "terminal.baglam") { try folders.folder(for: .brand(brandId)) }
    }

    var aiSettings: AISettings {
        #if !MAS
        AISettings(anthropicModel: anthropicModel, anthropicEffort: anthropicEffort.isEmpty ? nil : anthropicEffort,
                   codexModel: codexModel.isEmpty ? nil : codexModel, localBaseURL: localModel?.address, localModel: localModel?.model,
                   responseLength: responseLength)
        #else
        AISettings(anthropicModel: anthropicModel, anthropicEffort: anthropicEffort.isEmpty ? nil : anthropicEffort, responseLength: responseLength)
        #endif
    }

    private func pushSettings() {
        let s = aiSettings
        Task { await engine?.update(settings: s) }
    }

    /// Apple'ın cihaz üstü modelinin durumu (E-25). Yalnız sistem durumunu okur; modeli çağırmaz, içerik göndermez.
    var appleModelStatus: AppleModelAvailability { AppleModelAvailability.current() }

    #if !MAS
    /// Bu Mac'teki modeli kaydeder (doğrulanmamış adres hata fırlatır, tercihe yazılmaz).
    func saveLocalModel(address: String, model: String) throws {
        localModel = try LocalModelPreferences.save(address: address, model: model, to: preferences)
    }

    func clearLocalModel() {
        LocalModelPreferences.clear(preferences)
        localModel = nil
    }
    #endif

    #if !MAS
    /// Marka terminali ve Codex için seatbelt profili üreticisi.
    var isolation: BrandIsolation? {
        folders.map { BrandIsolation(workspace: workspaceURL, folders: $0) }
    }
    #endif

    /// Kendi şirketimiz (Stüdyo); kurulmamışsa `nil`. Müşteri değildir.
    var ownBrand: Brand? { brands.first(where: \.isOwn) }
    /// Müşteri markaları (kenar çubuğundaki "Markalar").
    var customerBrands: [Brand] { brands.filter { !$0.isOwn } }

    /// Stüdyoyu açar (⌘9): kuruluysa şirket sekmesi, değilse kurulum ekranı.
    func openStudio() {
        if let own = ownBrand { select(brand: own.id, tab: .info) } else { selection = .company }
    }

    /// Stüdyoyu kurar: kendi şirket olarak işaretli marka + şirket profili (aynı ad).
    func createStudio(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        // Tek işlem: marka ve şirket profilinin adı birlikte yazılır ya da hiçbiri yazılmaz (B7).
        let made: Brand?? = perform(title: L("Kurulamadı"), context: "studyo.kur") { try store?.createStudio(name: clean) }
        reloadBasics()
        if let b = made ?? nil { select(brand: b.id, tab: .info) }
    }

    /// Açılışta asistan panelinin durumu (H2-02): bilinçli seçim varsa ona, yoksa sağlayıcı bağlı mı ona göre. Tercihe yazmaz.
    func applyAssistantDefault() {
        applyingAssistantDefault = true
        defer { applyingAssistantDefault = false }
        showAssistant = AssistantPanelDefault.isOpen(savedChoice: preferences.string(forKey: "showAssistant"), providerConnected: aiConnected)
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
        let failure = diagnostics.visible(error, title: title, context: Self.contextKey(context, file: file, line: line))
        alert = AppAlert(title: failure.title, message: failure.message)
    }

    /// İkincil okuma (sayaç, seçenek listesi, ek bilgi): başarısızlıkta yedek değer döner, hata içeriksiz tanıya düşer.
    /// Çalışma alanı açık değilse yedek değer döner (kayıt yok).
    func read<T>(or fallback: @autoclosure () -> T, context: StaticString? = nil,
                 file: StaticString = #fileID, line: UInt = #line, _ body: (Store) throws -> T) -> T {
        guard let store else { return fallback() }
        return diagnostics.value(or: fallback(), context: Self.contextKey(context, file: file, line: line)) { try body(store) }
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

    #if !MAS
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
    #endif
}
