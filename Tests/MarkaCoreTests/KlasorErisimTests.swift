import Foundation
import Testing
@testable import MarkaCore

/// Sandbox geçişi S1–S3: `FolderAccess` arayüzü, `PathCanonical` yardımcısı ve derleme anahtarının kapalı hâli.
/// Bu testler MAS dışı (normal) kipte çalışır; MAS kipinde test hedefi derlenmek zorunda değildir (docs/sandbox-gecis-analizi.md).
@Suite struct KlasorErisimTests {

    /// Sahte erişim: yalnız izin verilen (kanonik) yolların altına erişir; kapsam başlat/bitir sayılır.
    final class SahteKlasorErisimi: FolderAccess, @unchecked Sendable {
        private let lock = NSLock()
        let rootURL: URL
        private var izinli: [String]
        var baslatilabilir = true
        private var _baslat = 0, _bitir = 0
        var baslat: Int { lock.lock(); defer { lock.unlock() }; return _baslat }
        var bitir: Int { lock.lock(); defer { lock.unlock() }; return _bitir }

        init(root: URL, izinli: [URL]) {
            self.rootURL = root
            self.izinli = izinli.map { PathCanonical.canonical($0.path) }
        }

        func kapsar(_ path: String) -> Bool {
            let c = PathCanonical.canonical(path)
            return izinli.contains { c == $0 || c.hasPrefix($0 + "/") }
        }

        func root() throws -> URL {
            guard kapsar(rootURL.path) else { throw FolderAccessError.izinGerekli(ipucuYol: rootURL.path) }
            return rootURL
        }

        func folder(savedPath: String) throws -> URL {
            guard kapsar(savedPath) else { throw FolderAccessError.izinGerekli(ipucuYol: savedPath) }
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }

        func begin(_ url: URL) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard baslatilabilir, kapsar(url.path) else { return false }
            _baslat += 1
            return true
        }

