import Foundation
import GRDB

extension Store {
    // MARK: Şirket profili (0.4.0)

    public func companyProfile() throws -> CompanyProfile {
        try read { db in try CompanyProfile.fetchOne(db, key: CompanyProfile.singletonId) ?? CompanyProfile() }
    }

    @discardableResult
    public func saveCompanyProfile(_ profile: CompanyProfile, actor: Actor = .user) throws -> CompanyProfile {
        var p = profile
        p.id = CompanyProfile.singletonId
        p.name = profile.name.trimmed; p.tagline = profile.tagline.trimmed; p.about = profile.about.trimmed
        p.mission = profile.mission.trimmed; p.website = profile.website.trimmed
        guard p.name.count <= 120 else { throw MarkaError.validation(LF("Ad çok uzun (en çok %d).", 120)) }
        if let d = p.foundedOn, DayString.date(d) == nil { throw MarkaError.validation(L("Tarih geçersiz.")) }
        p.updatedAt = Date()
        return try writer.write { db in
            let before = try CompanyProfile.fetchOne(db, key: p.id)
            try p.save(db)
            // Kendi şirketin adı marka adıyla aynı kalır (başka bir marka aynı adı taşımıyorsa).
            if !p.name.isEmpty, var own = try Brand.filter(Column("isOwn") == true).fetchOne(db), own.name != p.name {
                let tr = Locale(identifier: "tr_TR")
                let taken = try Brand.fetchAll(db).contains { $0.id != own.id && $0.name.lowercased(with: tr) == p.name.lowercased(with: tr) }
                if !taken {
                    let ownBefore = own
                    own.name = p.name; own.updatedAt = Date(); try own.update(db)
                    // Marka geçmişinde ad değişikliği görünsün (B4).
                    try audit(db, actor: actor, brandId: own.id, entity: "brand", entityId: own.id, action: "update", before: ownBefore, after: own)
                }
            }
            try audit(db, actor: actor, brandId: nil, entity: "company", entityId: p.id,
                      action: before == nil ? "create" : "update", before: before, after: p)
            return p
        }
    }

    // MARK: Hizmetler

    /// Önce etkin hizmetler, sonra planlananlar, sonra durdurulanlar; kendi içinde başlangıç gününe göre.
    public func services() throws -> [ServiceOffering] {
        try read { db in
            func rank(_ s: ServiceStatus) -> Int { s == .active ? 0 : s == .planned ? 1 : 2 }
            return try ServiceOffering.fetchAll(db).sorted {
                rank($0.status) != rank($1.status) ? rank($0.status) < rank($1.status)
                    : ($0.startedOn ?? "9999") != ($1.startedOn ?? "9999") ? ($0.startedOn ?? "9999") < ($1.startedOn ?? "9999")
                    : $0.name.localizedCompare($1.name) == .orderedAscending
            }
        }
    }

    @discardableResult
    public func saveService(_ service: ServiceOffering, actor: Actor = .user) throws -> ServiceOffering {
        var s = service
        s.name = service.name.trimmed; s.summary = service.summary.trimmed; s.details = service.details.trimmed
        guard !s.name.isEmpty else { throw MarkaError.validation(L("Ad boş olamaz.")) }
        guard s.name.count <= 120 else { throw MarkaError.validation(LF("Ad çok uzun (en çok %d).", 120)) }
        if let d = s.startedOn, DayString.date(d) == nil { throw MarkaError.validation(L("Tarih geçersiz.")) }
        s.updatedAt = Date()
        return try writer.write { db in
            let before = try ServiceOffering.fetchOne(db, key: s.id)
            try s.save(db)
            try audit(db, actor: actor, brandId: nil, entity: "serviceOffering", entityId: s.id,
                      action: before == nil ? "create" : "update", before: before, after: s)
            return s
        }
    }

    public func deleteService(_ id: String, actor: Actor = .user) throws {
        try writer.write { db in
            guard let before = try ServiceOffering.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            try before.delete(db)
            try audit(db, actor: actor, brandId: nil, entity: "serviceOffering", entityId: id,
                      action: "delete", before: before, after: ServiceOffering?.none)
        }
    }

    // MARK: Ekip

