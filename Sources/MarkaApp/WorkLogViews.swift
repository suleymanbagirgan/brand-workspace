import AppKit
import MarkaCore
import SwiftUI

/// İş kaydı düzenleyicisi (Akış › ayrıntı paneli › Düzenle): düz satırlar (sistem formu yok; U9) — başlık, tarih, görev,
/// yedi soru ve bağlı dosyalar. Doğrulama panelde yapılır (tek yer); doğrulanmış kaydın içeriği değişirse yeniden
/// "Doğrulanmadı" olur. Doğrulanmış kayıt buradan geri çekilir.
struct WorkLogEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var detail: WorkLogDetail
    @State private var inputs: Set<String> = []
    @State private var outputs: Set<String> = []
    @State private var confirmRetract = false

    init(detail: WorkLogDetail) {
        _detail = State(initialValue: detail)
        _inputs = State(initialValue: Set(detail.inputs.map(\.id)))
        _outputs = State(initialValue: Set(detail.outputs.map(\.id)))
    }

    var body: some View {
        let sources = (try? app.store?.sources(brandId: detail.log.brandId)) ?? []
        let tasks = (try? app.store?.tasks(brandId: detail.log.brandId)) ?? []
        VStack(alignment: .leading, spacing: 0) {
            PageScroll {
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    Text(L("İş kaydı")).font(Design.Font.title).accessibilityAddTraits(.isHeader)
                    if detail.log.status == .verified {
                        Text(L("Doğrulanmış iş kaydı. İçeriği değiştirirsen yeniden “Doğrulanmadı” olur ve tekrar doğrulaman gerekir."))
                            .captionStyle().fixedSize(horizontal: false, vertical: true)
                    }
                    row(L("Başlık")) { InputField(title: L("Başlık"), text: $detail.log.title) }
                    row(L("İşin tarihi")) { DateTimeField(date: $detail.log.occurredAt) }
                    row(L("Görev")) {
                        TextMenu(title: tasks.first { $0.id == detail.log.taskId }?.title ?? L("Yok"), help: L("Bağlı görev")) {
                            Button(L("Yok")) { detail.log.taskId = nil }
                            ForEach(tasks) { t in Button(t.title) { detail.log.taskId = t.id } }
                        }
                        .padding(.horizontal, -Design.Space.xs)
                    }
                    row(L("Ne istendi?")) { MultilineInputField(title: L("Ne istendi?"), text: $detail.log.requested) }
                    row(L("Hangi dosyalar kullanıldı?")) { SourcePicker(sources: sources.filter { $0.kind != .workOutput }, selection: $inputs) }
                    row(L("Ne yapıldı?")) { MultilineInputField(title: L("Ne yapıldı?"), text: $detail.log.performed) }
                    row(L("Hangi dosya veya bağlantı üretildi?")) { SourcePicker(sources: sources, selection: $outputs) }
                    row(L("Ne kararlaştırıldı?")) { MultilineInputField(title: L("Ne kararlaştırıldı?"), text: $detail.log.decision) }
                    row(L("Kim onayladı?")) { InputField(title: L("Kim onayladı?"), text: $detail.log.approvedBy) }
                    row(L("Müşteriye ne bildirildi?")) { MultilineInputField(title: L("Müşteriye ne bildirildi?"), text: $detail.log.clientNotified) }
                }
                .padding(Design.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: Design.Space.m) {
                if detail.log.status == .verified {
                    Button(L("Geri çek…")) { confirmRetract = true }.buttonStyle(.text)
                }
                Spacer()
                Button(L("Vazgeç")) { dismiss() }.buttonStyle(.text).keyboardShortcut(.cancelAction)
                Button(L("Kaydet"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(detail.log.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Design.Space.l).padding(.vertical, Design.Space.m)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 600)
        .confirmationDialog(L("İş kaydı geri çekilsin mi?"), isPresented: $confirmRetract) {
            Button(L("Geri çek"), role: .destructive) {
                if app.perform({ try app.store?.retractWorkLog(detail.log.id) }) != nil { dismiss() }
            }
        } message: {
            Text(L("Geri çekilen iş kaydı bundan sonraki rapor taslaklarına girmez ve yeniden doğrulanamaz. İş kaydı silinmez; içeriği ve geçmişi korunur. Bu işlem geri alınamaz."))
        }
    }

    /// Düz satır: solda soru (ek stil, sabit genişlik), sağda alan.
    private func row<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(label).captionStyle().frame(width: 180, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func save() {
        guard let store = app.store else { return }
        let ok = app.perform {
            try store.saveWorkLog(detail.log, inputSourceIds: Array(inputs), outputSourceIds: Array(outputs))
        }
        if ok != nil { dismiss() }
    }
}

/// Tarih ve saat. Ekran çiziminde (AppKit denetimi) düz metin.
struct DateTimeField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @Binding var date: Date
    var body: some View {
        if isSnapshot {
            Text(date, format: .dateTime.day().month(.wide).year().hour().minute())
        } else {
            DatePicker("", selection: $date).labelsHidden().fixedSize()
        }
    }
}

/// Dosya seçimi (uygulamanın tek kutusuyla liste; 8'den fazlaysa süzgeç).
struct SourcePicker: View {
    let sources: [Source]
    @Binding var selection: Set<String>
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            if sources.count > 8 { InputField(title: L("Filtrele"), text: $query) }
            let list = sources.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || selection.contains($0.id) }
            if list.isEmpty { EmptyStateView(message: L("Bu markada uygun dosya yok.")) }
            ForEach(list.prefix(30)) { s in
                let on = Binding(get: { selection.contains(s.id) }, set: { if $0 { selection.insert(s.id) } else { selection.remove(s.id) } })
                HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                    CheckBox(isOn: on, label: s.title)
                    Text(s.title).lineLimit(1).onTapGesture { on.wrappedValue.toggle() }.accessibilityHidden(true)
                }
            }
        }
    }
}
