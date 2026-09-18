import AppKit
import MarkaCore
import SwiftTerm
import SwiftUI

/// Marka terminali oturumu: SwiftTerm görünümü + kabuk süreci. `AppModel.terminals` önbelleğinde marka başına yaşar
/// (U9): paneli gizlemek, başka markaya ya da Bugün'e geçmek, paneli yana/alta almak ve yalıtım ayarını değiştirmek süreci
/// **öldürmez**; panel yeniden gösterilince aynı görünüm yeniden ebeveynlenir. Süreç yalnız kullanıcı kabuktan çıkınca,
/// marka arşivlenince ya da uygulama kapanınca (tek soruyla) biter. Uygulamanın veri tabanına yazmaz.
@MainActor
final class TerminalSession {
    let brandId: String
    let view: LocalProcessTerminalView
    private let delegate: Delegate

    /// Yalıtımlı terminalde Codex CLI'yı başlatma komutu (sınırı terminal profili koyar; güvenli sayılmayan komut onay ister).
    static let codexCommand = "codex --sandbox danger-full-access --ask-for-approval untrusted"
    static var codexHint: String { LF("Codex için: %@", codexCommand) }

    /// Kabuğu marka klasöründe başlatır. `profile` verilirse `sandbox-exec -p <profil> <kabuk> -l` (profil tüm alt süreçlere
    /// geçer). `onExit` kabuk bitince (ana kuyrukta) çağrılır.
    init(brandId: String, directory: URL, brandName: String, profile: String?, onExit: @escaping @MainActor () -> Void) {
        self.brandId = brandId
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        delegate = Delegate(onExit: onExit)
        view.processDelegate = delegate
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // API anahtarları (uygulama anahtar tanımlı bir kabuktan açıldıysa) marka terminaline inmez.
        var env = ChildEnvironment.current
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "tr_TR.UTF-8"
        env["MARKA_ADI"] = brandName
        env["MARKA_KLASORU"] = directory.path
        env["MARKA_BAGLAM"] = directory.appendingPathComponent("BAGLAM.md").path
        env["MARKA_YALITIM"] = profile == nil ? "0" : "1"
        let envList = env.map { "\($0.key)=\($0.value)" }
        if let profile {
            // Codex CLI'nın kendi sandbox'ı bu terminalde iç içe kurulamaz; elle başlatma bayrakları kaybolmasın diye tek satır
            // ipucu yalnız ekrana yazılır (kabuğa gönderilmez; dotfile, ortam ve geçmiş değişmez).
            view.feed(text: "\u{1B}[2m" + Self.codexHint + "\u{1B}[0m\r\n")
            view.startProcess(executable: SandboxRunner.executable.path, args: ["-p", profile, shell, "-l"], environment: envList,
                              execName: "sandbox-exec", currentDirectory: directory.path)
        } else {
            view.startProcess(executable: shell, args: [], environment: envList,
                              execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: directory.path)
        }
    }

    /// Kabuk sürecinin kimliği (0: başlamadı).
    var pid: pid_t { view.process.shellPid }

    /// Süreci sonlandırır (yalnız arşivleme ve uygulama kapanışı). Etkileşimli kabuk SIGTERM'i yok sayar (ölçüldü: `/bin/sh`
    /// SIGTERM sonrası yaşıyordu); bu yüzden Terminal.app'in pencere kapatmasındaki gibi kabuğun süreç grubuna SIGHUP
    /// gönderilir (içinde çalışan iş de sonlansın), 2 saniye sonra hâlâ yaşıyorsa SIGKILL; süreç toplanır (zombi kalmaz).
    func terminate() {
        let pid = self.pid
        view.terminate()
        guard pid > 0 else { return }
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            for _ in 0..<20 {
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                usleep(100_000)
            }
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }
    }

    @MainActor
    final class Delegate: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let onExit: @MainActor () -> Void
        init(onExit: @escaping @MainActor () -> Void) { self.onExit = onExit }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        // SwiftTerm bunu ana kuyrukta çağırır (LocalProcess varsayılan kuyruğu).
        func processTerminated(source: TerminalView, exitCode: Int32?) { onExit() }
    }
}

