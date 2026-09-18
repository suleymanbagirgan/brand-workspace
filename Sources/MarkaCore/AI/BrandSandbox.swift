import Foundation
import GRDB

/// macOS seatbelt (`sandbox-exec`) profili: marka okuma/yazma yalıtımı.
///
/// Ölçülen davranış (2026-09-18, macOS 26.3):
/// - Aynı işlem için **sonraki kural öncekini ezer**: kökü yasaklayıp oturum markasının klasörünü sonra açmak çalışır.
/// - Yol eşleşmesi sembolik bağı çözmez (`/tmp` kuralı `/private/tmp` erişimini tutmaz) → yollar `realpath` ile yazılır.
/// - Yol eşleşmesi Unicode biçiminden (NFC/NFD) bağımsızdır; "Çalışma" iki biçimde de tutar.
/// - Profil alt süreçlere (zsh -c, cat, ls) miras geçer; iç içe `sandbox-exec` ise çalışmaz (`sandbox_apply: Operation not permitted`).
/// - `realpath` yol üzerindeki her üst klasörün meta verisini okur; yasaklı kökün altında açılan klasörün
///   üst klasörlerine yalnızca meta veri (`file-read-metadata`) izni verilir, içerik listesi (`file-read-data`) kapalı kalır.
public struct SandboxProfile: Sendable, Equatable {
    /// Okuması ve yazması tümüyle yasak kökler (alt yollarıyla).
    public var denied: [String]
    /// Yasaklı kökün altında yeniden açılan klasörler (okuma + yazma).
    public var reopened: [String]
    /// Yasaklı kökün altında yeniden açılan tekil dosyalar (okuma + yazma).
    public var reopenedFiles: [String]
    /// Yasaklı kökün altında yalnızca okunabilen klasörler (ör. Codex'in kurulu olduğu klasör).
    public var readOnly: [String]
    /// `nil`: yazma kısıtı yok. Aksi hâlde yalnızca bu klasörlere (ve `/dev`) yazılabilir.
    public var writable: [String]?
    /// Yazma kısıtı varken yazılabilen tekil dosyalar.
    public var writableFiles: [String]
    /// Yazma kısıtı yokken (terminal) yine de yazması kapatılan klasörler (kabuk/araç yapılandırması, köprü dosyaları).
    public var writeProtected: [String]
    /// Yazması kapatılan tekil dosyalar (ör. `~/.zshenv`, `~/.gitconfig`).
    public var writeProtectedFiles: [String]
    /// Açıksa: LaunchServices/AppleEvents/Kısayollar ile profil dışı süreç başlatma ve yerel Unix soketi köprüsü kapatılır.
    /// Kullanıcının ssh-agent soketi (`$SSH_AUTH_SOCK`, launchd `Listeners`) açık kalır; `git push` (ssh) bozulmaz.
    public var hardenLaunch: Bool

    public init(denied: [String], reopened: [String] = [], reopenedFiles: [String] = [], readOnly: [String] = [],
                writable: [String]? = nil, writableFiles: [String] = [], writeProtected: [String] = [],
                writeProtectedFiles: [String] = [], hardenLaunch: Bool = false) {
        self.denied = denied; self.reopened = reopened; self.reopenedFiles = reopenedFiles
        self.readOnly = readOnly; self.writable = writable; self.writableFiles = writableFiles
        self.writeProtected = writeProtected; self.writeProtectedFiles = writeProtectedFiles
        self.hardenLaunch = hardenLaunch
    }

    /// Seatbelt dizgesi: `\` ve `"` kaçışlanır. Denetim karakterli yollar `validate()` ile önceden reddedilir.
    public static func quote(_ path: String) -> String {
        return "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Denetim karakteri (satır sonu vb.) içeren ya da mutlak olmayan yol profil sözdizimini bozabilir; yalıtım kurulmaz.
    public func validate() throws {
        for path in denied + reopened + reopenedFiles + readOnly + (writable ?? []) + writableFiles + writeProtected + writeProtectedFiles {
            if !path.hasPrefix("/") || path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
                throw MarkaError.validation(L("Marka yalıtımı kurulamadı: klasör yolu desteklenmeyen karakter içeriyor."))
            }
        }
    }

