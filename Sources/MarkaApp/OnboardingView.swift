import AppKit
import MarkaCore
import SwiftUI

/// İlk açılış: tek ekran (plan §4). Kısa başlık, tek cümle, "Marka adı", *Başla*. Pencerenin tamamını kaplar (sayfa değil).
/// Eski görev listesi içe aktarımı buradan kalktı; Ayarlar › Veri'de.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 40)).foregroundStyle(Design.accent)
                    .accessibilityHidden(true)
                Text(L("Workspace AI'a hoş geldin")).font(.system(size: 26, weight: .bold)).tracking(-0.5)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                Text(L("Bir markaya bakınca ne yapıldığını, ne beklediğini ve müşteriye ne gideceğini gör."))
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 18) {
                point("sparkles", L("Asistana sor"), L("Yapay zekâ markanın görev, not ve dosyalarını okur; ne yapman gerektiğini söyler ve görev önerir."))
                point("checkmark.seal", L("Burada onayla"), L("Asistanın önerdiği işler seni bekler. Onaylamadığın hiçbir şey kayda girmez."))
                point("doc.text", L("Müşteriye raporla"), L("Haftalık rapor, doğrulanmış işlerden tek tıkla PDF olur."))
                point("lock", L("Verin sende kalır"), L("Her şey bu Mac'te durur. Yapay zekâ yalnızca senin izin verdiğin yerde çalışır."))
            }
            VStack(spacing: 12) {
                InputField(title: L("İlk markanın adı"), text: $name, focus: $focused)
                    .onSubmit(start).onAppear { DispatchQueue.main.async { focused = true } }
                Button(action: start) { Text(L("Başla")).frame(maxWidth: .infinity) }
                    .actionPrimary().keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 440)
        .padding(Design.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.windowBackground)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Design.accent).frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    func start() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let created = app.perform({ try app.store?.createBrand(name: name) }), let brand = created else { return }
        try? app.store?.setSetting("onboarded", ISO8601DateFormatter().string(from: Date()))
        app.reloadBasics()
        app.select(brand: brand.id, tab: .flow)
        app.showOnboarding = false
        app.showNewBrand = false
    }
}

/// joi-todo (cli-todo-for-agentic) aktarımı: salt okunur, eşleme kullanıcıda, tekrar çalıştırılabilir. Ayarlar › Veri ›
/// İçe aktarım bölümünde yerinde açılır. Liste denetimi yok (düz satırlar).
struct JoiImportView: View {
    @Environment(AppModel.self) private var app
    @State private var analysis: JoiTodoImporter.Analysis?
    @State private var targets: [String: String] = [:] // proje → marka adı ("" = atla)
    @State private var result: JoiTodoImporter.Result?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Text(L("Eski görev listesinin görevleri, son tarihleri, durumları ve süre kayıtları aktarılır. Eski listenin dosyaları yalnızca okunur; aynı aktarımı tekrar çalıştırmak kopya oluşturmaz."))
                .captionStyle().fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).foregroundStyle(Design.danger).fixedSize(horizontal: false, vertical: true) }
            if let analysis {
                Text(summary(analysis)).captionStyle().fixedSize(horizontal: false, vertical: true)
                Text(L("Her projenin hangi markaya aktarılacağını yaz. Boş bırakılan proje aktarılmaz; aynı adı birden fazla projeye yazarak birleştirebilirsin."))
                    .captionStyle().fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(analysis.projects) { p in
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                            VStack(alignment: .leading, spacing: Design.Space.xs) {
                                Text(verbatim: p.project.isEmpty ? L("(projesiz)") : "+\(p.project)")
                                Text(LF("%1$d açık · %2$d biten · %3$@", p.openCount, p.doneCount, DurationFormat.short(p.seconds)) + (p.categoryName.map { " · \($0)" } ?? ""))
                                    .captionStyle()
                            }
                            Spacer()
                            InputField(title: L("Marka adı (boş = aktarılmaz)"), text: Binding(get: { targets[p.project] ?? "" }, set: { targets[p.project] = $0 }))
                                .frame(width: 220)
                        }
                        .padding(.vertical, Design.Space.s)
                        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
                    }
                }
                if let result {
                    Text(LF("%1$d görev ve %2$d süre kaydı aktarıldı, %3$d marka oluşturuldu. Daha önce aktarılmış %4$d görev atlandı.",
                            result.importedTasks, result.importedTimeEntries, result.createdBrands, result.skippedExistingTasks))
                        .captionStyle()
                }
            }
            HStack(spacing: Design.Space.m) {
                Button(analysis == nil ? L("Veri klasörünü seç…") : L("Başka klasör seç…")) { choose() }
                    .buttonStyle(.text)
                Spacer()
                if let analysis {
                    Button(L("Aktar")) { run(analysis) }.buttonStyle(.borderedProminent)
                        .disabled(!targets.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            if analysis == nil, let dir = JoiTodoImporter.candidateDirectories().first { load(dir) }
        }
    }

    private func summary(_ a: JoiTodoImporter.Analysis) -> String {
        var parts = [LF("%d görev", a.tasks.count), LF("%d süre kaydı", a.stops.count), LF("toplam %@", DurationFormat.short(a.totalSeconds))]
        if a.statusDoneConflicts > 0 { parts.append(LF("%d tutarsız durum (status esas alınır)", a.statusDoneConflicts)) }
        if !a.suspiciousTimeTasks.isEmpty {
            parts.append(LF("%d görevde 12 saati aşan süre var (açık unutulmuş sayaç olabilir; aktarım sonrası kontrol et)", a.suspiciousTimeTasks.count))
        }
        if a.malformedEventLines > 0 { parts.append(LF("%d bozuk olay satırı atlandı", a.malformedEventLines)) }
        return parts.joined(separator: " · ")
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = L("tasks.json dosyasını içeren klasörü seç (ör. ~/.joi-todo)")
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ dir: URL) {
        do {
            let a = try JoiTodoImporter().analyze(directory: dir)
            analysis = a
            error = nil
            targets = Dictionary(uniqueKeysWithValues: a.projects.map { ($0.project, $0.suggestedBrand ?? "") })
        } catch {
            app.diagnostics.record(error, context: "iceaktarim.joi.analiz")
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func run(_ analysis: JoiTodoImporter.Analysis) {
        guard let store = app.store else { return }
        var mapping: [String: JoiTodoImporter.Target] = [:]
        for p in analysis.projects {
            let name = (targets[p.project] ?? "").trimmingCharacters(in: .whitespaces)
            if name.isEmpty { mapping[p.project] = .skip; continue }
            if let existing = app.brands.first(where: { $0.name.lowercased(with: Locale(identifier: "tr_TR")) == name.lowercased(with: Locale(identifier: "tr_TR")) }) {
                mapping[p.project] = .existingBrand(existing.id)
            } else {
                mapping[p.project] = .newBrand(name)
            }
        }
        let snapshot = app.workspaceURL.appendingPathComponent("İçe aktarımlar/joi-todo \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "."))")
        result = app.perform(title: L("İçe aktarım başarısız"), context: "iceaktarim.joi") { try JoiTodoImporter().run(analysis, mapping: mapping, store: store, snapshotDirectory: snapshot) }
        if result != nil {
            try? store.setSetting("onboarded", ISO8601DateFormatter().string(from: Date()))
            app.reloadBasics()
        }
    }
}
