import Foundation

/// OpenAI Codex App Server istemcisi: kullanıcının kurulu `codex` aracını `codex app-server` olarak başlatır,
/// satır sonlu JSON-RPC ile konuşur. Oturum açma Codex'in kendi akışıyla yapılır; uygulama belirteç saklamaz.
/// Not: App Server OpenAI tarafından "experimental" olarak işaretlidir.
///
/// Marka yalıtımı: `isolation` verilirse süreç bizim seatbelt profilimizle (`sandbox-exec`) başlar. İç içe sandbox
/// macOS'ta çalışmadığı için Codex'in kendi sandbox'ı o zaman kapatılır (`danger-full-access`); okuma ve yazma sınırını
/// dış profil koyar. Profilin tuttuğu ölçülemezse süreç başlatılmaz (kapalı kalır).
public actor CodexAppServer {
    public enum State: Sendable, Equatable { case stopped, starting, ready, failed(String) }

    public struct Account: Sendable, Equatable {
        public var type: String
        public var email: String?
        public var planType: String?
    }

    public struct ModelInfo: Sendable, Hashable, Identifiable {
        public var id: String
        public var displayName: String
        public var isDefault: Bool
    }

    /// Yalıtımlı başlatma bilgisi: profil, kapsamın Codex ev dizini ve profilin tuttuğunu ölçmek için yasaklı bir dosya.
    public struct Isolation: Sendable {
        public var profile: SandboxProfile
        public var codexHome: URL
        /// Kullanıcının kendi Codex ev dizini; giriş dosyası (`auth.json`) buradan bağlanır.
        public var userCodexHome: URL
        /// Profilin okumayı gerçekten kapattığını ölçmek için yasaklı alanda oluşturulan dosya.
        public var probeFile: URL
        public init(profile: SandboxProfile, codexHome: URL, userCodexHome: URL, probeFile: URL) {
            self.profile = profile; self.codexHome = codexHome; self.userCodexHome = userCodexHome; self.probeFile = probeFile
        }
    }

    public private(set) var state: State = .stopped
    /// Dış profil ölçülerek uygulandıysa `true`; Codex'in iç sandbox'ı yalnızca o zaman kapatılır.
    public private(set) var isolated = false
    private let isolationProvider: (@Sendable (URL) throws -> Isolation)?
    /// `false`: süreç profil altında başlar ama tur çalıştırmaz (denetim süreci: hesap/giriş/model listesi). Kullanıcının
    /// `codex` ikilisi kurcalanmış olsa bile marka klasörleri OS düzeyinde kapalıdır; profil uygulanamazsa yalıtımsız başlar.
    private let controlOnly: Bool
    private var resumed = Set<String>()
    private var process: Process?
    private var stdin: FileHandle?
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var threadHandlers: [String: @Sendable (JSONValue) async -> Void] = [:]
    private var requestHandlers: [String: @Sendable (String, JSONValue) async -> JSONValue] = [:]
    private var globalHandler: (@Sendable (String, JSONValue) -> Void)?
    private var readerTask: Task<Void, Never>?
    private var startTask: Task<Void, Error>?
    public let clientVersion: String

    /// - Parameter isolation: Codex ikilisinin yoluyla başlatma anında çağrılır (sonradan eklenen marka klasörleri de girsin).
    ///   `nil` ise yalıtımsız başlar: yalnızca hesap, giriş ve model listesi içindir; tur çalıştırılmaz.
    ///   `controlOnly` verildiğinde profil altında başlar ama tur çalıştırmaz (denetim süreci).
    public init(clientVersion: String = MarkaCoreVersion.string, isolation: (@Sendable (URL) throws -> Isolation)? = nil,
                controlOnly: Bool = false) {
        self.clientVersion = clientVersion
        self.isolationProvider = isolation
        self.controlOnly = controlOnly
    }

    // MARK: Bulma

    public static func locateBinary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) { return found }
        // Kullanıcının etkileşimli kabuk PATH'i (ör. fnm/nvm ile kurulum).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "command -v codex"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        } catch {}
        return nil
    }

    // MARK: Yaşam döngüsü

    public func start() async throws {
        if state == .ready { return }
        // Eşzamanlı çağrılar tek süreç başlatır.
        if let startTask { return try await startTask.value }
        let task = Task { try await self.launch() }
        startTask = task
        defer { startTask = nil }
        try await task.value
    }

    private func launch() async throws {
        // Ölmüş sürecin borusuna yazmak uygulamayı SIGPIPE ile kapatmasın.
        signal(SIGPIPE, SIG_IGN)
        guard let binary = Self.locateBinary() else {
            state = .failed(L("codex bulunamadı"))
            throw MarkaError.ai(L("Codex CLI bulunamadı. Codex'i kurduktan sonra tekrar dene (Ayarlar › AI)."))
        }
        state = .starting
        isolated = false
        resumed.removeAll()
        let p = Process()
        var env = ChildEnvironment.current
        env["PATH"] = [binary.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", env["PATH"] ?? ""].joined(separator: ":")
        if let isolationProvider {
            let iso: Isolation
            let profileText: String
            do {
                iso = try isolationProvider(binary)
                // Denetim süreci kullanıcının kendi ~/.codex'ini kullanır: ev dizinini yeniden kurma (symlink/tmp) yapılmaz,
                // yalnızca ölçüm için yasaklı sınama dosyası yazılır.
                if controlOnly { try Self.writeProbe(iso) } else { try Self.prepareHome(iso) }
                profileText = iso.profile.render()
            } catch {
                state = .failed(L("marka yalıtımı kurulamadı"))
                throw error
            }
            // Profil gerçekten uygulanıyor ve yasaklı dosyayı kapatıyor mu? Ölçülmeden Codex'in iç sandbox'ı kapatılmaz.
            let applied = SandboxRunner.verify(profile: profileText, deniedFile: iso.probeFile, marker: Self.probeMarker)
            if applied {
                p.executableURL = SandboxRunner.executable
                p.arguments = ["-p", profileText, binary.path, "app-server"]
                if !controlOnly {
                    env["CODEX_HOME"] = iso.codexHome.path
                    env["TMPDIR"] = iso.codexHome.appendingPathComponent("tmp", isDirectory: true).path + "/"
                    isolated = true
                }
            } else if controlOnly {
                // Denetim süreci giriş/hesap için her zaman çalışabilmeli; profil uygulanamazsa (ör. iç içe sandbox)
                // yalıtımsız başlar. Tur çalıştırmadığı için marka verisi zaten okunmaz; bu bir sızıntı değildir.
                p.executableURL = binary
                p.arguments = ["app-server"]
            } else {
                state = .failed(L("marka yalıtımı uygulanamadı"))
                throw MarkaError.ai(L("Marka yalıtımı bu Mac'te uygulanamadı (sandbox-exec). Markalar arası okuma açık kalmasın diye Codex başlatılmadı."))
            }
        } else {
            p.executableURL = binary
            p.arguments = ["app-server"]
        }
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        let pid = ObjectIdentifier(p)
        p.terminationHandler = { [weak self] proc in
            Task { await self?.handleTermination(code: proc.terminationStatus, process: pid) }
        }
        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
        // Okuma dispatch'in okunabilirlik bildirimiyle yapılır; `FileHandle.bytes` eşzamanlı `read` ile ortak iş parçacığı
        // havuzunu bloklar ve birden çok (marka başına) Codex süreci açıkken yanıtlar hiç işlenmeyebilir (ölçüldü: askıda kaldı).
        let handle = outPipe.fileHandleForReading
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        let splitter = LineSplitter()
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                for line in splitter.flush() { continuation.yield(line) }
                continuation.finish()
                return
            }
            for line in splitter.append(data) { continuation.yield(line) }
        }
        readerTask = Task { [weak self] in
            for await line in lines {
                guard let self else { return }
                await self.handleLine(line)
            }
        }
        _ = try await request("initialize", [
            "clientInfo": ["name": "marka_calisma_alani", "title": "Marka Çalışma Alanı", "version": .string(clientVersion)],
            "capabilities": ["experimentalApi": true],
        ])
        try notify("initialized", nil)
        state = .ready
    }

    static let probeMarker = "MARKA-YALITIM-SINAMASI"

    /// Kapsamın Codex ev dizini: oturum kayıtları burada kalır, markalar arasında paylaşılmaz. Giriş dosyası kullanıcının
    /// Codex dizinine sembolik bağla bağlanır. config.toml bağlanmaz: içindeki proje yolları başka markaların adlarını taşır.
    static func prepareHome(_ iso: Isolation) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: iso.codexHome.appendingPathComponent("tmp", isDirectory: true), withIntermediateDirectories: true)
        let link = iso.codexHome.appendingPathComponent("auth.json")
        let target = iso.userCodexHome.appendingPathComponent("auth.json")
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != target.path {
            // Yerinde düz dosya ya da başka yere giden bağ varsa kaldırılır; tek giriş kaynağı kullanıcının Codex dizinidir.
            if fm.fileExists(atPath: link.path) || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try fm.removeItem(at: link)
            }
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        }
        try writeProbe(iso)
    }

    /// Profilin okumayı gerçekten kapattığını ölçmek için yasaklı alandaki sınama dosyasını yazar (uygulama veri alanında).
    static func writeProbe(_ iso: Isolation) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: iso.probeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((probeMarker + "\n").utf8).write(to: iso.probeFile)
    }

    /// İş parçacığı bu süreçte başlatılmadı ya da devam ettirilmediyse `true` (süreç yeniden başlayınca sıfırlanır).
    public func needsResume(_ threadId: String) -> Bool { !resumed.contains(threadId) }

    public func stop() async {
        let p = process
        process = nil
        stdin = nil
        readerTask?.cancel()
        state = .stopped
        p?.terminate()
        await failInFlight(message: L("Codex durduruldu."))
    }

    private func handleTermination(code: Int32, process terminated: ObjectIdentifier) async {
        // Yeniden başlatılmış yeni süreci eski sürecin gecikmeli bildirimi bozmasın.
        guard let current = process, ObjectIdentifier(current) == terminated else { return }
        process = nil
        stdin = nil
        if state != .stopped { state = .failed(LF("Codex süreci kapandı (%d)", Int(code))) }
        await failInFlight(message: L("Codex süreci beklenmedik şekilde kapandı."))
    }

    /// Bekleyen istekleri ve süren turları hata ile sonlandırır (asılı kalmasın).
    private func failInFlight(message: String) async {
        for (_, c) in pending { c.resume(throwing: MarkaError.ai(message)) }
        pending.removeAll()
        let handlers = threadHandlers
        for (threadId, h) in handlers {
            await h(["method": "turn/completed", "params": ["threadId": .string(threadId),
                     "turn": ["status": "failed", "error": ["message": .string(message)]]]])
        }
    }

    public func onGlobalNotification(_ handler: @escaping @Sendable (String, JSONValue) -> Void) {
        globalHandler = handler
    }

    // MARK: JSON-RPC

    private func send(_ message: JSONValue) throws {
        guard let stdin, process?.isRunning == true else { throw MarkaError.ai(L("Codex çalışmıyor.")) }
        var data = try message.data()
        data.append(0x0A)
        try stdin.write(contentsOf: data)
    }

    public func request(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        let id = nextId
        nextId += 1
        var msg: [String: JSONValue] = ["id": .number(Double(id)), "method": .string(method)]
        if let params { msg["params"] = params }
        return try await withCheckedThrowingContinuation { c in
            pending[id] = c
            do { try send(.object(msg)) } catch {
                pending[id] = nil
                c.resume(throwing: error)
            }
        }
    }

    func notify(_ method: String, _ params: JSONValue?) throws {
        var msg: [String: JSONValue] = ["method": .string(method)]
        if let params { msg["params"] = params }
        try send(.object(msg))
    }

    private func handleLine(_ line: String) async {
        guard let msg = try? JSONValue.parse(line) else { return }
        // Yön `method` alanından anlaşılır: sunucu istek kimlikleri istemcininkilerle çakışabilir.
        if let method = msg["method"]?.string {
            let params = msg["params"] ?? .null
            if let rawId = msg["id"] {
                // Onay kullanıcıyı bekleyebilir; okuma döngüsü (ve turn/interrupt yanıtı) bloklanmasın.
                Task { await self.handleServerRequest(id: rawId, method: method, params: params) }
            } else {
                globalHandler?(method, params)
                if let threadId = params["threadId"]?.string ?? params["thread"]?["id"]?.string,
                   let h = threadHandlers[threadId] {
                    await h(.object(["method": .string(method), "params": params]))
                }
            }
            return
        }
        guard let id = msg["id"]?.int, let c = pending.removeValue(forKey: id) else { return }
        if let err = msg["error"] {
            c.resume(throwing: MarkaError.ai(err["message"]?.string ?? L("Codex hatası")))
        } else {
            c.resume(returning: msg["result"] ?? .null)
        }
    }

    private func handleServerRequest(id: JSONValue, method: String, params: JSONValue) async {
        let threadId = params["threadId"]?.string ?? ""
        var result: JSONValue = ["decision": "decline"]
        if let h = requestHandlers[threadId] {
            result = await h(method, params)
        } else if method == "item/tool/call" {
            result = ["success": false, "contentItems": [["type": "inputText", "text": "Bu oturum için araç yürütücüsü yok."]]]
        }
        try? send(.object(["id": id, "result": result]))
    }

    // MARK: Hesap ve modeller

    public func account() async throws -> Account? {
        let r = try await request("account/read", ["refreshToken": false])
        guard let a = r["account"], let type = a["type"]?.string else { return nil }
        return Account(type: type, email: a["email"]?.string, planType: a["planType"]?.string)
    }

    /// ChatGPT ile oturum açma: tarayıcıda açılacak adresi döndürür; sonuç `account/login/completed` bildirimiyle gelir.
    public func startChatGPTLogin() async throws -> URL {
        let r = try await request("account/login/start", ["type": "chatgpt"])
        guard let s = r["authUrl"]?.string, let url = URL(string: s) else { throw MarkaError.ai(L("Codex giriş adresi alınamadı.")) }
        return url
    }

    public func logout() async throws { _ = try await request("account/logout", nil) }

    public func models() async throws -> [ModelInfo] {
        let r = try await request("model/list", .object([:]))
        return (r["data"]?.array ?? []).compactMap { m in
            guard let id = m["id"]?.string ?? m["model"]?.string, m["hidden"]?.bool != true else { return nil }
            return ModelInfo(id: m["model"]?.string ?? id, displayName: m["displayName"]?.string ?? id, isDefault: m["isDefault"]?.bool ?? false)
        }
    }

    // MARK: İş parçacıkları

    public func register(threadId: String, notifications: @escaping @Sendable (JSONValue) async -> Void,
                         requests: @escaping @Sendable (String, JSONValue) async -> JSONValue) {
        threadHandlers[threadId] = notifications
        requestHandlers[threadId] = requests
    }

    public func unregister(threadId: String) {
        threadHandlers[threadId] = nil
        requestHandlers[threadId] = nil
    }

    /// Tur yalnızca dış profil ölçülerek uygulanmış süreçte çalışır. Yalıtımsız süreç (hesap/giriş/model listesi) model
    /// komutu çalıştıramaz; Codex'in kendi sandbox'ı okumayı sınırlamadığı için markalar arası okuma açık kalırdı.
    private func requireIsolation() throws {
        guard isolated else { throw MarkaError.ai(L("Codex turu yalnızca marka yalıtımıyla başlatılmış süreçte çalışır.")) }
    }

    /// Codex'in iç sandbox'ı kapalıdır (sınırı dış profil koyar; iç içe seatbelt çalışmaz) ve onay istenmez:
    /// dış profilin reddi onayla aşılamaz, onay kartı yanıltıcı olurdu. Klasör dışına yazma kesin redle kapanır.
    static let sandboxMode: JSONValue = "danger-full-access"
    static let approvalPolicy: JSONValue = "never"
    static let sandboxPolicy: JSONValue = ["type": "dangerFullAccess"]

    public func startThread(cwd: URL, model: String, developerInstructions: String, tools: [ToolSpec]) async throws -> String {
        try requireIsolation()
        let r = try await request("thread/start", [
            "cwd": .string(cwd.path),
            "model": .string(model),
            "sandbox": Self.sandboxMode,
            "approvalPolicy": Self.approvalPolicy,
            "developerInstructions": .string(developerInstructions),
            "serviceName": "Marka Çalışma Alanı",
            "dynamicTools": .array(tools.map { ["type": "function", "name": .string($0.name), "description": .string($0.description), "inputSchema": $0.schema] }),
        ])
        guard let id = r["thread"]?["id"]?.string else { throw MarkaError.ai(L("Codex oturumu başlatılamadı.")) }
        resumed.insert(id)
        return id
    }

    public func resumeThread(_ threadId: String, cwd: URL, developerInstructions: String) async throws {
        try requireIsolation()
        _ = try await request("thread/resume", [
            "threadId": .string(threadId), "cwd": .string(cwd.path), "developerInstructions": .string(developerInstructions),
            "sandbox": Self.sandboxMode, "approvalPolicy": Self.approvalPolicy, "excludeTurns": true,
        ])
        resumed.insert(threadId)
    }

    public func startTurn(threadId: String, text: String) async throws -> String {
        try requireIsolation()
        let r = try await request("turn/start", ["threadId": .string(threadId), "input": [["type": "text", "text": .string(text)]],
                                                 "sandboxPolicy": Self.sandboxPolicy, "approvalPolicy": Self.approvalPolicy])
        return r["turn"]?["id"]?.string ?? ""
    }

    public func interrupt(threadId: String, turnId: String) async throws {
        _ = try await request("turn/interrupt", ["threadId": .string(threadId), "turnId": .string(turnId)])
    }

    /// Yapılandırılmış çıktı: kısa ömürlü (kaydedilmeyen) iş parçacığında tek tur. Komut gerekmez; iç sandbox "read-only"
    /// istenir, dış profil altında iç seatbelt kurulamadığı için olası bir komut çalışmadan başarısız olur.
    public func completeJSON(cwd: URL, model: String, instructions: String, prompt: String, schema: JSONValue) async throws -> (JSONValue, Int, Int) {
        try requireIsolation()
        let r = try await request("thread/start", [
            "cwd": .string(cwd.path), "model": .string(model), "sandbox": "read-only", "approvalPolicy": "never",
            "developerInstructions": .string(instructions), "ephemeral": true,
        ])
        guard let threadId = r["thread"]?["id"]?.string else { throw MarkaError.ai(L("Codex oturumu başlatılamadı.")) }
        let collector = TurnCollector()
        register(threadId: threadId, notifications: { await collector.handle($0) }, requests: { _, _ in ["decision": "decline"] })
        defer { unregister(threadId: threadId) }
        _ = try await request("turn/start", ["threadId": .string(threadId), "input": [["type": "text", "text": .string(prompt)]], "outputSchema": schema])
        let (text, input, output, error) = await collector.wait()
        if let error { throw MarkaError.ai(error) }
        guard let json = try? JSONValue.parse(text) else { throw MarkaError.ai(L("Codex geçerli JSON döndürmedi.")) }
        return (json, input, output)
    }
}

