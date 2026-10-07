import Foundation

// H3-05 Onay ritüeli: onay sayfasının saf mantığı. Arayüz (`ApprovalSheet`) yalnız ince kabuktur; seçim durumu, yıkıcı
// ayrımı, toplu uygulama sonucu ve geri alma kapsamı burada ve testlidir (`OnayRituelTests`).
// Kural 3: AI veri değiştirmez, öneri üretir. Bu yüzden varsayılan seçim BOŞTUR; hiçbir öneri kendiliğinden seçili gelmez.

/// Onay sayfasındaki bir satırın türü.
public enum ApprovalItemKind: Hashable, Sendable {
    /// Terminal ya da uygulama içi AI önerisi.
    case proposal(ProposalKind)
    /// Hafıza güncellemesi (bilgi sayfası sürümü).
    case knowledge
    /// Marka klasöründe olup henüz eklenmemiş dosya.
    case folderFile
}

/// Onay sayfasındaki satırın çekirdek görünümü (kimlik + tür).
public struct ApprovalItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: ApprovalItemKind
    public init(id: String, kind: ApprovalItemKind) {
        self.id = id
        self.kind = kind
    }
}

/// Tür kuralları: hangi satır ek onay ister, hangisi reddedilebilir, hangisi uygulandıktan sonra gerçekten geri alınabilir.
public enum ApprovalPolicy {
    /// Yıkıcı = markadaki **mevcut** bir kaydı değiştiren öneri (görevi bitirme, görevi değiştirme). Bunlar ayrı onay adımı
    /// ister. Yeni kayıt ekleyen öneriler yıkıcı değildir. (Silme ya da arşivleme öneren bir tür bugün yok; eklenirse buraya.)
    public static func isDestructive(_ kind: ApprovalItemKind) -> Bool {
        switch kind {
        case .proposal(.completeTask), .proposal(.updateTask): true
        default: false
        }
    }

    /// Uygulandıktan sonra `revertProposal` ile uygulama öncesi duruma dönebilen türler. Hafıza güncellemesi (sürüm geçmişi
    /// Özet'ten yönetilir) ve klasörden eklenen dosya bu bildirimden geri alınamaz; onlar için "Geri al" gösterilmez.
    public static func isUndoable(_ kind: ApprovalItemKind) -> Bool {
        switch kind {
        case .proposal(.wikiRevision), .knowledge, .folderFile: false
        case .proposal: true
        }
    }

    /// Klasördeki dosya reddedilmez; klasörde kalır.
    public static func isRejectable(_ kind: ApprovalItemKind) -> Bool { kind != .folderFile }
}

/// Seçim ve klavye imleci. İmleç (odaklı satır) seçim değildir: ↑↓ yalnız imleci taşır, Boşluk imleçteki satırı seçer/bırakır.
public struct ProposalSelection: Equatable, Sendable {
    public private(set) var items: [ApprovalItem]
    public private(set) var selected: Set<String> = []
    public private(set) var cursor: String?

    /// Varsayılan seçim boştur; imleç ilk satırdadır.
    public init(items: [ApprovalItem]) {
        self.items = items
        cursor = items.first?.id
    }

    public func isSelected(_ id: String) -> Bool { selected.contains(id) }
    public var selectedItems: [ApprovalItem] { items.filter { selected.contains($0.id) } }
    public var allSelected: Bool { !items.isEmpty && selected.count == items.count }
    /// Seçililerden ek onay isteyenler.
    public var destructiveSelected: [ApprovalItem] { selectedItems.filter { ApprovalPolicy.isDestructive($0.kind) } }
    /// Seçililerden reddedilebilenler (klasör dosyaları hariç).
    public var rejectableSelected: [ApprovalItem] { selectedItems.filter { ApprovalPolicy.isRejectable($0.kind) } }

    /// ↑ (-1) / ↓ (+1): imleç uçlarda durur, sarmaz.
    public mutating func moveCursor(by delta: Int) {
        guard !items.isEmpty else { cursor = nil; return }
        let current = cursor.flatMap { c in items.firstIndex { $0.id == c } } ?? (delta > 0 ? -1 : items.count)
        cursor = items[min(max(current + delta, 0), items.count - 1)].id
    }

    public mutating func setCursor(_ id: String) {
        if items.contains(where: { $0.id == id }) { cursor = id }
    }

