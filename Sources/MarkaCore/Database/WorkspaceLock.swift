import Foundation

/// Bir veri alanını aynı anda tek süreç açsın diye `flock` kilidi. İkinci süreç açmaya çalışırsa kilit alınamaz (`nil`) ve kullanıcı
/// anlaşılır bir mesaj görür; iki süreç aynı SQLite dosyasında yazarsa "disk I/O error" gibi kafa karıştırıcı hatalar çıkar.
/// Kilit süreç bitince (çökse bile) işletim sistemi tarafından bırakılır.
public final class WorkspaceLock: @unchecked Sendable {
    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    /// Kilidi almayı dener. Başka süreç (ya da bu süreçte başka bir nesne) tutuyorsa `nil`.
    public static func acquire(directory: URL) -> WorkspaceLock? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("workspace.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        return WorkspaceLock(fd: fd)
    }

    /// Kilidi alır; alınamazsa tipli `WorkspaceLockError.alreadyOpen` atar (H1-09, U-08). Uygulama bu hatayı metinden değil
    /// tipinden tanır ve "Uygulama zaten açık" ekranını gösterir; yedekten geri yükleme önermez.
    public static func lock(directory: URL) throws -> WorkspaceLock {
        guard let lock = acquire(directory: directory) else { throw WorkspaceLockError.alreadyOpen }
        return lock
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN); close(fd); fd = -1
    }

    deinit { release() }
}

/// Veri alanı kilidi alınamadı: aynı veri alanı başka bir süreçte açık. Veri bozuk değildir; yedekten geri yükleme gerekmez.
public enum WorkspaceLockError: LocalizedError, Equatable {
    case alreadyOpen

    public var errorDescription: String? {
        switch self {
        case .alreadyOpen: L("Bu veri alanı başka bir Workspace AI penceresinde açık. Verin güvende; yedekten geri yüklemen gerekmez.")
        }
    }
}
