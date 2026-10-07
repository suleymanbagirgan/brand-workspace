import AppKit
import MarkaCore
import SwiftUI

// E-21 (docs/entegrasyon-plani-30.md): marka radarı. Kullanıcının elle eklediği rakip ya da sektör bağlantıları ve notları.
// İnternet taraması yoktur, bağlantının içeriği çekilmez. "Radarı özetle" asistana sorar; asistan yalnız öneri üretir.
// Radar maddesi müşteri kaynağı değildir: rapora girmez.

/// Radar kartı: madde ekleme (başlık, bağlantı, etiket, not), liste, arşivleme ve "Radarı özetle".
struct RadarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    let brand: Brand
    @State private var adding = false
    @State private var showArchived = false
    @State private var title = ""
    @State private var address = ""
    @State private var tag = ""
    @State private var note = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        let _ = app.revision
        let all = app.read(or: [], context: "radar.liste") { try $0.radarItems(brandId: brand.id, includeArchived: true) }
        let active = all.filter { !$0.isArchived }
        let shown = showArchived ? all : active
        let archivedCount = all.count - active.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Radar")).font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(L("Rakip ve sektör bağlantıları ile notların. Yalnız senin eklediklerin durur; bağlantıların içeriği çekilmez, rapora girmez."))
                        .captionStyle().fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if archivedCount > 0 {
                    Button(showArchived ? L("Arşivlenenleri gizle") : L("Arşivlenenleri göster")) { showArchived.toggle() }
                        .buttonStyle(.text)
                }
                if !active.isEmpty {
                    Button(L("Radarı özetle")) { app.askOrConnect(RadarItem.summaryPrompt, brand: brand, openSettings: openSettings) }
                        .buttonStyle(.text)
                        .help(L("Asistan radar notlarını özetler ve görev önerir; sen onaylamadan hiçbir şey değişmez."))
                }
                Button(adding ? L("Vazgeç") : L("Madde ekle")) {
                    adding.toggle()
                    if adding { DispatchQueue.main.async { titleFocused = true } } else { reset() }
                }
                .buttonStyle(.text)
            }
            if adding { form }
            if shown.isEmpty {
                EmptyStateView(title: L("Radar boş"),
                               message: L("Takip etmek istediğin rakip ya da sektör bağlantılarını ve notlarını ekle. Asistan bunları özetleyip görev önerebilir."),
                               symbol: "dot.radiowaves.left.and.right")
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { item in
                        row(item)
                        if item.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 18)
        .onChange(of: brand.id) { adding = false; showArchived = false; reset() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            InputField(title: L("Başlık (boşsa alan adı)"), text: $title, focus: $titleFocused)
            InputField(title: L("Bağlantı (isteğe bağlı), ör. ornek.com"), text: $address)
            InputField(title: L("Etiket (isteğe bağlı), ör. rakip"), text: $tag)
            InputField(title: L("Not"), text: $note)
            HStack {
                Spacer()
                Button(L("Ekle"), action: add).actionPrimary()
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Design.Space.m).frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .onSubmit(add)
        .onExitCommand { adding = false; reset() }
    }

    private func row(_ item: RadarItem) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.title).font(Design.Font.body)
                    .foregroundStyle(item.isArchived ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let u = item.url, let url = URL(string: u) {
                    Button(L("Aç")) { NSWorkspace.shared.open(url) }
                        .buttonStyle(.text)
                        .help(L("Bağlantıyı tarayıcıda açar"))
                }
                Button(item.isArchived ? L("Arşivden çıkar") : L("Arşivle")) { setArchived(item, !item.isArchived) }
                    .buttonStyle(.text)
            }
            HStack(spacing: 8) {
                if !item.tag.isEmpty { Pill(text: item.tag, tint: AnyShapeStyle(Design.accent)) }
                Text(Self.meta(item)).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1)
            }
            if !item.note.isEmpty {
                Text(item.note).font(Design.Font.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    static func meta(_ item: RadarItem) -> String {
        var parts = [item.createdAt.formatted(.dateTime.day().month(.abbreviated).year())]
        if let u = item.url, let host = URL(string: u)?.host { parts.append(host) }
        if item.isArchived { parts.append(L("Arşivlendi")) }
        return parts.joined(separator: "  ·  ")
    }

    private func add() {
        guard let store = app.store else { return }
        let ok: Void? = app.perform(title: L("Radar maddesi eklenemedi"), context: "radar.ekle") {
            _ = try store.addRadarItem(brandId: brand.id, title: title, address: address, note: note, tag: tag)
        }
        if ok != nil { adding = false; reset() }
    }

    private func setArchived(_ item: RadarItem, _ archived: Bool) {
        guard let store = app.store else { return }
        _ = app.perform(title: L("Radar maddesi güncellenemedi"), context: "radar.arsiv") {
            try store.setRadarItemArchived(item.id, brandId: brand.id, archived: archived)
        }
    }

    private func reset() { title = ""; address = ""; tag = ""; note = "" }
}
