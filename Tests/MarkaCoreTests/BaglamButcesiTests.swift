import Foundation
import Testing
@testable import MarkaCore

@Suite struct BaglamButcesiTests {
    @Test func sinirAsanGorevListesiKirpilirVeDogruSayidaNotGelir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let toplam = ContextLimits.listItems + 7
        for i in 1...toplam { try store.saveTask(WorkTask(brandId: b.id, title: "Görev \(i)")) }
        let ctx = try ContextBuilder(store: store).brandContext(brandId: b.id)
        let satirlar = ctx.split(separator: "\n").filter { $0.contains(" id=") && $0.contains("[durum:") }
        #expect(satirlar.count == ContextLimits.listItems)
        #expect(ctx.contains("… ve 7 öğe daha var (kırpıldı)"))
    }

    @Test func sinirAltindaNotYokVeCiktiEskisiyleAyni() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        for i in 1...ContextLimits.listItems { try store.saveTask(WorkTask(brandId: b.id, title: "Görev \(i)")) }
        let ctx = try ContextBuilder(store: store).brandContext(brandId: b.id)
        #expect(!ctx.contains("kırpıldı"))
        #expect(ContextLimits.truncationNote(total: ContextLimits.listItems) == "")
        let satirlar = ctx.split(separator: "\n").filter { $0.contains("[durum:") }
        #expect(satirlar.count == ContextLimits.listItems)
    }

    @Test func baskaMarkaninGoreviBaglamaGirmez() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let other = try store.createBrand(name: "Kuzey Lojistik")
        try store.saveTask(WorkTask(brandId: b.id, title: "Kendi görevim"))
        for i in 1...(ContextLimits.listItems + 3) { try store.saveTask(WorkTask(brandId: other.id, title: "Yabancı görev \(i)")) }
        let ctx = try ContextBuilder(store: store).brandContext(brandId: b.id)
        #expect(ctx.contains("Kendi görevim"))
        #expect(!ctx.contains("Yabancı görev"))
        #expect(!ctx.contains("kırpıldı"))
    }
}
