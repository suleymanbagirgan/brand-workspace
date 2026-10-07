import Foundation
import GRDB

/// "Biz kimiz" (0.4.0): çalışma alanının sahibi olan şirket. Tek satır, markaya bağlı değil; müşteri verisi içermez.
public struct CompanyProfile: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "company"
    public static let singletonId = "self"
    public var id: String
    public var name: String
    public var tagline: String
    public var about: String
    public var mission: String
    /// Kuruluş günü, `yyyy-MM-dd`.
    public var foundedOn: String?
    public var website: String
    public var updatedAt: Date

    public init(name: String = "", tagline: String = "", about: String = "", mission: String = "",
                foundedOn: String? = nil, website: String = "", updatedAt: Date = Date()) {
        self.id = Self.singletonId; self.name = name; self.tagline = tagline; self.about = about
        self.mission = mission; self.foundedOn = foundedOn; self.website = website; self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        name.trimmed.isEmpty && tagline.trimmed.isEmpty && about.trimmed.isEmpty && mission.trimmed.isEmpty
    }
}

public enum ServiceStatus: String, Codable, Sendable, CaseIterable { case active, planned, paused }

/// Şirketin sunduğu hizmet.
public struct ServiceOffering: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "serviceOffering"
    public var id: String
    public var name: String
    public var summary: String
    /// Kime, nasıl, neyle teslim edilir; yapay zekâ bağlamına girer.
    public var details: String
    public var status: ServiceStatus
    /// Hizmetin başladığı gün, `yyyy-MM-dd`.
    public var startedOn: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), name: String, summary: String = "", details: String = "", status: ServiceStatus = .active,
                startedOn: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.summary = summary; self.details = details; self.status = status
        self.startedOn = startedOn; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum MemberKind: String, Codable, Sendable, CaseIterable { case human, ai }
public enum MemberStatus: String, Codable, Sendable, CaseIterable { case active, archived }

/// Gerçek dünyadaki unvan kademeleri; sıra = kıdem.
public enum MemberLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case intern, junior, mid, senior, lead, director
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// Ekip üyesi: gerçek kişi ya da yapay zekâ çalışan. İkisi aynı şemada, aynı organizasyon şemasında durur.
///
/// Yapay zekâ çalışan bir *rol tanımıdır* (sağlayıcı + model + görev tarifi + yetenekler); kendi başına çalışan bir süreç değildir.
/// Değişmez kural: yapay zekâ çalışan veri yazmaz, öneri üretir; öneriyi insan onaylar.
public struct TeamMember: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "teamMember"
    public var id: String
    public var kind: MemberKind
    public var name: String
    public var title: String
    public var level: MemberLevel
    public var department: String
    /// Bağlı olduğu yönetici (organizasyon şeması).
    public var reportsToId: String?
    public var bio: String
    public var startedOn: String?
    public var email: String
    public var status: MemberStatus
    /// Yalnız yapay zekâ çalışanda: sağlayıcı kimliği (`anthropic`, `codex`, `apple`…), model adı, görev tarifi, yetenekler.
    public var provider: String
    public var model: String
    public var charter: String
    public var skillsJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), kind: MemberKind, name: String, title: String, level: MemberLevel = .mid,
                department: String = "", reportsToId: String? = nil, bio: String = "", startedOn: String? = nil,
                email: String = "", status: MemberStatus = .active, provider: String = "", model: String = "",
                charter: String = "", skills: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.name = name; self.title = title; self.level = level
        self.department = department; self.reportsToId = reportsToId; self.bio = bio; self.startedOn = startedOn
        self.email = email; self.status = status; self.provider = provider; self.model = model; self.charter = charter
        self.skillsJSON = Store.json(skills) ?? "[]"; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var skills: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(skillsJSON.utf8))) ?? [] }
        set { skillsJSON = Store.json(newValue) ?? "[]" }
    }
}

public enum AssignmentRole: String, Codable, Sendable, CaseIterable { case lead, member }

/// Müşteri ekibi: hangi ekip üyesi hangi markaya atanmış.
public struct BrandAssignment: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "brandAssignment"
    public var brandId: String
    public var memberId: String
    public var role: AssignmentRole
    public var createdAt: Date

    public init(brandId: String, memberId: String, role: AssignmentRole = .member, createdAt: Date = Date()) {
        self.brandId = brandId; self.memberId = memberId; self.role = role; self.createdAt = createdAt
    }
}

/// Organizasyon şemasındaki bir düğüm.
public struct OrgNode: Sendable, Identifiable, Hashable {
    public var member: TeamMember
    public var children: [OrgNode]
    public var id: String { member.id }
}
