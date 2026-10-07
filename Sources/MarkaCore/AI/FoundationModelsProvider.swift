import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Foundation Models sağlayıcısı (E-25, araçsız ilk dilim)
//
// Apple'ın cihaz üstü modeli (macOS 26). Fikir carbocation/CarbocationLocalLLM'den (tek API arkasında yerel model);
// uygulama özgündür. Denemenin (docs/foundation-models-denemesi.md) bulguları burada kurala dönüşür:
// - Araçsız (`supportsTools == false`): denemede araç argümanlarında tarih/parametre hataları ölçüldü; araçlı tur ayrı görevdir.
// - Göreli tarihleri model değil uygulama çözer: talimatın başına hesaplanmış tarih tablosu konur (deneme §4b).
// - Pencere 4096 belirteç (talimat + geçmiş + yanıt toplamı); Türkçede ~2,1 karakter/belirteç ölçüldü (deneme §5):
//   talimat ve geçmiş karakter bütçesiyle kırpılır, aşım yine olursa bağlam hatası olarak bildirilir.
// - Makro yok (Generable makrosu Xcode ister); düz metin yanıtı şema gerektirmez. Command Line Tools ile derlenir.
// - `#if canImport(FoundationModels)` + `@available(macOS 26, *)`: çerçeve yoksa ya da sistem eskiyse sağlayıcı
//   kayıtlı kalır ama anlaşılır bir durum metniyle reddeder; model çağrılmaz.
// - Ağ isteği ve süreç yok: MAS derlemesinde de vardır. Marka × sağlayıcı izni ChatEngine'de denetlenir (varsayılan kapalı).

/// Apple'ın cihaz üstü modelinin durumu (uygulamanın kendi türü; FoundationModels olmadan da derlenir).
public enum AppleModelAvailability: String, Sendable, Equatable, CaseIterable {
    case available
    /// macOS 26 değil ya da bu derlemede FoundationModels yok.
    case unsupportedSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown

    public var isAvailable: Bool { self == .available }

    /// Ayarlar'daki durum satırı ve oturum açılamadığında gösterilen hata.
    public var statusText: String {
        switch self {
        case .available: L("Apple Intelligence bu Mac'te kullanılabilir.")
        case .unsupportedSystem: L("Apple Intelligence için macOS 26 gerekir; bu sistemde kullanılamaz.")
        case .deviceNotEligible: L("Bu Mac Apple Intelligence'ı desteklemiyor.")
        case .appleIntelligenceNotEnabled: L("Apple Intelligence açık değil. Sistem Ayarları'ndan açabilirsin.")
        case .modelNotReady: L("Apple Intelligence modeli henüz hazır değil; indiriliyor olabilir. Biraz sonra yeniden dene.")
        case .unknown: L("Apple Intelligence durumu okunamadı.")
        }
    }

    /// Sistemin bildirdiği durum. Yalnız durumu okur; modeli çağırmaz, içerik göndermez.
    public static func current() -> AppleModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .unknown
                }
            }
        }
        #endif
        return .unsupportedSystem
    }

    /// Bu ikilide FoundationModels derlendi mi (CLT/Xcode SDK'sında çerçeve varsa `true`).
    public static var frameworkCompiledIn: Bool {
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }
}

/// Göreli Türkçe tarih ifadelerinin uygulamanın hesapladığı karşılıkları (deneme §4b: tabloyla 10/10, tablosuz 6/6 yanlış).
enum AppleDateTable {
    /// Gün adları (Gregoryen `weekday`: 1 = pazar).
    static let weekdayNames = ["pazar", "pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi"]

