import MarkaCore
import SwiftUI

/// Marka Bilgileri (0.3.0): markanın ortak bağlamı. Terminaldeki yapay zekâ bu metinleri her oturumda `BAGLAM.md` olarak
/// okur; bu yüzden her bölümün altında yazmaya yardım eden sorular vardır. Boş bölüm bağlama girmez ve kendiliğinden
/// doldurulmaz. Altta eski *ayrıntılar* (ad, sektör, kişiler, projeler, AI izinleri) yerinde düzenlenir.
struct BrandProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    let brand: Brand
    @State private var editing: Target?
    @State private var draft = ""
    @State private var showContext = false
    @State private var selection: PanelTarget?
    // Geliştirme: `MARKA_PARCA=goals|people|access` alt sekmeyi seçer (gerçek pencere doğrulaması için).
    @State private var part: Part = ProcessInfo.processInfo.environment["MARKA_PARCA"].flatMap { ["goals": Part.goals, "people": .people, "access": .access][$0] } ?? .profile

    /// Alt sekmeler: sayfa tek uzun sayfa olmasın diye konuya göre bölünür.
    enum Part: CaseIterable { case profile, goals, people, access
        var title: String { switch self { case .profile: L("Profil"); case .goals: L("Hedefler"); case .people: L("Kişiler ve projeler"); case .access: L("Ayrıntılar ve izinler") } }
    }

    enum Target: Hashable { case summary, section(ProfileSection) }

    var body: some View {
        let _ = app.revision
        let current = (try? app.store?.brand(brand.id)) ?? brand
        let profile = (try? app.store?.profile(brandId: brand.id)) ?? [:]
        let filledSections = ProfileSection.allCases.filter { !(profile[$0] ?? "").isEmpty }.count
        let filled = filledSections + (current.summary.isEmpty ? 0 : 1)
        let total = ProfileSection.allCases.count + 1
        ListWithPanel(selection: $selection) {
        PageScroll(backgroundTap: { selection = nil }) {
            VStack(alignment: .leading, spacing: Design.Space.l) {
                SectionHeading(title: L("Marka Bilgileri"), subtitle: L("İş planının ve yapay zekânın ortak bağlamı."), symbol: "text.book.closed", tintKey: brand.id) {
                    Button(showContext ? L("Önizlemeyi gizle") : L("Yapay zekâ ne okuyor?")) { showContext.toggle() }
                        .actionSecondary()
                }
                if showContext { contextPreview }
                SegmentedChoice(options: Part.allCases.map { ($0, $0.title) }, selection: $part)
                switch part {
                case .profile:
                    overview(current, filled: filled, total: total)
                    block(title: L("Markayı tanı"), prompt: L("Marka ne yapıyor, ne satıyor, kimin için? İki üç cümle."),
                          text: current.summary, target: .summary)
                    // Aynı satırdaki kartlar eşit yükseklikte (Grid satır yüksekliğini eşitler).
                    let sections = ProfileSection.allCases
                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        ForEach(Array(stride(from: 0, to: sections.count, by: 2)), id: \.self) { i in
                            GridRow {
                                profileCard(sections[i], profile)
                                if i + 1 < sections.count { profileCard(sections[i + 1], profile) } else { Color.clear.frame(height: 0) }
                            }
                        }
                    }
                case .goals:
                    GoalsSection(brand: brand, selection: $selection)
                    decisions
                case .people:
                    BrandInfoView(brand: brand, embedded: true, show: .people)
                case .access:
                    BrandInfoView(brand: brand, embedded: true, show: .access)
                }
            }
            .pagePadding().padding(.vertical, Design.Space.l)
        }
        }
        .onChange(of: brand.id) { editing = nil; showContext = false; selection = nil; part = .profile }
    }

    private func profileCard(_ section: ProfileSection, _ profile: [ProfileSection: String]) -> some View {
        block(title: section.title, prompt: section.prompt, text: profile[section] ?? "", target: .section(section))
            .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Bölümler

    private func block(title: String, prompt: String, text: String, target: Target) -> some View {
        let isEditing = editing == target
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if !isEditing { Button(text.isEmpty ? L("Yaz") : L("Düzenle")) { begin(target, text) }.buttonStyle(.text) }
            }
            if isEditing {
                editor(prompt: prompt, target: target)
            } else if text.isEmpty {
                Text(prompt).font(.system(size: 12)).foregroundStyle(.tertiary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).onTapGesture { begin(target, text) }
            } else {
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 18)
    }

    private func editor(prompt: String, target: Target) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt).font(.system(size: 11)).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(8).frame(minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Design.panel))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Design.line))
            HStack {
                Text(verbatim: "\(draft.count)/\(ProfileSection.maxLength)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button(L("Vazgeç")) { editing = nil }.actionSecondary()
                Button(L("Kaydet")) { save(target) }.actionPrimary().disabled(draft.count > ProfileSection.maxLength)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func begin(_ target: Target, _ text: String) {
        draft = text
        editing = target
    }

    private func save(_ target: Target) {
        guard let store = app.store else { return }
        // ⌘Z için önceki metin.
        let previous: String = {
            switch target {
            case .summary: return (try? store.brand(brand.id))?.summary ?? ""
            case .section(let section): return ((try? store.profile(brandId: brand.id)) ?? [:])[section] ?? ""
            }
        }()
        let ok: Void? = app.perform(title: L("Kaydedilemedi"), context: "marka.profil") {
            switch target {
            case .summary:
                var b = try store.brand(brand.id)
                b.summary = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                try store.updateBrand(b)
            case .section(let section):
                try store.setProfileSection(brandId: brand.id, section, body: draft)
            }
        }
        guard ok != nil else { return }
        let brandId = brand.id
        undoManager?.registerUndo(withTarget: app) { _ in
            MainActor.assumeIsolated {
                switch target {
                case .summary:
                    if var b = try? store.brand(brandId) { b.summary = previous; try? store.updateBrand(b) }
                case .section(let section):
                    try? store.setProfileSection(brandId: brandId, section, body: previous)
                }
                _ = app.writeContext(brandId: brandId)
            }
        }
        undoManager?.setActionName(L("Metni düzenle"))
        editing = nil
        _ = app.writeContext(brandId: brand.id)
    }

    // MARK: Kararlar ve notlar (yalnız okunur)

    @ViewBuilder private var decisions: some View {
        let records = ((try? app.store?.records(brandId: brand.id, kinds: [.decision])) ?? []).filter { $0.isOpen }
        let meetings = ((try? app.store?.sources(brandId: brand.id)) ?? []).filter { $0.kind == .meeting }.prefix(5)
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Kararlar ve görüşme notları")).font(.system(size: 15, weight: .semibold))
            if records.isEmpty && meetings.isEmpty {
                Text(L("Bekleyen karar ya da görüşme notu yok. Bunlar Görevler ve Dosyalar'dan gelir.")).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            ForEach(records) { r in
                line(r.title, meta: L("Karar bekleniyor") + (r.dueDate.map { " · " + $0 } ?? ""))
            }
            ForEach(Array(meetings)) { m in
                line(m.title, meta: L("Görüşme") + " · " + m.capturedAt.formatted(.dateTime.day().month(.abbreviated)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 18)
    }

    private func line(_ title: String, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13))
            Text(meta).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Yan sütun

    /// Üstte iki kart: marka künyesi ve bağlam doluluğu (dar pencerede alt alta).
    private func overview(_ current: Brand, filled: Int, total: Int) -> some View {
        let contacts = (try? app.store?.contacts(brandId: brand.id)) ?? []
        let projects = (try? app.store?.projects(brandId: brand.id)) ?? []
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 13) {
                fact(L("Sektör"), current.sector.isEmpty ? "—" : current.sector)
                fact(L("İlgili kişi"), contacts.first.map { $0.role.isEmpty ? $0.name : $0.name + " · " + $0.role } ?? "—")
                fact(L("Projeler"), projects.isEmpty ? "—" : projects.map(\.name).joined(separator: ", "))
                fact(L("Eklendi"), current.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .card(padding: 18)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Bağlam doluluğu")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(verbatim: "\(filled)/\(total)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(BrandTintStyle(key: brand.id))
                }
                Capsule().fill(Design.line).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in Capsule().fill(BrandTintStyle(key: brand.id)).frame(width: geo.size.width * CGFloat(filled) / CGFloat(max(total, 1)), height: 6) }
                    }
                    .frame(height: 6)
                Text(L("Doldurduğun bölümler BAGLAM.md dosyasına yazılır; terminaldeki araç her oturumda okur. Boş bölümler bağlama girmez, uydurulmaz."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .card(padding: 18)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(value).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Önizleme

    private var contextPreview: some View {
        let text = (try? app.store.map { try ContextBuilder(store: $0).brandContext(brandId: brand.id) }) ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Terminaldeki yapay zekânın BAGLAM.md içinde okuduğu marka bağlamı:")).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines)).font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Design.panel))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Design.line))
    }
}
