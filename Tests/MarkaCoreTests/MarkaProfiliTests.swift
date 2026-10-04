import Foundation
import Testing
@testable import MarkaCore

@Suite struct MarkaProfiliTests {
    @Test func bolumYazilirOkunurVeBosMetinSiler() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        #expect(try store.profile(brandId: b.id).isEmpty)
        try store.setProfileSection(brandId: b.id, .audience, body: "  Kurumsal satın alma müdürleri  ")
        #expect(try store.profile(brandId: b.id)[.audience] == "Kurumsal satın alma müdürleri")
        try store.setProfileSection(brandId: b.id, .audience, body: "Tesis yöneticileri")
        #expect(try store.profile(brandId: b.id)[.audience] == "Tesis yöneticileri")
        try store.setProfileSection(brandId: b.id, .audience, body: "   ")
        #expect(try store.profile(brandId: b.id).isEmpty)
    }

    @Test func profilBaskaMarkayaSizmazVeYazmaDenetimBirakir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let b = try store.createBrand(name: "Kuzey Lojistik")
        try store.setProfileSection(brandId: a.id, .voice, body: "Sade ve güvenilir")
        #expect(try store.profile(brandId: b.id).isEmpty)
        let trail = try store.auditTrail(entity: "brandProfile", entityId: a.id + "/voice")
        #expect(trail.count == 1)
        #expect(trail.first?.action == "set")
    }

    @Test func bagiamYalnizDoldurulanBolumleriIcerirVeSoruMetniGirmez() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let empty = try ContextBuilder(store: store).brandContext(brandId: b.id)
        #expect(!empty.contains("Marka profili"))
        try store.setProfileSection(brandId: b.id, .constraints, body: "Fiyat vaadi verilmez")
        let ctx = try ContextBuilder(store: store).brandContext(brandId: b.id)
        #expect(ctx.contains("### Kısıtlar ve dikkat edilecekler"))
        #expect(ctx.contains("Fiyat vaadi verilmez"))
        #expect(!ctx.contains("### Hedef kitle"))
        #expect(!ctx.contains(ProfileSection.audience.prompt))
    }

    @Test func cokUzunMetinReddedilirVeOlmayanMarkaHataVerir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        #expect(throws: (any Error).self) {
            try store.setProfileSection(brandId: b.id, .scope, body: String(repeating: "a", count: ProfileSection.maxLength + 1))
        }
        #expect(throws: (any Error).self) { try store.setProfileSection(brandId: "yok", .scope, body: "x") }
    }
}
