import Foundation
import Testing
@testable import MarkaCore

/// Marka yalıtımı: seatbelt profil üreticisi ve gerçek `sandbox-exec` ile okuma/yazma denemeleri.
@Suite struct IsolationTests {
    /// Geçici klasörde iki markalı çalışma alanı: kök adı Türkçe ve boşluklu, markalar kök altında.
    func setup() throws -> (store: Store, isolation: BrandIsolation, a: Brand, b: Brand, root: URL, ws: URL) {
        let base = try tempDir("yalitim")
        let root = base.appendingPathComponent("Marka Çalışma Alanı", isDirectory: true)
        let ws = base.appendingPathComponent("Uygulama Verisi", isDirectory: true)
        let store = Store(database: try AppDatabase.open(at: ws))
        let a = try store.createBrand(name: "Örnek Yangın")
        let b = try store.createBrand(name: "Gizli Şirket")
        let folders = BrandFolders(root: root, store: store)
        _ = try folders.folder(for: .brand(a.id))
        _ = try folders.folder(for: .brand(b.id))
        return (store, BrandIsolation(workspace: ws, folders: folders), a, b, root, ws)
    }

    func run(_ profile: String, _ script: String) throws -> SandboxRunner.Result {
        try SandboxRunner.run(profile: profile, ["/bin/sh", "-c", script])
    }

    func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @Test func profilDizgesiTirnakVeTersBoluyuKacislar() {
        #expect(SandboxProfile.quote(#"/a/Marka "X" \ Y"#) == #""/a/Marka \"X\" \\ Y""#)
        #expect(SandboxProfile.quote("/Users/ş/Marka Çalışma Alanı") == "\"/Users/ş/Marka Çalışma Alanı\"")
        #expect(throws: MarkaError.self) { try SandboxProfile(denied: ["/a\nb"]).validate() }
        #expect(throws: MarkaError.self) { try SandboxProfile(denied: ["goreli/yol"]).validate() }
    }

    @Test func sembolikBagCozulurVeOlmayanYolUstKlasordenKurulur() {
        #expect(SandboxProfile.canonical("/tmp") == "/private/tmp")
        #expect(SandboxProfile.canonical("/tmp/marka-olmayan-\(UUID().uuidString)/alt").hasPrefix("/private/tmp/marka-olmayan-"))
        #expect(SandboxProfile.canonical("/var/folders").hasPrefix("/private/var/folders"))
    }

    @Test func markaKlasoruAcikDigerleriVeUygulamaVerisiKapali() throws {
        let t = try setup()
        let p = try t.isolation.terminalProfile(brandId: t.a.id)
        let own = SandboxProfile.canonical(try t.isolation.folders.folder(for: .brand(t.a.id)).path)
        let other = SandboxProfile.canonical(try t.isolation.folders.folder(for: .brand(t.b.id)).path)
        #expect(p.denied.contains(SandboxProfile.canonical(t.root.path)))
        #expect(p.denied.contains(other))
        #expect(p.denied.contains(SandboxProfile.canonical(t.ws.path)))
        #expect(p.reopened == [own])
        #expect(p.writable == nil)
        let text = p.render()
        // Sonraki kural öncekini ezer: yasak önce, markanın kendi klasörü sonra.
        let deny = try #require(text.range(of: "(deny file-read* file-write*"))
        let allow = try #require(text.range(of: "(allow file-read* file-write* (subpath \(SandboxProfile.quote(own)))"))
        #expect(deny.lowerBound < allow.lowerBound)
        #expect(text.contains("Marka Çalışma Alanı"))
        // Kökün kendisine yalnızca meta veri izni (realpath için); listeleme yasak kalır.
        #expect(p.metadataAncestors() == [SandboxProfile.canonical(t.root.path)])
    }

    @Test func codexProfiliYazmayiMarkaKlasoruVeGeciciKlasorlerleSinirlar() throws {
        let t = try setup()
        let home = try tempDir("ev")
        let iso = BrandIsolation(workspace: t.ws, folders: t.isolation.folders, home: home)
        let binary = iso.userCodexHome.appendingPathComponent("packages/standalone/bin/codex")
        let p = try iso.codexProfile(scope: .brand(t.a.id), codexBinary: binary)
        let own = SandboxProfile.canonical(try t.isolation.folders.folder(for: .brand(t.a.id)).path)
        let codexHome = SandboxProfile.canonical(iso.codexHome(for: .brand(t.a.id)).path)
        let userCodex = SandboxProfile.canonical(iso.userCodexHome.path)
        let writable = try #require(p.writable)
        #expect(writable.contains(own))
        #expect(writable.contains(codexHome))
        #expect(writable.contains("/private/tmp"))
        #expect(!writable.contains(SandboxProfile.canonical(home.path)))
        #expect(p.denied.contains(userCodex))
        #expect(p.denied.contains(SandboxProfile.canonical(home.appendingPathComponent(".claude").path)))
        #expect(p.reopenedFiles == [userCodex + "/auth.json"])
        #expect(p.readOnly == [userCodex + "/packages"])
        // Kapsamların Codex ev dizinleri ayrıdır; oturum kayıtları markalar arasında paylaşılmaz.
        #expect(iso.codexHome(for: .brand(t.a.id)) != iso.codexHome(for: .brand(t.b.id)))
        #expect(iso.codexHome(for: .allBrands) != iso.codexHome(for: .brand(t.a.id)))
    }

