import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-14 (docs/entegrasyon-plani-30.md): yetenek klasörü içe aktarma ekranı. Önizleme verisi E-02/E-07 testleriyle kanıtlı;
/// burada "Vazgeç" yolunun hiçbir şey yazmadığı ve arayüz kaynağının kurallara uyduğu denetlenir. Adlar uydurmadır.
@Suite struct YetenekIceAktarmaEkraniTests {
    static let uygulama = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/MarkaApp")

    func paket() throws -> URL {
        let dir = try tempDir("yetenek-ekran").appendingPathComponent("vitrin-denetimi")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("references"), withIntermediateDirectories: true)
        try Data("---\nname: vitrin-denetimi\ndescription: Örnek Kafe Zinciri vitrin metnini denetler.\n---\nAdım 1: menüyü oku.".utf8)
            .write(to: dir.appendingPathComponent("SKILL.md"))
        try Data("Kontrol: fiyat görünür mü?".utf8).write(to: dir.appendingPathComponent("references/kontrol.md"))
        return dir
    }

    func olaySayisi(_ store: Store) throws -> Int {
        try store.database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent") ?? 0 }
    }

    /// Ekranın "Vazgeç" yolu: klasör okunur ve önizleme kurulur, `importSkillBundle` çağrılmaz. Kütüphane sayısı ve denetim
    /// kaydı değişmez; aynı önizleme ancak onayla (Ekle) kaydedilir.
    @Test func vazgecilenIceAktarmadaKutuphaneSayisiDegismez() throws {
        let store = try makeStore()
        _ = try store.installSkillPack(SkillPacks.method)
        let onceSayi = try store.skills().count
        let onceOlay = try olaySayisi(store)

        let onizleme = SkillBundleReader.preview(try SkillBundleReader.read(folder: try paket()), existing: try store.skills())
        #expect(onizleme.action == .add && !onizleme.exceedsLibraryLimit && onizleme.referencePaths == ["references/kontrol.md"])
        // Vazgeç: hiçbir yazma yok.
        #expect(try store.skills().count == onceSayi)
        #expect(try olaySayisi(store) == onceOlay)
        #expect(try store.skills().contains { $0.name == "vitrin-denetimi" } == false)

        // Karşı kanıt: onayla bir kayıt eklenir, köken adlı klasördür (adsız `folder:` değil).
        let eklenen = try store.importSkillBundle(onizleme, folderName: "vitrin-denetimi")
        #expect(try store.skills().count == onceSayi + 1)
        #expect(eklenen.originKind == .folder("vitrin-denetimi"))
    }

    /// Arayüz kaynağı: klasör yalnız `NSOpenPanel` ile seçilir, kayıt tek yerden ("Ekle") yapılır, yalnız klasör adı geçer
    /// (mutlak yol saklanmaz); dosyadan içe aktarmada da dosya adı geçirilir (köken adsız `file:` kalmaz).
    @Test func iceAktarmaEkraniKaydiYalnizOnaylaYaparVeYalnizAdGecirir() throws {
        let sayfa = try String(contentsOf: Self.uygulama.appendingPathComponent("SkillImportSheet.swift"), encoding: .utf8)
        let sirket = try String(contentsOf: Self.uygulama.appendingPathComponent("CompanyView.swift"), encoding: .utf8)
        #expect(sayfa.contains("NSOpenPanel()") && sayfa.contains("canChooseDirectories = true"))
        #expect(sayfa.components(separatedBy: "importSkillBundle(").count - 1 == 1)
        #expect(sayfa.contains("folderName: url.lastPathComponent"))
        #expect(!sayfa.contains("UserDefaults") && !sayfa.contains("bookmarkData"))
        #expect(sirket.contains("importSkill(markdown: text, fileName: url.lastPathComponent)"))
        #expect(!sirket.contains("importSkillBundle("), "kayıt yalnız onay sayfasından")
    }
}