        func end(_ url: URL) { lock.lock(); _bitir += 1; lock.unlock() }
    }

    struct Ortam {
        let base: URL
        let root: URL
        let store: Store
        let a: Brand
        let b: Brand
    }

    func ortam() throws -> Ortam {
        let base = try tempDir("erisim")
        let store = Store(database: try AppDatabase.open(at: base.appendingPathComponent("veri", isDirectory: true)))
        let a = try store.createBrand(name: "Kuzey Lojistik")
        let b = try store.createBrand(name: "Deneme Yangın")
        return Ortam(base: base, root: base.appendingPathComponent("Marka Çalışma Alanı", isDirectory: true), store: store, a: a, b: b)
    }

    func izinGerekliMi(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch let e as FolderAccessError {
            if case .izinGerekli = e { return true }
            return false
        } catch { return false }
    }

    // MARK: İzin yoksa izinGerekli

    @Test func izinYokkenKokIsteyenIslemlerIzinGerekliFirlatirVeKlasorOlusturmaz() throws {
        let o = try ortam()
        let erisim = SahteKlasorErisimi(root: o.root, izinli: [])
        let folders = BrandFolders(root: o.root, store: o.store, access: erisim)
        #expect(izinGerekliMi { _ = try folders.folder(for: .allBrands) })
        #expect(izinGerekliMi { _ = try folders.folder(for: .brand(o.a.id)) })
        #expect(!FileManager.default.fileExists(atPath: o.root.path))
        // Yeni marka klasörü ayarı yazılmadı (izin gelince yeniden denenir).
        #expect(try o.store.setting("folder.\(o.a.id)") == nil)
        #expect(erisim.baslat == 0 && erisim.bitir == 0)
    }

    @Test func kayitliKlasorIzinsizseYokDegilIzinGerekliDoner() throws {
        let o = try ortam()
        let eski = o.base.appendingPathComponent("Eski Konum/Kuzey Lojistik", isDirectory: true)
        try FileManager.default.createDirectory(at: eski, withIntermediateDirectories: true)
        try o.store.setSetting("folder.\(o.a.id)", eski.path)
        let folders = BrandFolders(root: o.root, store: o.store, access: SahteKlasorErisimi(root: o.root, izinli: [o.root]))
        // Klasör diskte var ama izin yok: `existingFolder` sessizce nil dönmez (a3: "yok" ile "izin yok" ayrılır).
        #expect(izinGerekliMi { _ = try folders.existingFolder(brandId: o.a.id) })
        #expect(izinGerekliMi { _ = try folders.folder(for: .brand(o.a.id)) })
        #expect(!FileManager.default.fileExists(atPath: eski.appendingPathComponent("ciktilar").path))
        // Öneri taraması izinsiz klasörde hiçbir şey yapmaz.
        #expect(SuggestionInbox(folders: folders).scan(brandId: o.a.id).created.isEmpty)
    }

    @Test func baslatilamayanKapsamIzinGerekliVerirVeBitirilmez() throws {
        let o = try ortam()
        let erisim = SahteKlasorErisimi(root: o.root, izinli: [o.root])
        erisim.baslatilabilir = false
        let folders = BrandFolders(root: o.root, store: o.store, access: erisim)
        #expect(izinGerekliMi { _ = try folders.folder(for: .brand(o.a.id)) })
        #expect(erisim.baslat == 0 && erisim.bitir == 0)
    }

    // MARK: Kapsam eşleşmesi

    @Test func kapsamBaslatBitirSayisiTumKlasorIslemlerindeEsit() throws {
        let o = try ortam()
        let erisim = SahteKlasorErisimi(root: o.root, izinli: [o.root])
        let folders = BrandFolders(root: o.root, store: o.store, access: erisim)
        try o.store.setAIProviders(o.a.id, providers: [.codex])
        let dir = try folders.folder(for: .brand(o.a.id))
        _ = try folders.folder(for: .brand(o.a.id))
        _ = try folders.folder(for: .allBrands)
        _ = try folders.existingFolder(brandId: o.a.id)
        _ = try #require(try folders.writeContextFile(brandId: o.a.id))
        try "çıktı".write(to: dir.appendingPathComponent("ciktilar/rapor.md"), atomically: true, encoding: .utf8)
        #expect(try folders.importableFiles(brandId: o.a.id).map(\.lastPathComponent) == ["rapor.md"])
        try #"{"surum": 1, "gorevler": [{"baslik": "Web sitesi"}]}"#
            .write(to: dir.appendingPathComponent("oneriler/gorev.json"), atomically: true, encoding: .utf8)
        #expect(SuggestionInbox(folders: folders).scan(brandId: o.a.id).created.count == 1)
        #expect(erisim.baslat >= 7)
        #expect(erisim.baslat == erisim.bitir)
    }

    @Test func hataVerenIslemdeDeKapsamKapanir() throws {
        let o = try ortam()
        let erisim = SahteKlasorErisimi(root: o.root, izinli: [o.root])
        let folders = BrandFolders(root: o.root, store: o.store, access: erisim)
        struct Bilerek: Error {}
        #expect(throws: Bilerek.self) { try folders.withAccess(o.root) { _ in throw Bilerek() } }
        // Kök bir dosya: klasör oluşturma hata verir; kapsam yine kapanır.
        try FileManager.default.createDirectory(at: o.base, withIntermediateDirectories: true)
        try "dosya".write(to: o.root, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { _ = try folders.folder(for: .brand(o.a.id)) }
        #expect(erisim.baslat == 2)
        #expect(erisim.baslat == erisim.bitir)
    }

    // MARK: Varsayılan uygulama = bugünkü davranış

    @Test func varsayilanUygulamaEskiDavranislaAyniYollariUretir() throws {
        let o = try ortam()
        let folders = BrandFolders(root: o.root, store: o.store)
        #expect(folders.access is AbsolutePathFolderAccess)
        // Eski davranış: kök/<güvenli ad>, çakışmada "… 2", tüm markalar "_Tüm Markalar", ayar mutlak yol.
        try FileManager.default.createDirectory(at: o.root.appendingPathComponent("Deneme Yangın"), withIntermediateDirectories: true)
        let a = try folders.folder(for: .brand(o.a.id))
        let b = try folders.folder(for: .brand(o.b.id))
        #expect(a.path == o.root.appendingPathComponent("Kuzey Lojistik").path)
        #expect(b.path == o.root.appendingPathComponent("Deneme Yangın 2").path)
        #expect(try o.store.setting("folder.\(o.b.id)") == b.path)
        #expect(FileManager.default.fileExists(atPath: b.appendingPathComponent("ciktilar").path))
        #expect(try folders.folder(for: .allBrands).path == o.root.appendingPathComponent(BrandFolders.allBrandsFolderName).path)
        // Kayıtlı yol olduğu gibi kullanılır (kanonikleştirilmez); silinmişse existingFolder nil (izin hatası değil).
        let disari = o.base.appendingPathComponent("Taşınmış", isDirectory: true)
        try o.store.setSetting("folder.\(o.a.id)", disari.path)
        #expect(try folders.existingFolder(brandId: o.a.id) == nil)
        #expect(try folders.folder(for: .brand(o.a.id)).path == disari.path)
        #expect(try folders.existingFolder(brandId: o.a.id)?.path == disari.path)
        // Varsayılan uygulama yolu değiştirmez.
        let v = AbsolutePathFolderAccess(root: URL(fileURLWithPath: "/tmp/kok", isDirectory: true))
        #expect(try v.root().path == "/tmp/kok")
        #expect(try v.folder(savedPath: "/tmp/a/../b").path == URL(fileURLWithPath: "/tmp/a/../b", isDirectory: true).path)
        #expect(v.begin(URL(fileURLWithPath: "/olmayan")))
    }

    // MARK: Marka yalıtımı

    @Test func birMarkaninIzniBaskaMarkaninKlasorunuAcmaz() throws {
        let o = try ortam()
        let dirA = o.base.appendingPathComponent("Klasorler/Kuzey", isDirectory: true)
        let dirB = o.base.appendingPathComponent("Klasorler/Kuzey 2", isDirectory: true)   // ön eki aynı kardeş klasör
        for d in [dirA, dirB] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try o.store.setSetting("folder.\(o.a.id)", dirA.path)
        try o.store.setSetting("folder.\(o.b.id)", dirB.path)
        // Yalnız A'nın klasörüne izin var (kök yok).
        let erisim = SahteKlasorErisimi(root: o.root, izinli: [dirA])
        let folders = BrandFolders(root: o.root, store: o.store, access: erisim)
        #expect(try folders.folder(for: .brand(o.a.id)).path == dirA.path)
        #expect(izinGerekliMi { _ = try folders.folder(for: .brand(o.b.id)) })
        #expect(izinGerekliMi { _ = try folders.existingFolder(brandId: o.b.id) })
        // `..` ile A'nın izninden B'ye geçilemez; kapsam da açılmaz.
        let kacis = dirA.path + "/../Kuzey 2"
        try o.store.setSetting("folder.\(o.b.id)", kacis)
        #expect(izinGerekliMi { _ = try folders.folder(for: .brand(o.b.id)) })
        #expect(!erisim.begin(URL(fileURLWithPath: kacis)))
        #expect(!FileManager.default.fileExists(atPath: dirB.appendingPathComponent("ciktilar").path))
        #expect(erisim.baslat == erisim.bitir)
    }

    // MARK: PathCanonical = eski SandboxProfile.canonical

    /// Taşımadan önceki `SandboxProfile.canonical` gövdesinin bire bir kopyası (karşılaştırma için).
    static func eskiCanonical(_ path: String) -> String {
        func rp(_ p: String) -> String? {
            guard let r = realpath(p, nil) else { return nil }
            defer { free(r) }
            return String(cString: r)
        }
        let standardized = (path as NSString).standardizingPath
        var head = standardized
        var tail: [String] = []
        while head.count > 1 {
            if let resolved = rp(head) {
                return tail.reversed().reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return standardized
    }

    @Test func pathCanonicalSembolikBagiCozerVeEskisiyleAyni() throws {
        let base = try tempDir("kanonik")
        let hedef = base.appendingPathComponent("hedef", isDirectory: true)
        try FileManager.default.createDirectory(at: hedef.appendingPathComponent("alt"), withIntermediateDirectories: true)
        let bag = base.appendingPathComponent("bag")
        try FileManager.default.createSymbolicLink(at: bag, withDestinationURL: hedef)
        let gercek = Self.eskiCanonical(hedef.path)
        #expect(PathCanonical.canonical(bag.path) == gercek)
        #expect(PathCanonical.canonical(bag.path + "/alt") == gercek + "/alt")
        #expect(PathCanonical.canonical(bag.path + "/yok/daha") == gercek + "/yok/daha")
        #expect(PathCanonical.canonical("/tmp") == "/private/tmp")
        for p in [bag.path, bag.path + "/alt", bag.path + "/yok/daha", "/tmp", "/var/folders", hedef.path + "/"] {
            #expect(PathCanonical.canonical(p) == Self.eskiCanonical(p))
            #expect(PathCanonical.canonical(p) == SandboxProfile.canonical(p))
        }
    }

    @Test func pathCanonicalNoktaNoktaVeOlmayanYoldaEskisiyleAyni() throws {
        let base = try tempDir("kanonik-nokta")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        let kok = Self.eskiCanonical(base.path)
        #expect(PathCanonical.canonical(base.path + "/a/b/../../c") == kok + "/c")
        #expect(PathCanonical.canonical(base.path + "/a/./b/..") == kok + "/a")
        #expect(PathCanonical.canonical("/tmp/marka-olmayan-\(UUID().uuidString)/../x").hasPrefix("/private/tmp/"))
        for p in [base.path + "/a/b/../../c", base.path + "/a/./b/..", base.path + "/olmayan/../a", "/", "/olmayan-kok-\(UUID().uuidString)/x",
                  "~/../..", "göreli/yol", ""] {
            #expect(PathCanonical.canonical(p) == Self.eskiCanonical(p), "\(p)")
        }
    }

    // MARK: Anahtar kapalıyken bugünkü davranış

    @Test func masAnahtariKapaliykenTumSaglayicilarSecilebilir() {
        #expect(BuildFlavor.isMAS == false)
        #expect(AIProviderKind.selectable == AIProviderKind.allCases)
        #expect(AIProviderKind.codex.isSelectable)
        #expect(SummaryProviderChoice.choose(allowsAnthropic: false, hasAnthropicKey: false, allowsCodex: true) == .codex)
    }
}
