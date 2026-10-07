import Foundation

/// Otomatik yedek kararı: saf ve saati/takvimi/saat dilimini dışarıdan alır (test edilebilir).
/// Günde en çok bir kez "evet" der; "gün" verilen takvimin (ve saat diliminin) gece yarısı sınırıdır.
public enum BackupSchedule {
    /// - Parameters:
    ///   - lastBackupAt: son otomatik yedeğin zamanı; yoksa `nil`.
    ///   - now: şimdiki zaman (enjekte edilir).
    ///   - calendar: gün sınırını belirleyen takvim (saat dilimi dahil).
    /// - Returns: `lastBackupAt` ile `now` aynı takvim gününde değilse `true`.
    ///   Son yedek `now`'dan ilerideyse (saat geri alındı) gün farklı olduğundan `true`; yedek alınınca son yedek `now` olur, aynı gün ikinci çağrı `false` döner.
    public static func shouldBackup(lastBackupAt: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastBackupAt else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}
