import AppKit
import MarkaCore
import SwiftUI
import UniformTypeIdentifiers

/// Rapor (plan §4, U9): *müşteriye ne gidecek.* Açılışta bu haftanın raporu, doğrulanmış iş kayıtlarından canlı önizleme
/// (belge görünümü). Durum *Taslak / Hazır* ("Onayla" fiili yalnız öneride). Birincil düğme taslakta **"Hazır, PDF al"**
/// (raporu hazır işaretler ve temiz PDF verir), hazırken **"PDF"**. Dönem küçük bir metin menüsünden seçilir; kaydedilmiş
/// raporlar, sürümler ve paylaşımlar tek yerde, altta açılır "Geçmiş"te. Rapor ilk PDF/e-posta anında ya da düzenlenince
/// taslak sürüm olarak kaydedilir (çekirdeğin yolları: `createReportDraft`, `saveReportVersion`, `approveReport`,
/// `recordShare`). Planlı gönderim arayüzde yok.
struct ReportsView: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var range: ReportRange = .thisWeek
    /// "Geçmiş"ten açılan dönem (dört sabit dönemin dışında olabilir).
    @State private var opened: Report?
    /// Düzenlenen içerik (Düzenle ↔ Kaydet/Vazgeç).
    @State private var editing: ReportContent?
    @State private var summarizing = false
    @State private var showHistory = false

    private var period: ReportPeriod { opened?.period ?? range.period }
    private var interval: DateInterval {
        if let opened { return DateInterval(start: opened.periodStart, end: opened.periodEnd) }
        return range.interval(now: Date())
    }

    var body: some View {
        let _ = app.revision
        PageScroll {
            Group {
                if let store = app.store {
                    switch Result(catching: { try store.reportPreview(brandId: brand.id, period: period, interval: interval) }) {
                    case .failure(let error):
                        ReadErrorView(error: error, context: "okuma.rapor") { app.reloadViews() }
                    case .success(let preview):
                        content(preview)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Space.l).padding(.top, Design.Space.s).padding(.bottom, Design.Space.l)
        }
        .onChange(of: brand.id) { opened = nil; editing = nil; range = .thisWeek }
    }

    /// Başlık satırı tam genişlik (birincil düğme sağ kenarda); belge ve Geçmiş en çok 720 pt.
    private func content(_ p: ReportPreview) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.m) {
            header(p)
            notices(p)
            Group {
                if let draft = Binding($editing) {
                    ReportPage(content: p.content, draft: draft, caption: caption(p), brandName: brand.name)
                } else if p.isEmpty {
                    EmptyStateView(message: L("Bu dönemde doğrulanmış iş kaydı yok."))
                } else {
                    ReportPage(content: p.content, draft: nil, caption: caption(p), brandName: brand.name)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            history(p).frame(maxWidth: 720, alignment: .leading)
        }
    }

    // MARK: Başlık satırı

    /// Ekranda tek birincil düğme: taslakta *Hazır, PDF al*, hazırken *PDF*, düzenlerken *Kaydet*. "···" menüsünde
    /// Düzenle ve E-posta taslağı; düzenlerken yalnız AI özeti (ya da özeti kaldırma) ve *Vazgeç* (Esc).
    private func header(_ p: ReportPreview) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            // Dönem: dört sabit dönem (kaydedilmiş raporlar Geçmiş'te).
            TextMenu(title: periodTitle, help: L("Dönem")) {
                ForEach(ReportRange.allCases, id: \.self) { r in
                    Button(title(r)) { editing = nil; range = r; opened = nil }
                }
            }
            .padding(.horizontal, -Design.Space.xs)
            Text(L("· yalnız doğrulanmış iş kayıtlarından")).captionStyle().lineLimit(1)
            Spacer(minLength: Design.Space.m)
            if let draft = editing {
                let hasSummary = !draft.summary.isEmpty
                if hasSummary || brand.allows(.anthropic) || brand.allows(.codex) {
                    // Tek düğme: özet yoksa AI ile yazdırır, varsa kaldırır.
                    Button(hasSummary ? L("Özeti kaldır") : (summarizing ? L("Yazılıyor…") : L("AI ile özet"))) {
                        if hasSummary { editing?.summary = [] } else { summarize() }
                    }
                    .buttonStyle(.text)
                    .disabled(!hasSummary && (summarizing || !summaryChoice.isAvailable))
                    .help(hasSummary ? L("AI özetini rapordan çıkarır") : summaryChoice.help)
                }
                Button(L("Vazgeç")) { editing = nil }
                    .buttonStyle(.text).keyboardShortcut(.cancelAction)
                Button(L("Kaydet")) { save(p) }.buttonStyle(.borderedProminent)
            } else {
                TextMenu(title: "···", help: L("Diğer")) {
                    Button(L("Düzenle")) { editing = p.content }.disabled(p.isEmpty)
                    Button(p.isApproved ? L("E-posta taslağı…") : L("E-posta taslağı… (rapor hazır olunca)")) { mailDraft(p) }
                        .disabled(!p.isApproved)
                }
                Button(p.isApproved ? L("PDF") : L("Hazır, PDF al")) { exportPDF(p, markReady: !p.isApproved) }
                    .buttonStyle(.borderedProminent)
                    .disabled(p.isEmpty)
                    .help(p.isApproved ? L("PDF olarak kaydet") : L("Raporu hazır olarak işaretler ve müşteriye gidecek PDF'i kaydeder"))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var periodTitle: String {
        if let opened { return Self.rangeText(DateInterval(start: opened.periodStart, end: opened.periodEnd)) }
        return title(range)
    }

    private func title(_ r: ReportRange) -> String {
        switch r {
        case .thisWeek: L("Bu hafta")
        case .lastWeek: L("Geçen hafta")
        case .thisMonth: L("Bu ay")
        case .lastMonth: L("Geçen ay")
        }
    }

    static func rangeText(_ interval: DateInterval) -> String {
        (interval.start..<interval.end.addingTimeInterval(-1)).formatted(.interval.day().month(.wide).year())
    }

    private func caption(_ p: ReportPreview) -> String {
        let kind = p.period == .weekly ? L("Haftalık rapor") : L("Aylık rapor")
        let state: String
        if let v = p.version, p.showsSaved {
            state = p.isApproved ? LF("Hazır · %d. sürüm", v.number) : LF("Taslak · %d. sürüm", v.number)
        } else {
            state = L("Taslak")
        }
        return [kind, Self.rangeText(p.interval), state].joined(separator: " · ")
    }

    // MARK: Uyarılar (tek satır)

    /// Rapora girmeyenler ve değişen iş kayıtları tek satırda; eylemler aynı satırda metin düğmesi.
    @ViewBuilder private func notices(_ p: ReportPreview) -> some View {
        let excluded = p.live.warnings
        let changed = p.showsSaved && p.changedWorkLogs > 0 && editing == nil
        let parts = noticeParts(p, changed: changed)
        if !parts.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                Text(parts.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .help(([parts.joined(separator: "\n")] + excluded.map(\.text)).joined(separator: "\n"))
                if p.unverifiedWorkLogs > 0 || !excluded.isEmpty {
                    Button(L("Akış'ta gör")) { app.brandTab = .flow }.buttonStyle(.text)
                }
                if changed {
                    Button(L("İş kayıtlarından yenile")) { refresh(p) }.buttonStyle(.text)
                        .help(L("İş kayıtlarından yeni taslak sürüm oluşturur. Düzenlemeler yeni sürüme taşınmaz; eski sürüm Geçmiş'te kalır."))
                }
            }
        }
    }

    private func noticeParts(_ p: ReportPreview, changed: Bool) -> [String] {
        var parts: [String] = []
        if p.unverifiedWorkLogs > 0 { parts.append(LF("%d iş kaydı doğrulanmadı", p.unverifiedWorkLogs)) }
        if !p.live.warnings.isEmpty { parts.append(LF("%d biten görev rapora girmedi (iş kaydı yok)", p.live.warnings.count)) }
        if changed { parts.append(LF("Bu sürümden sonra %d iş kaydı değişti", p.changedWorkLogs)) }
        return parts
    }

    // MARK: Geçmiş (tek yer)

    private func history(_ p: ReportPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(showHistory ? "▾ " + L("Geçmiş") : "▸ " + L("Geçmiş")) { showHistory.toggle() }
                .buttonStyle(.text)
                .padding(.horizontal, -Design.Space.xs)
                .padding(.vertical, Design.Space.s)
                .accessibilityValue(showHistory ? L("Açık") : L("Kapalı"))
            if showHistory { HistoryList(current: p.report, brandId: brand.id, open: open) }
        }
    }

    private func open(_ r: Report) {
        editing = nil
        if let match = ReportRange.allCases.first(where: { $0.period == r.period && $0.interval(now: Date()).start == r.periodStart }) {
            range = match
            opened = nil
        } else {
            opened = r
        }
    }

    // MARK: Eylemler

    /// Gösterilen içeriğin sürümü: yeniden kullanılabilir son sürüm ya da kayıtlardan yeni taslak (ilk PDF/e-posta/onay anı).
    private func ensureVersion(_ p: ReportPreview) -> (Report, ReportVersion)? {
        if let r = p.report, let v = p.reusableVersion { return (r, v) }
        guard let store = app.store else { return nil }
        return app.perform(context: "rapor.taslak") {
            try store.createReportDraft(brandId: brand.id, period: p.period, interval: p.interval, content: p.live)
        }
    }

    private func refresh(_ p: ReportPreview) {
        app.perform(context: "rapor.yenile") {
            try app.store?.createReportDraft(brandId: brand.id, period: p.period, interval: p.interval, content: p.live)
        }
    }

    private func save(_ p: ReportPreview) {
        guard var draft = editing else { return }
        // Metni silinen madde rapordan çıkar; ona dayanan özet cümlesi de.
        let removed = Set(draft.sections.flatMap(\.items).filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.id))
        for i in draft.sections.indices { draft.sections[i].items.removeAll { removed.contains($0.id) } }
        draft.summary.removeAll { !Set($0.itemIds).isDisjoint(with: removed) }
        draft.intro = draft.intro.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.sameItems(as: p.content) { editing = nil; return }
        guard let (report, _) = ensureVersion(p) else { return }
        if app.perform(context: "rapor.duzenle", { try app.store?.saveReportVersion(reportId: report.id, content: draft, note: L("Düzenlendi")) }) != nil {
            editing = nil
        }
    }

    private func renderPDF(_ content: ReportContent, version: ReportVersion) -> Data? {
        guard let store = app.store else { return nil }
        // Sunum: boş bölümler PDF'e girmez; maddeler ve dayanaklar aynı.
        return ReportPDFRenderer(content: content.withoutEmptySections, isDraft: version.approvedAt == nil, versionNumber: version.number,
                                 describe: { try? store.describe($0) }).render()
    }

    /// PDF'i kaydeder. `markReady`: önce rapor hazır işaretlenir (çekirdekte `approveReport`), PDF filigransız çıkar.
    /// Kaydetme paneli iptal edilirse hiçbir şey değişmez ve rapor taslak kalır.
    private func exportPDF(_ p: ReportPreview, markReady: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(brand.name) \(p.interval.start.formatted(.iso8601.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let (report, draft) = ensureVersion(p), let store = app.store else { return }
        app.perform(context: "rapor.pdf") {
            if markReady && draft.approvedAt == nil { try store.approveReport(reportId: report.id, versionId: draft.id) }
            // Hazır işaretlendiyse onay zamanı taşıyan güncel kayıt okunur.
            let version = try store.read { db in try ReportVersion.fetchOne(db, key: draft.id) } ?? draft
            let content = try store.content(of: version)
            guard let data = renderPDF(content, version: version) else { return }
            try data.write(to: url)
            try store.recordShare(reportId: report.id, versionId: version.id, channel: .pdfExport, filePath: url.path,
                                  note: version.approvedAt == nil ? L("TASLAK filigranlı") : "")
        }
    }

    /// Mail'de taslak açar (yalnız onaylı rapor). Uygulama e-postayı kendisi göndermez.
    private func mailDraft(_ p: ReportPreview) {
        guard p.isApproved, let report = p.report, let version = p.version, let store = app.store,
              let content = try? store.content(of: version), let data = renderPDF(content, version: version) else { return }
        // Sistem geçici klasörü marka terminalinden ve Codex'ten okunabilir; PDF uygulama veri alanına (yalıtımda yasak) yazılır.
        let dir = app.workspaceURL.appendingPathComponent("Gecici", isDirectory: true)
        let url = dir.appendingPathComponent("\(content.brandName) rapor v\(version.number).pdf")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch { app.show(error: error, context: "rapor.pdf"); return }
        guard let service = NSSharingService(named: .composeEmail) else {
            app.alert = AppAlert(title: L("E-posta açılamadı"), message: L("Mail uygulaması yapılandırılmamış görünüyor. PDF dışa aktarımını kullanabilirsin."))
            return
        }
        let recipients = (try? store.contacts(brandId: report.brandId).map(\.email).filter { !$0.isEmpty }) ?? []
        service.recipients = []
        service.subject = content.title
        service.perform(withItems: [content.title, url])
        app.perform {
            try store.recordShare(reportId: report.id, versionId: version.id, channel: .mailDraft,
                                  recipient: recipients.isEmpty ? "" : L("alıcı Mail'de seçilir"), filePath: url.path, note: L("Gönderim kullanıcıya bırakıldı"))
        }
    }

    // MARK: AI ile özet (izinli sağlayıcı; çekirdekteki izin denetimli yol)

    /// Anahtar yoksa sebep "izin yok" değil "anahtar eklenmemiş".
    private var summaryChoice: SummaryProviderChoice {
        .choose(allowsAnthropic: brand.allows(.anthropic), hasAnthropicKey: app.hasAnthropicKey, allowsCodex: brand.allows(.codex))
    }

    private func summarize() {
        guard let content = editing, let store = app.store, let brand = try? store.brand(brand.id) else { return }
        // Önbellekteki anahtar durumu yerine Keychain'e bakılır: anahtar bu arada silinmişse doğru sebep söylenir.
        let key = brand.allows(.anthropic) ? Keychain.load(account: app.anthropicKeyAccount).flatMap { $0.isEmpty ? nil : $0 } : nil
        let choice = SummaryProviderChoice.choose(allowsAnthropic: brand.allows(.anthropic), hasAnthropicKey: key != nil,
                                                  allowsCodex: brand.allows(.codex))
        summarizing = true
        Task {
            // Codex süreci özet turu boyunca "meşgul" kalır (boştaki süreç durdurma onu öldürmesin); bitince serbest bırakılır.
            var releaseCodex: (@Sendable () async -> Void)?
            defer { summarizing = false; let r = releaseCodex; Task { await r?() } }
            do {
                let provider: StructuredProvider
                switch choice {
                case .anthropic:
                    provider = .anthropic(AnthropicClient(apiKey: key ?? "", model: app.anthropicModel, effort: app.anthropicEffort.isEmpty ? nil : app.anthropicEffort))
                case .codex:
                    // Markanın yalıtımlı Codex süreci: özet turu da diğer markaların klasörlerini okuyamaz.
                    guard let engine = app.engine else { throw MarkaError.ai(L("Çalışma alanı açık değil.")) }
                    let server = try await engine.retainCodexServer(for: .brand(brand.id))
                    releaseCodex = { await engine.releaseCodexServer(for: .brand(brand.id)) }
                    let model = app.codexModel.isEmpty ? (try await server.models().first(where: \.isDefault)?.id ?? "") : app.codexModel
                    provider = .codex(server, model: model, cwd: try app.folders!.folder(for: .brand(brand.id)))
                case .missingAnthropicKey, .notAllowed:
                    throw MarkaError.ai(choice.unavailableReason ?? "")
                }
                let (kept, dropped, usage) = try await ReportSummarizer().summarize(content: content, brand: brand, provider: provider)
                var u = usage
                u.brandId = brand.id
                u.purpose = "report"
                let entry = u
                try store.write { db in try entry.insert(db) }
                // Bekleme sırasında yapılan düzenlemeler korunur; yalnızca özet değişir.
                editing?.summary = kept
                if dropped > 0 {
                    app.alert = AppAlert(title: L("Bazı cümleler atıldı"), message: LF("%d cümle geçerli bir maddeye dayanmadığı için eklenmedi.", dropped))
                }
            } catch {
                app.show(error: error, title: L("Özet oluşturulamadı"), context: "ai.rapor.ozet")
            }
        }
    }
}

/// Belge görünümü: beyaz sayfa (koyu görünümde koyu yüzey), ince çizgi, tek köşe yarıçapı — ekrandaki tek kutu istisnası.
/// Boş bölümler ve süre yoksa "Harcanan süre" gösterilmez. Düzenlemede giriş notu ve maddeler satır içi düzenlenir;
/// metni silinen madde kaydedilince rapordan çıkar. Okurken maddeye tıklamak dayanağını yerinde (Akış paneli) açar.
struct ReportPage: View {
    @Environment(AppModel.self) private var app
    let content: ReportContent
    /// Düzenleme kipinde bağlı içerik.
    var draft: Binding<ReportContent>?
    let caption: String
    let brandName: String

    private var shown: ReportContent { draft?.wrappedValue ?? content }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text(caption).captionStyle()
                Text(brandName).font(Design.Font.title).accessibilityAddTraits(.isHeader)
            }
            if let draft {
                TextField(L("Giriş notu (isteğe bağlı)"), text: draft.intro, axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.roundedBorder)
            } else if !shown.intro.isEmpty {
                Text(shown.intro).fixedSize(horizontal: false, vertical: true)
            }
            if !shown.summary.isEmpty {
                block(L("Özet")) {
                    Text(shown.summary.map(\.text).joined(separator: " ")).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(shown.withoutEmptySections.sections) { section in
                block(ReportSectionTitles.title(section.kind)) {
                    if section.kind == .timeSpent {
                        Text(LF("Toplam: %@", DurationFormat.short(shown.totalSeconds))).captionStyle()
                    }
                    ForEach(section.items) { item in itemRow(item, in: section.kind) }
                }
            }
        }
        .padding(Design.Space.l + Design.Space.m)
        .frame(maxWidth: 720, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.radius).fill(Design.bandBackground))
        .overlay(RoundedRectangle(cornerRadius: Design.radius).strokeBorder(Design.line))
    }

    private func block<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Text(title).font(Design.Font.section).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    @ViewBuilder private func itemRow(_ item: ReportItem, in kind: ReportSectionKind) -> some View {
        if let draft, let s = draft.wrappedValue.sections.firstIndex(where: { $0.kind == kind }),
           let i = draft.wrappedValue.sections[s].items.firstIndex(where: { $0.id == item.id }) {
            TextField(L("Madde (boş bırakılırsa çıkar)"), text: Binding(
                get: { draft.wrappedValue.sections[s].items[i].text },
                set: { v in
                    draft.wrappedValue.sections[s].items[i].text = v
                    draft.wrappedValue.sections[s].items[i].edited = true
                }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        } else {
            Button { if let ref = item.refs.first { app.open(ref) } } label: {
                Text(verbatim: "— " + item.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Dayanağını aç"))
        }
    }
}

/// "Geçmiş": açık raporun sürümleri ve paylaşımları (sade liste). Geçmiş raporların kendisi dönem menüsünde.
struct HistoryList: View {
    @Environment(AppModel.self) private var app
    let current: Report?
    let brandId: String
    /// Kaydedilmiş raporu açar (dönemi seçer).
    let open: (Report) -> Void

    var body: some View {
        let versions = current.flatMap { try? app.store?.reportVersions(reportId: $0.id) } ?? []
        let shares = current.flatMap { try? app.store?.reportShares(reportId: $0.id) } ?? []
        let saved = ((try? app.store?.reports(brandId: brandId)) ?? []).filter { $0.id != current?.id }
        VStack(alignment: .leading, spacing: 0) {
            if versions.isEmpty && shares.isEmpty {
                EmptyStateView(message: L("Bu rapor henüz kaydedilmedi; ilk PDF, e-posta taslağı ya da düzenlemede kaydedilir."))
            }
            if !versions.isEmpty {
                Text(L("Bu raporun sürümleri")).captionStyle().padding(.top, Design.Space.s).padding(.bottom, Design.Space.xs)
                ForEach(versions) { v in
                    line(title: LF("%d. sürüm", v.number) + (v.note.isEmpty ? "" : " · " + v.note),
                         detail: v.approvedAt != nil ? L("Hazır") : v.actor.title, date: v.createdAt)
                }
            }
            if !saved.isEmpty {
                Text(L("Diğer raporlar")).captionStyle().padding(.top, Design.Space.m).padding(.bottom, Design.Space.xs)
                ForEach(saved) { r in
                    Button { open(r) } label: {
                        line(title: r.period.title + " · " + ReportsView.rangeText(DateInterval(start: r.periodStart, end: r.periodEnd)),
                             detail: r.status == .approved ? L("Hazır") : L("Taslak"), date: r.updatedAt)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(HoverHighlight())
                    .help(L("Bu raporu aç"))
                }
            }
            if !shares.isEmpty {
                Text(L("Paylaşımlar")).captionStyle().padding(.top, Design.Space.m).padding(.bottom, Design.Space.xs)
                ForEach(shares) { s in
                    line(title: shareTitle(s.channel) + (versions.first { $0.id == s.versionId }.map { " · " + LF("%d. sürüm", $0.number) } ?? ""),
                         detail: s.note, date: s.sharedAt)
                }
            }
        }
    }

    private func line(title: String, detail: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if !detail.isEmpty { Text(detail).captionStyle().lineLimit(1) }
            Text(date, format: .dateTime.day().month(.abbreviated).hour().minute()).captionStyle()
        }
        .padding(.vertical, Design.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
    }

    private func shareTitle(_ c: ShareChannel) -> String {
        switch c {
        case .pdfExport: L("PDF dışa aktarıldı")
        case .mailDraft: L("E-posta taslağı açıldı")
        case .scheduledDraft: L("Planlı taslak oluşturuldu")
        }
    }
}