    @Test func tumMarkalarKipindeHicbirMarkaKlasoruAcilmaz() throws {
        let t = try setup()
        let p = try t.isolation.codexProfile(scope: .allBrands, codexBinary: URL(fileURLWithPath: "/usr/local/bin/codex"))
        let allFolder = SandboxProfile.canonical(try t.isolation.folders.folder(for: .allBrands).path)
        let codexHome = SandboxProfile.canonical(t.isolation.codexHome(for: .allBrands).path)
        #expect(p.reopened == [allFolder, codexHome])
        for id in [t.a.id, t.b.id] {
            let folder = SandboxProfile.canonical(try t.isolation.folders.folder(for: .brand(id)).path)
            #expect(!p.reopened.contains { folder == $0 || folder.hasPrefix($0 + "/") })
        }
    }

    /// Gerçek `sandbox-exec`: izin verilen okunur/yazılır, yasaklı okunamaz/yazılamaz. Tırnak, ters bölü ve Türkçe karakterli yol.
    @Test func gercekSandboxIleYasakliKlasorOkunamazIzinliOkunur() throws {
        let base = try tempDir("seatbelt")
        let root = base.appendingPathComponent("Marka Çalışma Alanı", isDirectory: true)
        let own = root.appendingPathComponent(#"Örnek "Yangın" \ A.Ş."#, isDirectory: true)
        let other = root.appendingPathComponent("Gizli Şirket", isDirectory: true)
        let ws = base.appendingPathComponent("veri", isDirectory: true)
        for d in [own, other, ws] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try "ACIK-A".write(to: own.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "GIZLI-B".write(to: other.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "VERI".write(to: ws.appendingPathComponent("workspace.sqlite"), atomically: true, encoding: .utf8)
        let profile = SandboxProfile(denied: [root.path, ws.path].map(SandboxProfile.canonical),
                                     reopened: [SandboxProfile.canonical(own.path)])
        try profile.validate()
        let text = profile.render()

        let readOwn = try run(text, "cat \(shellQuote(own.appendingPathComponent("a.txt").path))")
        #expect(readOwn.status == 0 && readOwn.stdout == "ACIK-A")
        let readOther = try run(text, "cat \(shellQuote(other.appendingPathComponent("b.txt").path))")
        #expect(readOther.status != 0 && !readOther.stdout.contains("GIZLI-B") && readOther.stderr.contains("Operation not permitted"))
        let listRoot = try run(text, "ls \(shellQuote(root.path))")
        #expect(listRoot.status != 0 && !listRoot.stdout.contains("Gizli"))
        let readData = try run(text, "cat \(shellQuote(ws.appendingPathComponent("workspace.sqlite").path))")
        #expect(readData.status != 0 && !readData.stdout.contains("VERI"))
        let writeOwn = try run(text, "echo yaz > \(shellQuote(own.appendingPathComponent("w.txt").path)) && cd \(shellQuote(own.path)) && pwd -P")
        #expect(writeOwn.status == 0)
        let writeOther = try run(text, "echo yaz > \(shellQuote(other.appendingPathComponent("w.txt").path))")
        #expect(writeOther.status != 0)
        #expect(!FileManager.default.fileExists(atPath: other.appendingPathComponent("w.txt").path))
        // Profil alt süreçlere miras geçer (kabuk → alt kabuk → cat).
        let nested = try run(text, "/bin/zsh -c \(shellQuote("cat " + shellQuote(other.appendingPathComponent("b.txt").path)))")
        #expect(nested.status != 0 && !nested.stdout.contains("GIZLI-B"))
        #expect(SandboxRunner.verify(profile: text, deniedFile: other.appendingPathComponent("b.txt"), marker: "GIZLI-B"))
        // Kural yoksa ölçüm "uygulanmadı" der (yasaklı dosya okunur).
        #expect(!SandboxRunner.verify(profile: "(version 1)(allow default)", deniedFile: other.appendingPathComponent("b.txt"), marker: "GIZLI-B"))
    }

    /// Gerçek `sandbox-exec` + üretilen Codex profili: diğer marka ve ev dizini yazılamaz, kendi klasörü ve geçici klasör yazılır.
    @Test func gercekSandboxIleCodexProfiliEvDizininiVeDigerMarkayiKapatir() throws {
        let t = try setup()
        let ownDir = try t.isolation.folders.folder(for: .brand(t.a.id))
        let otherDir = try t.isolation.folders.folder(for: .brand(t.b.id))
        try "GIZLI-B".write(to: otherDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let profile = try t.isolation.codexProfile(scope: .brand(t.a.id), codexBinary: URL(fileURLWithPath: "/usr/local/bin/codex")).render()
        let homeProbe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".marka-yalitim-sinamasi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: homeProbe) }

        let tmpProbe = "/private/tmp/marka-yalitim-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpProbe) }
        #expect(try run(profile, "echo x > \(shellQuote(ownDir.appendingPathComponent("ciktilar/cikti.md").path))").status == 0)
        #expect(try run(profile, "echo x > \(shellQuote(tmpProbe)) && echo ok").stdout.contains("ok"))
        let home = try run(profile, "echo x > \(shellQuote(homeProbe.path))")
        #expect(home.status != 0)
        #expect(!FileManager.default.fileExists(atPath: homeProbe.path))
        let other = try run(profile, "cat \(shellQuote(otherDir.appendingPathComponent("b.txt").path))")
        #expect(other.status != 0 && !other.stdout.contains("GIZLI-B"))
        #expect(try run(profile, "echo x > \(shellQuote(otherDir.appendingPathComponent("w.txt").path))").status != 0)
        #expect(try run(profile, "ls \(shellQuote(t.ws.path))").status != 0)
    }

    @Test func klasorGoruntusuSembolikBaglaAcilanKlasordeGoreliYolVerir() throws {
        let t = try setup()
        let dir = try t.isolation.folders.folder(for: .brand(t.a.id))
        try "x".write(to: dir.appendingPathComponent("ciktilar/teklif.md"), atomically: true, encoding: .utf8)
        // Geçici klasör /var altında; numaralandırıcı /private/var döndürür.
        #expect(dir.path.hasPrefix("/var/") || dir.path.hasPrefix("/private/"))
        #expect(Set(t.isolation.folders.snapshot(dir).keys) == ["ciktilar/teklif.md"])
        let viaPrivate = URL(fileURLWithPath: SandboxProfile.canonical(dir.path), isDirectory: true)
        #expect(Set(t.isolation.folders.snapshot(viaPrivate).keys) == ["ciktilar/teklif.md"])
    }

    @Test func codexCiktisiParcaParcaGelseDeSatirlaraBolunur() {
        let s = LineSplitter()
        #expect(s.append(Data("{\"a\":1}\n{\"b\":".utf8)) == ["{\"a\":1}"])
        #expect(s.append(Data("2}\nÇ".utf8)) == ["{\"b\":2}"])
        #expect(s.append(Data("alışma\n".utf8)) == ["Çalışma"])
        #expect(s.append(Data("son".utf8)).isEmpty)
        #expect(s.flush() == ["son"])
        #expect(s.flush().isEmpty)
    }

    @Test func altSurecOrtamindanApiAnahtarlariCikarilir() {
        let env = ["ANTHROPIC_API_KEY": "sk-ant-x", "ANTHROPIC_BASE_URL": "https://x", "ANTHROPIC_AUTH_TOKEN": "t",
                   "OPENAI_API_KEY": "sk-x", "PATH": "/usr/bin", "HOME": "/Users/x", "ANTHROPIC_MODEL": "m"]
        let clean = ChildEnvironment.sanitized(env)
        #expect(clean == ["PATH": "/usr/bin", "HOME": "/Users/x", "ANTHROPIC_MODEL": "m"])
        #expect(ChildEnvironment.current.keys.allSatisfy { !ChildEnvironment.removedKeys.contains($0) })
    }

    @Test func terminalProfiliKabukBaslangicDosyalariniVeIkiliYollariniYazmayaKapatir() throws {
        let t = try setup()
        let home = try tempDir("ev")
        let iso = BrandIsolation(workspace: t.ws, folders: t.isolation.folders, home: home)
        let p = try iso.terminalProfile(brandId: t.a.id)
        func h(_ rel: String) -> String { SandboxProfile.canonical(home.appendingPathComponent(rel).path) }
        #expect(p.writeProtectedFiles.contains(h(".zshenv")))
        #expect(p.writeProtectedFiles.contains(h(".gitconfig")))
        #expect(p.writeProtectedFiles.contains(h(".claude/settings.json")))
        #expect(p.writeProtectedFiles.contains(h(".codex/config.toml")))
        #expect(p.writeProtected.contains(h(".config")))
        #expect(p.writeProtected.contains(h(".claude/hooks")))
        #expect(p.writeProtected.contains("/opt/homebrew/bin"))
        // Kabuk geçmişi ve oturum kayıtları yazılabilir kalır (kabuk bozulmasın).
        #expect(!p.writeProtectedFiles.contains(h(".zsh_history")))
        #expect(!p.writeProtected.contains(h(".claude/sessions")))
        #expect(p.hardenLaunch)
    }

    @Test func gercekSandboxTerminalYapilandirmaYazmasiniKapatirGecmisiAcikBirakir() throws {
        let t = try setup()
        let home = try tempDir("ev")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/hooks"), withIntermediateDirectories: true)
        let iso = BrandIsolation(workspace: t.ws, folders: t.isolation.folders, home: home)
        let profile = try iso.terminalProfile(brandId: t.a.id).render()
        func w(_ rel: String) throws -> Int32 {
            try run(profile, "echo yuk > \(shellQuote(home.appendingPathComponent(rel).path))").status
        }
        #expect(try w(".zshenv") != 0)
        #expect(try w(".gitconfig") != 0)
        #expect(try w(".claude/settings.json") != 0)
        #expect(try w(".claude/hooks/x.sh") != 0)
        #expect(try w(".codex/config.toml") != 0)
        // Kabuk geçmişi yazılabilir (kabuk bozulmasın).
        #expect(try w(".zsh_history") == 0)
    }

    @Test func profilSertlestirmesiLaunchServicesVeSoketKoprusuKurallariIcerir() throws {
        let t = try setup()
        let text = try t.isolation.terminalProfile(brandId: t.a.id).render()
        #expect(text.contains("com.apple.coreservices.launchservicesd"))
        #expect(text.contains("(deny appleevent-send)"))
        #expect(text.contains("com.apple.WorkflowKit"))
        #expect(text.contains("(deny network-outbound (remote unix-socket"))
        // ssh-agent (launchd Listeners) istisnası: git push (ssh) bozulmasın.
        #expect(text.contains("launchd\\.[A-Za-z0-9]+/Listeners$"))
        // Codex profili de aynı sertleştirmeyi taşır.
        let codex = try t.isolation.codexProfile(scope: .brand(t.a.id), codexBinary: URL(fileURLWithPath: "/usr/local/bin/codex")).render()
        #expect(codex.contains("com.apple.coreservices.launchservicesd"))
        #expect(codex.contains("(deny network-outbound (remote unix-socket"))
    }

    @Test func codexProfiliKullanicininKabukGecmisiniOkumayaKapatir() throws {
        let t = try setup()
        let home = try tempDir("ev")
        let iso = BrandIsolation(workspace: t.ws, folders: t.isolation.folders, home: home)
        let p = try iso.codexProfile(scope: .brand(t.a.id), codexBinary: URL(fileURLWithPath: "/usr/local/bin/codex"))
        func h(_ rel: String) -> String { SandboxProfile.canonical(home.appendingPathComponent(rel).path) }
        #expect(p.denied.contains(h(".zsh_history")))
        #expect(p.denied.contains(h(".bash_history")))
        #expect(p.denied.contains(h(".zsh_sessions")))
    }

    @Test func denetimProfiliMarkaKlasorleriniVeVeriAlaniniKapatirGirisiAcikBirakir() throws {
        let t = try setup()
        let home = try tempDir("ev")
        let iso = BrandIsolation(workspace: t.ws, folders: t.isolation.folders, home: home)
        let p = try iso.controlProfile()
        #expect(p.denied.contains(SandboxProfile.canonical(t.root.path)))
        #expect(p.denied.contains(SandboxProfile.canonical(t.ws.path)))
        #expect(p.denied.contains(SandboxProfile.canonical(home.appendingPathComponent(".claude").path)))
        // Kullanıcının ~/.codex'i (giriş/hesap) yasak değil; yazma kısıtı yok (belirteç yenilemesi).
        #expect(!p.denied.contains(SandboxProfile.canonical(iso.userCodexHome.path)))
        #expect(p.writable == nil)
        // ChatGPT girişi tarayıcı açar: LaunchServices kapatılmaz.
        #expect(!p.hardenLaunch)
    }

    @Test func gercekSandboxDenetimProfiliBaskaMarkayiKapatir() throws {
        let t = try setup()
        let otherDir = try t.isolation.folders.folder(for: .brand(t.b.id))
        try "GIZLI-B".write(to: otherDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let profile = try t.isolation.controlProfile().render()
        let r = try run(profile, "cat \(shellQuote(otherDir.appendingPathComponent("b.txt").path))")
        #expect(r.status != 0 && !r.stdout.contains("GIZLI-B"))
        #expect(try run(profile, "ls \(shellQuote(t.ws.path))").status != 0)
    }

    @Test func sembolikBagIceAktarilamazVeMarkaDisiYolReddedilir() throws {
        let base = try tempDir("import")
        let a = base.appendingPathComponent("A", isDirectory: true)
        let b = base.appendingPathComponent("B", isDirectory: true)
        for d in [a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        let secret = b.appendingPathComponent("gizli.txt")
        try "GIZLI-B".write(to: secret, atomically: true, encoding: .utf8)
        let real = a.appendingPathComponent("gercek.txt")
        try "ACIK-A".write(to: real, atomically: true, encoding: .utf8)
        // Dosya sembolik bağı reddedilir.
        let link = a.appendingPathComponent("bag.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        #expect(throws: MarkaError.self) { try FileImportGuard.canonicalRegularFile(at: link, confineTo: a) }
        // Marka klasörü dışını gösteren gerçek yol reddedilir.
        #expect(throws: MarkaError.self) { try FileImportGuard.canonicalRegularFile(at: secret, confineTo: a) }
        // Gerçek, klasör içindeki dosya kabul edilir ve bağ izlemeden okunur.
        let ok = try FileImportGuard.canonicalRegularFile(at: real, confineTo: a)
        #expect(try FileImportGuard.readNoFollow(ok) == Data("ACIK-A".utf8))
        // Ara klasör başka markaya bağlıysa realpath dışarı çıkar ve yakalanır.
        let dirLink = a.appendingPathComponent("Bdir")
        try FileManager.default.createSymbolicLink(at: dirLink, withDestinationURL: b)
        #expect(throws: MarkaError.self) { try FileImportGuard.canonicalRegularFile(at: dirLink.appendingPathComponent("gizli.txt"), confineTo: a) }
    }

    @Test func klasorGoruntusuSembolikBaglariAtlar() throws {
        let t = try setup()
        let dir = try t.isolation.folders.folder(for: .brand(t.a.id))
        let other = try t.isolation.folders.folder(for: .brand(t.b.id))
        try "GIZLI-B".write(to: other.appendingPathComponent("gizli.txt"), atomically: true, encoding: .utf8)
        try "ACIK".write(to: dir.appendingPathComponent("ciktilar/gercek.txt"), atomically: true, encoding: .utf8)
        // Dosya bağı ve klasör bağı: ikisi de görüntüye girmez.
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("ciktilar/bag.txt"), withDestinationURL: other.appendingPathComponent("gizli.txt"))
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("ciktilar/Bdir"), withDestinationURL: other)
        #expect(Set(t.isolation.folders.snapshot(dir).keys) == ["ciktilar/gercek.txt"])
        // İçe aktarılabilir dosyalarda B'nin içeriği yok.
        let importable = try t.isolation.folders.importableFiles(brandId: t.a.id).map(\.lastPathComponent)
        #expect(importable == ["gercek.txt"])
    }

    @Test func tumMarkalarAdiMarkaKlasoruOlamaz() throws {
        let t = try setup()
        let clash = try t.store.createBrand(name: BrandFolders.allBrandsFolderName)
        let clashFolder = SandboxProfile.canonical(try t.isolation.folders.folder(for: .brand(clash.id)).path)
        let allFolder = SandboxProfile.canonical(try t.isolation.folders.folder(for: .allBrands).path)
        #expect(clashFolder != allFolder)
        #expect((clashFolder as NSString).lastPathComponent != BrandFolders.allBrandsFolderName)
    }

    @Test func yalitimsizCodexSureciTurCalistirmaz() async throws {
        let server = CodexAppServer()
        await #expect(throws: MarkaError.self) { _ = try await server.startTurn(threadId: "t", text: "x") }
        await #expect(throws: MarkaError.self) {
            _ = try await server.startThread(cwd: URL(fileURLWithPath: "/tmp"), model: "m", developerInstructions: "", tools: [])
        }
        await #expect(throws: MarkaError.self) {
            _ = try await server.completeJSON(cwd: URL(fileURLWithPath: "/tmp"), model: "m", instructions: "", prompt: "", schema: .object([:]))
        }
    }
}