    /// Boşluk: satırı seçer ya da bırakır (bilinmeyen kimlik yok sayılır).
    public mutating func toggle(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public mutating func toggleAtCursor() {
        if let cursor { toggle(cursor) }
    }

    /// ⌘A
    public mutating func selectAll() { selected = Set(items.map(\.id)) }
    public mutating func clearSelection() { selected = [] }

    /// Uygulanan/reddedilen satırlar listeden çıkar; imleç kalan ilk sonraki satıra (yoksa öncekine) geçer.
    public mutating func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var newCursor = cursor
        if let c = cursor, ids.contains(c), let i = items.firstIndex(where: { $0.id == c }) {
            newCursor = items[i...].first { !ids.contains($0.id) }?.id ?? items[..<i].last { !ids.contains($0.id) }?.id
        }
        items.removeAll { ids.contains($0.id) }
        selected.subtract(ids)
        cursor = newCursor
    }

    /// Veri tabanından yenilenen liste: seçim yalnız hâlâ var olan satırlarda korunur, yeni satır seçili gelmez.
    public mutating func replaceItems(_ newItems: [ApprovalItem]) {
        let ids = Set(newItems.map(\.id))
        items = newItems
        selected.formIntersection(ids)
        if cursor.map({ !ids.contains($0) }) ?? true { cursor = newItems.first?.id }
    }
}

/// Bir toplu kararın (onay ya da ret) sonucu. Kısmi hata diğerlerini engellemez: her satır kendi işlemindedir.
public struct ApprovalBatchResult: Equatable, Sendable {
    public struct Failure: Equatable, Sendable {
        public let item: ApprovalItem
        public let message: String
    }
    /// Başarıyla uygulananlar, uygulama sırasıyla.
    public var succeeded: [ApprovalItem] = []
    public var failures: [Failure] = []
    /// Yıkıcı olduğu hâlde ek onayı verilmediği için hiç denenmeyenler (seçili kalır, bekler).
    public var awaitingConfirmation: [ApprovalItem] = []

    public init() {}

    /// Bildirimin geri alma kapsamı.
    public var undo: ApprovalUndoScope { ApprovalUndoScope(applied: succeeded) }
}

public enum ApprovalBatch {
    /// Seçilileri sırayla uygular. `destructiveConfirmed` false ise yıkıcı satırlar denenmez (`awaitingConfirmation`).
    /// `apply` her satırı kendi işleminde uygular (ve denetim olayını kendisi bırakır); hata fırlatırsa satır `failures`'a
    /// düşer, sonraki satırlar yine denenir.
    public static func run(_ items: [ApprovalItem], destructiveConfirmed: Bool,
                           apply: (ApprovalItem) throws -> Void) -> ApprovalBatchResult {
        var result = ApprovalBatchResult()
        for item in items {
            if ApprovalPolicy.isDestructive(item.kind) && !destructiveConfirmed {
                result.awaitingConfirmation.append(item)
                continue
            }
            do {
                try apply(item)
                result.succeeded.append(item)
            } catch {
                result.failures.append(.init(item: item, message: message(error)))
            }
        }
        return result
    }

    /// Ret: yalnız reddedilebilen satırlar denenir (dosyalar klasörde kalır); ret ek onaydan sonra çağrılır.
    public static func reject(_ items: [ApprovalItem], reject: (ApprovalItem) throws -> Void) -> ApprovalBatchResult {
        var result = ApprovalBatchResult()
        for item in items where ApprovalPolicy.isRejectable(item.kind) {
            do {
                try reject(item)
                result.succeeded.append(item)
            } catch {
                result.failures.append(.init(item: item, message: message(error)))
            }
        }
        return result
    }

    static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// "N öneri uygulandı · Geri al" bildiriminin kapsamı. Düğme yalnız gerçekten geri alınabilen satır varsa görünür.
public struct ApprovalUndoScope: Equatable, Sendable {
    public let appliedCount: Int
    /// Geri alınabilenlerin kimlikleri, uygulama sırasıyla (geri alma ters sırayla yürür).
    public let undoableIds: [String]

    public init(applied: [ApprovalItem]) {
        appliedCount = applied.count
        undoableIds = applied.filter { ApprovalPolicy.isUndoable($0.kind) }.map(\.id)
    }

    public var showsUndo: Bool { !undoableIds.isEmpty }
    /// Uygulanan ama bu bildirimden geri alınamayanların sayısı (metinde dürüstçe söylenir).
    public var notUndoableCount: Int { appliedCount - undoableIds.count }

    /// Ters sırayla geri alır (sonra uygulanan önce: iş kaydı görevinden önce). Kısmi hata diğerlerini engellemez.
    public func revert(_ revert: (String) throws -> Void) -> (reverted: [String], failures: [String: String]) {
        var reverted: [String] = [], failures: [String: String] = [:]
        for id in undoableIds.reversed() {
            do {
                try revert(id)
                reverted.append(id)
            } catch {
                failures[id] = ApprovalBatch.message(error)
            }
        }
        return (reverted, failures)
    }
}
