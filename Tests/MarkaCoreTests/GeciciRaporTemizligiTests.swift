import Foundation
import Testing
@testable import MarkaCore

/// U-45: açılışta 7 günden eski geçici rapor PDF'leri silinir; yeni dosya, başka ad ve alt klasör kalır.
@Suite struct GeciciRaporTemizligiTests {
    private func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marka-gecici-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func make(_ name: String, in dir: URL, ageDays: Double, now: Date) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ageDays * 86_400)], ofItemAtPath: url.path)
        return url
    }

    @Test func yediGundenEskiGeciciRaporSilinirYeniVeBaskaAdKalir() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let eski = try make("Deneme Yangın rapor v3.pdf", in: dir, ageDays: 8, now: now)
        let yeni = try make("Deneme Yangın rapor v4.pdf", in: dir, ageDays: 1, now: now)
        let baskaEski = try make("kullanici-dosyasi.pdf", in: dir, ageDays: 30, now: now)
        let baskaUzanti = try make("Deneme Yangın rapor v3.txt", in: dir, ageDays: 30, now: now)
        let sayisiz = try make("rapor vX.pdf", in: dir, ageDays: 30, now: now)
        let altKlasor = dir.appendingPathComponent("Eski rapor v1.pdf")
        try FileManager.default.createDirectory(at: altKlasor, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: altKlasor.path)

        #expect(GeciciRaporTemizligi.clean(directory: dir, now: now) == 1)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: eski.path))
        for kalan in [yeni, baskaEski, baskaUzanti, sayisiz, altKlasor] { #expect(fm.fileExists(atPath: kalan.path)) }
    }

    @Test func eksikKlasorHataVermezVeSifirDoner() {
        let yok = FileManager.default.temporaryDirectory.appendingPathComponent("marka-yok-\(UUID().uuidString)")
        #expect(GeciciRaporTemizligi.clean(directory: yok) == 0)
    }

    @Test func yediGunSinirindaYasKorunurSinirdanSonraSilinir() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let sinir = try make("A rapor v1.pdf", in: dir, ageDays: 6.9, now: now)
        let gecmis = try make("A rapor v2.pdf", in: dir, ageDays: 7.1, now: now)
        GeciciRaporTemizligi.clean(directory: dir, now: now)
        #expect(FileManager.default.fileExists(atPath: sinir.path))
        #expect(!FileManager.default.fileExists(atPath: gecmis.path))
    }
}
