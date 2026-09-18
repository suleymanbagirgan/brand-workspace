import AppKit
import MarkaCore
import SwiftUI

/// ··· › Bilgiler ve AI izinleri: tek sayfa, sade bölümler — *Profil* (ad, sektör, tanım), *AI izinleri*, *Kişiler*,
/// *Projeler* ve (varsa) *Hedef, teklif ve tarihler* (salt okunur; terminal önerisiyle gelen kayıtlar). Satıra tıklayınca
/// satır yerinde düzenlenir (ayrı düzenleyici sayfası yok); Enter kaydeder, Esc vazgeçer.
/// Söz, karar bekleniyor ve talepler burada değil, Yapılacaklar ve Akış'ta; dosya ve notlar Akış'ta.
struct BrandInfoView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let brand: Brand
    /// Aynı anda tek satır düzenlenir.
    @State private var profileDraft: Brand?
    @State private var contactDraft: Contact?
    @State private var projectDraft: Project?
    @State private var deletingContact: Contact?

    private var isEditing: Bool { profileDraft != nil || contactDraft != nil || projectDraft != nil }

    var body: some View {
        let _ = app.revision
        let current = (try? app.store?.brand(brand.id)) ?? brand
        VStack(spacing: 0) {
            PageScroll {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    Text(L("Bilgiler")).font(Design.Font.title).accessibilityAddTraits(.isHeader)
                    profile(current)
                    permissions(current)
                    contacts
                    projects
                    references
                }
                .padding(Design.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                // Tek alt düğme: "Kapat" (düzenlenmemişse Enter). Satır düzenlenirken birincil düğme satırdaki "Kaydet";
                // Esc düzenlemeden vazgeçer, "Kapat" kaydedilmemiş düzenlemeyi bırakıp sayfayı kapatır.
                Button(L("Kapat")) { dismiss() }
                    .buttonStyle(.text)
                    .keyboardShortcut(isEditing ? nil : KeyboardShortcut.defaultAction)
            }
            .padding(.horizontal, Design.Space.l).padding(.vertical, Design.Space.m)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 640)
        .confirmationDialog(L("Kişi silinsin mi?"), isPresented: Binding(get: { deletingContact != nil }, set: { if !$0 { deletingContact = nil } }),
                            presenting: deletingContact) { c in
            Button(L("Kişiyi sil"), role: .destructive) {
                if app.perform({ try app.store?.deleteContact(c.id) }) != nil { contactDraft = nil }
            }
        } message: { c in
            Text(LF("“%@” ve iletişim bilgileri kalıcı olarak silinir. Bu işlem geri alınamaz.", c.name))
        }
    }

    private func header(_ title: String, action: String? = nil, _ perform: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Design.Font.section).accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action, action: perform).buttonStyle(.text).disabled(isEditing)
            }
        }
    }

    private func edit(profile: Brand? = nil, contact: Contact? = nil, project: Project? = nil) {
        profileDraft = profile
        contactDraft = contact
        projectDraft = project
    }

    private func cancelEdit() { edit() }

    // MARK: Profil

    private func profile(_ b: Brand) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            header(L("Profil"))
            if let binding = Binding($profileDraft) {
                InfoEditForm(canSave: !binding.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty,
                             cancel: cancelEdit,
                             save: { if app.perform({ try app.store?.updateBrand(binding.wrappedValue) }) != nil { profileDraft = nil } }) {
                    InputField(title: L("Marka adı"), text: binding.name)
                    InputField(title: L("Sektör"), text: binding.sector)
                    MultilineInputField(title: L("Kısa tanım"), text: binding.summary)
                }
            } else {
                EditableRow(disabled: isEditing, action: { edit(profile: b) }) {
                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        InfoKeyRow(L("Ad"), b.name)
                        InfoKeyRow(L("Sektör"), b.sector)
                        InfoKeyRow(L("Tanım"), b.summary)
                    }
                }
            }
        }
    }

    // MARK: AI izinleri

    /// Bu markanın verisinin gönderilebileceği sağlayıcılar (varsayılan kapalı).
    private func permissions(_ b: Brand) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            header(L("AI izinleri"))
            Text(L("Uygulama içindeki rapor özeti yalnız izin verdiğin sağlayıcıyı kullanır. Terminal bu izne bağlı değildir."))
                .captionStyle().fixedSize(horizontal: false, vertical: true)
            ForEach(AIProviderKind.allCases) { p in
                let on = Binding(get: { b.allows(p) }, set: { value in
                    var set = b.allowedProviders
                    if value { set.insert(p) } else { set.remove(p) }
                    app.perform { try app.store?.setAIProviders(brand.id, providers: set) }
                })
                HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                    CheckBox(isOn: on, label: p.shortName)
                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        Text(p.shortName).onTapGesture { on.wrappedValue.toggle() }.accessibilityHidden(true)
                        Text(p == .anthropic
                             ? L("Kendi API anahtarınla; kullanım başına ücretli.")
                             : L("Kendi ChatGPT planınla; bu markanın klasöründe yalıtılmış çalışır. Kabuk komutlarının ağ erişimi açıktır."))
                            .captionStyle().fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Kişiler

    private var contacts: some View {
        let list = (try? app.store?.contacts(brandId: brand.id)) ?? []
        let isNew = contactDraft.map { d in !list.contains { $0.id == d.id } } ?? false
        return VStack(alignment: .leading, spacing: Design.Space.s) {
            header(L("Kişiler"), action: L("Ekle")) { edit(contact: Contact(brandId: brand.id, name: "")) }
            if list.isEmpty && !isNew { EmptyStateView(message: L("Kişi eklenmemiş.")) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(list) { c in
                    if contactDraft?.id == c.id {
                        contactEditor(saved: true)
                    } else {
                        EditableRow(disabled: isEditing, action: { edit(contact: c) }) {
                            HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                                Text(c.name)
                                if !c.role.isEmpty { Text(c.role).foregroundStyle(.secondary) }
                                Spacer()
                                if !c.email.isEmpty { Text(c.email).captionStyle() }
                            }
                        }
                    }
                }
                if isNew { contactEditor(saved: false) }
            }
        }
    }

    @ViewBuilder private func contactEditor(saved: Bool) -> some View {
        if let binding = Binding($contactDraft) {
            InfoEditForm(canSave: !binding.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty,
                         cancel: cancelEdit,
                         save: { if app.perform({ try app.store?.saveContact(binding.wrappedValue) }) != nil { contactDraft = nil } },
                         delete: saved ? { deletingContact = binding.wrappedValue } : nil) {
                InputField(title: L("Ad soyad"), text: binding.name)
                InputField(title: L("Rol"), text: binding.role)
                InputField(title: L("E-posta"), text: binding.email)
                InputField(title: L("Telefon"), text: binding.phone)
                MultilineInputField(title: L("Notlar"), text: binding.notes)
                Text(L("İletişim bilgileri AI'a gönderilen bağlama eklenmez.")).captionStyle()
            }
        }
    }

    // MARK: Projeler

    private var projects: some View {
        let list = (try? app.store?.projects(brandId: brand.id)) ?? []
        let isNew = projectDraft.map { d in !list.contains { $0.id == d.id } } ?? false
        return VStack(alignment: .leading, spacing: Design.Space.s) {
            header(L("Projeler"), action: L("Ekle")) { edit(project: Project(brandId: brand.id, name: "")) }
            if list.isEmpty && !isNew { EmptyStateView(message: L("Proje eklenmemiş.")) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(list) { p in
                    if projectDraft?.id == p.id {
                        projectEditor
                    } else {
                        EditableRow(disabled: isEditing, action: { edit(project: p) }) {
                            HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                                Text(p.name)
                                Spacer()
                                Text(p.status.title).captionStyle()
                                if let d = p.dueDate { DueLabel(day: d) }
                            }
                        }
                    }
                }
                if isNew { projectEditor }
            }
        }
    }

    @ViewBuilder private var projectEditor: some View {
        if let binding = Binding($projectDraft) {
            InfoEditForm(canSave: !binding.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty,
                         cancel: cancelEdit,
                         save: { if app.perform({ try app.store?.saveProject(binding.wrappedValue) }) != nil { projectDraft = nil } }) {
                InputField(title: L("Proje adı"), text: binding.name)
                MultilineInputField(title: L("Amaç"), text: binding.goal)
                let statuses: [ProjectStatus] = [.active, .paused, .done]
                StatusMenu(current: binding.wrappedValue.status.title, options: statuses.map(\.title)) { i in
                    binding.wrappedValue.status = statuses[i]
                }
                OptionalDayPicker(title: L("Bitiş tarihi"), day: binding.dueDate)
            }
        }
    }

    // MARK: Hedef, teklif ve tarihler (salt okunur)

    /// Terminal önerisiyle (ya da eski sürümde) gelen hedef, teklif, sözleşme ve önemli tarih kayıtları. Yalnız varsa görünür.
    @ViewBuilder private var references: some View {
        let list = (try? app.store?.referenceRecords(brandId: brand.id)) ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Design.Space.s) {
                header(L("Hedef, teklif ve tarihler"))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { r in
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                            Text(r.kind.title).captionStyle().frame(width: InfoKeyRow.keyWidth, alignment: .leading)
                            Text(r.title).lineLimit(1)
                            Spacer()
                            if BrandRecord.defaultStatus(for: r.kind) != r.status { Text(r.status.title).captionStyle() }
                            if let d = r.dueDate { DueLabel(day: d) }
                        }
                        .padding(.vertical, Design.Space.xs)
                    }
                }
            }
        }
    }
}

