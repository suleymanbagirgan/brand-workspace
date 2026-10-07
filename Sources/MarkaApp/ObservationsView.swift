import MarkaCore
import SwiftUI

// E-12 (docs/entegrasyon-plani-30.md): "Marka belleği" — onaylı gözlemler. Ad sözlüğü: "Hafıza" markanın uzun bilgi
// sayfalarıdır (wiki); "Marka belleği" onaylanmış tek cümlelik gözlemlerdir (kaynağa dayanır, bayatlayınca kapatılır).
// Gözlemi yapay zekâ önerir, kullanıcı onaylar (Öneriler); burada yalnız okunur ve kullanıcı "artık geçerli değil" diye
// kapatabilir. Gözlem silinmez, metni değişmez; kapatma denetim olayı bırakır (`Store.invalidateObservation`).

/// Marka belleği kartı: geçerli gözlemler (istenirse kapatılmış geçmiş de); her satırda cümle, durum, kanıt sayısı ve
/// dayandığı kaynakların bağlantısı. Kaynağa tıklayınca ayrıntı paneli açılır.
struct ObservationsView: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @Binding var selection: PanelTarget?
    @State private var showHistory = false

    var body: some View {
        let _ = app.revision
        let all = app.read(or: [], context: "gozlem.liste") { try $0.observations(brandId: brand.id, includeInvalidated: true) }
        let shown = showHistory ? all : all.filter(\.isValid)
        let closedCount = all.count - all.filter(\.isValid).count
        let titles: [String: String] = Dictionary(
            (app.read(or: [], context: "gozlem.kaynaklar") { try $0.sources(brandId: brand.id, includeArchived: true) }).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Marka belleği")).font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(L("Onayladığın tek cümlelik gözlemler ve dayandıkları kaynaklar. Uzun notlar Hafıza sayfalarında durur."))
                        .captionStyle().fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if closedCount > 0 {
                    Button(showHistory ? L("Kapatılanları gizle") : L("Kapatılanları göster")) { showHistory.toggle() }
                        .buttonStyle(.text)
                }
            }
            if shown.isEmpty {
                EmptyStateView(title: L("Henüz onaylı gözlem yok"),
                               message: L("Asistan sohbette kaynağa dayanan bir gözlem önerebilir; onayladıkların burada listelenir."),
                               actionTitle: L("Asistanı aç"), action: { app.showAssistant = true },
                               symbol: "brain")
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { o in
                        row(o, titles: titles)
                        if o.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 18)
        .onChange(of: brand.id) { showHistory = false }
    }

    private func row(_ o: BrandObservation, titles: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(o.statement).font(Design.Font.body)
                    .foregroundStyle(o.isValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if o.isValid {
                    Button(L("Artık geçerli değil")) { invalidate(o) }
                        .buttonStyle(.text)
                        .help(L("Gözlemi kapatır; silinmez, geçmişte kalır."))
                }
            }
            HStack(spacing: 8) {
                Pill(text: Self.statusTitle(o), tint: o.isValid ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
                Text(Self.meta(o)).font(Design.Font.small).foregroundStyle(.secondary).monospacedDigit()
            }
            FlowLayout(spacing: 8) {
                ForEach(o.evidenceSourceIds, id: \.self) { sid in
                    Button {
                        selection = selection == .source(sid) ? nil : .source(sid)
                    } label: {
                        Label(titles[sid] ?? L("Kaynak bulunamadı"), systemImage: "doc.text").labelStyle(.titleAndIcon).lineLimit(1)
                    }
                    .buttonStyle(.plain).font(Design.Font.callout).foregroundStyle(Design.accent)
                    .disabled(titles[sid] == nil)
                    .accessibilityHint(L("Kaynağı ayrıntı panelinde açar"))
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private func invalidate(_ o: BrandObservation) {
        guard let store = app.store else { return }
        _ = app.perform(title: L("Gözlem kapatılamadı"), context: "gozlem.kapat") {
            try store.invalidateObservation(o.id, brandId: brand.id)
        }
    }

    static func statusTitle(_ o: BrandObservation) -> String {
        if o.isValid { return L("Geçerli") }
        return o.supersededBy != nil ? L("Yerine geçildi") : L("Artık geçerli değil")
    }

    static func meta(_ o: BrandObservation) -> String {
        var parts = [o.validFrom.formatted(.dateTime.day().month(.abbreviated).year())]
        if let end = o.invalidatedAt { parts.append(LF("Kapanış: %@", end.formatted(.dateTime.day().month(.abbreviated).year()))) }
        parts.append(LF("Kanıt sayısı: %d", o.evidenceCount))
        return parts.joined(separator: "  ·  ")
    }
}
