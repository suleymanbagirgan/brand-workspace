import AppKit
import MarkaCore
import SwiftTerm
import SwiftUI

/// SwiftTerm da bir `Color` tipi sunar; bu dosyada SwiftUI'nınki kullanılır.
private typealias Color = SwiftUI.Color

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
        // Tasarım teslimi: terminal her iki görünümde de koyu (#151820 zemin, #D9DFEB yazı).
        view.nativeBackgroundColor = NSColor(srgbRed: 0x15 / 255, green: 0x18 / 255, blue: 0x20 / 255, alpha: 1)
        view.nativeForegroundColor = NSColor(srgbRed: 0xD9 / 255, green: 0xDF / 255, blue: 0xEB / 255, alpha: 1)
        view.caretColor = NSColor(srgbRed: 0xB9 / 255, green: 0xBA / 255, blue: 0xF8 / 255, alpha: 1)
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
            // Codex CLI'nın kendi sandbox'ı bu terminalde iç içe kurulamaz; doğru bayraklarla başlatma panelin "Codex" düğmesindedir.
            view.startProcess(executable: SandboxRunner.executable.path, args: ["-p", profile, shell, "-l"], environment: envList,
                              execName: "sandbox-exec", currentDirectory: directory.path)
        } else {
            view.startProcess(executable: shell, args: [], environment: envList,
                              execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: directory.path)
        }
    }

    /// Komutu kabuğa yazar ve Enter'a basar (kullanıcının kendi kabuğu; araç başlatma düğmeleri için).
    func run(_ command: String) {
        view.send(data: ArraySlice(Array((command + "\r").utf8)))
        view.window?.makeFirstResponder(view)
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

/// Terminal paneli (0.3.0, tasarım teslimi): koyu sağ sütun. Üstte başlık (gizle · ···), marka satırı ve oturum durumu,
/// araç başlatıcıları (Claude Code · Codex), konum satırı; ortada markanın süren kabuğu; altta kabuk ve yalıtım durumu.
/// Genişliği `BrandDetailView` sürüklemeyle belirler ve hatırlar. Gizlemek ⌘J; oturum sürer.
struct TerminalPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.isSnapshot) private var isSnapshot
    let brand: Brand
    @State private var session: TerminalSession?
    @State private var isolationError: String?

    var body: some View {
        let _ = app.terminalRevision
        VStack(spacing: 0) {
            titleBar
            brandRow
            launchers
            locationRow
            content
            footer
        }
        .background(Design.terminalBackground)
        .environment(\.colorScheme, .dark)
        .onAppear { if !isSnapshot { attach() } }
    }

    private var info: TerminalSessionInfo? { app.terminals.info(brand.id) }
    private var isolated: Bool { info?.isolated ?? app.terminalIsolation }

    // MARK: Bölümler

    private var titleBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "terminal").font(.system(size: 13)).foregroundStyle(Design.terminalMuted)
            Text(L("Terminal")).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.95))
            Spacer()
            iconButton("sidebar.right", help: L("Terminali gizle (⌘J); oturum sürer")) { app.showAssistant = false }
            Menu {
                if info?.running == false { Button(L("Yeni oturum"), action: attach) }
                Button(L("Terminali gizle")) { app.showAssistant = false }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Design.terminalMuted).frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(L("Diğer")).accessibilityLabel(L("Diğer"))
        }
        .padding(.horizontal, 18).frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.terminalLine).frame(height: 1) }
    }

    private var brandRow: some View {
        HStack {
            Text(brand.name).font(.system(size: 11)).foregroundStyle(Color(white: 0.9)).lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText).font(.system(size: 10)).foregroundStyle(Design.terminalMuted)
            }
        }
        .padding(.horizontal, 18).frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.terminalLine).frame(height: 1) }
    }

    private var statusText: String {
        if isolationError != nil { return L("Başlatılamadı") }
        if let info, !info.running { return L("Kabuk kapandı") }
        return L("Oturum açık")
    }

    private var statusColor: Color {
        if isolationError != nil { return Color(red: 1, green: 0.6, blue: 0.56) }
        if let info, !info.running { return Design.terminalMuted }
        return Color(red: 0.52, green: 0.86, blue: 0.62)
    }

    private var launchers: some View {
        HStack(spacing: 4) {
            launcher(L("Claude Code"), help: L("Terminalde claude komutunu çalıştırır")) { $0.run("claude") }
            launcher(L("Codex"), help: L("Terminalde codex komutunu çalıştırır")) { $0.run(isolated ? TerminalSession.codexCommand : "codex") }
            Spacer()
            if info?.running == false {
                Button(L("Yeni oturum"), action: attach).buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.97))
            }
        }
        .padding(.horizontal, 12).frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.terminalLine).frame(height: 1) }
    }

    private func launcher(_ title: String, help: String, _ run: @escaping (TerminalSession) -> Void) -> some View {
        Button { if let session { run(session) } } label: {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.92))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Design.terminalPanel))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Design.terminalLine))
        }
        .buttonStyle(.plain).disabled(session == nil || info?.running == false).help(help)
    }

    private var locationRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder").font(.system(size: 11))
            Text(locationText).lineLimit(1).truncationMode(.head)
        }
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Design.terminalMuted)
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var locationText: String {
        let path = (try? app.folders?.existingFolder(brandId: brand.id))??.path ?? brand.name
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    @ViewBuilder private var content: some View {
        if let isolationError {
            // Yalıtım açıkken profil kurulamazsa kabuk yalıtımsız başlatılmaz.
            VStack(alignment: .leading, spacing: Design.Space.s) {
                Text(L("Marka yalıtımı kurulamadığı için terminal başlatılmadı.")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                Text(isolationError).font(.system(size: 11)).foregroundStyle(Design.terminalMuted)
                Button(L("Tekrar dene"), action: attach).buttonStyle(.plain).font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.97))
            }
            .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isSnapshot {
            TerminalSketch(brand: brand.name)
        } else if let session {
            TerminalHost(session: session)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            if app.terminals.isolationDiffers(brand.id, current: app.terminalIsolation) {
                Text(L("Yalıtım ayarı yeni oturumda geçerli")).lineLimit(1)
                    .help(info?.isolated == true
                          ? L("Bu oturum yalıtımlı başladı; ayar değişikliği kabuktan çıkınca açılan yeni oturumda geçerli.")
                          : L("Bu oturum yalıtımsız başladı; ayar değişikliği kabuktan çıkınca açılan yeni oturumda geçerli."))
            } else {
                Text(shellName + " · " + brand.name).lineLimit(1)
            }
            Spacer()
            Text(isolated ? L("Marka yalıtımı açık") : L("Marka yalıtımı kapalı"))
                .help(isolated
                      ? L("Senin kabuğun, marka yalıtımlı: diğer markaların klasörleri ve uygulama verisi buradan okunamaz, yazılamaz. BAGLAM.md'yi okur, çıktıları ciktilar/, görev ve iş önerilerini oneriler/ klasörüne bırakırsın.")
                      : L("Senin kabuğun; marka yalıtımı kapalı (Ayarlar › Genel). Bu terminal diğer markaların klasörlerini okuyabilir."))
        }
        .font(.system(size: 10)).foregroundStyle(Design.terminalMuted)
        .padding(.horizontal, 18).frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(Design.terminalLine).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private var shellName: String { ((ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") as NSString).lastPathComponent }

    private func iconButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Design.terminalMuted).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
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

/// Ekran çizimi için terminal taslağı (gerçek kabuk başlatılmaz; AppKit görünümü çizilemez).
private struct TerminalSketch: View {
    let brand: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "$ claude").foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.97))
            Text(verbatim: "\(brand) / çalışma oturumu").foregroundStyle(Design.terminalMuted)
            Spacer()
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 18).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        terminal.autoresizingMask = []
        addSubview(terminal)
        needsLayout = true
        DispatchQueue.main.async { [weak terminal] in
            guard let terminal, let window = terminal.window else { return }
            window.makeFirstResponder(terminal)
        }
    }

    override func layout() {
        super.layout()
        for view in subviews { view.frame = bounds.insetBy(dx: 16, dy: 4) }
    }

    override var isFlipped: Bool { true }

    /// Kap sökülürken yalnız görünüm çıkarılır; başka kaba taşınmışsa dokunulmaz.
    func detach() {
        for view in subviews { view.removeFromSuperview() }
    }
}