    /// Etkin üyeler önce; kıdem yüksekten düşüğe, sonra ada göre.
    public func teamMembers(kind: MemberKind? = nil, includeArchived: Bool = false) throws -> [TeamMember] {
        try read { db in
            var q = TeamMember.all()
            if let kind { q = q.filter(Column("kind") == kind.rawValue) }
            if !includeArchived { q = q.filter(Column("status") == MemberStatus.active.rawValue) }
            return try q.fetchAll(db).sorted {
                $0.level != $1.level ? $0.level > $1.level : $0.name.localizedCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Ekler ya da günceller. Yönetici kendisi ya da kendi astı olamaz (döngü yok); yönetici arşivde olamaz.
    @discardableResult
    public func saveTeamMember(_ member: TeamMember, actor: Actor = .user) throws -> TeamMember {
        let m = try Self.normalized(member)
        return try writer.write { db in try persistMember(db, m, actor: actor) }
    }

    /// Ön doğrulama ve temizlik (veri tabanına dokunmaz).
    static func normalized(_ member: TeamMember) throws -> TeamMember {
        var m = member
        m.name = member.name.trimmed; m.title = member.title.trimmed; m.department = member.department.trimmed
        m.bio = member.bio.trimmed; m.email = member.email.trimmed; m.charter = member.charter.trimmed
        m.provider = member.provider.trimmed; m.model = member.model.trimmed
        guard !m.name.isEmpty else { throw MarkaError.validation(L("Ad boş olamaz.")) }
        guard !m.title.isEmpty else { throw MarkaError.validation(L("Unvan boş olamaz.")) }
        guard m.name.count <= 120, m.title.count <= 120 else { throw MarkaError.validation(LF("Ad çok uzun (en çok %d).", 120)) }
        if let d = m.startedOn, DayString.date(d) == nil { throw MarkaError.validation(L("Tarih geçersiz.")) }
        if m.kind == .human { m.provider = ""; m.model = ""; m.charter = ""; m.skillsJSON = "[]" }
        m.skills = m.skills.map(\.trimmed).filter { !$0.isEmpty }
        m.updatedAt = Date()
        return m
    }

    /// Yönetici ağacı kurallarını denetleyip kaydeder; çağıran bir yazma işleminin içindedir (öneri onayı da buradan geçer).
    func persistMember(_ db: Database, _ m: TeamMember, actor: Actor) throws -> TeamMember {
        if let boss = m.reportsToId {
            guard boss != m.id else { throw MarkaError.validation(L("Kimse kendine bağlı olamaz.")) }
            guard let bossRow = try TeamMember.fetchOne(db, key: boss) else { throw MarkaError.notFound(boss) }
            if bossRow.status == .archived, m.status == .active { throw MarkaError.validation(L("Arşivdeki birine bağlanamaz.")) }
            var cursor: String? = bossRow.reportsToId
            var hops = 0
            while let c = cursor, hops < 1000 {
                if c == m.id { throw MarkaError.validation(L("Bu bağlantı bir döngü oluşturur.")) }
                cursor = try TeamMember.fetchOne(db, key: c)?.reportsToId
                hops += 1
            }
        }
        let before = try TeamMember.fetchOne(db, key: m.id)
        if let before, before.kind != m.kind { throw MarkaError.validation(L("Üyenin türü değiştirilemez.")) }
        try m.save(db)
        try audit(db, actor: actor, brandId: nil, entity: "teamMember", entityId: m.id,
                  action: before == nil ? "create" : "update", before: before, after: m)
        return m
    }

    /// Arşivler: üye geçmişte kalır, şemadan ve yeni atamalardan çıkar; astları üstüne devredilir. Geri alınabilir (`restoreTeamMember`).
    public func archiveTeamMember(_ id: String, actor: Actor = .user) throws {
        try writer.write { db in try archiveMember(db, id, actor: actor, action: "archive") }
    }

    func archiveMember(_ db: Database, _ id: String, actor: Actor, action: String) throws {
        guard var m = try TeamMember.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
        let before = m
        for var r in try TeamMember.filter(Column("reportsToId") == id).fetchAll(db) {
            let rBefore = r
            r.reportsToId = m.reportsToId; r.updatedAt = Date(); try r.update(db)
            // Astın yöneticisi değişti: her ast için ayrı iz (B4).
            try audit(db, actor: actor, brandId: nil, entity: "teamMember", entityId: r.id, action: "update", before: rBefore, after: r)
        }
        m.status = .archived; m.reportsToId = nil; m.updatedAt = Date()
        try m.update(db)
        try audit(db, actor: actor, brandId: nil, entity: "teamMember", entityId: id, action: action, before: before, after: m)
    }

    public func restoreTeamMember(_ id: String, actor: Actor = .user) throws {
        try writer.write { db in
            guard var m = try TeamMember.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            let before = m
            m.status = .active; m.updatedAt = Date()
            try m.update(db)
            try audit(db, actor: actor, brandId: nil, entity: "teamMember", entityId: id, action: "restore", before: before, after: m)
        }
    }

    /// Organizasyon şeması: yöneticisi olmayanlar kök; kıdem sırasıyla. Yalnız etkin üyeler.
    public func orgChart() throws -> [OrgNode] {
        let members = try teamMembers()
        let byBoss = Dictionary(grouping: members, by: \.reportsToId)
        func node(_ m: TeamMember) -> OrgNode { OrgNode(member: m, children: (byBoss[m.id] ?? []).map(node)) }
        let ids = Set(members.map(\.id))
        let roots = members.filter { $0.reportsToId == nil || !ids.contains($0.reportsToId!) }
        return roots.map(node)
    }

    // MARK: Müşteri ekibi (atamalar)

    /// Markanın ekibi: lider önce, sonra kıdem.
    public func brandTeam(brandId: String) throws -> [(member: TeamMember, role: AssignmentRole)] {
        try read { db in
            // Kendi şirketimizin (Stüdyo) ekibi, atama gerekmeden etkin tüm üyelerdir.
            if try Brand.fetchOne(db, key: brandId)?.isOwn == true {
                return try TeamMember.filter(Column("status") == MemberStatus.active.rawValue).fetchAll(db).sorted {
                    $0.level != $1.level ? $0.level > $1.level : $0.name.localizedCompare($1.name) == .orderedAscending
                }.map { ($0, AssignmentRole.member) }
            }
            let rows = try BrandAssignment.filter(Column("brandId") == brandId).fetchAll(db)
            // Arşivdeki üye atamasıyla tarihte kalır ama ekipte ve yapay zekâ bağlamında görünmez (B3).
            let members = try TeamMember.fetchAll(db, keys: rows.map(\.memberId)).filter { $0.status == .active }
            let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
            return rows.compactMap { r in byId[r.memberId].map { ($0, r.role) } }.sorted {
                $0.role != $1.role ? $0.role == .lead : $0.member.level != $1.member.level
                    ? $0.member.level > $1.member.level : $0.member.name.localizedCompare($1.member.name) == .orderedAscending
            }
        }
    }

    /// Üyenin atandığı markalar (yalnız kimlik; marka verisi okunmaz).
    public func assignments(memberId: String) throws -> [BrandAssignment] {
        try read { db in try BrandAssignment.filter(Column("memberId") == memberId).fetchAll(db) }
    }

    /// Üyeyi markaya atar (varsa rolünü günceller). Arşivdeki üye atanamaz. Markada tek lider olur: yeni lider eskisini üye yapar.
    public func assignMember(_ memberId: String, to brandId: String, role: AssignmentRole = .member, actor: Actor = .user) throws {
        try writer.write { db in
            guard let target = try Brand.fetchOne(db, key: brandId) else { throw MarkaError.notFound(brandId) }
            if target.isOwn { throw MarkaError.validation(L("Şirketin ekibi herkestir; ayrıca atama gerekmez.")) }
            guard let m = try TeamMember.fetchOne(db, key: memberId) else { throw MarkaError.notFound(memberId) }
            guard m.status == .active else { throw MarkaError.validation(L("Arşivdeki biri atanamaz.")) }
            if role == .lead {
                for var other in try BrandAssignment.filter(Column("brandId") == brandId && Column("role") == AssignmentRole.lead.rawValue
                                                            && Column("memberId") != memberId).fetchAll(db) {
                    let before = other
                    other.role = .member; try other.update(db)
                    try audit(db, actor: actor, brandId: brandId, entity: "brandAssignment", entityId: other.memberId,
                              action: "update", before: before, after: other)
                }
            }
            let before = try BrandAssignment.filter(Column("brandId") == brandId && Column("memberId") == memberId).fetchOne(db)
            let row = BrandAssignment(brandId: brandId, memberId: memberId, role: role, createdAt: before?.createdAt ?? Date())
            try row.save(db)
            try audit(db, actor: actor, brandId: brandId, entity: "brandAssignment", entityId: memberId,
                      action: before == nil ? "create" : "update", before: before, after: row)
        }
    }

    public func unassignMember(_ memberId: String, from brandId: String, actor: Actor = .user) throws {
        try writer.write { db in
            guard let before = try BrandAssignment.filter(Column("brandId") == brandId && Column("memberId") == memberId).fetchOne(db)
            else { throw MarkaError.notFound(memberId) }
            try before.delete(db)
            try audit(db, actor: actor, brandId: brandId, entity: "brandAssignment", entityId: memberId,
                      action: "delete", before: before, after: BrandAssignment?.none)
        }
    }

    // MARK: Önerinin sahibi

    /// Öneri bir çalışan rolüyle açılmış sohbetten geldiyse o çalışan (arşivlenmiş olsa da ad geçmişte kalır).
    /// Oturumun markası önerinin markasından farklıysa kimse gösterilmez (B6).
    public func proposer(of proposal: AIProposal) throws -> TeamMember? {
        guard let sessionId = proposal.sessionId else { return nil }
        return try read { db in
            guard let session = try AISession.fetchOne(db, key: sessionId), session.brandId == proposal.brandId,
                  let memberId = session.memberId else { return nil }
            return try TeamMember.fetchOne(db, key: memberId)
        }
    }

    // MARK: Ekip şablonları

    /// Şablon kurulumunun sonucu: açılan öneriler ve atlanan rol adları.
    public struct TeamTemplateResult: Sendable {
        public var proposals: [AIProposal]
        public var skipped: [String]
    }

    /// Şablondaki her rol için onay bekleyen bir "çalışan önerisi" açar; ekip kendiliğinden oluşmaz.
    /// Yalnız Stüdyo (kendi şirket) markasında çalışır. Aynı adlı etkin üye ya da bekleyen öneri varsa o rol atlanır.
    /// `reportsToId` verilirse (var olan bir üye) roller ona bağlanır; şablon içinde rol rolün altına bağlanmaz, bu yüzden döngü oluşamaz.
    public func proposeTeamTemplate(_ template: TeamTemplate, reportsToId: String? = nil) throws -> TeamTemplateResult {
        guard let own = try ownBrand() else {
            throw MarkaError.validation(L("Çalışan önerisi yalnız şirket sohbetinde verilebilir."))
        }
        let tr = Locale(identifier: "tr_TR")
        func key(_ s: String) -> String { s.trimmed.lowercased(with: tr) }
        var taken = Set(try teamMembers().map { key($0.name) })
        for p in try proposals(brandId: own.id, status: .pending) where p.kind == .createTeamMember {
            if let x = p.payload(ProposalPayload.CreateTeamMember.self) { taken.insert(key(x.name)) }
        }
        var made: [AIProposal] = [], skipped: [String] = []
        for r in template.roles {
            guard !taken.contains(key(r.name)) else { skipped.append(r.name); continue }
            let payload = ProposalPayload.CreateTeamMember(name: r.name, title: r.title, level: r.level.rawValue, department: r.department,
                                                           reportsToId: reportsToId, charter: r.charter, skills: r.skills)
            made.append(try createProposal(sessionId: nil, brandId: own.id, kind: .createTeamMember,
                                           summary: LF("Yeni çalışan: %@", r.name), payload: payload))
            taken.insert(key(r.name))
        }
        return TeamTemplateResult(proposals: made, skipped: skipped)
    }

    // MARK: Çalışan etkinliği

    /// Bir yapay zekâ çalışanın rolüyle açılan sohbetlerden gelen önerilerin dökümü.
    public struct MemberActivity: Sendable, Hashable {
        public var pending = 0, applied = 0, rejected = 0
        public var lastActiveAt: Date?
    }

    /// Üye kimliği → etkinlik. Yalnızca rolle açılmış oturumlar sayılır; sayılar kayıttan gelir, tahmin değildir.
    /// Bilinçli istisna: markalar arası toplu sorgudur ama yalnız sayı ve tarih döner, içerik dönmez; yapay zekâ bağlamına girmez.
    public func memberActivity() throws -> [String: MemberActivity] {
        try read { db in
            var out: [String: MemberActivity] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.memberId AS m, p.status AS st, COUNT(*) AS n FROM aiProposal p
                JOIN aiSession s ON s.id = p.sessionId WHERE s.memberId IS NOT NULL GROUP BY s.memberId, p.status
                """)
            for r in rows {
                let id: String = r["m"]; let n: Int = r["n"]
                switch ProposalStatus(rawValue: r["st"]) {
                case .pending: out[id, default: .init()].pending += n
                case .applied: out[id, default: .init()].applied += n
                case .rejected: out[id, default: .init()].rejected += n
                default: break
                }
            }
            for r in try Row.fetchAll(db, sql: "SELECT memberId AS m, MAX(updatedAt) AS t FROM aiSession WHERE memberId IS NOT NULL GROUP BY memberId") {
                let id: String = r["m"]
                out[id, default: .init()].lastActiveAt = r["t"]
            }
            return out
        }
    }
}
