import Foundation
import Testing
@testable import MarkaCore

/// D1: deneme veri alanı gerçek tercihleri ve Keychain kaydını paylaşmaz. Keychain'e yazan/silen test yoktur; hesap adı
/// hesaplaması saf fonksiyonla sınanır.
@Suite struct TercihYalitimTests {
    let varsayilan = URL(fileURLWithPath: "/Users/ornek/Library/Application Support/MarkaCalismaAlani", isDirectory: true)

    @Test func varsayilanVeriAlaniGercekTercihleriVeGercekAnahtarHesabiniKullanir() {
        let scope = PreferenceScope.resolve(workspace: varsayilan, defaultWorkspace: varsayilan, snapshot: false)
        #expect(scope == .standard)
        #expect(scope.suiteName == nil)
        #expect(scope.persistsPreferences)
        #expect(scope.keychainAccount(ChatEngine.anthropicKeyAccount) == "anthropic-api-key")
        // Sondaki "/" ve "." bileşenleri aynı yolu farklı alan saydırmaz.
        let ayniYol = URL(fileURLWithPath: varsayilan.path + "/./", isDirectory: true)
        #expect(PreferenceScope.resolve(workspace: ayniYol, defaultWorkspace: varsayilan, snapshot: false) == .standard)
    }

    @Test func ozelVeriAlaniAyriTercihTakimiVeAyriAnahtarHesabiKullanir() throws {
        let deneme = URL(fileURLWithPath: "/Users/ornek/Desktop/marka-test/ws", isDirectory: true)
        let scope = PreferenceScope.resolve(workspace: deneme, defaultWorkspace: varsayilan, snapshot: false)
        #expect(scope.kind == .trial)
        #expect(scope.persistsPreferences)
        let suite = try #require(scope.suiteName)
        #expect(suite != PreferenceScope.appDomain)
        #expect(suite.hasPrefix(PreferenceScope.appDomain + ".deneme."))
        #expect(!suite.contains("marka-test"), "tercih takımı adı yolu açık etmemeli")
        let hesap = scope.keychainAccount(ChatEngine.anthropicKeyAccount)
        #expect(hesap != ChatEngine.anthropicKeyAccount)
        #expect(hesap.hasPrefix(ChatEngine.anthropicKeyAccount + ".deneme."))
        // Kararlı: aynı yol her açılışta aynı ada gider; farklı yol farklı ada.
        let tekrar = PreferenceScope.resolve(workspace: URL(fileURLWithPath: deneme.path + "/"), defaultWorkspace: varsayilan, snapshot: false)
        #expect(tekrar == scope)
        let baska = PreferenceScope.resolve(workspace: URL(fileURLWithPath: "/tmp/baska-ws"), defaultWorkspace: varsayilan, snapshot: false)
        #expect(baska.suiteName != scope.suiteName)
        #expect(baska.keychainAccount("a") != scope.keychainAccount("a"))
    }

    @Test func ekranCizimiKipiGercekAnahtarHesabinaBakmazVeTercihYazmaz() throws {
        // Varsayılan veri alanıyla bile ekran çizimi kalıcı tercihe yazmaz ve gerçek Keychain hesabını kullanmaz.
        let scope = PreferenceScope.resolve(workspace: varsayilan, defaultWorkspace: varsayilan, snapshot: true)
        #expect(scope.kind == .snapshot)
        #expect(!scope.persistsPreferences)
        #expect(scope.suiteName != nil && scope.suiteName != PreferenceScope.appDomain)
        #expect(scope.keychainAccount(ChatEngine.anthropicKeyAccount) != ChatEngine.anthropicKeyAccount)

        let key = "test-\(UUID().uuidString)"
        let prefs = PreferenceStore(scope: scope)
        prefs.set("marka-1", forKey: key)
        #expect(prefs.string(forKey: key) == "marka-1")
        #expect(prefs.defaults.string(forKey: key) == nil, "ekran çizimi tercihi diske yazmamalı")
        #expect(PreferenceStore(scope: scope).string(forKey: key) == nil)
    }

    @Test func denemeAlanininTercihleriYalnizcaKendiTakimindaDurur() throws {
        // Sabit yol: her koşu aynı tercih takımını kullanır; sonunda takım ve dosyası silinir (diskte iz kalmaz).
        let ws = URL(fileURLWithPath: "/tmp/marka-tercih-yalitim-testi", isDirectory: true)
        let scope = PreferenceScope.resolve(workspace: ws, defaultWorkspace: varsayilan, snapshot: false)
        let suite = try #require(scope.suiteName)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        let key = "lastBrand-\(UUID().uuidString)"
        let prefs = PreferenceStore(scope: scope)
        prefs.set("deneme-marka", forKey: key)
        #expect(PreferenceStore(scope: scope).string(forKey: key) == "deneme-marka")
        #expect(UserDefaults(suiteName: suite)?.string(forKey: key) == "deneme-marka")
        #expect(UserDefaults.standard.string(forKey: key) == nil, "deneme tercihi standart alana sızmamalı")
        prefs.set(nil, forKey: key)
        #expect(prefs.string(forKey: key) == nil)
    }

    /// Uygulama katmanı tercih ve anahtara yalnızca kapsam üzerinden erişir: `UserDefaults.standard` ya da sabit Keychain
    /// hesabı doğrudan kullanılırsa deneme kopyası gerçek kopyayla yeniden ortak olur.
    @Test func uygulamaKatmaniTercihVeAnahtaraYalnizcaKapsamUzerindenErisir() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/MarkaApp")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count > 5)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("UserDefaults.standard"), "\(file.lastPathComponent) UserDefaults.standard kullanıyor")
            #expect(!text.contains("UserDefaults("), "\(file.lastPathComponent) kendi tercih takımını açıyor")
            #expect(!text.contains("account: ChatEngine.anthropicKeyAccount"), "\(file.lastPathComponent) sabit Keychain hesabını kullanıyor")
        }
        let app = try String(contentsOf: dir.appendingPathComponent("MarkaApp.swift"), encoding: .utf8)
        #expect(app.components(separatedBy: ".defaultAppStorage(app.preferences.defaults)").count - 1 == 2,
                "ana pencere ve Ayarlar @AppStorage için kapsamın tercih takımını kullanmalı")
        let model = try String(contentsOf: dir.appendingPathComponent("AppModel.swift"), encoding: .utf8)
        #expect(model.contains("anthropicKey: { Keychain.load(account: keyAccount) }"), "sohbet motoru kapsamın anahtar hesabını kullanmalı")
    }
}