/// Terminal paneli: başlıkta ad, oturumun yalıtım durumu ve *Yana al / Alta al*; altında markanın süren oturumu.
/// Kapatmak (gizlemek) marka başlığındaki "Terminal" ya da ⌘J; oturum sürer.
struct TerminalPanel: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var session: TerminalSession?
    @State private var isolationError: String?

    var body: some View {
        let _ = app.terminalRevision
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
                .background(.bar)
            if let isolationError {
                // Yalıtım açıkken profil kurulamazsa kabuk yalıtımsız başlatılmaz.
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    EmptyStateView(title: L("Marka yalıtımı kurulamadığı için terminal başlatılmadı."), message: isolationError,
                                   actionTitle: L("Tekrar dene"), action: attach)
                }
                .padding(Design.Space.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let session {
                TerminalHost(session: session)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: attach)
    }

    private var info: TerminalSessionInfo? { app.terminals.info(brand.id) }

    /// Başlık: ad; oturum yalıtımsızsa ya da açık oturum eski yalıtım ayarıyla sürüyorsa tek satır; kabuk bittiyse
    /// "Yeni oturum"; sağda yer değiştirme (oturum sürer).
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            Text(LF("Terminal · %@", brand.name)).font(Design.Font.caption).lineLimit(1)
                .help(info?.isolated ?? app.terminalIsolation
                      ? L("Senin kabuğun, marka yalıtımlı: diğer markaların klasörleri ve uygulama verisi buradan okunamaz, yazılamaz. BAGLAM.md'yi okur, çıktıları ciktilar/, görev ve iş önerilerini oneriler/ klasörüne bırakırsın.")
                      : L("Senin kabuğun; marka yalıtımı kapalı (Ayarlar › Genel). Bu terminal diğer markaların klasörlerini okuyabilir."))
            if let info, !info.running {
                Text(L("Kabuk kapandı.")).captionStyle()
                Button(L("Yeni oturum"), action: attach).buttonStyle(.text).font(Design.Font.caption)
            } else if app.terminals.isolationDiffers(brand.id, current: app.terminalIsolation) {
                // Yalıtım ayarı değişti: açık oturum eski profilde kalır, yeni açılan yeni profille başlar.
                Text(info?.isolated == true
                     ? L("Bu oturum yalıtımlı başladı; ayar değişikliği kabuktan çıkınca açılan yeni oturumda geçerli.")
                     : L("Bu oturum yalıtımsız başladı; ayar değişikliği kabuktan çıkınca açılan yeni oturumda geçerli."))
                    .captionStyle().lineLimit(1).truncationMode(.tail)
            } else if info?.isolated == false {
                Text(L("yalıtım kapalı")).captionStyle()
            }
            Spacer(minLength: Design.Space.s)
            Button(app.terminalOnSide ? L("Alta al") : L("Yana al")) { app.terminalOnSide.toggle() }
                .buttonStyle(.text).font(Design.Font.caption)
                .help(L("Terminalin yerini değiştirir; oturum sürer"))
        }
    }

    /// Markanın süren oturumunu bağlar; yoksa (ya da kabuk bittiyse) yenisini başlatır. BAGLAM.md her gösterimde yenilenir.
    private func attach() {
        isolationError = nil
        guard let folder = app.writeContext(brandId: brand.id) else { return }
        do {
            session = try app.terminalSession(brand: brand, directory: folder)
        } catch {
            session = nil
            isolationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Önbellekteki terminal görünümünü taşıyan kap. SwiftUI kabı her gösterimde yeniden kurar; içindeki terminal görünümü
/// aynı kalır (yeniden ebeveynleme). Kap söküldüğünde süreç **sonlandırılmaz**.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalContainer {
        let container = TerminalContainer()
        container.attach(session.view)
        return container
    }

    func updateNSView(_ container: TerminalContainer, context: Context) { container.attach(session.view) }

    static func dismantleNSView(_ container: TerminalContainer, coordinator: ()) { container.detach() }
}

final class TerminalContainer: NSView {
    /// Görünümü bu kaba taşır (başka kaptaysa oradan çıkar) ve klavye odağını verir.
    func attach(_ terminal: NSView) {
        guard terminal.superview !== self else { return }
        for view in subviews where view !== terminal { view.removeFromSuperview() }
        terminal.removeFromSuperview()
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        DispatchQueue.main.async { [weak terminal] in
            guard let terminal, let window = terminal.window else { return }
            window.makeFirstResponder(terminal)
        }
    }

    /// Kap sökülürken yalnız görünüm çıkarılır; başka kaba taşınmışsa dokunulmaz.
    func detach() {
        for view in subviews { view.removeFromSuperview() }
    }
}