    /// Ör. "bugün=2026-10-04 pazar; yarın=2026-10-05; …; pazartesi=2026-10-05; …; cuma=2026-10-09; …".
    /// Gün adı, bugünden SONRAKİ ilk o gündür (bugün cumaysa "cuma" gelecek haftanınkidir).
    static func table(now: Date = Date(), calendar: Calendar = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = calendar.timeZone
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int) -> String {
            DayString.from(cal.date(byAdding: .day, value: offset, to: today) ?? today, calendar: cal)
        }
        let w = cal.component(.weekday, from: today)   // 1…7
        var parts = ["bugün=\(day(0)) \(weekdayNames[w - 1])", "yarın=\(day(1))", "öbür gün=\(day(2))"]
        for k in 1...7 {
            let target = (w - 1 + k) % 7   // 0 = pazar
            parts.append("\(weekdayNames[target])=\(day(k))")
        }
        parts.append("haftaya bugün=\(day(7))")
        return "# Tarih tablosu (uygulama hesapladı)\n" + parts.joined(separator: "; ")
            + "\n“Önümüzdeki/bu/gelecek” + gün adı tablodaki o günün tarihidir. Göreli tarihi kendin hesaplama; yalnız bu tablodan al. Tarihleri yyyy-MM-dd yaz.\n"
    }
}

/// Cihaz üstü modelin küçük penceresi için karakter bütçesi (deneme §5: 4096 belirteç toplam, Türkçe ~2,1 karakter/belirteç;
/// 6.000 karakter sığdı, 9.000 karakter aştı). Talimat + geçmiş ≈ 6.000 karakter ≈ 2.900 belirteç; kalan yanıta.
enum AppleContextBudget {
    static let contextTokens = 4096
    static let instructionChars = 3600
    static let promptChars = 2400
    static let responseTokens = 800
    static let clippedMark = "\n…(kısaltıldı)"

    /// Metni sınıra sığdırır (baştan korunur, sonu kesilir ve işaretlenir).
    static func clip(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > clippedMark.count else { return String(text.prefix(max(0, limit))) }
        return String(text.prefix(limit - clippedMark.count)) + clippedMark
    }

    /// Modele gidecek istem: son kullanıcı mesajı (gerekirse kırpılır) + bütçe kalırsa yeniden eskiye önceki mesajlar.
    /// Toplam `limit` karakteri aşmaz. Mesajlar eskiden yeniye verilir; son mesaj şimdiki kullanıcı mesajıdır.
    static func prompt(messages: [AIMessage], limit: Int = promptChars) -> String {
        let list = messages.filter { !$0.text.isEmpty }
        guard let last = list.last else { return "" }
        let currentHead = "Kullanıcının şimdiki mesajı:\n"
        let historyHead = "Önceki konuşma (en yeniler; kısaltılmış olabilir):\n"
        let current = clip(last.text, to: max(0, limit - currentHead.count))
        guard list.count > 1 else { return current }
        var room = limit - currentHead.count - current.count - historyHead.count - 2
        var lines: [String] = []
        for m in list.dropLast().reversed() {
            guard room > 0 else { break }
            let who = m.role == .user ? "Kullanıcı: " : "Asistan: "
            let line = who + m.text.replacingOccurrences(of: "\n", with: " ")
            if line.count <= room {
                lines.append(line); room -= line.count + 1
            } else {
                if room > who.count + clippedMark.count + 20 { lines.append(clip(line, to: room)) }
                break
            }
        }
        guard !lines.isEmpty else { return current }
        return historyHead + lines.reversed().joined(separator: "\n") + "\n\n" + currentHead + current
    }
}

/// Apple'ın cihaz üstü modeli. Araçsız; tur yalnız metin yanıtı üretir (veri değiştirmez, öneri de kaydetmez).
struct AppleFoundationModelsProvider: AIProvider {
    /// Oturumun model adı (kalıcı kayıtta görünür; kullanıcı verisi değil).
    static let modelName = "apple-on-device"
    let kind = AIProviderKind.apple
    let capabilities = AIProviderCapabilities(supportsTools: false, contextTokens: AppleContextBudget.contextTokens,
                                              onDevice: true, needsAPIKey: false)
    /// Durum kaynağı; testler sabit durum verir (model çağrılmadan).
    var availability: @Sendable () -> AppleModelAvailability = { AppleModelAvailability.current() }

    func sessionModel(settings: AISettings) -> String { Self.modelName }

    /// Görev iptali yeterli: akış kesilir; durdurulacak uzak oturum yok.
    func cancel(sessionId: String) async {}

