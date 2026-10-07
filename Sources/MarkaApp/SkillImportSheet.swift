import AppKit
import MarkaCore
import SwiftUI

/// E-14: SKILL.md klasör paketini kaydetmeden önce gösteren onay sayfası. Kullanıcı "Ekle" (ya da "Güncelle") demeden
/// hiçbir yetenek kütüphaneye girmez; "Vazgeç" hiçbir şey yazmaz. Önizleme E-02 (`SkillBundleReader`), kayıt E-07
/// (`Store.importSkillBundle`, önizleme bayatsa reddeder) yolundan gider.
///
/// Klasör erişimi yalnız `NSOpenPanel` seçimiyle olur (MAS'ta da). Mutlak yol saklanmaz: sayfada ve kökende yalnız klasörün adı
/// (son yol bileşeni) tutulur.
struct SkillImportDraft: Identifiable {
    let id = UUID()
    var preview: SkillBundlePreview
    /// Seçilen klasörün yalnız adı (köken `folder:<ad>`).
    var folderName: String
    /// Güncellemede ezilecek mevcut kayıt (başlık ve yerel değişiklik uyarısı için).
    var existing: Skill?

    /// Klasör seçtirir ve paketi okur. Vazgeçilirse ya da okunamazsa `nil` (hata kullanıcıya gösterilir). Hiçbir şey yazmaz.
    @MainActor
    static func choose(app: AppModel) -> SkillImportDraft? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = L("SKILL.md taşıyan yetenek klasörünü seç")
        panel.prompt = L("İncele")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return load(folder: url, app: app)
    }

    /// Klasörü okur ve önizlemeyi kurar. Yol yalnız okuma süresince kullanılır; saklanmaz.
    @MainActor
    static func load(folder url: URL, app: AppModel) -> SkillImportDraft? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bundle = app.perform(title: L("Paket okunamadı"), context: "yetenek.klasor", { try SkillBundleReader.read(folder: url) })
        else { return nil }
        let library = app.read(or: []) { try $0.skills() }
        let preview = SkillBundleReader.preview(bundle, existing: library)
        return SkillImportDraft(preview: preview, folderName: url.lastPathComponent,
                                existing: library.first { $0.id == preview.existingId })
    }
}

struct SkillImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isSnapshot) private var isSnapshot
    let draft: SkillImportDraft
    /// Kayıttan sonra çağrılır (üst görünüm bildirim gösterir).
    var onAdded: (Skill) -> Void = { _ in }

    private var preview: SkillBundlePreview { draft.preview }
    private var isUpdate: Bool { preview.action == .update }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Design.Space.m) {
                header
                summary
                if preview.exceedsLibraryLimit {
                    notice(symbol: "exclamationmark.triangle",
                           text: LF("Birleşik metin kütüphane sınırını aşıyor; bu paket eklenemez. Karakter sınırı: %d", SkillBundleReader.libraryBodyLimit),
                           tint: AnyShapeStyle(Design.danger))
                }
                if isUpdate, draft.existing?.hasLocalChanges == true {
                    notice(symbol: "pencil.and.outline",
                           text: L("Mevcut yetenekte yerel değişiklik var; güncelleme bu değişikliklerin üzerine yazar."),
                           tint: AnyShapeStyle(Design.accent))
                }
                fullText
                Text(L("Kaydetmeden önce tam metni oku. Sen eklemeden kütüphaneye hiçbir şey girmez. Yetenek yetki vermez: yapay zekâ çalışan yeteneğiyle de yalnızca öneri üretir."))
                    .captionStyle().fixedSize(horizontal: false, vertical: true)
            }
            .padding(Design.Space.l)
            Divider()
            HStack {
                Spacer()
                Button(L("Vazgeç")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isUpdate ? L("Güncelle") : L("Ekle")) { add() }
                    .keyboardShortcut(.defaultAction).actionPrimary()
                    .disabled(preview.exceedsLibraryLimit)
                    .help(preview.exceedsLibraryLimit ? L("Paket kütüphane sınırını aştığı için eklenemez.") : "")
            }
            .padding(Design.Space.l)
        }
        .frame(width: 640, height: isSnapshot ? nil : 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(L("Yetenek paketini incele")).font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
            HStack(spacing: Design.Space.s) {
                Pill(text: isUpdate ? L("Güncelleme") : L("Yeni yetenek"), tint: AnyShapeStyle(Design.accent))
                Label(LF("Kaynak klasör: %@", draft.folderName), systemImage: "folder")
                    .font(Design.Font.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            row(L("Ad"), preview.title.isEmpty ? preview.name : "\(preview.title) (\(preview.name))")
            row(L("Tanım"), preview.description)
            if isUpdate, let old = draft.existing { row(L("Ezilecek kayıt"), old.displayTitle) }
            row(L("Boyut"), ByteCountFormatter.string(fromByteCount: Int64(preview.totalBytes), countStyle: .file))
            row(L("Referans dosyaları"), preview.referencePaths.isEmpty ? L("Yok") : preview.referencePaths.joined(separator: "\n"))
            if !preview.skipped.isEmpty {
                row(L("Okunmadan atlananlar"), preview.skipped.joined(separator: "\n"))
            }
            row(L("İçerik özeti"), String(preview.digest.prefix(16)))
        }
        .padding(Design.Space.m)
        .card(radius: Design.Radius.medium)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(title).font(Design.Font.callout).foregroundStyle(.secondary).frame(width: 148, alignment: .leading)
            Text(value).font(Design.Font.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func notice(symbol: String, text: String, tint: AnyShapeStyle) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).font(Design.Icon.medium) }
            .font(Design.Font.callout).foregroundStyle(tint)
    }

    /// Kütüphaneye yazılacak birleşik gövdenin tamamı (referanslar çerçeveli).
    private var fullText: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(LF("Tam metin · karakter: %d", preview.combinedBody.count)).font(Design.Font.callout.weight(.semibold))
            Group {
                if isSnapshot {
                    // Ekran çiziminde kaydırma kapsayıcısı boş çizilir; metnin başı gösterilir.
                    bodyText(String(preview.combinedBody.prefix(1200)))
                } else {
                    ScrollView { bodyText(preview.combinedBody) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isSnapshot ? 240 : .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(Design.panel))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).stroke(Design.line))
            .accessibilityLabel(L("Paketin tam metni"))
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text).font(Design.Font.callout.monospaced()).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading).padding(Design.Space.s)
    }

    private func add() {
        if let skill = app.perform(title: L("İçe aktarılamadı"), context: "yetenek.klasor.ekle", {
            try app.store?.importSkillBundle(preview, folderName: draft.folderName)
        }) ?? nil {
            app.reloadViews()
            onAdded(skill)
            dismiss()
        }
    }
}
