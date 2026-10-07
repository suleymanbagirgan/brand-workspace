import AppKit
import MarkaCore
import SwiftUI

// MARK: Adlar

extension MemberLevel {
    var title: String {
        switch self {
        case .intern: L("Stajyer")
        case .junior: L("Junior")
        case .mid: L("Orta düzey")
        case .senior: L("Kıdemli")
        case .lead: L("Takım lideri")
        case .director: L("Direktör")
        }
    }
}

extension ServiceStatus {
    var title: String {
        switch self {
        case .active: L("Sürüyor")
        case .planned: L("Planlanan")
        case .paused: L("Durduruldu")
        }
    }
}

/// Yapay zekâ sağlayıcı kimliği → görünen ad. Kimlik `TeamMember.provider` alanında tutulur.
enum MemberProvider: String, CaseIterable {
    case none = "", anthropic, apple, codex, other
    var title: String {
        switch self {
        case .none: L("Belirtilmedi")
        case .anthropic: L("Claude (Anthropic)")
        case .apple: L("Apple Zekâ (cihaz üstü)")
        case .codex: L("Codex")
        case .other: L("Diğer")
        }
    }
}

private extension TeamMember {
    var providerTitle: String { (MemberProvider(rawValue: provider) ?? .other).title }
    /// "Kıdemli · Tasarım" gibi alt satır.
    var subtitle: String { [level.title, department].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// Üyenin avatarı; yapay zekâ çalışanın köşesinde küçük bir parıltı rozeti olur.
struct MemberAvatar: View {
    let member: TeamMember
    var size: CGFloat = 34
    var body: some View {
        BrandAvatar(name: member.name, tintKey: member.id, size: size)
            .overlay(alignment: .bottomTrailing) {
                if member.kind == .ai {
                    // sabit-boyut: simge, avatar kutusunun boyutuyla orantılı.
                    Image(systemName: "sparkles").font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white)
                        .frame(width: size * 0.46, height: size * 0.46)
                        .background(Circle().fill(Design.accentFill))
                        .overlay(Circle().strokeBorder(Design.windowBackground, lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: Şirket sayfası

/// Şirket (Stüdyo): kimlik kartı, özet kutucukları ve beş sekme: Genel, Hizmetler, Ekip, Şema, Yetenekler. Çalışma alanı seviyesindedir;
/// müşteri ekibi atamalarla kurulur ve yalnız atandığı markanın yapay zekâ bağlamına girer. Kendi şirketimizde (Stüdyo) ekip herkestir.
struct CompanyView: View {
    enum Tab: String, CaseIterable { case about, services, team, chart, skills }
    @Environment(AppModel.self) private var app
    /// Geliştirme: `MARKA_PARCA=about|services|team|chart|skills` açılış sekmesini seçer (ekran doğrulaması için).
    @State private var tab: Tab
    @State private var memberDraft: MemberDraft?
    @State private var serviceDraft: ServiceDraft?
    @State private var skillDraft: SkillDraft?

    init(tab: Tab? = nil) {
        _tab = State(initialValue: tab ?? DevHook.value("MARKA_PARCA").flatMap(Tab.init(rawValue:)) ?? .about)
    }

    var body: some View {
        let _ = app.revision
        PageScroll {
            VStack(alignment: .leading, spacing: Design.Space.l) {
                CompanyHero()
                CompanyStats(open: { tab = $0 })
                SegmentedChoice(options: [(Tab.about, L("Genel")), (.services, L("Hizmetler")), (.team, L("Ekip")), (.chart, L("Şema")), (.skills, L("Yetenekler"))],
                                selection: $tab)
                switch tab {
                case .about: CompanyAboutForm()
                case .services: ServicesList(draft: $serviceDraft)
                case .team: TeamList(draft: $memberDraft)
                case .chart: OrgChartView(draft: $memberDraft)
                case .skills: SkillsLibrary(draft: $skillDraft)
                }
            }
            .pagePadding().padding(.vertical, Design.Space.l)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        // Açılışta ilk metin alanı odak halkası almasın.
        .onAppear { OpeningFocus.settle() }
        .sheet(item: $memberDraft) { MemberSheet(draft: $0) }
        .sheet(item: $serviceDraft) { ServiceSheet(draft: $0) }
        .sheet(item: $skillDraft) { SkillSheet(draft: $0) }
    }
}

/// Kimlik kartı: avatar, şirket adı, slogan, kuruluş ve süre, web sitesi.
private struct CompanyHero: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let c = app.read(or: CompanyProfile()) { try $0.companyProfile() }
        let own = app.ownBrand
        let name = c.name.isEmpty ? (own?.name ?? L("Şirketimiz")) : c.name
        HStack(alignment: .center, spacing: 20) {
            BrandAvatar(name: name, tintKey: own?.id, size: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(name).font(Design.Font.display).tracking(-0.9).lineLimit(1).accessibilityAddTraits(.isHeader)
                if !c.tagline.isEmpty { Text(c.tagline).font(Design.Font.heading).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 8) {
                    if let f = c.foundedOn, let date = DayString.date(f) {
                        Pill(text: LF("Kuruluş: %@", date.formatted(.dateTime.month(.wide).year())))
                        if let age = Self.age(since: date) { Pill(text: age) }
                    }
                    if !c.website.isEmpty, let url = URL(string: c.website), url.scheme != nil {
                        Link(destination: url) { Label(c.website.replacingOccurrences(of: "https://", with: ""), systemImage: "arrow.up.right").font(Design.Font.small.weight(.medium)) }
                            .foregroundStyle(Design.accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Design.Space.l)
        .background(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).fill(BrandTintStyle(key: own?.id ?? "stüdyo").opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).strokeBorder(Design.line))
        .accessibilityElement(children: .combine)
    }

    /// "2 yıl 6 ay"; bir aydan kısaysa `nil`.
    static func age(since date: Date) -> String? {
        guard date < Date().addingTimeInterval(-30 * 86_400) else { return nil }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.year, .month]; f.unitsStyle = .full; f.maximumUnitCount = 2
        return f.string(from: date, to: Date())
    }
}

/// Beş özet kutucuğu; her biri ilgili sekmeye götürür. Sayılar kayıttan gelir.
private struct CompanyStats: View {
    @Environment(AppModel.self) private var app
    let open: (CompanyView.Tab) -> Void

    var body: some View {
        let members = app.read(or: []) { try $0.teamMembers() }
        let activity = app.read(or: [:]) { try $0.memberActivity() }
        let pending = activity.values.reduce(0) { $0 + $1.pending }
        HStack(spacing: Design.Space.m) {
            TodayTile(symbol: "briefcase", title: L("Hizmet"), count: (app.read(or: []) { try $0.services() }).count, titleLines: 2) { open(.services) }
            TodayTile(symbol: "person.2", title: L("İnsan"), count: members.filter { $0.kind == .human }.count, titleLines: 2) { open(.team) }
            TodayTile(symbol: "sparkles", title: L("Yapay zekâ çalışan"), count: members.filter { $0.kind == .ai }.count, titleLines: 2) { open(.team) }
            TodayTile(symbol: "wand.and.stars", title: L("Yetenek"), count: (app.read(or: []) { try $0.skills() }).count, titleLines: 2) { open(.skills) }
            TodayTile(symbol: "checkmark.seal", title: L("Bekleyen öneri"), count: pending, emphasize: pending > 0, titleLines: 2) { open(.team) }
        }
    }
}

/// Stüdyo kurulmamışken gösterilen ekran: kendi şirketini kur.
struct StudioSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: Design.Space.l) {
                SectionHeading(title: L("Stüdyo"), subtitle: L("Müşterilerine hizmet verirken kendi şirketini de organize et."))
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    Text(L("Stüdyonu kur")).font(Design.Font.heading.weight(.bold)).tracking(-0.3)
                    Text(L("Kendi şirketin de bir iş alanıdır: web sitesini geliştirmek, reklam vermek, yeni müşterilerle görüşmek gibi kendi işlerin burada durur. Ekibin (insanlar ve yapay zekâ çalışanlar), hizmetlerin ve yeteneklerin de burada."))
                        .font(Design.Font.body).foregroundStyle(.secondary)
                    HStack {
                        TextField(L("Şirket adı"), text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(create)
                        Button(L("Kur"), action: create).actionPrimary().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(maxWidth: 460)
                }
                .padding(Design.Space.l).card()
            }
            .pagePadding().padding(.vertical, Design.Space.l)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func create() { app.createStudio(name: name) }
}

struct MemberDraft: Identifiable {
    var member: TeamMember
    var isNew: Bool
    var id: String { member.id }
}

struct ServiceDraft: Identifiable {
    var service: ServiceOffering
    var isNew: Bool
    var id: String { service.id }
}

/// Tarih isteğe bağlı: anahtar kapalıysa değer `nil`.
struct OptionalDayField: View {
    let title: String
    @Binding var day: String?
    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { day != nil }, set: { day = $0 ? (day ?? DayString.from(Date())) : nil }))
            if let current = day {
                Spacer()
                DatePicker("", selection: Binding(get: { DayString.date(current) ?? Date() }, set: { day = DayString.from($0) }),
                           displayedComponents: .date).labelsHidden()
            }
        }
    }
}

// MARK: Biz

private struct CompanyAboutForm: View {
    @Environment(AppModel.self) private var app
    @State private var draft = CompanyProfile()
    @State private var saved = CompanyProfile()
    @State private var loaded = false
    @State private var pendingId = UUID()

    private var dirty: Bool {
        draft.name != saved.name || draft.tagline != saved.tagline || draft.about != saved.about
            || draft.mission != saved.mission || draft.foundedOn != saved.foundedOn || draft.website != saved.website
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            VStack(alignment: .leading, spacing: Design.Space.m) {
                HStack(alignment: .top, spacing: Design.Space.l) {
                    labeled(L("Şirket adı")) { TextField(L("Örn. Örnek Ajans"), text: $draft.name).textFieldStyle(.roundedBorder).accessibilityLabel(L("Şirket adı")) }
                    labeled(L("Slogan")) { TextField(L("Tek cümlede ne yapıyoruz"), text: $draft.tagline).textFieldStyle(.roundedBorder).accessibilityLabel(L("Slogan")) }
                }
                HStack(alignment: .top, spacing: Design.Space.l) {
                    labeled(L("Web sitesi")) { TextField(L("https://"), text: $draft.website).textFieldStyle(.roundedBorder).accessibilityLabel(L("Web sitesi")) }
                    labeled(L("Kuruluş")) { OptionalDayField(title: L("Kuruluş günü belli"), day: $draft.foundedOn) }
                }
                labeled(L("Biz kimiz")) { editor($draft.about, label: L("Biz kimiz"), height: 110) }
                labeled(L("Misyon")) { editor($draft.mission, label: L("Misyon"), height: 70) }
            }
            .padding(Design.Space.l).card()
            HStack {
                Text(L("Bu bilgiler, yapay zekâya izin verdiğin her markanın bağlamına girer. Müşteri verisi içermez."))
                    .captionStyle()
                Spacer()
                Button(L("Kaydet")) { saveProfile() }
                .actionPrimary().disabled(!dirty)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear {
            guard !loaded, let p = try? app.store?.companyProfile() else { return }
            draft = p; saved = p; loaded = true
        }
        .onChange(of: draft) { _, _ in registerPending() }
        .onDisappear { PendingEdits.shared.flush(pendingId) }
    }

    /// Yazarken uygulama kapanırsa form kaybolmasın (U-07). Her değişimde yeniden kaydedilir; kapanış güncel taslağı okur.
    private func registerPending() {
        guard loaded else { return }
        if dirty { PendingEdits.shared.register(pendingId, save: { saveProfile() }) }
        else { PendingEdits.shared.clear(pendingId) }
    }

    private func saveProfile() {
        PendingEdits.shared.clear(pendingId)
        guard dirty else { return }
        if let p = app.perform(title: L("Kaydedilemedi"), context: "sirket.kaydet", { try app.store?.saveCompanyProfile(draft) }) ?? nil {
            saved = p; draft = p
            app.reloadViews()
        } else {
            registerPending()   // kaydedilemedi: kapanışta yeniden denensin
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Design.Font.callout.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func editor(_ text: Binding<String>, label: String, height: CGFloat) -> some View {
        TextEditor(text: text).font(Design.Font.body).scrollContentBackground(.hidden).accessibilityLabel(label).padding(6)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.windowBackground.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
    }
}

// MARK: Hizmetler

private struct ServicesList: View {
    @Environment(AppModel.self) private var app
    @Binding var draft: ServiceDraft?

    var body: some View {
        let items = app.read(or: []) { try $0.services() }
        VStack(alignment: .leading, spacing: Design.Space.m) {
            HStack {
                Text(items.isEmpty ? "" : LF("Hizmetler: %d", items.count)).captionStyle()
                Spacer()
                Button { draft = ServiceDraft(service: ServiceOffering(name: ""), isNew: true) } label: {
                    Label(L("Hizmet ekle"), systemImage: "plus").labelStyle(.titleAndIcon)
                }.actionPrimary()
            }
            if items.isEmpty {
                EmptyStateView(title: L("Henüz hizmet yok"),
                               message: L("Sunduğun hizmetleri yaz: yapay zekâ, müşteriye ne sattığını buradan öğrenir."),
                               actionTitle: L("Hizmet ekle"), action: { draft = ServiceDraft(service: ServiceOffering(name: ""), isNew: true) },
                               symbol: "briefcase")
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { s in
                        Button { draft = ServiceDraft(service: s, isNew: false) } label: { row(s) }.buttonStyle(.plain)
                        if s.id != items.last?.id { Divider().padding(.leading, Design.Space.l) }
                    }
                }
                .card()
            }
        }
    }

    private func row(_ s: ServiceOffering) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(Design.Font.heading.weight(.semibold))
                if !s.summary.isEmpty { Text(s.summary).font(Design.Font.callout).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: Design.Space.m)
            if let d = s.startedOn, let date = DayString.date(d) {
                Text(LF("Başlangıç: %@", date.formatted(.dateTime.month(.abbreviated).year()))).captionStyle()
            }
            Pill(text: s.status.title, tint: s.status == .active ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, Design.Space.l).padding(.vertical, 12).contentShape(Rectangle())
        .hoverRow()
        .accessibilityElement(children: .combine)
    }
}

private struct ServiceSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var draft: ServiceDraft
    @State private var confirmDelete = false

    init(draft: ServiceDraft) { _draft = State(initialValue: draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField(L("Hizmet adı"), text: $draft.service.name)
                TextField(L("Kısa tanım"), text: $draft.service.summary)
                Picker(L("Durum"), selection: $draft.service.status) {
                    ForEach(ServiceStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                OptionalDayField(title: L("Başlangıç günü belli"), day: $draft.service.startedOn)
                Section(L("Ayrıntı (kime, nasıl, neyle teslim edilir)")) {
                    TextEditor(text: $draft.service.details).accessibilityLabel(L("Ayrıntı (kime, nasıl, neyle teslim edilir)")).frame(minHeight: 110)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !draft.isNew { Button(L("Sil"), role: .destructive) { confirmDelete = true } }
                Spacer()
                Button(L("İptal")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Kaydet")) {
                    if app.perform(title: L("Kaydedilemedi"), context: "hizmet.kaydet", { try app.store?.saveService(draft.service) }) != nil {
                        app.reloadViews(); dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction).actionPrimary()
                .disabled(draft.service.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Design.Space.l)
        }
        .frame(width: 500, height: 560)
        .confirmationDialog(LF("“%@” silinsin mi?", draft.service.name), isPresented: $confirmDelete) {
            Button(L("Sil"), role: .destructive) {
                if app.perform(title: L("Silinemedi"), context: "hizmet.sil", { try app.store?.deleteService(draft.service.id) }) != nil {
                    app.reloadViews(); dismiss()
                }
            }
        } message: { Text(L("Hizmet kalıcı olarak silinir. Bu işlem geri alınamaz.")) }
    }
}

// MARK: Ekip

private struct TeamList: View {
    @Environment(AppModel.self) private var app
    @Binding var draft: MemberDraft?
    @State private var showArchived = false
    /// E-18: şablondan ekip önerisi sayfası.
    @State private var showTemplate = false
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let all = app.read(or: []) { try $0.teamMembers(includeArchived: showArchived) }
        let activity = app.read(or: [:]) { try $0.memberActivity() }
        let names = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name) })
        let humans = all.filter { $0.kind == .human }
        let ais = all.filter { $0.kind == .ai }
        VStack(alignment: .leading, spacing: Design.Space.l) {
            // Geliştirme: ekran çiziminde şablon sayfası sayfa içinde çizilir (`MARKA_SABLON`; sayfa çizilemez).
            if isSnapshot, DevHook.value("MARKA_SABLON") != nil { TeamTemplateSheet().card() }
            HStack {
                Toggle(L("Arşivdekileri göster"), isOn: $showArchived).toggleStyle(.checkbox).font(Design.Font.callout)
                Spacer()
                Button { showTemplate = true } label: {
                    Label(L("Şablondan kur"), systemImage: "rectangle.stack.badge.plus").labelStyle(.titleAndIcon)
                }.actionSecondary()
                    .help(L("Hazır ekip şablonundan onay bekleyen çalışan önerileri oluştur"))
                Button { draft = MemberDraft(member: TeamMember(kind: .human, name: "", title: ""), isNew: true) } label: {
                    Label(L("Kişi ekle"), systemImage: "person.badge.plus").labelStyle(.titleAndIcon)
                }.actionSecondary()
                Button { draft = MemberDraft(member: TeamMember(kind: .ai, name: "", title: "", level: .junior, provider: MemberProvider.anthropic.rawValue), isNew: true) } label: {
                    Label(L("Yapay zekâ çalışan ekle"), systemImage: "sparkles").labelStyle(.titleAndIcon)
                }.actionPrimary()
            }
            group(L("İnsanlar"), members: humans, names: names, activity: activity,
                  empty: L("Henüz kimse yok. Kendini ve birlikte çalıştığın insanları ekle."))
            group(L("Yapay zekâ ekibi"), members: ais, names: names, activity: activity,
                  empty: L("Henüz yapay zekâ çalışan yok. Bir rol, bir kıdem ve görev tarifi ver."))
            Text(L("Yapay zekâ çalışanlar şimdilik rol tanımıdır: görev tarifi ve yetenekleri, atandığı markanın yapay zekâ bağlamına girer. Kendi başlarına çalışmazlar; ürettikleri her şey öneridir ve onayı sendedir."))
                .captionStyle()
        }
        .sheet(isPresented: $showTemplate) { TeamTemplateSheet() }
    }

    @ViewBuilder private func group(_ title: String, members: [TeamMember], names: [String: String], activity: [String: Store.MemberActivity], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Text(title).font(Design.Font.body.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            if members.isEmpty {
                Text(empty).font(Design.Font.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Design.Space.l).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { m in
                        Button { draft = MemberDraft(member: m, isNew: false) } label: { row(m, boss: m.reportsToId.flatMap { names[$0] }, activity: activity[m.id]) }.buttonStyle(.plain)
                        if m.id != members.last?.id { Divider().padding(.leading, 62) }
                    }
                }
                .card()
            }
        }
    }

    private func row(_ m: TeamMember, boss: String?, activity: Store.MemberActivity?) -> some View {
        HStack(spacing: Design.Space.m) {
            MemberAvatar(member: m)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(Design.Font.heading.weight(.semibold))
                Text([m.title, m.department, boss.map { LF("Bağlı: %@", $0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Design.Font.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Design.Space.m)
            if let a = activity {
                if a.pending > 0 { Pill(text: LF("Bekleyen öneri: %d", a.pending), tint: AnyShapeStyle(Design.accent)) }
                else if let t = a.lastActiveAt { Text(t.formatted(.relative(presentation: .named))).captionStyle() }
            }
            Pill(text: m.level.title)
            if m.kind == .ai { Pill(text: m.model.isEmpty ? m.providerTitle : m.model, tint: AnyShapeStyle(Design.accent)) }
            if m.status == .archived { Pill(text: L("Arşivde")) }
        }
        .padding(.horizontal, Design.Space.l).padding(.vertical, 10).contentShape(Rectangle())
        .hoverRow()
        .accessibilityElement(children: .combine)
    }
}

// MARK: Şema

private struct OrgChartView: View {
    @Environment(AppModel.self) private var app
    @Binding var draft: MemberDraft?

    var body: some View {
        let roots = app.read(or: []) { try $0.orgChart() }
        VStack(alignment: .leading, spacing: Design.Space.m) {
            if roots.isEmpty {
                EmptyStateView(title: L("Şema boş"), message: L("Ekip sekmesinde üye ekle; “bağlı olduğu kişi” ile şemayı kur."), symbol: "person.3")
            } else {
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    ForEach(roots) { NodeView(node: $0, depth: 0, draft: $draft) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Şemada yalnızca etkin üyeler görünür. Bir üyeyi arşivlemek, astlarını onun yöneticisine bağlar."))
                    .captionStyle()
            }
        }
    }

    private struct NodeView: View {
        let node: OrgNode
        let depth: Int
        @Binding var draft: MemberDraft?

        var body: some View {
            VStack(alignment: .leading, spacing: Design.Space.s) {
                Button { draft = MemberDraft(member: node.member, isNew: false) } label: {
                    HStack(spacing: Design.Space.m) {
                        MemberAvatar(member: node.member, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.member.name).font(Design.Font.body.weight(.semibold))
                            Text([node.member.title, node.member.level.title].joined(separator: " · ")).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if node.member.kind == .ai { Pill(text: L("Yapay zekâ"), tint: AnyShapeStyle(Design.accent)) }
                        if !node.children.isEmpty { Text(LF("Doğrudan bağlı: %d", node.children.count)).captionStyle() }
                    }
                    .padding(.horizontal, Design.Space.m).padding(.vertical, 8).card(radius: Design.Radius.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("%1$@, %2$@", node.member.name, node.member.title))
                if !node.children.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle().fill(Design.line).frame(width: 1).padding(.leading, 17)
                        VStack(alignment: .leading, spacing: Design.Space.s) {
                            ForEach(node.children) { child in
                                HStack(alignment: .top, spacing: 0) {
                                    Rectangle().fill(Design.line).frame(width: Design.Space.l, height: 1).padding(.top, 23)
                                    NodeView(node: child, depth: depth + 1, draft: $draft)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Yetenekler

struct SkillDraft: Identifiable {
    var skill: Skill
    var isNew: Bool
    var id: String { skill.id }
}

/// Yetenek kütüphanesi: SKILL.md biçiminde yetenekler. Çalışana ad ile bağlanır; yapay zekâ çalışanın bağlamına tanım ve yönergeler girer.
private struct SkillsLibrary: View {
    @Environment(AppModel.self) private var app
    @Binding var draft: SkillDraft?
    @State private var notice: String?
    /// E-14: klasör paketi önizlemesi (onay sayfası).
    @State private var importDraft: SkillImportDraft?
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let skills = app.read(or: []) { try $0.skills() }
        let members = app.read(or: []) { try $0.teamMembers() }
        VStack(alignment: .leading, spacing: Design.Space.l) {
            HStack(spacing: Design.Space.s) {
                Text(skills.isEmpty ? "" : LF("Yetenekler: %d", skills.count)).captionStyle()
                Spacer()
                Menu {
                    ForEach(SkillPacks.all) { pack in
                        Button("\(pack.title) (\(pack.skills.count))") { install(pack) }
                    }
                } label: { Label(L("Hazır paket yükle"), systemImage: "square.and.arrow.down").labelStyle(.titleAndIcon) }
                    .menuStyle(.button).fixedSize()
                Menu {
                    Button(L("SKILL.md içe aktar…")) { importFile() }
                    Button(L("Klasörden içe aktar…")) { importDraft = SkillImportDraft.choose(app: app) }
                } label: { Label(L("İçe aktar"), systemImage: "doc.badge.plus").labelStyle(.titleAndIcon) }
                    .menuStyle(.button).fixedSize()
                    .help(L("SKILL.md dosyası ya da yetenek klasörü içe aktar"))
                    .accessibilityLabel(L("İçe aktar"))
                Button { draft = SkillDraft(skill: Skill(name: "", description: ""), isNew: true) } label: {
                    Label(L("Yetenek ekle"), systemImage: "plus").labelStyle(.titleAndIcon)
                }.actionPrimary()
            }
            if let notice { Text(notice).font(Design.Font.callout).foregroundStyle(Design.accent) }
            // Geliştirme: ekran çiziminde onay sayfası sayfa içinde çizilir (`MARKA_YETENEK_KLASORU`; sayfa çizilemez).
            if isSnapshot, let path = DevHook.value("MARKA_YETENEK_KLASORU"),
               let preview = SkillImportDraft.load(folder: URL(fileURLWithPath: path, isDirectory: true), app: app) {
                SkillImportSheet(draft: preview).card()
            }
            if skills.isEmpty {
                EmptyStateView(title: L("Henüz yetenek yok"),
                               message: L("Yetenek, bir çalışana verdiğin küçük bir çalışma yöntemidir. Hazır bir paketle başla ya da kendin yaz."),
                               symbol: "wand.and.stars")
            } else {
                ForEach(groups(skills), id: \.key) { group in
                    VStack(alignment: .leading, spacing: Design.Space.s) {
                        Text(group.title).font(Design.Font.body.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(group.items) { sk in
                                Button { draft = SkillDraft(skill: sk, isNew: false) } label: { row(sk, users: members.filter { $0.skills.contains(sk.name) }) }
                                    .buttonStyle(.plain)
                                if sk.id != group.items.last?.id { Divider().padding(.leading, Design.Space.l) }
                            }
                        }
                        .card()
                    }
                }
            }
            Text(L("Yetenek yetki vermez: yapay zekâ çalışan yeteneğiyle de yalnızca öneri üretir. Hazır paketlerin metinleri bu uygulamaya aittir; biçim, ajan yeteneklerinde yaygın SKILL.md düzenini izler."))
                .captionStyle()
        }
        .sheet(item: $importDraft) { d in
            SkillImportSheet(draft: d) { sk in notice = LF("“%@” eklendi.", sk.displayTitle) }
        }
    }

    private func groups(_ skills: [Skill]) -> [(key: String, title: String, items: [Skill])] {
        var out: [(key: String, title: String, items: [Skill])] = []
        for pack in SkillPacks.all {
            let items = skills.filter { $0.pack == pack.key }
            if !items.isEmpty { out.append((pack.key, pack.title, items)) }
        }
        let own = skills.filter { s in !SkillPacks.all.contains { $0.key == s.pack } }
        if !own.isEmpty { out.append(("", L("Kendi yeteneklerimiz"), own)) }
        return out
    }

    private func row(_ sk: Skill, users: [TeamMember]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sk.displayTitle).font(Design.Font.heading.weight(.semibold))
                Text(sk.description).font(Design.Font.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: Design.Space.m)
            if sk.hasLocalChanges { Pill(text: L("Yerel değişiklik var"), tint: AnyShapeStyle(Design.accent)) }
            if sk.isImported { Pill(text: L("İçe aktarıldı")) }
            if !users.isEmpty { Text(LF("Kullanan: %d", users.count)).captionStyle() }
        }
        .padding(.horizontal, Design.Space.l).padding(.vertical, 12).contentShape(Rectangle())
        .hoverRow()
        .help(Self.originHelp(sk))
        .accessibilityElement(children: .combine)
    }

    /// Satır ipucu: ad, köken (yalnız dosya/klasör adı) ve yerel değişiklik.
    static func originHelp(_ sk: Skill) -> String {
        var parts = [sk.name]
        switch sk.originKind {
        case .folder(let n) where !n.isEmpty: parts.append(LF("Kaynak klasör: %@", n))
        case .file(let n) where !n.isEmpty: parts.append(LF("Kaynak dosya: %@", n))
        case .folder, .file: parts.append(L("İçe aktarıldı"))
        case .pack: parts.append(L("Hazır paket"))
        case .manual: break
        }
        if sk.hasLocalChanges { parts.append(L("Yerel değişiklik var: metin içe aktarıldığı hâlinden farklı.")) }
        return parts.joined(separator: " · ")
    }

    private func install(_ pack: SkillPack) {
        if let n = app.perform(title: L("Yüklenemedi"), context: "yetenek.paket", { try app.store?.installSkillPack(pack) }) ?? nil {
            notice = n == 0 ? LF("“%@” zaten yüklü.", pack.title) : LF("“%1$@” paketi yüklendi (yeni yetenek: %2$d).", pack.title, n)
            app.reloadViews()
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.message = L("SKILL.md dosyasını seç")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = app.perform(title: L("Dosya okunamadı"), context: "yetenek.oku", { try String(contentsOf: url, encoding: .utf8) }) else { return }
        if let sk = app.perform(title: L("İçe aktarılamadı"), context: "yetenek.ice", { try app.store?.importSkill(markdown: text, fileName: url.lastPathComponent) }) ?? nil {
            notice = LF("“%@” eklendi.", sk.displayTitle)
            app.reloadViews()
        }
    }
}

private struct SkillSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var draft: SkillDraft
    @State private var nameEdited: Bool
    @State private var confirmDelete = false

    init(draft: SkillDraft) { _draft = State(initialValue: draft); _nameEdited = State(initialValue: !draft.isNew) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField(L("Başlık (örn. SEO denetimi)"), text: Binding(get: { draft.skill.title }, set: { v in
                    draft.skill.title = v
                    if !nameEdited { draft.skill.name = SkillMarkdown.slug(v) }
                }))
                TextField(L("Ad (küçük harf-tire)"), text: Binding(get: { draft.skill.name }, set: { draft.skill.name = $0; nameEdited = true }))
                    .font(.system(.body, design: .monospaced))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Tanım: ne yapar, ne zaman kullanılır")).font(Design.Font.callout).foregroundStyle(.secondary)
                    TextEditor(text: $draft.skill.description).accessibilityLabel(L("Tanım: ne yapar, ne zaman kullanılır")).frame(minHeight: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Yönergeler (adım adım)")).font(Design.Font.callout).foregroundStyle(.secondary)
                    TextEditor(text: $draft.skill.body).accessibilityLabel(L("Yönergeler (adım adım)")).font(Design.Font.body).frame(minHeight: 180)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !draft.isNew {
                    Button(L("Sil"), role: .destructive) { confirmDelete = true }
                    Button(L("SKILL.md kopyala")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SkillMarkdown.export(draft.skill), forType: .string)
                    }
                }
                Spacer()
                Button(L("İptal")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Kaydet")) {
                    if app.perform(title: L("Kaydedilemedi"), context: "yetenek.kaydet", { try app.store?.saveSkill(draft.skill) }) != nil {
                        app.reloadViews(); dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction).actionPrimary()
                .disabled(draft.skill.name.isEmpty || draft.skill.description.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Design.Space.l)
        }
        .frame(width: 560, height: 640)
        .confirmationDialog(LF("“%@” silinsin mi?", draft.skill.displayTitle), isPresented: $confirmDelete) {
            Button(L("Sil"), role: .destructive) {
                if app.perform(title: L("Silinemedi"), context: "yetenek.sil", { try app.store?.deleteSkill(draft.skill.id) }) != nil {
                    app.reloadViews(); dismiss()
                }
            }
        } message: { Text(L("Yetenek kütüphaneden silinir; çalışanların listesindeki adı serbest metin olarak kalır.")) }
    }
}

// MARK: Üye sayfası

private struct MemberSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var draft: MemberDraft
    @State private var skills: [String]
    @State private var newSkill = ""
    @State private var teams: [String: AssignmentRole] = [:]

    init(draft: MemberDraft) {
        _draft = State(initialValue: draft)
        _skills = State(initialValue: draft.member.skills)
    }

    private var isAI: Bool { draft.member.kind == .ai }
    private var canSave: Bool {
        !draft.member.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.member.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        let others = (app.read(or: []) { try $0.teamMembers() }).filter { $0.id != draft.member.id }
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField(isAI ? L("Ad (örn. Claude Code)") : L("Ad soyad"), text: $draft.member.name)
                    TextField(L("Unvan (örn. Kıdemli yazılımcı)"), text: $draft.member.title)
                    Picker(L("Kıdem"), selection: $draft.member.level) {
                        ForEach(MemberLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField(L("Bölüm (örn. Tasarım)"), text: $draft.member.department)
                    Picker(L("Bağlı olduğu kişi"), selection: $draft.member.reportsToId) {
                        Text(L("Kimse")).tag(String?.none)
                        ForEach(others) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    OptionalDayField(title: L("Başlangıç günü belli"), day: $draft.member.startedOn)
                }
                if isAI { aiSection } else {
                    Section { TextField(L("E-posta"), text: $draft.member.email) }
                }
                Section(L("Hakkında")) { TextEditor(text: $draft.member.bio).accessibilityLabel(L("Hakkında")).frame(minHeight: 70) }
                if !draft.isNew { assignmentSection }
            }
            .formStyle(.grouped)
            HStack {
                if !draft.isNew {
                    if draft.member.status == .active {
                        Button(L("Arşivle")) { run("uye.arsivle") { try app.store?.archiveTeamMember(draft.member.id) } }
                    } else {
                        Button(L("Geri yükle")) { run("uye.geri") { try app.store?.restoreTeamMember(draft.member.id) } }
                    }
                }
                Spacer()
                Button(L("İptal")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Kaydet")) {
                    draft.member.skills = skills
                    run("uye.kaydet") { try app.store?.saveTeamMember(draft.member) }
                }
                .keyboardShortcut(.defaultAction).actionPrimary().disabled(!canSave)
            }
            .padding(Design.Space.l)
        }
        .frame(width: 540, height: 680)
        .onAppear { loadTeams() }
    }

    private func run<T>(_ context: StaticString, _ action: () throws -> T) {
        if app.perform(title: L("Kaydedilemedi"), context: context, action) != nil { app.reloadViews(); dismiss() }
    }

    private var aiSection: some View {
        Section(L("Yapay zekâ çalışan")) {
            Picker(L("Sağlayıcı"), selection: Binding(get: { MemberProvider(rawValue: draft.member.provider) ?? .other },
                                                    set: { draft.member.provider = $0.rawValue })) {
                ForEach(MemberProvider.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField(L("Model (örn. claude-opus-5-5)"), text: $draft.member.model)
            skillsEditor
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Görev tarifi")).font(Design.Font.callout).foregroundStyle(.secondary)
                TextEditor(text: $draft.member.charter).accessibilityLabel(L("Görev tarifi")).frame(minHeight: 90)
            }
            Text(L("Sağlayıcı ve model şimdilik kayıt amaçlıdır; sohbet paneli seçili sağlayıcıyla çalışır. Görev tarifi, atandığı markanın bağlamına girer."))
                .captionStyle()
        }
    }

    /// Yetenek seçimi: kütüphaneden ekle, ya da serbest metin yaz; çıkarmak için ×.
    private var skillsEditor: some View {
        let library = app.read(or: []) { try $0.skills() }
        let titles = Dictionary(uniqueKeysWithValues: library.map { ($0.name, $0.displayTitle) })
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Yetenekler")).font(Design.Font.callout).foregroundStyle(.secondary)
            if !skills.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(skills, id: \.self) { name in
                        HStack(spacing: 4) {
                            Image(systemName: titles[name] != nil ? "wand.and.stars" : "text.alignleft").font(Design.Icon.small)
                            Text(titles[name] ?? name).lineLimit(1)
                            Button { skills.removeAll { $0 == name } } label: { Image(systemName: "xmark").font(Design.Icon.small.weight(.bold)) }
                                .buttonStyle(.plain).accessibilityLabel(LF("%@ yeteneğini çıkar", titles[name] ?? name))
                        }
                        .font(Design.Font.small.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Design.accent.opacity(0.12)))
                    }
                }
            }
            HStack {
                Menu(L("Kütüphaneden ekle")) {
                    ForEach(library.filter { !skills.contains($0.name) }) { sk in Button(sk.displayTitle) { skills.append(sk.name) } }
                }
                .menuStyle(.borderlessButton).fixedSize().disabled(library.allSatisfy { skills.contains($0.name) })
                TextField(L("Başka yetenek (↩)"), text: $newSkill).onSubmit {
                    let t = newSkill.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty, !skills.contains(t) { skills.append(t) }
                    newSkill = ""
                }
            }
        }
    }

    /// Hangi markalarda çalışıyor: her marka için Yok / Üye / Lider. Seçim anında kaydedilir (atama ayrı bir kayıttır).
    private var assignmentSection: some View {
        Section(L("Müşteri ekibi")) {
            if app.customerBrands.isEmpty {
                Text(L("Henüz marka yok.")).foregroundStyle(.secondary)
            } else {
                ForEach(app.customerBrands) { brand in
                    Picker(brand.name, selection: Binding(get: { teams[brand.id] }, set: { set(brand.id, $0) })) {
                        Text(L("Atanmadı")).tag(AssignmentRole?.none)
                        Text(L("Ekip üyesi")).tag(AssignmentRole?.some(.member))
                        Text(L("Ekip lideri")).tag(AssignmentRole?.some(.lead))
                    }
                    .disabled(draft.member.status == .archived)
                }
            }
        }
    }

    private func loadTeams() {
        guard !draft.isNew else { return }
        let rows = app.read(or: []) { try $0.assignments(memberId: draft.member.id) }
        teams = Dictionary(uniqueKeysWithValues: rows.map { ($0.brandId, $0.role) })
    }

    private func set(_ brandId: String, _ role: AssignmentRole?) {
        let id = draft.member.id
        let ok: Void? = app.perform(title: L("Atanamadı"), context: "uye.ata") {
            if let role { try app.store?.assignMember(id, to: brandId, role: role) } else { try app.store?.unassignMember(id, from: brandId) }
        }
        if ok != nil { app.reloadViews() }
        loadTeams()
    }
}


private struct HoverRow: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(Rectangle().fill(hovering ? AnyShapeStyle(Design.rowSelected.opacity(0.55)) : AnyShapeStyle(.clear)))
            .onHover { hovering = $0 }
    }
}

private extension View {
    /// Satırın üstüne gelince hafif zemin: tıklanabilir olduğu belli olsun.
    func hoverRow() -> some View { modifier(HoverRow()) }
}
