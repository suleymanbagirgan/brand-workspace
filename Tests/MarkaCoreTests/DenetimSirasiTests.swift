import Foundation
import Testing
@testable import MarkaCore

@Suite struct DenetimSirasiTests {
    /// Kök neden: `auditTrail` yalnız zamana göre sıralıyordu; aynı milisaniyede oluşan "oluştur" ve "sil" olaylarında sıra
    /// belirsizdi (kararsız test). Eşit zamanda sonradan eklenen önce gelir.
    @Test func ayniAnaDusenDenetimOlaylariSonEklenenOnceSiralanir() throws {
        let store = try makeStore()
        let at = Date()
        try store.write { db in
            for action in ["create", "update", "delete"] {
                try AuditEvent(at: at, actor: .user, brandId: nil, entity: "task", entityId: "x", action: action).insert(db)
            }
        }
        #expect(try store.auditTrail(entity: "task", entityId: "x").map(\.action) == ["delete", "update", "create"])
    }
}