    /// Profil metni. Kural sırası anlamlıdır (sonraki kural öncekini ezer).
    public func render() -> String {
        func clause(_ kind: String, _ paths: [String]) -> String {
            unique(paths).map { "(\(kind) \(Self.quote($0)))" }.joined(separator: " ")
        }
        var lines = ["(version 1)", "(allow default)"]
        if let writable {
            lines.append(";; Yazma: yalnızca izin verilen yollar")
            lines.append("(deny file-write*)")
            lines.append("(allow file-write* (subpath \"/dev\") \(clause("subpath", writable)) \(clause("literal", writableFiles)))")
        }
        if !denied.isEmpty {
            lines.append(";; Diğer markalar ve uygulama verisi: okuma ve yazma yasak")
            lines.append("(deny file-read* file-write* \(clause("subpath", denied)))")
        }
        if !reopened.isEmpty || !reopenedFiles.isEmpty {
            lines.append(";; Oturumun kendi alanı yeniden açılır")
            lines.append("(allow file-read* file-write* \(clause("subpath", reopened)) \(clause("literal", reopenedFiles)))")
        }
        if !readOnly.isEmpty {
            lines.append("(allow file-read* \(clause("subpath", readOnly)))")
        }
        let ancestors = metadataAncestors()
        if !ancestors.isEmpty {
            lines.append(";; Yasaklı kök altındaki üst klasörler: yalnızca meta veri (realpath için); içerik listelenemez")
            lines.append("(allow file-read-metadata \(clause("literal", ancestors)))")
        }
        if !writeProtected.isEmpty || !writeProtectedFiles.isEmpty {
            // Yazma kısıtı olmayan (terminal) profilde bile kabuk/araç yapılandırmasına ve köprü dosyalarına yazma kapatılır:
            // A markası bu dosyalara yük yazıp B oturumunda çalıştırarak köprü kuramaz. Sonraki kural olduğu için öncekini ezer.
            lines.append(";; Kabuk/araç yapılandırması ve köprü dosyaları: yazma kapalı (okuma açık kalır)")
            lines.append("(deny file-write* \(clause("subpath", writeProtected)) \(clause("literal", writeProtectedFiles)))")
        }
        if hardenLaunch {
            lines.append(contentsOf: Self.launchHardeningLines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Profil dışı süreç başlatma yollarını ve yerel Unix soketi köprüsünü kapatan kurallar (ölçümle doğrulandı).
    /// - LaunchServices/`open`, AppleEvents ve Kısayollar: launchd/XPC ile başlatılan süreç profili miras almaz.
    /// - Yerel Unix soketi: `/private/tmp` ve `/private/var/folders` altındaki soketlerle (tmux/screen) B oturumuna köprü.
    ///   Kullanıcının ssh-agent soketi (launchd `Listeners`) istisnadır: `git push` (ssh) çalışmaya devam eder.
    static let launchHardeningLines: [String] = [
        ";; LaunchServices / AppleEvents / Kısayollar: launchd'nin başlattığı süreç profil dışında kalır",
        "(deny mach-lookup (global-name \"com.apple.coreservices.launchservicesd\") (global-name-prefix \"com.apple.lsd\") (global-name \"com.apple.coreservices.quarantine-resolver\"))",
        "(deny appleevent-send)",
        "(deny mach-lookup (global-name-prefix \"com.apple.shortcuts\") (global-name-prefix \"com.apple.WorkflowKit\") (global-name-prefix \"com.apple.siriactionsd\") (global-name-prefix \"com.apple.siri.VoiceShortcuts\") (global-name-prefix \"com.apple.linkd\"))",
        ";; Yerel Unix soketi köprüsü (tmux/screen) kapalı; ssh-agent (launchd Listeners) açık kalır",
        "(deny network-outbound (remote unix-socket (path-regex #\"^/private/tmp/\") (path-regex #\"^/private/var/folders/\")))",
        "(allow network-outbound (remote unix-socket (path-regex #\"^/private/tmp/com\\.apple\\.launchd\\.[A-Za-z0-9]+/Listeners$\")))",
    ]

    /// Yeniden açılan yolların, yasaklı bir kökün içinde kalan üst klasörleri (kök dahil).
    func metadataAncestors() -> [String] {
        var out: [String] = []
        for path in reopened + reopenedFiles + readOnly {
            var parent = (path as NSString).deletingLastPathComponent
            while parent.count > 1 {
                if denied.contains(where: { parent == $0 || parent.hasPrefix($0 + "/") }) { out.append(parent) }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return unique(out).sorted()
    }

    private func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// Sembolik bağları çözülmüş mutlak yol. Henüz var olmayan yolda var olan en uzun üst klasör çözülür, kalanı eklenir.
    public static func canonical(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        var head = standardized
        var tail: [String] = []
        while head.count > 1 {
            if let resolved = realpathString(head) {
                return tail.reversed().reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return standardized
    }

    private static func realpathString(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}

/// Marka yalıtımı profillerini üretir: Codex App Server ve marka terminali için.
public struct BrandIsolation: Sendable {
    /// Uygulama veri alanı (veri tabanı, Files, Yedekler).
    public let workspace: URL
    public let folders: BrandFolders
    public let home: URL

    public init(workspace: URL, folders: BrandFolders, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.workspace = workspace; self.folders = folders; self.home = home
    }

    /// Uygulamanın Codex süreçlerinin kapsam başına ev dizini (`CODEX_HOME`). Oturum kayıtları markalar arasında paylaşılmaz.
    public func codexHome(for scope: SessionScope) -> URL {
        let key: String
        switch scope {
        case .brand(let id): key = "marka-" + BrandFolders.safeName(id)
        case .allBrands: key = "tum-markalar"
        }
        return workspace.appendingPathComponent("Codex", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }

    /// Kullanıcının kendi Codex ev dizini (giriş bilgisi `auth.json` burada).
    public var userCodexHome: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        return home.appendingPathComponent(".codex", isDirectory: true)
    }

    /// Kaydedilmiş tüm marka klasörleri (kök dışına taşınmış olanlar dahil).
    public func savedBrandFolders() throws -> [String] {
        try folders.store.read { db in
            try String.fetchAll(db, sql: "SELECT value FROM setting WHERE key LIKE 'folder.%' ORDER BY key")
        }
    }

    /// Her oturumda yasak olan alan: marka klasörleri kökü, kayıtlı tüm marka klasörleri, uygulama veri alanı.
    func deniedCore() throws -> [String] {
        ([folders.root.path] + (try savedBrandFolders()) + [workspace.path]).map(SandboxProfile.canonical)
    }

    private func homePath(_ rel: String) -> String { SandboxProfile.canonical(home.appendingPathComponent(rel).path) }

    /// Terminalde yazması kapatılan tekil dosyalar: kabuk başlangıç dosyaları ve araçların yürütülebilir yapılandırması.
    /// Bunlara yük yazıp B oturumunda çalıştırarak köprü kurulamaz. `~/.zsh_history`/`~/.bash_history` yazılabilir kalır
    /// (kabuk geçmişi bozulmasın diye — ölçüldü). Claude/Codex'in oturum ve geçmiş yazmaları da açık kalır.
    func terminalWriteProtectedFiles() -> [String] {
        [".zshenv", ".zshrc", ".zprofile", ".zlogin", ".zlogout",
         ".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".profile", ".inputrc",
         ".gitconfig", ".claude.json",
         ".claude/settings.json", ".claude/settings.local.json", ".claude/CLAUDE.md",
         ".codex/config.toml"].map(homePath)
    }

    /// Terminalde yazması kapatılan klasörler: kabuk oturum dosyaları, araç yapılandırma/eklenti klasörleri, ikili yolları.
    func terminalWriteProtected() -> [String] {
        [".zsh_sessions", ".config", ".ssh", "Library/LaunchAgents",
         ".claude/hooks", ".claude/commands", ".claude/agents", ".claude/skills", ".claude/plugins",
         ".codex/packages", ".local/bin"].map(homePath)
        + ["/usr/local/bin", "/opt/homebrew/bin"].map(SandboxProfile.canonical)
    }

    /// Marka terminali: diğer markalar ve uygulama verisi okunamaz, yazılamaz. Kullanıcının kendi kabuğu (yazma kısıtı yok),
    /// ama kabuk/araç yapılandırma dosyalarına yazma kapalı (köprü önlenir) ve profil dışı süreç başlatma yolları kapalı.
    public func terminalProfile(brandId: String) throws -> SandboxProfile {
        let own = SandboxProfile.canonical(try folders.folder(for: .brand(brandId)).path)
        let profile = SandboxProfile(denied: try deniedCore(), reopened: [own],
                                     writeProtected: terminalWriteProtected(), writeProtectedFiles: terminalWriteProtectedFiles(),
                                     hardenLaunch: true)
        try profile.validate()
        return profile
    }

    /// Codex App Server: okuma yasağı terminaldekiyle aynı, ek olarak kullanıcının Codex/Claude geçmişi de kapalı;
    /// yazma yalnızca oturum klasörü, kapsamın Codex ev dizini, giriş dosyası ve geçici klasörler.
    public func codexProfile(scope: SessionScope, codexBinary: URL) throws -> SandboxProfile {
        let own = SandboxProfile.canonical(try folders.folder(for: scope).path)
        let codexHome = SandboxProfile.canonical(codexHome(for: scope).path)
        let userHome = SandboxProfile.canonical(userCodexHome.path)
        let claude = SandboxProfile.canonical(home.appendingPathComponent(".claude").path)
        let claudeJSON = SandboxProfile.canonical(home.appendingPathComponent(".claude.json").path)
        let auth = userHome + "/auth.json"
        // ~/.codex: tüm Codex oturumlarının kayıtları (başka markaların ve terminalde çalıştırılan Codex CLI'nın) ve
        // config.toml'daki proje yolları (marka adları) burada. Yalnızca giriş dosyası açılır; belirteç yenilemesi ona yazar.
        var denied = try deniedCore() + [userHome, claude]
        denied.append(claudeJSON)
        // Kullanıcının kabuk geçmişi Codex'ten okunamaz (Codex'in kendi CODEX_HOME'u ayrıdır, etkilenmez).
        denied += [".zsh_history", ".zsh_sessions", ".bash_history", ".sh_history"].map { homePath($0) }
        // Codex bağımsız kurulumu ~/.codex/packages altında olabilir; çalıştırılabilmesi için yalnızca okuma açılır.
        var readOnly: [String] = []
        let binary = SandboxProfile.canonical(codexBinary.path)
        if binary.hasPrefix(userHome + "/") {
            let first = binary.dropFirst(userHome.count + 1).split(separator: "/").first.map(String.init) ?? ""
            if !first.isEmpty { readOnly.append(userHome + "/" + first) }
        }
        // Geçici klasörler: Codex'in kendi geçici klasörü kapsamın ev dizinindedir (TMPDIR); macOS araçlarından bazıları
        // (ör. mktemp) TMPDIR'ı değil kullanıcının sistem geçici klasörünü kullanır — ölçüldü, bu yüzden o da açık.
        let temps = ["/private/tmp", Self.darwinDir(_CS_DARWIN_USER_TEMP_DIR)].compactMap { $0 }.map(SandboxProfile.canonical)
        let profile = SandboxProfile(denied: denied, reopened: [own, codexHome], reopenedFiles: [auth], readOnly: readOnly,
                                     writable: [own, codexHome] + temps, writableFiles: [auth], hardenLaunch: true)
        try profile.validate()
        return profile
    }

    /// Denetim (yalıtımsız tur çalıştırmayan) Codex süreci için profil: hesap, giriş ve model listesi. Kullanıcıya ait
    /// `codex` ikilisi kurcalanmış olsa bile tüm marka klasörleri ve uygulama veri alanı OS düzeyinde kapalıdır.
    /// LaunchServices kapatılmaz: ChatGPT girişi tarayıcı açar. Yazma kısıtı yoktur (belirteç yenilemesi `~/.codex`'e yazar).
    public func controlProfile() throws -> SandboxProfile {
        // Kullanıcının Claude verisi de kapalı; ~/.codex açık kalır (giriş/hesap için gerekir).
        let denied = try deniedCore() + [homePath(".claude"), homePath(".claude.json")]
        let profile = SandboxProfile(denied: denied)
        try profile.validate()
        return profile
    }

    /// Codex App Server'ın yalıtımlı başlatma bilgisi. Sınama dosyası uygulama veri alanındadır (profilde yasak).
    public func codexIsolation(scope: SessionScope, codexBinary: URL) throws -> CodexAppServer.Isolation {
        CodexAppServer.Isolation(profile: try codexProfile(scope: scope, codexBinary: codexBinary), codexHome: codexHome(for: scope),
                                 userCodexHome: userCodexHome, probeFile: probeFile)
    }

    /// Denetim sürecinin başlatma bilgisi: control profili, kullanıcının Codex ev dizini ve okuma sınamasıyla.
    public func controlIsolation() throws -> CodexAppServer.Isolation {
        CodexAppServer.Isolation(profile: try controlProfile(), codexHome: userCodexHome,
                                 userCodexHome: userCodexHome, probeFile: probeFile)
    }

    /// Profilin okumayı gerçekten kapattığını ölçmek için yasaklı alanda duran dosya.
    public var probeFile: URL { workspace.appendingPathComponent("Codex", isDirectory: true).appendingPathComponent(".yalitim-sinamasi") }

    static func darwinDir(_ name: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(name, &buf, buf.count) > 0 else { return nil }
        let s = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return s.isEmpty ? nil : s
    }
}

/// `sandbox-exec` ile çalıştırma ve profilin gerçekten uygulandığının ölçülmesi.
public enum SandboxRunner {
    public static let executable = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    public struct Result: Sendable { public var status: Int32; public var stdout: String; public var stderr: String }

    /// Komutu profil altında çalıştırıp çıktısını döndürür (sınama ve doğrulama için).
    public static func run(profile: String, _ arguments: [String], environment: [String: String]? = nil) throws -> Result {
        let p = Process()
        p.executableURL = executable
        p.arguments = ["-p", profile] + arguments
        if let environment { p.environment = environment }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, stdout: String(decoding: o, as: UTF8.self), stderr: String(decoding: e, as: UTF8.self))
    }

    /// Profilin bu süreçte uygulanabildiğini ve yasaklı dosyayı gerçekten kapattığını ölçer.
    /// Uygulama iç içe bir sandbox'ta çalışıyorsa `sandbox-exec` başarısız olur; o zaman yalıtım yok sayılır.
    public static func verify(profile: String, deniedFile: URL, marker: String) -> Bool {
        guard let r = try? run(profile: profile, ["/bin/cat", deniedFile.path]) else { return false }
        return r.status != 0 && !r.stdout.contains(marker) && r.stderr.contains("Operation not permitted")
    }
}