extension ProjectStatus {
    var title: String {
        switch self {
        case .active: L("Aktif")
        case .paused: L("Duraklatıldı")
        case .done: L("Bitti")
        }
    }
}

/// Tıklayınca yerinde düzenlemeye geçen satır (profil, kişi, proje). Üzerine gelince hafif zemin alır (düzenlenebilir).
struct EditableRow<Content: View>: View {
    var disabled: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        Button(action: action) {
            content
                .padding(.vertical, Design.Space.xs).padding(.horizontal, Design.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverHighlight(enabled: !disabled))
        .padding(.horizontal, -Design.Space.xs)
        .disabled(disabled)
        .help(L("Düzenle"))
        .accessibilityHint(L("Düzenlemek için aç"))
    }
}

/// Bilgi satırı: solda ikincil anahtar, sağda değer; değer boşsa "—".
struct InfoKeyRow: View {
    static let keyWidth: CGFloat = 120
    let key: String
    let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(key).foregroundStyle(.secondary).frame(width: Self.keyWidth, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Satır içi düzenleyici: alanlar + altta *Sil…* (kayıtlıysa, solda) ve birincil *Kaydet*. Enter kaydeder; Esc (ya da sayfanın
/// alt düğmesi "Vazgeç") vazgeçer.
struct InfoEditForm<Fields: View>: View {
    var canSave: Bool
    let cancel: () -> Void
    let save: () -> Void
    var delete: (() -> Void)? = nil
    @ViewBuilder var fields: Fields

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            fields
            HStack(spacing: Design.Space.m) {
                if let delete {
                    Button(L("Sil…"), action: delete).buttonStyle(.text)
                }
                Spacer()
                Button(L("Kaydet"), action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(.vertical, Design.Space.s)
        .onSubmit { if canSave { save() } }
        .onExitCommand(perform: cancel)
        .accessibilityAction(named: L("Vazgeç"), cancel)
    }
}

/// Çok satırlı giriş alanı (2–5 satır). Ekran çiziminde `InputField` karşılığı.
struct MultilineInputField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    @Binding var text: String
    var body: some View {
        if isSnapshot {
            InputField(title: title, text: $text)
        } else {
            TextField(title, text: $text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
        }
    }
}
