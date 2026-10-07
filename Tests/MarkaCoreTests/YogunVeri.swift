import Foundation
import GRDB
@testable import MarkaCore

/// Ölçek testleri için yoğun SENTETİK veri (bir danışmanın ~1 yılı). Tüm adlar ve metinler uydurmadır; gerçek veri yoktur.
/// Üretim belirlenimlidir (sabit tohum): aynı ölçek her çalıştırmada aynı dağılımı verir.
///
/// Markalar `createBrand` ile (kurallar + denetim olayı) açılır; geri kalan satırlar hız için tek işlemde doğrudan yazılır.
/// Bu yüzden toplu satırlar kendi denetim olayını bırakmaz; yerine `auditPerBrand` kadar sentetik denetim olayı eklenir.
struct YogunVeri {
    struct Olcek: Sendable {
        var brands = 8
        var tasksPerBrand = 2_500
        var sourcesPerBrand = 1_500
        var workLogsPerBrand = 800
        var financePerBrand = 100
        var timeEntriesPerBrand = 500
        var recordsPerBrand = 300
        var proposalsPerBrand = 200
        var auditPerBrand = 5_000
        var wikiPagesPerBrand = 30
        var sessionsPerBrand = 30
        var teamMembers = 40

        static let tam = Olcek()
        /// Hızlı testler için küçük ölçek (aynı dağılım).
        static let kucuk = Olcek(brands: 3, tasksPerBrand: 120, sourcesPerBrand: 80, workLogsPerBrand: 40, financePerBrand: 10,
                                 timeEntriesPerBrand: 30, recordsPerBrand: 20, proposalsPerBrand: 20, auditPerBrand: 100,
                                 wikiPagesPerBrand: 5, sessionsPerBrand: 5, teamMembers: 12)
    }

    let store: Store
    let brandIds: [String]
    /// Stüdyo (kendi şirket) markası; `brandIds[0]`.
    var ownBrandId: String { brandIds[0] }
    let now: Date

    /// Belirlenimli sözde rastgele (SplitMix64).
    struct Zar {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
        mutating func chance(_ p: Double) -> Bool { Double(next() % 10_000) / 10_000 < p }
        mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    }

    static let kelimeler = ["kampanya", "lansman", "bülten", "sosyal", "medya", "içerik", "takvim", "bütçe", "rapor", "görsel",
                            "afiş", "katalog", "basın", "etkinlik", "fuar", "web", "sayfa", "tasarım", "metin", "çekim",
                            "video", "röportaj", "anket", "müşteri", "teklif", "sözleşme", "toplantı", "sunum", "strateji",
                            "marka", "logo", "renk", "yazı", "ölçüm", "dönüşüm", "reklam", "arama", "e-posta", "abone",
                            "ürün", "fiyat", "kargo", "şube", "menü", "yangın", "lojistik", "kafe", "depo", "ızgara", "çiçek"]

    static func cumle(_ z: inout Zar, _ n: Int) -> String {
        (0..<n).map { _ in z.pick(kelimeler) }.joined(separator: " ")
    }

