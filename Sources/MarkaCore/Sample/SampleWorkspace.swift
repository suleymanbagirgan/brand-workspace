import Foundation
import GRDB

/// Örnek marka: ilk açılışta kullanıcı kendi markasını eklemeden uygulamayı tanısın diye tek, uydurma bir marka ve küçük ama
/// gerçekçi veri (profil, proje, görev, hedef, karar bekleyen kayıt, not, doğrulanmış iş kaydı, finans). Yapay zekâ gerekmez:
/// rapor önizlemesi ve PDF doğrulanmış iş kayıtlarından kurulur.
///
/// Kurallar: hepsi tek işlemde yazılır ve her yazma denetim olayı bırakır (aktör `.system`); örnek markanın AI izni yoktur
/// (varsayılan); kimliği `setting(sampleBrandId)` ile işaretlenir (yeni migration yok); aynı çalışma alanında ikinci örnek
/// açılmaz. Örnek marka normal arşiv yoluyla (`setBrandArchived`) arşivlenir. Ad ve içerik uydurmadır.
public enum SampleWorkspace {
    /// Örnek markanın kimliğini tutan ayar anahtarı.
    public static let settingKey = "sampleBrandId"
    /// Örnek markanın adı (veri; dil ayarından bağımsız).
    public static let brandName = "Örnek Marka"
    /// İş kayıtlarını doğrulayan olarak yazılan ad.
    public static let verifier = "Örnek veri"
}

extension Store {
    /// Örnek markanın kimliği (işaretli ve marka hâlâ varsa); yoksa `nil`.
    public func sampleBrandId() throws -> String? {
        try read { db in try Self.sampleBrandId(db) }
    }

    /// Bu marka örnek marka mı?
    public func isSampleBrand(_ brandId: String) -> Bool {
        (try? sampleBrandId()) == brandId
    }

