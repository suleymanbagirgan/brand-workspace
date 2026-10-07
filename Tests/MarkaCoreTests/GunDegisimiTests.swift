import Foundation
import Testing
@testable import MarkaCore

/// H1-02 (U-06, U-25): otomatik yedek kararı saf yardımcıda; saat ve saat dilimi enjekte edilir.
@Suite struct GunDegisimiTests {
    func takvim(_ kimlik: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: kimlik)!
        return c
    }

    func an(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func gunDegisinceYedekKarariBirKezEvetDer() {
        let c = takvim("Europe/Istanbul")
        let son = an("2026-10-05T10:00:00+03:00")
        let yarin = an("2026-10-06T00:00:05+03:00")
        #expect(BackupSchedule.shouldBackup(lastBackupAt: son, now: yarin, calendar: c))
        // Yedek alındı: son yedek artık yarın; aynı gün ikinci çağrı hayır.
        #expect(!BackupSchedule.shouldBackup(lastBackupAt: yarin, now: yarin.addingTimeInterval(3600), calendar: c))
    }

    @Test func ayniGunIkinciCagriHayirDer() {
        let c = takvim("Europe/Istanbul")
        #expect(!BackupSchedule.shouldBackup(lastBackupAt: an("2026-10-05T00:00:01+03:00"),
                                             now: an("2026-10-05T23:59:59+03:00"), calendar: c))
    }

    @Test func hicYedekYoksaEvetDer() {
        #expect(BackupSchedule.shouldBackup(lastBackupAt: nil, now: an("2026-10-05T12:00:00+03:00"), calendar: takvim("UTC")))
    }

    @Test func saatDilimiDegisinceGeceYarisiSiniriKayar() {
        // 21:30 UTC = İstanbul'da ertesi gün 00:30.
        let son = an("2026-10-05T20:00:00Z")   // İstanbul 23:00 (5 Ekim), UTC 20:00 (5 Ekim)
        let simdi = an("2026-10-05T21:30:00Z") // İstanbul 00:30 (6 Ekim), UTC 21:30 (5 Ekim)
        #expect(BackupSchedule.shouldBackup(lastBackupAt: son, now: simdi, calendar: takvim("Europe/Istanbul")))
        #expect(!BackupSchedule.shouldBackup(lastBackupAt: son, now: simdi, calendar: takvim("UTC")))
        // Aynı iki an, takvim UTC'den İstanbul'a geçince karar "hayır"dan "evet"e döner.
    }

    @Test func ileriTarihliSonYedekteSaatGeriAlindiysaBirKezEvetDer() {
        let c = takvim("UTC")
        let simdi = an("2026-10-05T12:00:00Z")
        let ileri = an("2026-10-09T12:00:00Z")
        #expect(BackupSchedule.shouldBackup(lastBackupAt: ileri, now: simdi, calendar: c))
        #expect(!BackupSchedule.shouldBackup(lastBackupAt: simdi, now: simdi.addingTimeInterval(60), calendar: c))
        // Aynı gün içinde ileri tarihli kayıt (saat birkaç saat geri alındı) gereksiz yedek üretmez.
        #expect(!BackupSchedule.shouldBackup(lastBackupAt: an("2026-10-05T18:00:00Z"), now: simdi, calendar: c))
    }
}