/// Gelen baytları satırlara böler (satır sonu `\n`); yarım satır bir sonraki parçayı bekler.
final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var out: [String] = []
        while let i = buffer.firstIndex(of: 0x0A) {
            out.append(String(decoding: buffer[buffer.startIndex..<i], as: UTF8.self))
            buffer = Data(buffer[buffer.index(after: i)...])
        }
        return out
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !buffer.isEmpty else { return [] }
        defer { buffer = Data() }
        return [String(decoding: buffer, as: UTF8.self)]
    }
}

/// Tek bir turun metnini ve bitişini toplar.
actor TurnCollector {
    private var text = ""
    private var input = 0, output = 0
    private var error: String?
    private var done = false
    private var waiters: [CheckedContinuation<(String, Int, Int, String?), Never>] = []

    func handle(_ note: JSONValue) {
        let method = note["method"]?.string ?? ""
        let params = note["params"] ?? .null
        switch method {
        case "item/completed":
            if params["item"]?["type"]?.string == "agentMessage" { text = params["item"]?["text"]?.string ?? text }
        case "thread/tokenUsage/updated":
            input = params["tokenUsage"]?["last"]?["inputTokens"]?.int ?? input
            output = params["tokenUsage"]?["last"]?["outputTokens"]?.int ?? output
        case "turn/completed":
            if params["turn"]?["status"]?.string == "failed" { error = params["turn"]?["error"]?["message"]?.string ?? "Codex turu başarısız" }
            done = true
            for w in waiters { w.resume(returning: (text, input, output, error)) }
            waiters.removeAll()
        default: break
        }
    }

    func wait() async -> (String, Int, Int, String?) {
        if done { return (text, input, output, error) }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
