import Foundation

// Terminal/CLI öneri köprüsü (İ7). Marka terminalindeki araçlar (Claude Code, Codex CLI) uygulamanın veri tabanına yazamaz;
// yaptıklarını marka klasöründeki `oneriler/*.json` dosyasına yazar. Uygulama dosyayı okur, bekleyen AI önerisine çevirir;
// kullanıcı inceleme sayfasında onaylar. Marka dosyanın bulunduğu klasörden belirlenir; dosyadaki marka adı/kimliği yok sayılır.

/// Öneri dosyasının ayrıştırılmış hâli (şema sürüm 1). Veri tabanına ve dosya sistemine dokunmaz.
public struct SuggestionDocument: Sendable, Hashable {
    public static let schemaVersion = 1
    public static let maxFileBytes = 256 * 1024
    public static let maxItems = 50
    public static let maxFilesPerLog = 20
    public static let maxTitle = 200
    public static let maxShort = 200
    public static let maxText = 8_000
    public static let maxNoteText = 50_000

    public struct TaskItem: Sendable, Hashable {
        public var title: String
        public var notes: String?
        public var status: TaskStatus?
        public var dueDate: String?
        public var priority: Int?
        public var assignee: String?
        public var project: String?
        public var taskId: String?
    }

    public struct WorkLogItem: Sendable, Hashable {
        public var title: String
        public var requested: String
        public var performed: String
        public var decision: String?
        public var approvedBy: String?
        public var clientNotified: String?
        public var date: String?
        public var taskTitle: String?
        public var taskId: String?
        public var inputFiles: [String]
        public var outputFiles: [String]
        public var inputSourceIds: [String]
        public var outputSourceIds: [String]
    }

    public struct RecordItem: Sendable, Hashable {
        public var kind: BrandRecordKind
        public var title: String
        public var detail: String?
        public var dueDate: String?
    }

    public struct NoteItem: Sendable, Hashable {
        public var kind: SourceKind
        public var title: String
        public var body: String
        public var date: String?
    }

    public var tasks: [TaskItem] = []
    public var workLogs: [WorkLogItem] = []
    public var records: [RecordItem] = []
    public var notes: [NoteItem] = []
    public var itemCount: Int { tasks.count + workLogs.count + records.count + notes.count }

    /// JSON'u şemaya göre doğrular. Tanınmayan alanlar (ör. `marka`, `markaId`) yok sayılır; biçim dışı değer dosyayı reddeder.
    public static func parse(_ data: Data) throws -> SuggestionDocument {
        guard data.count <= maxFileBytes else { throw MarkaError.validation(L("Dosya çok büyük (en fazla 256 KB).")) }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MarkaError.validation(L("Dosya geçerli bir JSON nesnesi değil."))
        }
        guard let v = root["surum"] as? NSNumber, !isBool(v), v.doubleValue == Double(schemaVersion) else {
            throw MarkaError.validation(L("“surum” alanı eksik ya da desteklenmiyor (beklenen: 1)."))
        }
        var doc = SuggestionDocument()
        func list(_ key: String) throws -> [[String: Any]] {
            guard let raw = root[key] else { return [] }
            guard let array = raw as? [Any] else { throw MarkaError.validation(LF("“%@” bir dizi olmalı.", key)) }
            return try array.map {
                guard let o = $0 as? [String: Any] else { throw MarkaError.validation(LF("“%@” dizisindeki her öğe bir nesne olmalı.", key)) }
                return o
            }
        }
        var notes = try list("notlar")
        if let single = root["not"] {
            guard let o = single as? [String: Any] else { throw MarkaError.validation(LF("“%@” bir nesne olmalı.", "not")) }
            notes.append(o)
        }
        let tasks = try list("gorevler"), logs = try list("calismaKayitlari"), records = try list("kayitlar")
        let total = tasks.count + logs.count + records.count + notes.count
        guard total > 0 else {
            throw MarkaError.validation(L("Dosyada öneri yok: gorevler, calismaKayitlari, kayitlar ya da notlar dizisi bekleniyor."))
        }
        guard total <= maxItems else { throw MarkaError.validation(LF("Çok fazla öğe: %1$d (sınır: %2$d).", total, maxItems)) }