    static func sampleBrandId(_ db: Database) throws -> String? {
        guard let id = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [SampleWorkspace.settingKey]),
              try Brand.fetchOne(db, key: id) != nil else { return nil }
        return id
    }

    /// Örnek markayı oluşturur ya da var olanı döndürür (idempotent). Var olan arşivlenmişse arşivden çıkarılır (kullanıcı
    /// "Örnek markayla gez" dediğinde markaya gidilebilsin); bu da denetim olayı bırakır.
    @discardableResult
    public func createSampleBrand(now: Date = Date(), calendar: Calendar = StatusService.turkishCalendar) throws -> Brand {
        try writer.write { db in
            if let id = try Self.sampleBrandId(db), var existing = try Brand.fetchOne(db, key: id) {
                if existing.status == .archived {
                    let before = existing
                    existing.status = .active
                    existing.updatedAt = Date()
                    try existing.update(db)
                    try audit(db, actor: .system, brandId: id, entity: "brand", entityId: id, action: "update", before: before, after: existing)
                }
                return existing
            }
            return try seedSample(db, now: now, calendar: calendar)
        }
    }

    private func seedSample(_ db: Database, now: Date, calendar: Calendar) throws -> Brand {
        let actor = Actor.system
        // Ad çakışırsa (kullanıcı aynı adda marka açmışsa) numaralı ad.
        let tr = Locale(identifier: "tr_TR")
        let taken = Set(try String.fetchAll(db, sql: "SELECT name FROM brand").map { $0.lowercased(with: tr) })
        var name = SampleWorkspace.brandName
        var n = 2
        while taken.contains(name.lowercased(with: tr)) { name = "\(SampleWorkspace.brandName) \(n)"; n += 1 }

        let brand = try insertBrand(db, name: name,
                                    summary: "Uydurma örnek: el yapımı granola ve atıştırmalık üreten küçük bir marka. Ambalaj yenileme, sosyal medya ve bayi satışı için danışmanlık alıyor.",
                                    sector: "Doğal atıştırmalık", isOwn: false, actor: actor)
        let b = brand.id

        // Tarihler: bu haftanın içinde kalır (rapor önizlemesi "Bu hafta" dönemini gösterir).
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 86400)
        let windowStart = max(week.start, now.addingTimeInterval(-3 * 86400))
        func moment(_ fraction: Double) -> Date { windowStart.addingTimeInterval(now.timeIntervalSince(windowStart) * fraction) }
        func day(_ offset: Int) -> String { DayString.from(calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar) }
        let today = day(0)
        let lastDayOfWeek = DayString.from(week.end.addingTimeInterval(-1), calendar: calendar)
        let thisWeekDue = min(day(2), lastDayOfWeek)

        // Marka profili (5 bölüm).
        let profile: [(ProfileSection, String)] = [
            (.audience, "Şehirde yaşayan, sağlıklı atıştırmalık arayan 25–45 yaş arası çalışanlar. Satın alma çoğunlukla kahve dükkânı ve şarküteri raflarında, anlık karar."),
            (.positioning, "Katkısız, az şekerli ve yerel üreticiden yulaf. Vaat: “Rafta en kısa içindekiler listesi.”"),
            (.voice, "Samimi ve sade; hitap “sen”. Abartılı sağlık iddiası yok, “süper gıda” gibi ifadeler kullanılmaz."),
            (.scope, "Ambalaj yenileme, Instagram içerik takvimi ve bayi sunumu. Onayı kurucu verir; teslimler iki haftada bir."),
            (.constraints, "Gıda etiketinde yasal zorunlu bilgiler değişmez. Sağlık beyanı yalnız belgeye dayanır. Rakip ürün adı anılmaz."),
        ]
        for (section, body) in profile {
            try db.execute(sql: "INSERT INTO brandProfile (brandId, section, body, updatedAt) VALUES (?, ?, ?, ?)",
                           arguments: [b, section.rawValue, body, Date()])
            try audit(db, actor: actor, brandId: b, entity: "brandProfile", entityId: b + "/" + section.rawValue,
                      action: "set", before: String?.none, after: body)
        }

        // Projeler.
        let packaging = Project(brandId: b, name: "Ambalaj yenileme", goal: "Rafta fark edilen, içindekileri öne çıkaran yeni ambalaj", dueDate: day(30))
        let social = Project(brandId: b, name: "Sosyal medya ve bayi", goal: "Instagram düzeni ve bayilere yeni sunum", dueDate: day(45))
        for p in [packaging, social] {
            try p.insert(db)
            try audit(db, actor: actor, brandId: b, entity: "project", entityId: p.id, action: "create", before: Project?.none, after: p)
        }

        // Notlar (değişmez kaynak).
        func note(_ kind: SourceKind, _ title: String, _ body: String, at: Date) throws -> Source {
            let data = Data(body.utf8)
            return try insertSource(db, Source(brandId: b, kind: kind, title: title, body: body, sha256: FileVault.sha256(data),
                                               byteSize: data.count, capturedAt: at, actor: actor))
        }
        let meeting = try note(.meeting, "Kurucuyla haftalık görüşme",
                               "Ambalajda içindekiler listesi ön yüze taşınacak. Instagram için haftada üç paylaşım yeterli. Bayi sunumunda fiyat listesi ayrı sayfa olacak.",
                               at: moment(0.1))
        let memo = try note(.note, "Fuar standı notları",
                            "Stant 3×2 metre. Tadım tabağı ve küçük boy paket dağıtılacak. Ölçüler tedarikçiye bu hafta iletilmeli.",
                            at: moment(0.15))

        // Görevler: üçü bu hafta bitti (iş kayıtlarıyla), biri gecikmiş, biri bu hafta bitiyor.
        func task(_ title: String, project: Project?, status: TaskStatus, priority: Int, due: String?, completedAt: Date? = nil,
                  assignee: String = "") throws -> WorkTask {
            try saveTask(db, WorkTask(brandId: b, projectId: project?.id, title: title, assignee: assignee, priority: priority,
                                      dueDate: due, status: status, completedAt: completedAt, actor: actor), actor: actor)
        }
        let doneTimes = [moment(0.3), moment(0.55), moment(0.8)]
        let revision = try task("Ambalaj revizyon listesini çıkar", project: packaging, status: .done, priority: 2, due: day(-1), completedAt: doneTimes[0])
        let calendarTask = try task("Ekim Instagram içerik takvimi", project: social, status: .done, priority: 2, due: today, completedAt: doneTimes[1])
        let deck = try task("Bayi sunum dosyasını güncelle", project: social, status: .done, priority: 1, due: today, completedAt: doneTimes[2])
        _ = try task("Fuar standı ölçülerini tedarikçiye gönder", project: nil, status: .inProgress, priority: 3, due: day(-3))
        _ = try task("Yeni ürün fotoğraf çekimini planla", project: packaging, status: .todo, priority: 2, due: thisWeekDue)
        _ = try task("Müşteri yorumlarını derle", project: social, status: .waiting, priority: 1, due: day(7))
        _ = try task("Web sitesi ürün sayfası metinleri", project: social, status: .todo, priority: 1, due: nil)
        _ = try task("Kasım kampanya fikirleri", project: nil, status: .todo, priority: 0, due: day(14))

        // Doğrulanmış iş kayıtları (rapor maddesi yalnız bunlardan gelir): her biri göreve, biri nota da bağlı.
        let logs: [(WorkTask, String, String, String, [String])] = [
            (revision, "Mevcut ambalajın sorunları ve istenen değişiklikler", "Ön yüz, yan yüz ve etiket için 14 maddelik revizyon listesi çıkarıldı.",
             "İçindekiler listesi ön yüze taşınacak", [meeting.id]),
            (calendarTask, "Ekim ayı için düzenli paylaşım planı", "12 paylaşımlık takvim hazırlandı; her hafta bir tarif, bir üretim, bir müşteri paylaşımı.",
             "Haftada üç paylaşım", []),
            (deck, "Bayilere gidecek güncel sunum", "Sunum yeni fiyat listesi ve raf görselleriyle güncellendi; fiyatlar ayrı sayfaya alındı.", "", [memo.id]),
        ]
        for (i, entry) in logs.enumerated() {
            let log = try saveWorkLog(db, WorkLog(brandId: b, taskId: entry.0.id, title: entry.0.title, requested: entry.1,
                                                  performed: entry.2, decision: entry.3, approvedBy: "Kurucu",
                                                  occurredAt: doneTimes[i], actor: actor),
                                      inputs: entry.4, outputs: [], actor: actor)
            try verifyWorkLog(db, log.id, verifiedBy: SampleWorkspace.verifier, actor: actor)
        }

        // Hedefler ve karar bekleyen kayıt.
        let records = [
            BrandRecord(brandId: b, kind: .goal, title: "Yeni ambalaj yılbaşından önce rafta", detail: "Baskı onayı Kasım ortasına kadar.",
                        dueDate: day(60), projectId: packaging.id),
            BrandRecord(brandId: b, kind: .goal, title: "Bayi sayısını 12'den 18'e çıkar", detail: "Yeni sunumla üç şehirde görüşme.",
                        dueDate: day(90), projectId: social.id),
            BrandRecord(brandId: b, kind: .decision, title: "Ambalaj rengi: krem mi yeşil mi?", detail: "İki örnek baskı kurucuya gönderildi.",
                        dueDate: day(4), sourceId: meeting.id),
        ]
        for r in records {
            try r.insert(db)
            try audit(db, actor: actor, brandId: b, entity: "brandRecord", entityId: r.id, action: "create", before: BrandRecord?.none, after: r)
        }

        // Finans: iki ödeme satırı, bir bütçe.
        let finance = [
            FinanceEntry(brandId: b, kind: .payment, title: "Eylül danışmanlık ücreti", amountMinor: 2_500_000, date: day(-20), status: .collected),
            FinanceEntry(brandId: b, kind: .payment, title: "Ekim danışmanlık ücreti", amountMinor: 2_500_000, date: day(10), status: .planned),
            FinanceEntry(brandId: b, kind: .budget, title: "Ambalaj örnek baskısı", amountMinor: 850_000, note: "İki renk, 50'şer adet"),
        ]
        for e in finance {
            try e.insert(db)
            try audit(db, actor: actor, brandId: b, entity: "financeEntry", entityId: e.id, action: "create", before: FinanceEntry?.none, after: e)
        }

        try db.execute(sql: "INSERT INTO setting(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       arguments: [SampleWorkspace.settingKey, b])
        return brand
    }
}
