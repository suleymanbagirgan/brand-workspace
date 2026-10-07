import Foundation
import Testing
@testable import MarkaCore

/// H1-08 (U-19): başka sayaç sessizce durmaz; durdurulan görev, marka ve süre bildirim için döner.
@Suite struct SayacBildirimiTests {
    @Test func baskaMarkadakiSayacDurunceAdiMarkasiVeSuresiDoner() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let eski = try store.saveTask(WorkTask(brandId: a.id, title: "Katalog"))
        let yeni = try store.saveTask(WorkTask(brandId: b.id, title: "Teklif", status: .waiting))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try store.startTimer(taskId: eski.id, at: t0)
        let h = try store.startTimerReportingHandoff(taskId: yeni.id, at: t0.addingTimeInterval(25 * 60))
        #expect(h.stopped == TimerHandoff.Stopped(taskTitle: "Katalog", brandId: a.id, brandName: "Deneme Yangın", seconds: 1500))
        #expect(h.movedToInProgress)          // "Bekliyor" → "Sürüyor" sessiz kalmaz
        #expect(h.taskTitle == "Teklif")
        #expect(h.isWorthTelling)
        // Tek çalışan sayaç kuralı korunur.
        #expect(try store.runningTimer()?.taskId == yeni.id)
    }

    @Test func ayniGorevdeYenidenBaslatmakBildirimUretmez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Örnek Kafe Zinciri")
        let t = try store.saveTask(WorkTask(brandId: a.id, title: "Menü", status: .inProgress))
        try store.startTimer(taskId: t.id)
        let h = try store.startTimerReportingHandoff(taskId: t.id)
        #expect(h.stopped == nil)
        #expect(!h.movedToInProgress)
        #expect(!h.isWorthTelling)
    }
}

/// H1-09 (U-08): kilit hatası tipiyle ayırt edilir; yedekten geri yükleme ekranına düşmez.
@Suite struct VeriAlaniKilitHatasiTests {
    @Test func ikinciKilitTipliHataVerirBirakilincaYenidenDenemedeAcilir() throws {
        let dir = try tempDir("kilit-tipli")
        let first = try WorkspaceLock.lock(directory: dir)
        #expect(throws: WorkspaceLockError.alreadyOpen) { try WorkspaceLock.lock(directory: dir) }
        // Metin eşlemesi değil tip: genel doğrulama hatasından ayrı.
        do { _ = try WorkspaceLock.lock(directory: dir); Issue.record("kilit alınmamalıydı") }
        catch let e as WorkspaceLockError { #expect(e == .alreadyOpen) }
        catch { Issue.record("beklenmeyen hata türü: \(type(of: error))") }
        #expect(WorkspaceLockError.alreadyOpen.errorDescription?.isEmpty == false)
        first.release()
        // "Tekrar dene": kilit bırakılınca alınır ve veri tabanı açılır.
        let again = try WorkspaceLock.lock(directory: dir)
        _ = try AppDatabase.open(at: dir)
        again.release()
    }
}
