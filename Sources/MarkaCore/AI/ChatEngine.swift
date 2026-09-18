import Foundation
import GRDB

/// Terminal ve Codex'in çalıştığı marka klasörleri. Veri tabanına yazmazlar; yalnızca bağlam anlık görüntüsü ve çıktılar.
public struct BrandFolders: Sendable {
    public let root: URL
    public let store: Store

    public init(root: URL, store: Store) { self.root = root; self.store = store }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Marka Çalışma Alanı", isDirectory: true)
    }

    /// "Tüm markalar" kapsamının klasör adı. Marka ad alanının dışındadır: bu ada sahip bir marka bu klasörü paylaşamaz.
    public static let allBrandsFolderName = "_Tüm Markalar"

    static func safeName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-").trimmed
        return cleaned.isEmpty ? "Marka" : cleaned
    }

    public func folder(for scope: SessionScope) throws -> URL {
        let fm = FileManager.default
        switch scope {
        case .allBrands:
            let u = root.appendingPathComponent(Self.allBrandsFolderName, isDirectory: true)
            try fm.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        case .brand(let id):
            let key = "folder.\(id)"
            if let saved = try store.setting(key) {
                let u = URL(fileURLWithPath: saved, isDirectory: true)
                try fm.createDirectory(at: u.appendingPathComponent("ciktilar"), withIntermediateDirectories: true)
                return u
            }
            let brand = try store.brand(id)
            let base = Self.safeName(brand.name)
            func candidate(_ n: Int) -> URL { root.appendingPathComponent(n == 1 ? base : "\(base) \(n)", isDirectory: true) }
            var n = 1
            var u = candidate(n)
            // Rezerve "_Tüm Markalar" adı marka klasörü olamaz: aynı ada sahip marka "… 2" alır, tüm-markalar klasörünü paylaşmaz.
            while fm.fileExists(atPath: u.path) || u.lastPathComponent == Self.allBrandsFolderName {
                n += 1
                u = candidate(n)
            }
            try fm.createDirectory(at: u.appendingPathComponent("ciktilar"), withIntermediateDirectories: true)
            try store.setSetting(key, u.path)
            return u
        }
    }

    /// Markanın daha önce oluşturulmuş klasörü; hiç oluşturulmadıysa `nil` (klasör oluşturmaz, ayar yazmaz).
    public func existingFolder(brandId: String) throws -> URL? {
        guard let saved = try store.setting("folder.\(brandId)") else { return nil }
        let u = URL(fileURLWithPath: saved, isDirectory: true)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// BAGLAM.md: yalnızca bu markanın bağlamı. Terminaldeki araçlar bu dosyayı okuyabilir.
    @discardableResult
    public func writeContextFile(brandId: String) throws -> URL {
        let dir = try folder(for: .brand(brandId))
        let brand = try store.brand(brandId)
        // Öneri kutusu: terminaldeki araçlar yaptıklarını buraya JSON olarak bırakır (bkz. `SuggestionInbox`).
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(SuggestionInbox.folderName), withIntermediateDirectories: true)
        let body = """
        <!-- Marka Çalışma Alanı tarafından oluşturuldu. Elle düzenleme uygulamaya geri yazılmaz. -->
        # \(brand.name) — çalışma bağlamı

        Bu klasör yalnızca **\(brand.name)** markasına aittir. Diğer markaların bilgisi burada yoktur ve kullanılmamalıdır.

        - Ürettiğin dosyaları `ciktilar/` klasörüne kaydet. Uygulamada *Klasörden içe al* ile markanın kaynaklarına iş çıktısı olarak eklenir.
        - Bu klasördeki araçlar (Claude Code, Codex CLI) uygulamanın veri tabanına yazamaz. Görev, çalışma kaydı, marka kaydı ve not eklemek için aşağıdaki öneri dosyasını yaz; uygulama kullanıcıya onaylatır.

        \(Self.suggestionInstructions)

        \(try ContextBuilder(store: store).brandContext(brandId: brandId))
        """
        let url = dir.appendingPathComponent("BAGLAM.md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        writeAgentPointers(in: dir)
        return url
    }

    /// Uygulamanın ürettiği yönlendirme dosyalarının ilk satırı: yalnızca bununla başlayan dosya yeniden yazılır.
    public static let agentPointerMarker = "<!-- Marka Çalışma Alanı tarafından oluşturuldu: BAGLAM.md'ye yönlendirir. -->"

    /// Claude Code `CLAUDE.md`'yi, Codex CLI `AGENTS.md`'yi kendiliğinden okur; BAGLAM.md'yi okumayabilir. İkisi de BAGLAM.md'ye
    /// yönlendirilir, böylece "görev ekle" denince öneri dosyası yazılır. Kullanıcının kendi dosyası (işaretsiz) hiç değiştirilmez.
    func writeAgentPointers(in dir: URL) {
        let rule = "Görev, çalışma kaydı, marka kaydı ya da not eklemen istenince: `*_oner` araçların varsa (uygulama içi sohbet) onları kullan; "
            + "yoksa (terminal) uygulamanın veri tabanına yazamazsın, BAGLAM.md'deki şemayla `oneriler/<tarih>-<konu>.json` yaz. "
            + "Markdown görev listesi yazma. Uygulama kullanıcıya onaylatır."
        let files = [
            ("CLAUDE.md", "\(Self.agentPointerMarker)\n# Marka klasörü\n\n\(rule)\n\n@BAGLAM.md\n"),
            ("AGENTS.md", "\(Self.agentPointerMarker)\n# Marka klasörü\n\nÇalışmaya başlamadan önce `BAGLAM.md` dosyasını oku (markanın bağlamı ve kuralları).\n\n\(rule)\n"),
        ]
        for (name, text) in files {
            let url = dir.appendingPathComponent(name)
            var st = stat()
            if lstat(url.path, &st) == 0 {
                // Bağ ya da kullanıcının kendi dosyası: dokunulmaz.
                guard (st.st_mode & S_IFMT) == S_IFREG, let data = try? FileImportGuard.readNoFollow(url),
                      String(decoding: data.prefix(200), as: UTF8.self).hasPrefix(Self.agentPointerMarker) else { continue }
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// BAGLAM.md'deki öneri dosyası talimatı (şema sürüm 1). Tek kaynak: testler de bu metni ayrıştırılabilir örnek için kullanır.
    public static let suggestionInstructions = """
    ## Yaptıklarını uygulamaya aktarma: `oneriler/` (öneri dosyası)

    Oturumun sonunda ya da kullanıcı isteyince (ör. "görev ekle", "yaptıklarımızı aktar") yaptıklarını **`oneriler/<tarih>-<konu>.json`**
    olarak yaz (ör. `oneriler/2026-09-18-web-sitesi.json`). Uygulama dosyayı okur, kullanıcıya "Terminalden N öneri · İncele" olarak
    gösterir; kullanıcı onayladıkları bu markada oluşur ve geri alınabilir. İşlenen dosya `oneriler/islenmis/` altına taşınır.

    - Bu yol terminal (Claude Code, Codex CLI) içindir. Uygulama içi sohbette `*_oner` araçların varsa onları kullan.
    - Görev listesini markdown olarak yazma (`ciktilar/gorevler.md` gibi): uygulama onu görev olarak okumaz, yalnızca dosya olur.
    - Marka, dosyanın bulunduğu klasörden belirlenir; dosyaya marka adı ya da kimliği yazma (yazılırsa yok sayılır).
    - Tek dosyada birden çok tür olabilir (gün sonu dökümü). Dosya UTF-8 JSON, en fazla 256 KB ve toplam 50 öğe.
    - Geçersiz dosya hiç öneri oluşturmaz; uygulama hatayı kullanıcıya gösterir. Düzeltip yeniden yaz (yeni içerik yeniden okunur).

    Şema (`surum`: 1 zorunlu; diziler isteğe bağlı ama en az biri dolu; tarihler `YYYY-AA-GG`):
    - `gorevler[]`: `baslik` (zorunlu, ≤200), `aciklama`, `durum` (`yapilacak` | `suruyor` | `bekliyor` | `bitti`), `sonTarih`,
      `oncelik` (`dusuk` | `orta` | `yuksek`), `sorumlu`, `proje` (markadaki proje adı). `durum: bitti` olan ve markada aynı başlıklı
      açık görev varsa yeni görev açılmaz, o görevin tamamlanması önerilir; belirli bir görevi tamamlamak için `gorevId` ver (yalnızca `bitti` ile).
    - `calismaKayitlari[]` (taslak düşer, doğrulamayı kullanıcı yapar): `baslik` (zorunlu), `neIstendi`, `neYapildi` (zorunlu), `karar`,
      `kimOnayladi`, `musteriyeBildirilen`, `tarih`, `gorev` (görev başlığı) ya da `gorevId`, `girdiDosyalari[]` ve `ciktiDosyalari[]`
      (bu klasöre göreli yollar, ör. `ciktilar/rapor.md`; onayda kaynak olarak eklenip kayda bağlanır), `girdiKaynaklari[]` /
      `ciktiKaynaklari[]` (aşağıdaki listedeki kaynak kimlikleri).
    - `kayitlar[]`: `tur` (`hedef` | `talep` | `soz` | `karar` | `teklif` | `sozlesme` | `tarih`), `baslik` (zorunlu), `aciklama`, `sonTarih`.
    - `notlar[]`: `tur` (`not` | `gorusme`), `baslik` (zorunlu), `metin` (zorunlu), `tarih`.

    Örnek:
    ```json
    {
      "surum": 1,
      "gorevler": [
        {"baslik": "Web sitesi", "aciklama": "Ana sayfa taslağı", "durum": "yapilacak", "sonTarih": "2026-09-30", "oncelik": "yuksek"},
        {"baslik": "Katalog metinleri", "durum": "bitti"}
      ],
      "calismaKayitlari": [
        {"baslik": "Marka tanımı yazıldı", "neIstendi": "Klinik için marka tanımı", "neYapildi": "Konumlandırma ve ton metni hazırlandı",
         "gorev": "Web sitesi", "ciktiDosyalari": ["ciktilar/marka-tanimi.md"]}
      ],
      "kayitlar": [
        {"tur": "soz", "baslik": "Cuma'ya kadar site taslağı gönderilecek", "sonTarih": "2026-09-26"}
      ],
      "notlar": [
        {"tur": "gorusme", "baslik": "Müşteriyle ön görüşme", "metin": "Öncelik web sitesi; reklam kampanyası sonra.", "tarih": "2026-09-18"}
      ]
    }
    ```
    """

    public struct FileState: Sendable, Hashable { public var modified: Date; public var size: Int }

    public func snapshot(_ dir: URL) -> [String: FileState] {
        var out: [String: FileState] = [:]
        // /var ↔ /private/var gibi sembolik bağlar: göreli yol iki tarafta da aynı biçimden hesaplanır.
        let base = dir.resolvingSymlinksInPath().path
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
                                                     options: [.skipsHiddenFiles]) else { return out }
        for case let url as URL in e {
            let v0 = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            // Sembolik bağlar atlanır: başka markaya (ya da uygulama verisine) giden bağ marka klasörünün içeriği sayılmaz.
            // Bağ bir klasöre işaret ediyorsa içine de inilmez.
            if v0?.isSymbolicLink == true { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]), v.isDirectory != true else { continue }
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            // Uygulamanın ürettiği bağlam/yönlendirme dosyaları klasörün içeriği sayılmaz.
            if rel == "BAGLAM.md" || rel == "CLAUDE.md" || rel == "AGENTS.md" { continue }
            out[rel] = FileState(modified: v.contentModificationDate ?? .distantPast, size: v.fileSize ?? 0)
        }
        return out
    }

    public static func diff(before: [String: FileState], after: [String: FileState]) -> [(path: String, change: String)] {
        var changes: [(String, String)] = []
        for (path, state) in after.sorted(by: { $0.key < $1.key }) {
            if let old = before[path] { if old != state { changes.append((path, "modified")) } } else { changes.append((path, "added")) }
        }
        for path in before.keys.sorted() where after[path] == nil { changes.append((path, "deleted")) }
        return changes
    }

    /// Klasördeki, henüz kaynak olarak eklenmemiş dosyalar (sha256 ile karşılaştırılır).
    public func importableFiles(brandId: String) throws -> [URL] {
        let dir = try folder(for: .brand(brandId))
        let known = Set(try store.sources(brandId: brandId, includeArchived: true).map(\.sha256))
        // `snapshot` sembolik bağları zaten atlar; içerik yine bağ izlemeden (O_NOFOLLOW) ve marka klasörüne hapsedilerek okunur.
        // Öneri kutusu (`oneriler/`) iş çıktısı adayı değildir; öneri olarak ayrıca okunur.
        return snapshot(dir).keys.sorted().filter { !$0.hasPrefix(SuggestionInbox.folderName + "/") }.compactMap { rel in
            let url = dir.appendingPathComponent(rel)
            guard let canonical = try? FileImportGuard.canonicalRegularFile(at: url, confineTo: dir),
                  let data = try? FileImportGuard.readNoFollow(canonical), data.count < 50_000_000 else { return nil }
            return known.contains(FileVault.sha256(data)) ? nil : url
        }
    }
}

public struct AISettings: Sendable, Hashable {
    public var anthropicModel: String
    public var anthropicEffort: String?
    public var codexModel: String?
    /// Anthropic isteklerinin `max_tokens` üst sınırı; nil ise istemcinin varsayılanı. Doğrulama aracı maliyeti sınırlamak için kullanır.
    public var anthropicMaxTokens: Int?
    /// Varsayılan dışı API adresi (yalnızca doğrulama aracı; uygulama kullanmaz).
    public var anthropicBaseURL: URL?
    public init(anthropicModel: String = PriceTable.defaultAnthropicModel, anthropicEffort: String? = nil, codexModel: String? = nil,
                anthropicMaxTokens: Int? = nil, anthropicBaseURL: URL? = nil) {
        self.anthropicModel = anthropicModel; self.anthropicEffort = anthropicEffort; self.codexModel = codexModel
        self.anthropicMaxTokens = anthropicMaxTokens; self.anthropicBaseURL = anthropicBaseURL
    }
}

/// Sohbet motoru: sağlayıcı izni, bağlam, araç döngüsü, onaylar ve kalıcı geçmiş.
public actor ChatEngine {
    public static let anthropicKeyAccount = "anthropic-api-key"

    let store: Store
    /// Yalıtımsız Codex süreci: yalnızca hesap, giriş ve model listesi. Tur çalıştırmaz.
    public let codex: CodexAppServer
    let folders: BrandFolders
    public let isolation: BrandIsolation
    var settings: AISettings
    private var approvalWaiters: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var running: [String: Task<Void, Never>] = [:]
    private var codexTurns: [String: (key: String, server: CodexAppServer, thread: String, turn: String)] = [:]
    /// Kapsam başına ayrı, yalıtımlı Codex süreci (profil kapsamın klasörünü açar, diğerlerini kapatır).
    private var codexServers: [String: CodexAppServer] = [:]
    private var codexServerUse: [String: Date] = [:]
    /// Sohbet turu dışında süren işler (rapor özeti, bilgi derleme: `completeJSON`). Bu süreç boştaki sayılıp durdurulmamalı.
    private var structuredBusy: [String: Int] = [:]
    /// Aynı anda açık tutulan yalıtımlı Codex süreci üst sınırı; en uzun süredir boştaki durdurulur.
    static let maxCodexServers = 4
    let anthropicKey: @Sendable () -> String?
    let urlSession: URLSession
    /// Sağlayıcı hataları buraya içeriksiz kaydedilir (tür + yer; mesaj değil).
    let diagnostics: DiagnosticsLog?

    public init(store: Store, codex: CodexAppServer, folders: BrandFolders, workspace: URL, settings: AISettings,
                anthropicKey: @escaping @Sendable () -> String? = { Keychain.load(account: ChatEngine.anthropicKeyAccount) },
                urlSession: URLSession = .shared, diagnostics: DiagnosticsLog? = nil) {
        self.store = store; self.codex = codex; self.folders = folders; self.settings = settings
        self.isolation = BrandIsolation(workspace: workspace, folders: folders)
        self.anthropicKey = anthropicKey; self.urlSession = urlSession; self.diagnostics = diagnostics
    }

    // MARK: Yalıtımlı Codex süreçleri

    static func serverKey(_ scope: SessionScope) -> String {
        switch scope {
        case .brand(let id): "marka:" + id
        case .allBrands: "tum-markalar"
        }
    }

    /// Kapsamın yalıtımlı Codex süreci; gerekirse başlatılır. Profil başlatma anında üretilir ve ölçülerek doğrulanır.
    public func codexServer(for scope: SessionScope) async throws -> CodexAppServer {
        let key = Self.serverKey(scope)
        let server: CodexAppServer
        if let existing = codexServers[key] {
            server = existing
        } else {
            let isolation = isolation
            server = CodexAppServer(isolation: { binary in try isolation.codexIsolation(scope: scope, codexBinary: binary) })
            codexServers[key] = server
        }
        codexServerUse[key] = Date()
        await evictIdleServers(keeping: key)
        try await server.start()
        return server
    }

    /// Yapılandırılmış iş (rapor özeti/bilgi derleme) süresince kapsamın Codex sürecini alır ve "meşgul" işaretler; iş bitince
    /// `releaseCodexServer` çağrılmalı (boştaki süreç durdurma bu süreci öldürmesin). Süren derleme turu böyle korunur.
    public func retainCodexServer(for scope: SessionScope) async throws -> CodexAppServer {
        let server = try await codexServer(for: scope)
        structuredBusy[Self.serverKey(scope), default: 0] += 1
        return server
    }

    public func releaseCodexServer(for scope: SessionScope) {
        let key = Self.serverKey(scope)
        if let n = structuredBusy[key], n > 1 { structuredBusy[key] = n - 1 } else { structuredBusy[key] = nil }
    }

    private func evictIdleServers(keeping key: String) async {
        let busy = Set(codexTurns.values.map(\.key)).union(structuredBusy.keys).union([key])
        while codexServers.count > Self.maxCodexServers,
              let victim = codexServerUse.filter({ !busy.contains($0.key) }).min(by: { $0.value < $1.value })?.key {
            let s = codexServers.removeValue(forKey: victim)
            codexServerUse[victim] = nil
            await s?.stop()
        }
    }

    /// Tüm yalıtımlı Codex süreçlerini durdurur (çıkış yapıldığında ya da çalışma alanı kapanırken).
    public func stopCodexServers() async {
        let all = codexServers
        codexServers.removeAll()
        codexServerUse.removeAll()
        for (_, s) in all { await s.stop() }
    }

    public func update(settings: AISettings) { self.settings = settings }

    public func sessions(scope: SessionScope) throws -> [AISession] {
        try store.read { db in
            switch scope {
            case .brand(let id): try AISession.filter(Column("brandId") == id).order(Column("updatedAt").desc).fetchAll(db)
            case .allBrands: try AISession.filter(Column("scope") == AIScope.allBrands.rawValue).order(Column("updatedAt").desc).fetchAll(db)
            }
        }
    }

    public func messages(sessionId: String) throws -> [AIMessage] {
        try store.read { db in try AIMessage.filter(Column("sessionId") == sessionId).order(Column("createdAt")).fetchAll(db) }
    }

    /// Kapsamda kullanılabilecek markalar (sağlayıcı izni olanlar).
    func allowedBrandIds(scope: SessionScope, provider: AIProviderKind) throws -> Set<String> {
        switch scope {
        case .brand(let id):
            let b = try store.brand(id)
            guard b.allows(provider) else { throw MarkaError.providerNotAllowed(brand: b.name, provider: provider.displayName) }
            return [id]
        case .allBrands:
            return Set(try store.brands().filter { $0.allows(provider) }.map(\.id))
        }
    }

    public func createSession(scope: SessionScope, provider: AIProviderKind, title: String) throws -> AISession {
        _ = try allowedBrandIds(scope: scope, provider: provider)
        let model = provider == .anthropic ? settings.anthropicModel : (settings.codexModel ?? "codex")
        let s: AISession
        switch scope {
        case .brand(let id): s = AISession(brandId: id, scope: .brand, provider: provider, model: model, title: title)
        case .allBrands: s = AISession(brandId: nil, scope: .allBrands, provider: provider, model: model, title: title)
        }
        try store.write { db in try s.insert(db) }
        return s
    }

    public func respond(approvalId: String, decision: ApprovalDecision) {
        approvalWaiters.removeValue(forKey: approvalId)?.resume(returning: decision)
    }

    public func cancel(sessionId: String) async {
        running[sessionId]?.cancel()
        if let t = codexTurns[sessionId] { try? await t.server.interrupt(threadId: t.thread, turnId: t.turn) }
    }

    public func isRunning(sessionId: String) -> Bool { running[sessionId] != nil }

    /// Mesaj gönderir; olaylar akış olarak döner. Bitince mesaj kalıcı olarak kaydedilir.
    public func send(sessionId: String, text: String) -> AsyncStream<AIEvent> {
        if running[sessionId] != nil {
            return AsyncStream { c in
                c.yield(.failed(L("Bu oturumda yanıt sürüyor. Bitmesini bekle veya durdur.")))
                c.yield(.finished(stopReason: "busy"))
                c.finish()
            }
        }
        return AsyncStream { continuation in
            let task = Task {
                await self.runTurn(sessionId: sessionId, text: text, emit: { continuation.yield($0) })
                continuation.finish()
                self.finishRun(sessionId)
            }
            running[sessionId] = task
            continuation.onTermination = { _ in }
        }
    }

    private func finishRun(_ sessionId: String) {
        running[sessionId] = nil
        codexTurns[sessionId] = nil
    }

    private func runTurn(sessionId: String, text: String, emit: @escaping @Sendable (AIEvent) -> Void) async {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        var assistant = AIMessage(sessionId: sessionId, role: .assistant, text: "", state: .partial)
        var events: [ChatEventRecord] = []
        let recorder = EventRecorder()
        var context = "ai.oturum.akis"
        do {
            guard let session = try store.read({ db in try AISession.fetchOne(db, key: sessionId) }) else { throw MarkaError.notFound(sessionId) }
            context = "ai.\(session.provider.rawValue).akis"
            let scope = SessionScope(session: session)
            let allowed = try allowedBrandIds(scope: scope, provider: session.provider)
            let userMessage = AIMessage(sessionId: sessionId, role: .user, text: clean)
            try store.write { db in
                try userMessage.insert(db)
                var s = session
                s.updatedAt = Date()
                if s.title.isEmpty || s.title == L("Yeni oturum") { s.title = String(clean.prefix(60)) }
                try s.update(db)
            }
            assistant.createdAt = Date().addingTimeInterval(0.001)
            let wrappedEmit: @Sendable (AIEvent) -> Void = { event in
                recorder.record(event)
                emit(event)
            }
            switch session.provider {
            case .anthropic:
                try await runAnthropic(session: session, scope: scope, allowed: allowed, assistant: &assistant, emit: wrappedEmit)
            case .codex:
                try await runCodex(session: session, scope: scope, allowed: allowed, text: clean, assistant: &assistant, emit: wrappedEmit)
            }
            assistant.state = Task.isCancelled ? .partial : .complete
        } catch is CancellationError {
            assistant.state = .partial
            emit(.event(ChatEventRecord(kind: .notice, title: L("Durduruldu"), detail: L("Yanıt yarıda kesildi; öneriler uygulanmadı."))))
        } catch {
            assistant.state = assistant.text.isEmpty ? .failed : .partial
            diagnostics?.record(error, context: context)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let record = ChatEventRecord(kind: .error, title: L("Hata"), detail: message, status: "error")
            emit(.event(record))
            emit(.failed(message))
            recorder.record(.event(record))
        }
        events = recorder.events()
        assistant.eventsJSON = Store.json(events) ?? "[]"
        if assistant.state != .complete { assistant.rawJSON = "" }
        let final = assistant
        try? store.write { db in try final.insert(db) }
        emit(.finished(stopReason: final.state.rawValue))
    }

    // MARK: Anthropic

    func history(sessionId: String, excludingLastUser: Bool) throws -> [JSONValue] {
        var msgs = try messages(sessionId: sessionId)
        if excludingLastUser, msgs.last?.role == .user { msgs.removeLast() }
        var out: [JSONValue] = []
        for m in msgs {
            switch m.role {
            case .user:
                out.append(["role": "user", "content": [["type": "text", "text": .string(m.text)]]])
            case .assistant:
                if m.state == .complete, !m.rawJSON.isEmpty, let arr = try? JSONValue.parse(m.rawJSON).array, !arr.isEmpty {
                    out.append(contentsOf: arr)
                } else if !m.text.isEmpty {
                    out.append(["role": "assistant", "content": [["type": "text", "text": .string(m.text)]]])
                }
            }
        }
        return out
    }

    private func runAnthropic(session: AISession, scope: SessionScope, allowed: Set<String>, assistant: inout AIMessage,
                              emit: @escaping @Sendable (AIEvent) -> Void) async throws {
        guard let key = anthropicKey(), !key.isEmpty else {
            throw MarkaError.ai(L("Claude API anahtarı eklenmemiş. Ayarlar › Genel bölümünden ekleyebilirsin."))
        }
        var client = AnthropicClient(apiKey: key, model: session.model, effort: settings.anthropicEffort,
                                     maxTokensCap: settings.anthropicMaxTokens, session: urlSession)
        if let url = settings.anthropicBaseURL { client.baseURL = url }
        let system = try ContextBuilder(store: store).systemPrompt(scope: scope, allowedBrandIds: allowed)
        var messages = try history(sessionId: session.id, excludingLastUser: false)
        let tools = ToolCatalog.tools(for: scope)
        let executor = ToolExecutor(store: store, scope: scope, sessionId: session.id, allowedBrandIds: allowed)
        var turnRaw: [JSONValue] = []
        var fullText = ""
        let textBox = TextBox()
        for iteration in 0..<16 {
            try Task.checkCancellation()
            if iteration > 0, !fullText.isEmpty, !fullText.hasSuffix("\n") {
                fullText += "\n\n"
                emit(.textDelta("\n\n"))
            }
            let result = try await client.streamTurn(system: system, messages: messages, tools: tools) { piece in
                textBox.append(piece)
                emit(.textDelta(piece))
            }
            fullText += textBox.drain()
            assistant.text = fullText
            let cost = PriceTable.costMicros(model: result.model, input: result.inputTokens, output: result.outputTokens,
                                             cacheRead: result.cacheReadTokens, cacheWrite: result.cacheWriteTokens)
            let usage = UsageEntry(provider: .anthropic, model: result.model, sessionId: session.id, brandId: session.brandId, purpose: "chat",
                                   inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                                   cacheReadTokens: result.cacheReadTokens, cacheWriteTokens: result.cacheWriteTokens, costMicros: cost)
            try store.write { db in try usage.insert(db) }
            assistant.inputTokens += result.inputTokens + result.cacheReadTokens + result.cacheWriteTokens
            assistant.outputTokens += result.outputTokens
            assistant.costMicros += cost ?? 0
            emit(.usage(usage))

            var content = result.content
            if result.stopReason != "tool_use", content.contains(where: { $0["type"]?.string == "tool_use" }) {
                // Yarım kalan araç çağrısı sonucu olmadan geçmişe girerse oturum bozulur; çıkarılır.
                content.removeAll { $0["type"]?.string == "tool_use" }
                if content.isEmpty { content = [["type": "text", "text": .string(L("(yanıt kesildi)"))]] }
                emit(.event(ChatEventRecord(kind: .notice, title: L("Yarım kalan araç çağrısı atlandı"))))
            }
            let assistantMsg: JSONValue = ["role": "assistant", "content": .array(content)]
            messages.append(assistantMsg)
            turnRaw.append(assistantMsg)

            if result.stopReason == "refusal" {
                emit(.event(ChatEventRecord(kind: .notice, title: L("Model isteği reddetti"), detail: L("Claude güvenlik sınıflandırıcısı bu isteği yanıtlamadı."))))
                break
            }
            if result.stopReason == "max_tokens" {
                emit(.event(ChatEventRecord(kind: .notice, title: L("Yanıt uzunluk sınırına ulaştı"), detail: L("Devam etmesini isteyebilirsin."))))
            }
            let toolUses = result.content.filter { $0["type"]?.string == "tool_use" }
            guard result.stopReason == "tool_use", !toolUses.isEmpty else { break }
            var toolResults: [JSONValue] = []
            for use in toolUses {
                let name = use["name"]?.string ?? ""
                let id = use["id"]?.string ?? ""
                let input = use["input"] ?? .object([:])
                let r: ToolResult
                if input["_gecersiz_json"] != nil {
                    r = ToolResult(text: "HATA: araç girdisi geçerli JSON değil; tekrar dene.", isError: true,
                                   event: ChatEventRecord(kind: .error, title: LF("Araç girdisi okunamadı: %@", name), status: "error"))
                } else {
                    r = executor.run(name: name, input: input)
                }
                emit(.event(r.event))
                toolResults.append(["type": "tool_result", "tool_use_id": .string(id), "content": .string(r.text), "is_error": .bool(r.isError)])
            }
            let resultMsg: JSONValue = ["role": "user", "content": .array(toolResults)]
            messages.append(resultMsg)
            turnRaw.append(resultMsg)
        }
        // Sonu araç sonucu olan tur geçmişte tutarlı kalsın diye kaydedilir; bir sonraki kullanıcı mesajı birleşir.
        assistant.rawJSON = JSONValue.array(turnRaw).compactString()
    }

    // MARK: Codex

    private func runCodex(session: AISession, scope: SessionScope, allowed: Set<String>, text: String, assistant: inout AIMessage,
                          emit: @escaping @Sendable (AIEvent) -> Void) async throws {
        let codex = try await codexServer(for: scope)
        if try await codex.account() == nil {
            // Süreç girişten önce başlamış olabilir; giriş dosyası yeniden okunsun diye bir kez yeniden başlatılır.
            await codex.stop()
            try await codex.start()
            guard try await codex.account() != nil else {
                throw MarkaError.ai(L("Codex'e giriş yapılmamış. Ayarlar › AI bölümünden ChatGPT ile giriş yap."))
            }
        }
        let cwd = try folders.folder(for: scope)
        if case .brand(let b) = scope { try folders.writeContextFile(brandId: b) }
        let instructions = try ContextBuilder(store: store).systemPrompt(scope: scope, allowedBrandIds: allowed) + """

        # Codex çalışma kuralları
        - Çalışma klasörün: \(cwd.path). Yalnızca bu klasörde dosya oluştur veya değiştir; çıktıları `ciktilar/` altına koy.
        - Diğer marka klasörleri ve uygulama verisi işletim sistemi düzeyinde kapalıdır; bu klasör dışına yazma reddedilir. Reddedilen işlemi başka yoldan deneme.
        - Uygulama verisini değiştirmek için yalnızca sana verilen *_oner araçlarını kullan.
        """
        let executor = ToolExecutor(store: store, scope: scope, sessionId: session.id, allowedBrandIds: allowed)
        var threadId = session.providerThreadId
        if let existing = threadId, await codex.needsResume(existing) {
            do {
                try await codex.resumeThread(existing, cwd: cwd, developerInstructions: instructions)
            } catch {
                // Kayıt kapsamın Codex dizininde yok (ör. 0.1.0'da ortak ~/.codex'te açılmış iş parçacığı): yenisi açılır.
                // Uygulamadaki sohbet geçmişi korunur; Codex önceki turları hatırlamaz.
                threadId = nil
                emit(.event(ChatEventRecord(kind: .notice, title: L("Codex oturumu yeniden başlatıldı"),
                                            detail: L("Önceki Codex kaydı bu markanın yalıtımlı alanında bulunamadı; Codex önceki mesajları hatırlamayabilir."))))
            }
        }
        if threadId == nil {
            var model = settings.codexModel
            if model == nil { model = try await codex.models().first(where: \.isDefault)?.id }
            guard let model else { throw MarkaError.ai(L("Codex model listesi alınamadı.")) }
            let id = try await codex.startThread(cwd: cwd, model: model, developerInstructions: instructions, tools: ToolCatalog.tools(for: scope))
            threadId = id
            try store.write { db in
                var s = session
                s.providerThreadId = id
                s.model = model
                try s.update(db)
            }
        }
        let thread = threadId!
        let before = folders.snapshot(cwd)
        let collector = CodexTurnState()
        await codex.register(threadId: thread, notifications: { note in
            await collector.handle(note, emit: emit)
        }, requests: { [weak self] method, params in
            guard let self else { return ["decision": "decline"] }
            return await self.handleCodexRequest(method: method, params: params, executor: executor, emit: emit)
        })
        defer { Task { await codex.unregister(threadId: thread) } }
        let turnId = try await codex.startTurn(threadId: thread, text: text)
        codexTurns[session.id] = (Self.serverKey(scope), codex, thread, turnId)
        let outcome = await collector.waitForCompletion()
        assistant.text = outcome.text
        assistant.inputTokens = outcome.inputTokens
        assistant.outputTokens = outcome.outputTokens
        if outcome.inputTokens > 0 || outcome.outputTokens > 0 {
            let usage = UsageEntry(provider: .codex, model: session.model, sessionId: session.id, brandId: session.brandId, purpose: "chat",
                                   inputTokens: outcome.inputTokens, outputTokens: outcome.outputTokens, cacheReadTokens: outcome.cachedTokens, costMicros: nil)
            try store.write { db in try usage.insert(db) }
            emit(.usage(usage))
        }
        for change in BrandFolders.diff(before: before, after: folders.snapshot(cwd)) {
            emit(.event(ChatEventRecord(kind: .fileChange, title: change.path, detail: cwd.appendingPathComponent(change.path).path,
                                        status: change.change, refId: change.path)))
        }
        if outcome.status == "failed" { throw MarkaError.ai(outcome.error ?? L("Codex turu başarısız oldu.")) }
        if outcome.status == "interrupted" { throw CancellationError() }
    }

    private func handleCodexRequest(method: String, params: JSONValue, executor: ToolExecutor, emit: @escaping @Sendable (AIEvent) -> Void) async -> JSONValue {
        switch method {
        case "item/tool/call":
            let r = executor.run(name: params["tool"]?.string ?? "", input: params["arguments"] ?? .object([:]))
            emit(.event(r.event))
            return ["success": .bool(!r.isError), "contentItems": [["type": "inputText", "text": .string(r.text)]]]
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            let isCommand = method.contains("command")
            let request = ApprovalRequest(
                id: newID(), kind: isCommand ? .command : .fileChange,
                title: isCommand ? L("Komut çalıştırma izni") : L("Dosya değişikliği izni"),
                detail: isCommand ? (params["command"]?.string ?? "") : (params["grantRoot"]?.string ?? L("Çalışma klasöründe dosya değişikliği")),
                reason: params["reason"]?.string ?? "")
            emit(.event(ChatEventRecord(id: request.id, kind: .approval, title: request.title, detail: request.detail, status: "pending")))
            let decision = await withCheckedContinuation { c in
                approvalWaiters[request.id] = c
                emit(.approvalNeeded(request))
            }
            emit(.eventUpdated(ChatEventRecord(id: request.id, kind: .approval, title: request.title, detail: request.detail, status: decision.rawValue)))
            return ["decision": .string(decision.rawValue)]
        default:
            return ["decision": "decline"]
        }
    }
}

extension AIProviderKind {
    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude API)"
        case .codex: "OpenAI Codex"
        }
    }
}