        for (i, o) in tasks.enumerated() {
            let r = Reader(dict: o, label: LF("%d. görev", i + 1))
            doc.tasks.append(TaskItem(
                title: try r.title(), notes: try r.text("aciklama", max: maxText),
                status: try r.choice("durum", taskStatuses), dueDate: try r.day("sonTarih"),
                priority: try r.priority("oncelik"), assignee: try r.text("sorumlu", max: maxShort),
                project: try r.text("proje", max: maxShort), taskId: try r.text("gorevId", max: maxShort)))
            if doc.tasks[i].taskId != nil, doc.tasks[i].status != .done {
                throw MarkaError.validation(LF("%@: “gorevId” yalnızca “durum”: “bitti” ile kullanılır (var olan görevi tamamlamak için).", r.label))
            }
        }
        for (i, o) in logs.enumerated() {
            let r = Reader(dict: o, label: LF("%d. iş kaydı", i + 1))
            let performed = try r.text("neYapildi", max: maxText)
            guard let performed else { throw MarkaError.validation(LF("%1$@: “%2$@” alanı zorunlu.", r.label, "neYapildi")) }
            doc.workLogs.append(WorkLogItem(
                title: try r.title(), requested: try r.text("neIstendi", max: maxText) ?? "", performed: performed,
                decision: try r.text("karar", max: maxText), approvedBy: try r.text("kimOnayladi", max: maxShort),
                clientNotified: try r.text("musteriyeBildirilen", max: maxText), date: try r.day("tarih"),
                taskTitle: try r.text("gorev", max: maxTitle), taskId: try r.text("gorevId", max: maxShort),
                inputFiles: try r.strings("girdiDosyalari"), outputFiles: try r.strings("ciktiDosyalari"),
                inputSourceIds: try r.strings("girdiKaynaklari"), outputSourceIds: try r.strings("ciktiKaynaklari")))
        }
        for (i, o) in records.enumerated() {
            let r = Reader(dict: o, label: LF("%d. kayıt", i + 1))
            guard let kind = try r.choice("tur", recordKinds) else { throw MarkaError.validation(LF("%1$@: “%2$@” alanı zorunlu.", r.label, "tur")) }
            doc.records.append(RecordItem(kind: kind, title: try r.title(), detail: try r.text("aciklama", max: maxText),
                                          dueDate: try r.day("sonTarih")))
        }
        for (i, o) in notes.enumerated() {
            let r = Reader(dict: o, label: LF("%d. not", i + 1))
            guard let body = try r.text("metin", max: maxNoteText) else { throw MarkaError.validation(LF("%1$@: “%2$@” alanı zorunlu.", r.label, "metin")) }
            doc.notes.append(NoteItem(kind: try r.choice("tur", noteKinds) ?? .note, title: try r.title(), body: body,
                                      date: try r.day("tarih")))
        }
        return doc
    }

    static let taskStatuses: [String: TaskStatus] = [
        "yapilacak": .todo, "todo": .todo, "suruyor": .inProgress, "devam": .inProgress, "inprogress": .inProgress,
        "bekliyor": .waiting, "waiting": .waiting, "bitti": .done, "tamamlandi": .done, "done": .done,
    ]
    static let recordKinds: [String: BrandRecordKind] = [
        "hedef": .goal, "goal": .goal, "talep": .request, "request": .request, "soz": .promise, "promise": .promise,
        "karar": .decision, "decision": .decision, "teklif": .proposal, "proposal": .proposal,
        "sozlesme": .contract, "contract": .contract, "tarih": .milestone, "milestone": .milestone,
    ]
    static let noteKinds: [String: SourceKind] = ["not": .note, "note": .note, "gorusme": .meeting, "meeting": .meeting]

    /// JSON'daki `true/false` da NSNumber'dır; sürüm alanında kabul edilmez.
    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    /// Seçenek değerlerini karşılaştırmak için: küçük harf, Türkçe karakterler ASCII'ye (ör. "Söz" → "soz", "Sürüyor" → "suruyor").
    static func fold(_ s: String) -> String {
        s.trimmed.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    struct Reader {
        let dict: [String: Any]
        let label: String

        func title() throws -> String {
            guard let t = try text("baslik", max: SuggestionDocument.maxTitle) else {
                throw MarkaError.validation(LF("%1$@: “%2$@” alanı zorunlu.", label, "baslik"))
            }
            // Başlık tek satır: satır sonları ve art arda boşluklar teke indirilir.
            return t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }

        /// Boş ya da `null` metin yok sayılır (`nil`).
        func text(_ key: String, max: Int) throws -> String? {
            guard let raw = dict[key], !(raw is NSNull) else { return nil }
            guard let s = raw as? String else { throw MarkaError.validation(LF("%1$@: “%2$@” metin olmalı.", label, key)) }
            let t = s.trimmed
            guard t.count <= max else { throw MarkaError.validation(LF("%1$@: “%2$@” çok uzun (sınır: %3$d karakter).", label, key, max)) }
            guard !t.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" && $0 != "\r" }) else {
                throw MarkaError.validation(LF("%1$@: “%2$@” denetim karakteri içeriyor.", label, key))
            }
            return t.isEmpty ? nil : t
        }

        func day(_ key: String) throws -> String? {
            guard let d = try text(key, max: 10) else { return nil }
            guard DayString.isValid(d) else { throw MarkaError.validation(LF("%1$@: “%2$@” YYYY-AA-GG biçiminde olmalı.", label, key)) }
            return d
        }

        func choice<T>(_ key: String, _ options: [String: T]) throws -> T? {
            guard let v = try text(key, max: 40) else { return nil }
            guard let hit = options[SuggestionDocument.fold(v)] else {
                throw MarkaError.validation(LF("%1$@: “%2$@” değeri tanınmadı: %3$@", label, key, v))
            }
            return hit
        }

        /// `dusuk` / `orta` / `yuksek` ya da 0–3.
        func priority(_ key: String) throws -> Int? {
            guard let raw = dict[key], !(raw is NSNull) else { return nil }
            if let n = raw as? NSNumber, !SuggestionDocument.isBool(n) {
                guard n.doubleValue == Double(n.intValue), (0...3).contains(n.intValue) else {
                    throw MarkaError.validation(LF("%1$@: “%2$@” değeri tanınmadı: %3$@", label, key, n.stringValue))
                }
                return n.intValue
            }
            return try choice(key, ["yok": 0, "dusuk": 1, "low": 1, "orta": 2, "medium": 2, "yuksek": 3, "high": 3])
        }

        func strings(_ key: String) throws -> [String] {
            guard let raw = dict[key], !(raw is NSNull) else { return [] }
            guard let array = raw as? [Any], array.allSatisfy({ $0 is String }) else {
                throw MarkaError.validation(LF("%1$@: “%2$@” metin dizisi olmalı.", label, key))
            }
            let out = (array as! [String]).map(\.trimmed).filter { !$0.isEmpty }
            guard out.count <= SuggestionDocument.maxFilesPerLog, out.allSatisfy({ $0.count <= 1024 }) else {
                throw MarkaError.validation(LF("%1$@: “%2$@” çok uzun (sınır: %3$d öğe).", label, key, SuggestionDocument.maxFilesPerLog))
            }
            return out
        }
    }
}