    /// Model kullanılamıyorsa anlaşılır nedenle reddeder (oturum açma ve her tur başında).
    func requireAvailable() throws {
        let a = availability()
        guard a.isAvailable else { throw MarkaError.validation(a.statusText) }
    }

    /// Bu sağlayıcıya özgü kurallar (araçsız ve küçük model; deneme §3: "oluşturdum" diye yanıltıcı özet yazabiliyor).
    static let rules = """
    # Bu sohbetin kuralları (cihaz üstü model, araçsız)
    - Bu sohbette aracın yok: veri değiştiremez, öneri kaydedemezsin. "*_oner aracını kullan" diyen kurallar bu sohbette geçmez.
    - "Oluşturdum", "değiştirdim", "kaydettim" deme. Yapılabilecek değişikliği yalnız öneri olarak yaz; kullanıcı kendisi uygular.
    - Kısa ve açık yaz. Bilmediğin şeyi uydurma; "kayıtlarda yok" de.

    """

    /// Talimat: tarih tablosu + kurallar başta (kırpılmaz), ardından genel istem bütçeye sığacak kadar.
    static func instructions(system: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let head = AppleDateTable.table(now: now, calendar: calendar) + "\n" + rules
        return head + AppleContextBudget.clip(system, to: max(0, AppleContextBudget.instructionChars - head.count))
    }

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        try requireAvailable()
        try turn.checkCancellation()
        let session = turn.session
        let system = try ContextBuilder(store: turn.store).turnPrompt(session: session, scope: turn.scope,
                                                                      allowedBrandIds: turn.allowedBrandIds, provider: kind,
                                                                      responseLength: turn.settings.responseLength)
        let instructions = Self.instructions(system: system)
        let prompt = AppleContextBudget.prompt(messages: try turn.storedMessages())
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            try await Self.generate(instructions: instructions, prompt: prompt, turn: turn, assistant: &assistant)
            // Belirteç sayımı (`tokenCount`) macOS 26.4 ister; sayılar bilinmiyor: 0. Maliyet yok. Kayıt içerik taşımaz.
            let usage = UsageEntry(provider: kind, model: Self.modelName, sessionId: session.id, brandId: session.brandId,
                                   purpose: "chat", inputTokens: 0, outputTokens: 0, costMicros: nil)
            try turn.store.write { db in try usage.insert(db) }
            turn.emit(.usage(usage))
            return
        }
        #endif
        throw MarkaError.validation(AppleModelAvailability.unsupportedSystem.statusText)
    }

    #if canImport(FoundationModels)
    /// Modelle tek tur (araçsız). Akış kümülatif anlık görüntü verir; `textDelta` için fark alınır.
    @available(macOS 26, *)
    static func generate(instructions: String, prompt: String, turn: AITurn, assistant: inout AIMessage) async throws {
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(maximumResponseTokens: AppleContextBudget.responseTokens)
        var text = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                try turn.checkCancellation()
                let full: String = snapshot.content
                if full.hasPrefix(text) {
                    let delta = String(full.dropFirst(text.count))
                    if !delta.isEmpty { turn.emit(.textDelta(delta)) }
                } else {
                    turn.emit(.textDelta(full))   // nadir: anlık görüntü önceki metnin devamı değil
                }
                text = full
                assistant.text = text
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw mapped(error)
        }
        assistant.text = text
    }

    /// Çerçeve hatası → uygulamanın türü. Hata ayrıntısı (bağlam, istem parçası) mesaja ve günlüğe taşınmaz.
    @available(macOS 26, *)
    static func mapped(_ error: LanguageModelSession.GenerationError) -> Error {
        switch error {
        case .exceededContextWindowSize: AIErrorKind.contextTooLong
        case .guardrailViolation, .refusal: AIErrorKind.refusal
        case .rateLimited: AIErrorKind.rateLimited
        case .concurrentRequests: AIErrorKind.overloaded
        case .assetsUnavailable: MarkaError.validation(AppleModelAvailability.modelNotReady.statusText)
        case .unsupportedLanguageOrLocale: MarkaError.validation(L("Apple'ın cihaz üstü modeli bu dili desteklemiyor."))
        default: AIErrorKind.unknown
        }
    }
    #endif
}