extension ContextBuilder {
    func systemPrompt(scope: SessionScope, allowedBrandIds: Set<String>) throws -> String {
        switch scope {
        case .brand: return try systemPrompt(scope: scope)
        case .allBrands:
            var s = try systemPrompt(scope: .brand("__none__"), skipBrand: true)
            s += "\n# Kapsam: TÜM MARKALAR (kullanıcı açıkça seçti)\nÖneri araçları yok; yalnızca okuma. Her cümlede hangi markadan söz ettiğini belirt, bilgileri karıştırma.\n"
            for b in try store.brands() where allowedBrandIds.contains(b.id) {
                let open = try store.tasks(brandId: b.id).filter(\.status.isOpen).count
                s += "- \(b.name) (açık görev: \(open)) id=\(b.id)\n"
            }
            let excluded = try store.brands().filter { !allowedBrandIds.contains($0.id) }.count
            if excluded > 0 { s += "\nNot: \(excluded) marka bu sağlayıcıya izin vermediği için kapsam dışı.\n" }
            return s
        }
    }

    func systemPrompt(scope: SessionScope, skipBrand: Bool) throws -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM yyyy EEEE"
        return Self.baseInstructions + "\n\nBugün: \(fmt.string(from: Date())) (\(DayString.from(Date())))\n"
    }
}