/// Marka klasöründeki `oneriler/` kutusunu tarar ve öneri dosyalarını bekleyen önerilere çevirir.
public struct SuggestionInbox: Sendable {
    public static let folderName = "oneriler"
    public static let processedFolderName = "islenmis"
    /// Çalışma kaydına bağlanan tek dosyanın üst sınırı (klasörden içe almayla aynı).
    public static let maxAttachmentBytes = 50_000_000

    public let folders: BrandFolders
    var store: Store { folders.store }

    public init(folders: BrandFolders) { self.folders = folders }

    public struct Failure: @unchecked Sendable {
        /// Marka klasörüne göreli ad (ör. `oneriler/gun-sonu.json`).
        public var fileName: String
        /// Kullanıcıya gösterilecek Türkçe açıklama.
        public var message: String
        /// Aynı dosya durumu için hatanın bir kez gösterilmesini sağlayan anahtar (ad + boyut + değişiklik zamanı).
        public var fingerprint: String
        /// Tanı kaydı için özgün hata (mesajı saklanmaz; yalnızca tür ve kod).
        public var error: Error
    }

    public struct Result: @unchecked Sendable {
        public var created: [AIProposal] = []
        public var failures: [Failure] = []
    }

    /// Markanın klasörü hiç oluşturulmadıysa (terminal/Codex açılmadıysa) tarama yapılmaz ve klasör oluşturulmaz.
    /// - Parameter settle: son bu kadar saniyede değişmiş dosya atlanır (yazılması sürüyor olabilir; yarım JSON hata sayılmasın).
    public func scan(brandId: String, settle: TimeInterval = 0, now: Date = Date()) -> Result {
        var result = Result()
        guard let dir = try? folders.existingFolder(brandId: brandId) else { return result }
        let inbox = dir.appendingPathComponent(Self.folderName, isDirectory: true)
        var st = stat()
        guard lstat(inbox.path, &st) == 0 else { return result }
        let kind = st.st_mode & S_IFMT
        let base = SandboxProfile.canonical(dir.path)
        if kind != S_IFDIR || !SandboxProfile.canonical(inbox.path).hasPrefix(base + "/") {
            // `oneriler` başka bir yere (ör. başka markanın klasörüne) giden bağ: hiç okunmaz.
            result.failures.append(Failure(fileName: Self.folderName, message: L("“oneriler” gerçek bir klasör değil (sembolik bağ olabilir); okunmadı."),
                                           fingerprint: "\(brandId)|\(Self.folderName)|\(kind)|\(st.st_mtimespec.tv_sec)",
                                           error: MarkaError.validation(L("“oneriler” gerçek bir klasör değil (sembolik bağ olabilir); okunmadı."))))
            return result
        }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? [])
            .filter { !$0.hasPrefix(".") && ($0 as NSString).pathExtension.lowercased() == "json" }
            .sorted()
        for name in names {
            let url = inbox.appendingPathComponent(name)
            var fst = stat()
            lstat(url.path, &fst)
            let modified = Double(fst.st_mtimespec.tv_sec) + Double(fst.st_mtimespec.tv_nsec) / 1e9
            if settle > 0, now.timeIntervalSince1970 - modified < settle { continue }
            let rel = Self.folderName + "/" + name
            do {
                result.created += try process(file: url, brandDir: dir, brandId: brandId)
            } catch {
                let message = (error as? MarkaError)?.errorDescription ?? L("Dosya okunamadı.")
                result.failures.append(Failure(fileName: rel, message: message,
                                               fingerprint: "\(brandId)|\(rel)|\(fst.st_size)|\(fst.st_mtimespec.tv_sec).\(fst.st_mtimespec.tv_nsec)",
                                               error: error))
            }
        }
        return result
    }

    /// Tek dosya: güvenli okuma → sha256 → daha önce işlendi mi → şema → öneriler (tek işlem) → `islenmis/` altına taşıma.
    func process(file: URL, brandDir: URL, brandId: String) throws -> [AIProposal] {
        let canonical = try FileImportGuard.canonicalRegularFile(at: file, confineTo: brandDir)
        var st = stat()
        if lstat(canonical.path, &st) == 0, st.st_size > SuggestionDocument.maxFileBytes {
            throw MarkaError.validation(L("Dosya çok büyük (en fazla 256 KB)."))
        }
        let data = try FileImportGuard.readNoFollow(canonical)
        guard data.count <= SuggestionDocument.maxFileBytes else { throw MarkaError.validation(L("Dosya çok büyük (en fazla 256 KB).")) }
        let sha = FileVault.sha256(data)
        if try store.isSuggestionFileProcessed(brandId: brandId, sha256: sha) {
            moveToProcessed(canonical, brandDir: brandDir, sha256: sha)
            return []
        }
        let doc = try SuggestionDocument.parse(data)
        let drafts = try makeDrafts(doc, brandId: brandId, brandDir: brandDir)
        let created = try store.ingestSuggestionFile(brandId: brandId, fileName: file.lastPathComponent, sha256: sha, drafts: drafts)
        moveToProcessed(canonical, brandDir: brandDir, sha256: sha)
        return created
    }

    func makeDrafts(_ doc: SuggestionDocument, brandId: String, brandDir: URL) throws -> [SuggestionDraft] {
        var drafts: [SuggestionDraft] = []
        let projects = try store.projects(brandId: brandId)
        let tr = Locale(identifier: "tr_TR")
        func ownTask(_ id: String, _ label: String) throws -> WorkTask {
            guard let t = try? store.task(id), t.brandId == brandId else {
                throw MarkaError.validation(LF("%1$@: “gorevId” bu markada bulunamadı: %2$@", label, id))
            }
            return t
        }
        for (i, t) in doc.tasks.enumerated() {
            let label = LF("%d. görev", i + 1)
            if t.status == .done {
                // "Bitti" denen iş markada açık bir görevse yeni görev açılmaz; o görevi tamamlama önerilir.
                let existing = try t.taskId.map { try ownTask($0, label) } ?? store.taskMatching(title: t.title, brandId: brandId, openOnly: true)
                if let existing, existing.status.isOpen {
                    drafts.append(SuggestionDraft(kind: .completeTask, summary: LF("Görevi tamamla: %@", existing.title),
                                                  payload: ProposalPayload.CompleteTask(taskId: existing.id)))
                    continue
                }
                if let existing { throw MarkaError.validation(LF("%1$@: görev zaten kapalı: %2$@", label, existing.title)) }
            }
            var notes = t.notes
            var projectId: String?
            if let name = t.project {
                projectId = projects.first { $0.name.trimmed.compare(name, options: .caseInsensitive, range: nil, locale: tr) == .orderedSame }?.id
                if projectId == nil { notes = [notes, LF("Proje: %@", name)].compactMap { $0 }.joined(separator: "\n") }
            }
            let payload = ProposalPayload.CreateTask(title: t.title, notes: notes, priority: t.priority, dueDate: t.dueDate,
                                                     assignee: t.assignee, projectId: projectId, status: t.status)
            drafts.append(SuggestionDraft(kind: .createTask, summary: t.status == .done ? LF("Tamamlanan iş: %@", t.title) : LF("Yeni görev: %@", t.title),
                                          payload: payload))
        }
        for r in doc.records {
            drafts.append(SuggestionDraft(kind: .createBrandRecord, summary: LF("Marka kaydı: %@", r.title),
                                          payload: ProposalPayload.CreateBrandRecord(kind: r.kind, title: r.title, detail: r.detail, dueDate: r.dueDate)))
        }
        for n in doc.notes {
            drafts.append(SuggestionDraft(kind: .createNote, summary: n.kind == .meeting ? LF("Görüşme notu: %@", n.title) : LF("Not: %@", n.title),
                                          payload: ProposalPayload.CreateNote(kind: n.kind, title: n.title, body: n.body, capturedOn: n.date)))
        }
        for (i, l) in doc.workLogs.enumerated() {
            let label = LF("%d. iş kaydı", i + 1)
            if let id = l.taskId { _ = try ownTask(id, label) }
            let payload = ProposalPayload.CreateWorkLog(
                title: l.title, requested: l.requested, performed: l.performed, decision: l.decision, clientNotified: l.clientNotified,
                taskId: l.taskId, inputSourceIds: l.inputSourceIds, outputSourceIds: l.outputSourceIds, approvedBy: l.approvedBy,
                occurredOn: l.date, taskTitle: l.taskId == nil ? l.taskTitle : nil,
                inputFiles: try l.inputFiles.map { try stage($0, brandDir: brandDir, label: label) },
                outputFiles: try l.outputFiles.map { try stage($0, brandDir: brandDir, label: label) })
            drafts.append(SuggestionDraft(kind: .createWorkLog, summary: LF("Çalışma kaydı: %@", l.title), payload: payload))
        }
        return drafts
    }

    /// Çalışma kaydına bağlanacak dosyayı marka klasöründen güvenle okur ve içerik adresli depoya alır. Kaynak kaydı onayda oluşur.
    func stage(_ rel: String, brandDir: URL, label: String) throws -> ProposalPayload.StagedFile {
        guard !rel.hasPrefix("/"), !rel.hasPrefix("~") else {
            throw MarkaError.validation(LF("%1$@: dosya yolu marka klasörüne göreli olmalı: %2$@", label, rel))
        }
        let url = brandDir.appendingPathComponent(rel)
        var st = stat()
        guard lstat(url.path, &st) == 0 else { throw MarkaError.validation(LF("%1$@: dosya bulunamadı: %2$@", label, rel)) }
        let canonical = try FileImportGuard.canonicalRegularFile(at: url, confineTo: brandDir)
        guard st.st_size <= Self.maxAttachmentBytes else { throw MarkaError.validation(LF("%1$@: dosya çok büyük: %2$@", label, rel)) }
        let data = try FileImportGuard.readNoFollow(canonical)
        let stored = try store.vault.store(data: data, fileExtension: url.pathExtension)
        return ProposalPayload.StagedFile(path: rel, fileName: url.lastPathComponent, storedPath: stored.relativePath,
                                          sha256: stored.sha256, byteSize: stored.byteSize, mimeType: TextExtractor.mimeType(for: url))
    }

    /// İşlenen dosyayı `oneriler/islenmis/` altına taşır. Hedef klasör gerçek bir klasör olmalı ve marka klasörünün içinde kalmalı
    /// (bağ üzerinden başka markanın klasörüne yazılmaz). Taşınamazsa sha256 kaydı yine ikinci kez önerilmesini engeller.
    @discardableResult
    func moveToProcessed(_ file: URL, brandDir: URL, sha256: String) -> Bool {
        let target = file.deletingLastPathComponent().appendingPathComponent(Self.processedFolderName, isDirectory: true)
        var st = stat()
        if lstat(target.path, &st) != 0 { mkdir(target.path, 0o755) }
        guard lstat(target.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR,
              SandboxProfile.canonical(target.path).hasPrefix(SandboxProfile.canonical(brandDir.path) + "/") else { return false }
        let name = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        for candidate in [file.lastPathComponent, "\(name)-\(sha256.prefix(8)).\(ext)", "\(name)-\(newID().prefix(8)).\(ext)"] {
            let dest = target.appendingPathComponent(candidate)
            if lstat(dest.path, &st) == 0 { continue }
            return rename(file.path, dest.path) == 0
        }
        return false
    }
}