    /// Yoğun çalışma alanı üretir. `now`: verinin yığıldığı son an; kayıtlar son 365 güne yayılır.
    static func uret(_ store: Store, olcek: Olcek = .tam, now: Date = Date(), seed: UInt64 = 2026) throws -> YogunVeri {
        var z = Zar(state: seed)
        let cal = StatusService.turkishCalendar
        let day: TimeInterval = 86_400
        let adlar = ["Deneme Yangın", "Kuzey Lojistik", "Örnek Kafe Zinciri", "Mavi Çiçekçilik", "Yıldız Kargo", "Ada Fırın",
                     "Bulut Yazılım", "Ege Zeytin", "Dağ Kampı", "Liman Gıda"]
        var brandIds: [String] = []
        for i in 0..<olcek.brands {
            let name = i == 0 ? "Deneme Stüdyo" : (i - 1 < adlar.count ? adlar[i - 1] : "Deneme Marka \(i)")
            let b = try store.createBrand(name: name, sector: "Sentetik", isOwn: i == 0)
            brandIds.append(b.id)
        }
        try store.write { db in
            // Ekip: hiyerarşik 40 üye (insan + yapay zekâ).
            var members: [TeamMember] = []
            for i in 0..<olcek.teamMembers {
                let boss = i == 0 ? nil : members[(i - 1) / 4].id
                let level: MemberLevel = i == 0 ? .director : i < 5 ? .lead : z.pick([.senior, .mid, .junior, .intern])
                let m = TeamMember(kind: i % 5 == 4 ? .ai : .human, name: "Üye \(i)", title: "Unvan \(i % 7)", level: level,
                                   department: "Bölüm \(i % 4)", reportsToId: boss, status: i % 13 == 12 ? .archived : .active,
                                   charter: i % 5 == 4 ? cumle(&z, 8) : "")
                try m.insert(db)
                members.append(m)
            }
            let activeMembers = members.filter { $0.status == .active }
            let aiMembers = members.filter { $0.kind == .ai }

            for (bi, brandId) in brandIds.enumerated() {
                func past(_ maxDays: Int = 365) -> Date { now.addingTimeInterval(-Double(z.int(maxDays * 24)) * 3600 - 60) }
                func dayString(_ offsetDays: Int) -> String { DayString.from(now.addingTimeInterval(Double(offsetDays) * day), calendar: cal) }

                if bi > 0 {
                    for (k, m) in activeMembers.shuffledDeterministic(&z).prefix(3 + bi % 4).enumerated() {
                        try BrandAssignment(brandId: brandId, memberId: m.id, role: k == 0 ? .lead : .member).insert(db)
                    }
                }
                for section in ProfileSection.allCases {
                    try db.execute(sql: "INSERT INTO brandProfile(brandId, section, body, updatedAt) VALUES (?, ?, ?, ?)",
                                   arguments: [brandId, section.rawValue, cumle(&z, 30), now])
                }
                for c in 0..<20 { try Contact(brandId: brandId, name: "Kişi \(c)", role: "Rol \(c % 3)").insert(db) }
                let projects = try (0..<10).map { p -> Project in
                    let pr = Project(brandId: brandId, name: "Proje \(p)", status: p < 7 ? .active : .done)
                    try pr.insert(db); return pr
                }

                // Görevler.
                var doneTaskIds: [String] = []
                var taskIds: [String] = []
                for t in 0..<olcek.tasksPerBrand {
                    let r = z.int(100)
                    let status: TaskStatus = r < 60 ? .done : r < 70 ? .cancelled : r < 90 ? .todo : r < 95 ? .inProgress : .waiting
                    let created = past()
                    let due: String? = z.chance(0.7) ? dayString(z.int(400) - 300) : nil
                    let completed: Date? = status == .done ? min(now, created.addingTimeInterval(Double(z.int(30 * 24)) * 3600)) : nil
                    let task = WorkTask(brandId: brandId, projectId: z.chance(0.4) ? z.pick(projects).id : nil,
                                        title: "Görev \(t) " + cumle(&z, 3), notes: cumle(&z, 12), assignee: z.chance(0.5) ? "Üye \(z.int(40))" : "",
                                        priority: z.int(4), dueDate: due, status: status, createdAt: created,
                                        updatedAt: completed ?? created, completedAt: completed)
                    try task.insert(db)
                    taskIds.append(task.id)
                    if status == .done { doneTaskIds.append(task.id) }
                }

                // Kaynaklar (not / dosya / görüşme …).
                var sourceIds: [String] = []
                for s in 0..<olcek.sourcesPerBrand {
                    let kind = z.pick(SourceKind.allCases)
                    let isFile = kind == .file || kind == .workOutput || kind == .imported
                    let sha = String(format: "%016llx%016llx", z.next(), z.next())
                    let captured = past()
                    let src = Source(brandId: brandId, kind: kind, title: "Kaynak \(s) " + cumle(&z, 3), body: cumle(&z, 40),
                                     fileName: isFile ? "dosya-\(s).pdf" : nil, filePath: isFile ? "\(sha.prefix(2))/\(sha)" : nil,
                                     mimeType: isFile ? "application/pdf" : nil, sha256: sha, byteSize: isFile ? 1000 + z.int(90_000) : 0,
                                     capturedAt: captured, createdAt: captured, archivedAt: z.chance(0.05) ? now : nil)
                    try src.insert(db)
                    sourceIds.append(src.id)
                }

                // İş kayıtları (yarısı biten göreve bağlı) + dosya bağları.
                for w in 0..<olcek.workLogsPerBrand {
                    let r = z.int(100)
                    let status: WorkLogStatus = r < 70 ? .verified : r < 95 ? .draft : .retracted
                    let at = past()
                    let log = WorkLog(brandId: brandId, taskId: z.chance(0.5) && !doneTaskIds.isEmpty ? z.pick(doneTaskIds) : nil,
                                      title: "İş \(w) " + cumle(&z, 3), requested: cumle(&z, 6), performed: cumle(&z, 10),
                                      decision: z.chance(0.3) ? cumle(&z, 5) : "", status: status,
                                      verifiedAt: status == .verified ? at : nil, verifiedBy: status == .verified ? "Deneme" : nil,
                                      occurredAt: at, createdAt: at, updatedAt: at)
                    try log.insert(db)
                    let a = z.pick(sourceIds), b = z.pick(sourceIds)
                    try WorkLogSource(workLogId: log.id, sourceId: a, role: .input).insert(db)
                    if b != a { try WorkLogSource(workLogId: log.id, sourceId: b, role: .output).insert(db) }
                }

                // Marka kayıtları.
                for k in 0..<olcek.recordsPerBrand {
                    let kind = z.pick(BrandRecordKind.allCases)
                    let created = past()
                    let closed = z.chance(0.6)
                    let status: RecordStatus = closed ? (z.chance(0.85) ? .done : .cancelled) : BrandRecord.defaultStatus(for: kind)
                    try BrandRecord(brandId: brandId, kind: kind, title: "Kayıt \(k) " + cumle(&z, 3), status: status,
                                    dueDate: z.chance(0.5) ? dayString(z.int(200) - 100) : nil, createdAt: created,
                                    updatedAt: created, closedAt: closed ? min(now, created.addingTimeInterval(7 * day)) : nil).insert(db)
                }

                // Finans ve süre kayıtları.
                for f in 0..<olcek.financePerBrand {
                    let kind: FinanceKind = f % 3 == 0 ? .budget : .payment
                    try FinanceEntry(brandId: brandId, kind: kind, title: "Kalem \(f)", amountMinor: Int64(1000 + z.int(500_000)),
                                     date: dayString(z.int(365) - 300), status: kind == .payment ? z.pick(PaymentStatus.allCases) : nil).insert(db)
                }
                for _ in 0..<olcek.timeEntriesPerBrand {
                    let start = past()
                    let secs = 300 + z.int(7200)
                    try TimeEntry(taskId: z.pick(taskIds), brandId: brandId, startedAt: start,
                                  endedAt: start.addingTimeInterval(Double(secs)), seconds: secs).insert(db)
                }
                try db.execute(sql: """
                    UPDATE workTask SET timeSpentSeconds = COALESCE((SELECT SUM(seconds) FROM timeEntry e
                      WHERE e.taskId = workTask.id AND e.endedAt IS NOT NULL), 0) WHERE brandId = ?
                    """, arguments: [brandId])

                // Bilgi sayfaları (bir kısmında onay bekleyen sürüm).
                for p in 0..<olcek.wikiPagesPerBrand {
                    let page = WikiPage(brandId: brandId, kind: z.pick(WikiPageKind.allCases), title: "Sayfa \(p) " + cumle(&z, 2), slug: "sayfa-\(p)")
                    try page.insert(db)
                    let rev = WikiRevision(pageId: page.id, brandId: brandId, number: 1, body: cumle(&z, 60), state: .approved, actor: .user,
                                           createdAt: past(), decidedAt: now)
                    try rev.insert(db)
                    try db.execute(sql: "UPDATE wikiPage SET currentRevisionId = ? WHERE id = ?", arguments: [rev.id, page.id])
                    if p % 10 == 0 {
                        try WikiRevision(pageId: page.id, brandId: brandId, number: 2, body: cumle(&z, 60), state: .proposed, actor: .ai,
                                         basedOnRevisionId: rev.id).insert(db)
                    }
                }

                // Sohbet oturumları (bir kısmı yapay zekâ çalışanı rolüyle) ve öneriler.
                var sessionIds: [String] = []
                for s in 0..<olcek.sessionsPerBrand {
                    let at = past()
                    let sess = AISession(brandId: brandId, scope: .brand, provider: .anthropic, model: "deneme", title: "Oturum \(s)",
                                         memberId: s % 3 == 0 && !aiMembers.isEmpty ? z.pick(aiMembers).id : nil, createdAt: at, updatedAt: at)
                    try sess.insert(db)
                    sessionIds.append(sess.id)
                }
                for p in 0..<olcek.proposalsPerBrand {
                    let r = z.int(100)
                    let status: ProposalStatus = r < 10 ? .pending : r < 70 ? .applied : r < 95 ? .rejected : .reverted
                    let created = past()
                    let terminal = z.chance(0.5)
                    let payload = #"{"title":"Öneri \#(p)"}"#
                    try AIProposal(sessionId: terminal ? nil : z.pick(sessionIds), brandId: brandId, kind: z.pick([.createTask, .createBrandRecord, .createNote]),
                                   summary: "Öneri \(p) " + cumle(&z, 3), payloadJSON: payload, status: status,
                                   createdAt: created, decidedAt: status == .pending ? nil : min(now, created.addingTimeInterval(day)),
                                   origin: terminal ? .terminal : nil, originRef: terminal ? "gorevler.json" : nil).insert(db)
                }

                // Sentetik denetim olayları.
                let entities = ["task", "source", "workLog", "brandRecord", "aiProposal", "financeEntry"]
                for _ in 0..<olcek.auditPerBrand {
                    try AuditEvent(at: past(), actor: z.pick(Actor.allCases), brandId: brandId, entity: z.pick(entities),
                                   entityId: z.pick(taskIds), action: z.pick(["create", "update", "delete"]),
                                   beforeJSON: nil, afterJSON: #"{"x":1}"#).insert(db)
                }
            }
        }
        return YogunVeri(store: store, brandIds: brandIds, now: now)
    }

    /// Bellek içi, süreç boyunca bir kez üretilen tam ölçekli çalışma alanı (salt okunur testler paylaşır; yazma YAPMAYIN).
    static let paylasilan: YogunVeri = {
        do { return try uret(Store(database: try AppDatabase.inMemory())) }
        catch { fatalError("yoğun veri üretilemedi: \(error)") }
    }()

    /// `ContinuousClock` ile `tekrar` kez ölçer, medyanı milisaniye olarak döndürür (ilk çağrı ısınma, sayılmaz).
    static func medyanMs(_ tekrar: Int = 5, _ blok: () throws -> Void) rethrows -> Double {
        try blok()
        let clock = ContinuousClock()
        var olcumler: [Double] = []
        for _ in 0..<tekrar {
            let d = try clock.measure(blok)
            olcumler.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        olcumler.sort()
        return olcumler[olcumler.count / 2]
    }
}

extension Array {
    func shuffledDeterministic(_ z: inout YogunVeri.Zar) -> [Element] {
        var a = self
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, z.int(i + 1)) }
        return a
    }
}