final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
    func drain() -> String { lock.lock(); defer { buffer = ""; lock.unlock() }; return buffer }
}

/// Olayları gönderim sırasıyla, eşzamanlı kaydeder.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [ChatEventRecord] = []
    func record(_ event: AIEvent) {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case .event(let e): list.append(e)
        case .eventUpdated(let e):
            if let i = list.firstIndex(where: { $0.id == e.id }) { list[i] = e } else { list.append(e) }
        default: break
        }
    }
    func events() -> [ChatEventRecord] { lock.lock(); defer { lock.unlock() }; return list }
}

actor CodexTurnState {
    struct Outcome: Sendable {
        var text: String
        var status: String
        var error: String?
        var inputTokens: Int
        var outputTokens: Int
        var cachedTokens: Int
    }
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private var outcome = Outcome(text: "", status: "inProgress", inputTokens: 0, outputTokens: 0, cachedTokens: 0)
    private var done = false
    private var waiters: [CheckedContinuation<Outcome, Never>] = []

    func handle(_ note: JSONValue, emit: @Sendable (AIEvent) -> Void) {
        let method = note["method"]?.string ?? ""
        let p = note["params"] ?? .null
        switch method {
        case "item/agentMessage/delta":
            let id = p["itemId"]?.string ?? ""
            if messages[id] == nil {
                if !order.isEmpty { emit(.textDelta("\n\n")) }
                order.append(id)
            }
            let d = p["delta"]?.string ?? ""
            messages[id, default: ""] += d
            emit(.textDelta(d))
        case "item/started":
            let item = p["item"] ?? .null
            switch item["type"]?.string {
            case "commandExecution":
                emit(.event(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .command, title: L("Komut"),
                                            detail: item["command"]?.string ?? "", status: "running")))
            case "fileChange":
                let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }.joined(separator: ", ")
                emit(.event(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .fileChange, title: L("Dosya değişikliği"), detail: paths, status: "running")))
            default: break
            }
        case "item/completed":
            let item = p["item"] ?? .null
            switch item["type"]?.string {
            case "agentMessage":
                let id = item["id"]?.string ?? ""
                if messages[id] == nil { order.append(id) }
                messages[id] = item["text"]?.string ?? messages[id]
            case "commandExecution":
                emit(.eventUpdated(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .command, title: L("Komut"),
                                                   detail: item["command"]?.string ?? "", status: item["status"]?.string ?? "completed")))
            case "fileChange":
                let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }.joined(separator: ", ")
                emit(.eventUpdated(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .fileChange, title: L("Dosya değişikliği"),
                                                   detail: paths, status: item["status"]?.string ?? "completed")))
            default: break
            }
        case "thread/tokenUsage/updated":
            let last = p["tokenUsage"]?["last"] ?? .null
            outcome.inputTokens += last["inputTokens"]?.int ?? 0
            outcome.outputTokens += last["outputTokens"]?.int ?? 0
            outcome.cachedTokens += last["cachedInputTokens"]?.int ?? 0
        case "turn/completed":
            outcome.status = p["turn"]?["status"]?.string ?? "completed"
            outcome.error = p["turn"]?["error"]?["message"]?.string
            outcome.text = order.compactMap { messages[$0] }.joined(separator: "\n\n")
            done = true
            for w in waiters { w.resume(returning: outcome) }
            waiters.removeAll()
        default: break
        }
    }

    func waitForCompletion() async -> Outcome {
        if done { return outcome }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
