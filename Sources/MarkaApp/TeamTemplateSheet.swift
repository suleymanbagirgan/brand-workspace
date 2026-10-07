import MarkaCore
import SwiftUI

/// E-18: "Şablondan ekip kur" sayfası. Şablon seçilince kurulacak roller, görev tarifleri ve yetenekler önizlenir.
/// "Önerileri oluştur" ekip kurmaz: her rol onay bekleyen bir "yeni çalışan" önerisi olur ve kullanıcı onay sayfasında tek tek seçer.
/// Varsayılan seçim boştur (şablon seçilmeden düğme kapalıdır); "Vazgeç" hiçbir şey yazmaz.
struct TeamTemplateSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isSnapshot) private var isSnapshot
    /// Şablonun hangi anahtarla başlayacağı; boşsa hiçbiri seçili değildir. Ekran çiziminde `MARKA_SABLON` önizlemeyi açar.
    @State private var selectedKey: String?
    @State private var reportsToId: String?
    @State private var result: Store.TeamTemplateResult?

    init() {
        _selectedKey = State(initialValue: DevHook.value("MARKA_SABLON"))
    }

    private var template: TeamTemplate? { TeamTemplates.all.first { $0.key == selectedKey } }

    var body: some View {
        let members = app.read(or: []) { try $0.teamMembers() }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Design.Space.m) {
                Text(L("Şablondan ekip kur")).font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if let result {
                    outcome(result)
                } else {
                    chooser
                    if let template {
                        preview(template, members: members)
                    } else {
                        Text(L("Bir şablon seç; kurulacak roller burada görünür. Seçmeden hiçbir şey oluşmaz."))
                            .font(Design.Font.callout).foregroundStyle(.secondary)
                    }
                }
                Text(L("Şablon ekip kurmaz: her rol onay bekleyen bir öneri olur. Onay sayfasında istediğini seçersin; seçmediğin hiçbir zaman eklenmez. Roller rol tanımıdır, kendi başlarına çalışmaz."))
                    .captionStyle().fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Space.l)
            Divider()
            HStack {
                Spacer()
                if result == nil {
                    Button(L("Vazgeç")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L("Önerileri oluştur")) { create() }
                        .keyboardShortcut(.defaultAction).actionPrimary()
                        .disabled(template == nil)
                        .help(template == nil ? L("Önce bir şablon seç.") : L("Her rol için onay bekleyen bir öneri açar."))
                } else {
                    Button(L("Kapat")) { dismiss() }.keyboardShortcut(.defaultAction).actionPrimary()
                }
            }
            .padding(Design.Space.l)
        }
        .frame(width: 640, height: isSnapshot ? nil : 640)
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            ForEach(TeamTemplates.all) { t in
                Button { selectedKey = t.key } label: {
                    HStack(alignment: .top, spacing: Design.Space.m) {
                        Image(systemName: selectedKey == t.key ? "largecircle.fill.circle" : "circle")
                            .font(Design.Font.heading).foregroundStyle(selectedKey == t.key ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Design.Space.xs) {
                            Text(t.title).font(Design.Font.body.weight(.semibold))
                            Text(t.summary).font(Design.Font.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Design.Space.m)
                        Pill(text: LF("Rol sayısı: %d", t.roles.count))
                    }
                    .padding(Design.Space.m).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card(radius: Design.Radius.medium)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selectedKey == t.key ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func preview(_ t: TeamTemplate, members: [TeamMember]) -> some View {
        let taken = takenNames(members: members)
        return VStack(alignment: .leading, spacing: Design.Space.s) {
            Picker(L("Bağlı olacağı kişi"), selection: $reportsToId) {
                Text(L("Kimseye bağlı değil")).tag(String?.none)
                ForEach(members) { m in Text(m.name).tag(String?.some(m.id)) }
            }
            .pickerStyle(.menu).fixedSize()
            Text(L("Kurulacak roller")).font(Design.Font.callout.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    ForEach(t.roles, id: \.name) { r in
                        roleCard(r, skipped: taken.contains(Self.key(r.name)))
                    }
                }
            }
            .frame(maxHeight: isSnapshot ? nil : 260)
        }
    }

    private func roleCard(_ r: TeamTemplateRole, skipped: Bool) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack(spacing: Design.Space.s) {
                Text(r.name).font(Design.Font.body.weight(.semibold))
                Pill(text: r.level.title)
                if !r.department.isEmpty { Pill(text: r.department) }
                if skipped { Pill(text: L("Zaten var, atlanır"), tint: AnyShapeStyle(Design.accent)) }
            }
            Text(r.charter).font(Design.Font.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(LF("Yetenekler: %@", r.skills.joined(separator: ", "))).captionStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.m).card(radius: Design.Radius.medium)
        .opacity(skipped ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private func outcome(_ r: Store.TeamTemplateResult) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Label(r.proposals.isEmpty ? L("Yeni öneri açılmadı.") : LF("Onay bekleyen öneri: %d", r.proposals.count),
                  systemImage: r.proposals.isEmpty ? "info.circle" : "checkmark.circle")
                .font(Design.Font.body.weight(.semibold))
            if !r.proposals.isEmpty {
                Text(L("Öneriler onay sayfasında bekliyor. Ekip, sen onaylayana kadar değişmez."))
                    .font(Design.Font.callout).foregroundStyle(.secondary)
            }
            if !r.skipped.isEmpty {
                Text(LF("Zaten var olduğu için atlananlar: %@", r.skipped.joined(separator: ", ")))
                    .font(Design.Font.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr_TR")) }

    /// Çekirdeğin atlayacağı adlar: etkin üyeler ve bekleyen çalışan önerileri (önizleme, kurulumla aynı kuralı gösterir).
    private func takenNames(members: [TeamMember]) -> Set<String> {
        var taken = Set(members.map { Self.key($0.name) })
        if let own = app.ownBrand {
            let pending = app.read(or: []) { try $0.proposals(brandId: own.id, status: .pending) }
            for p in pending where p.kind == .createTeamMember {
                if let x = p.payload(ProposalPayload.CreateTeamMember.self) { taken.insert(Self.key(x.name)) }
            }
        }
        return taken
    }

    private func create() {
        guard let template else { return }
        if let r = app.perform(title: L("Öneriler oluşturulamadı"), context: "ekip.sablon", {
            try app.store?.proposeTeamTemplate(template, reportsToId: reportsToId)
        }) ?? nil {
            app.reloadViews()
            result = r
        }
    }
}
