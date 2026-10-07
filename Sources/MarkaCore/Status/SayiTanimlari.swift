import Foundation

/// H3-10 (sayı tutarlılığı): ekranda görünen sayıların TEK tanımı. Bant, kutucuk ve süzgeç sayıyı buradan alır; böylece
/// "bant N diyor, tıklayınca başka sayıda satır geliyor" ya da "kutucuk farklı birimleri topluyor" durumu oluşmaz.
/// Hepsi saf fonksiyondur (veritabanı okumaz); testi `SayiTutarliligiTests`.

/// Görev listesindeki bir satırın aşaması (durum dairesi ve süzgeç aynı aşamayı kullanır).
public enum TodoStage: Sendable, Hashable, CaseIterable {
    case todo, doing, waiting, done
}

extension TodoItem {
    /// Satırın aşaması. "Karar bekleniyor" kaydı her zaman bekleyendir (müşteriden yanıt beklenir).
    public var stage: TodoStage {
        switch kind {
        case .task(.done): .done
        case .task(.inProgress): .doing
        case .task(.waiting): .waiting
        case .task: .todo
        case .record(.decision, _): .waiting
        case .record(_, .done): .done
        case .record: .todo
        }
    }
}

/// Görev listesinin durum süzgeci. Az önce tamamlanıp kısa süre listede kalan satır (`done`) yalnız "Tüm durumlar"da görünür.
public enum TodoStageFilter: Sendable, Hashable, CaseIterable {
    case all, todo, doing, waiting

    public func matches(_ item: TodoItem, done: Bool) -> Bool {
        switch self {
        case .all: return true
        case .todo: return !done && item.stage == .todo
        case .doing: return !done && item.stage == .doing
        case .waiting: return !done && item.stage == .waiting
        }
    }

    /// Süzgecin sonucu (sıra korunur). `doneIds`: az önce tamamlanan satırların kimlikleri.
    public func apply(_ items: [TodoItem], doneIds: Set<String> = []) -> [TodoItem] {
        items.filter { matches($0, done: doneIds.contains($0.id)) }
    }
}

public enum CountDefinitions {
    /// "Bekleyen iş" bandının sayısı: tanımı `.waiting` süzgecinin kendisidir. Bant "N" diyorsa bandın düğmesi aramayı
    /// temizleyip bu süzgeci açar ve tam N satır görünür.
    public static func waitingBandCount(_ open: [TodoItem]) -> Int {
        TodoStageFilter.waiting.apply(open).count
    }

    /// "Bu hafta" aralığı (Bugün ve Özet aynı aralığı kullanır): takvim haftasının başı dahil, sonu hariç.
    public static func week(containing now: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 86_400)
    }

    /// "Bu hafta biten görev" tanımı: durumu Bitti ve tamamlanma anı hafta içinde. İş kaydı bağlı olup olmaması fark etmez
    /// (iş kaydı bağlı görev Akış'ta ayrı satır olarak görünse de biten görevdir).
    public static func isDoneInWeek(_ task: WorkTask, week: DateInterval) -> Bool {
        guard task.status == .done, let at = task.completedAt else { return false }
        return at >= week.start && at < week.end
    }

    public static func doneInWeekCount(_ tasks: [WorkTask], week: DateInterval) -> Int {
        tasks.filter { isDoneInWeek($0, week: week) }.count
    }

    /// Bugün'deki "Bu hafta biten görev" kutucuğu: yalnız biten görevler toplanır; iş kaydı, dosya ve not ayrı birimdir
    /// ve kutucuğa karışmaz (eski "68" gibi karışık birimli toplam yok).
    public static func weekDoneTaskTotal(_ weeks: [TodaySummary.Week]) -> Int {
        weeks.reduce(0) { $0 + $1.tasksDone }
    }

    /// Haftalık dökümün birimi; her parça kendi birimiyle yazılır.
    public enum WeekUnit: Sendable, Hashable, CaseIterable {
        case task, workLog, file, note
    }

    public struct WeekPart: Sendable, Hashable {
        public var unit: WeekUnit
        public var count: Int
    }

    /// Haftalık satırın parçaları: sıfır olanlar yazılmaz; birimler toplanmaz.
    public static func weekParts(_ w: TodaySummary.Week) -> [WeekPart] {
        [WeekPart(unit: .task, count: w.tasksDone), WeekPart(unit: .workLog, count: w.workLogs),
         WeekPart(unit: .file, count: w.files), WeekPart(unit: .note, count: w.notes)].filter { $0.count > 0 }
    }
}
