import Foundation
import GRDB

public enum WikiRulesTemplate {
    public static let defaultBody = """
    # Bilgi kuralları

    Bu kurallar AI'ın bu markanın bilgi sayfalarını nasıl derleyeceğini belirler. İstediğin gibi düzenleyebilirsin.

    1. Yalnızca bu markanın kaynaklarını kullan. Başka marka hakkında bilgi yazma.
    2. Her önemli bilgiyi ayrı bir iddia olarak yaz ve dayandığı kaynağın kimliğini ekle. Kaynağı olmayan bilgi yazma.
    3. Kaynakta açıkça geçmeyen şeyi çıkarım olarak sunma; emin değilsen yazma.
    4. Yeni kaynak eski bir iddiayla çelişiyorsa ikisini de koru ve çelişkiyi işaretle; hangisinin doğru olduğuna kullanıcı karar verir.
    5. Tarihi geçmiş hedef, teklif veya kararları "eskimiş olabilir" olarak işaretle.
    6. Sayfa türleri: genel bakış, kişi, hedef, proje, karar, tercih, süreç.
    7. Kişisel iletişim bilgilerini (telefon, e-posta) bilgi sayfasına kopyalama; kişi kaydında zaten durur.
    8. Kısa ve olgusal yaz. Müşteriye gidecek dille değil, danışmanın çalışma notu diliyle yaz.
    """
}

public struct WikiClaimInput: Codable, Sendable, Hashable {
    public var text: String
    public var sourceId: String?
    public var status: ClaimStatus
    public var flagNote: String

    public init(text: String, sourceId: String? = nil, status: ClaimStatus = .current, flagNote: String = "") {
        self.text = text; self.sourceId = sourceId; self.status = status; self.flagNote = flagNote
    }
}

public struct WikiPageDetail: Sendable, Hashable, Identifiable {
    public var page: WikiPage
    public var current: WikiRevision?
    public var claims: [WikiClaim]
    public var revisions: [WikiRevision]
    public var links: [WikiPage]
    public var backlinks: [WikiPage]
    public var id: String { page.id }
}

public struct SearchHit: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case source, wiki }
    public var kind: Kind
    public var id: String
    public var brandId: String
    public var title: String
    public var snippet: String
}

public struct WikiLintIssue: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case unsourcedClaim, archivedSource, conflict, stale, pendingProposal, possiblyStale }
    public var kind: Kind
    public var pageId: String
    public var pageTitle: String
    public var detail: String
    public var id: String { "\(kind.rawValue)-\(pageId)-\(detail.hashValue)" }
}

extension Store {
    public func wikiRules(brandId: String) throws -> String {
        try read { db in try BrandRules.fetchOne(db, key: brandId)?.body } ?? WikiRulesTemplate.defaultBody
    }

    public func saveWikiRules(brandId: String, body: String) throws {
        try writer.write { db in
            let before = try BrandRules.fetchOne(db, key: brandId)
            let rules = BrandRules(brandId: brandId, body: body)
            try rules.save(db)
            try audit(db, actor: .user, brandId: brandId, entity: "brandRules", entityId: brandId, action: "update",
                      before: before, after: rules)
        }
    }

    public func wikiPages(brandId: String) throws -> [WikiPage] {
        try read { db in try WikiPage.filter(Column("brandId") == brandId).order(Column("kind"), Column("title")).fetchAll(db) }
    }

    public func wikiPageDetail(_ pageId: String) throws -> WikiPageDetail {
        try read { db in
            guard let page = try WikiPage.fetchOne(db, key: pageId) else { throw MarkaError.notFound(pageId) }
            let revisions = try WikiRevision.filter(Column("pageId") == pageId).order(Column("number").desc).fetchAll(db)
            let current = revisions.first { $0.id == page.currentRevisionId }
            let claims = try current.map { try WikiClaim.filter(Column("revisionId") == $0.id).fetchAll(db) } ?? []
            let links = try WikiPage.fetchAll(db, sql: "SELECT p.* FROM wikiPage p JOIN wikiLink l ON l.toPageId = p.id WHERE l.fromPageId = ?", arguments: [pageId])
            let backlinks = try WikiPage.fetchAll(db, sql: "SELECT p.* FROM wikiPage p JOIN wikiLink l ON l.fromPageId = p.id WHERE l.toPageId = ?", arguments: [pageId])
            return WikiPageDetail(page: page, current: current, claims: claims, revisions: revisions, links: links, backlinks: backlinks)
        }
    }

    public func claims(revisionId: String) throws -> [WikiClaim] {
        try read { db in try WikiClaim.filter(Column("revisionId") == revisionId).fetchAll(db) }
    }

    public func pendingRevisions(brandId: String) throws -> [WikiRevision] {
        try read { db in
            try WikiRevision.filter(Column("brandId") == brandId && Column("state") == RevisionState.proposed.rawValue)
                .order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public static func slug(_ title: String) -> String {
        let folded = title.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        let s = folded.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return s.split(separator: "-").joined(separator: "-")
    }

    /// Kullanıcının yazdığı sürüm doğrudan onaylıdır (kullanıcı otoritedir). AI sürümü öneri olarak girer.
    @discardableResult
    public func writeWikiRevision(brandId: String, pageId: String?, kind: WikiPageKind, title: String, body: String,
                                  claims: [WikiClaimInput], links: [String] = [], note: String = "",
                                  actor: Actor) throws -> WikiRevision {
        try writer.write { db in
            try writeWikiRevision(db, brandId: brandId, pageId: pageId, kind: kind, title: title, body: body,
                                  claims: claims, links: links, note: note, actor: actor)
        }
    }

    func writeWikiRevision(_ db: Database, brandId: String, pageId: String?, kind: WikiPageKind, title: String, body: String,
                           claims: [WikiClaimInput], links: [String], note: String, actor: Actor) throws -> WikiRevision {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else { throw MarkaError.validation(L("Sayfa başlığı boş olamaz.")) }
        guard !body.trimmed.isEmpty || !claims.isEmpty else { throw MarkaError.validation(L("Sayfa içeriği boş olamaz.")) }
        // Kaynak doğrulaması: iddia kaynağı aynı markadan olmalı; AI iddiası kaynaksız olamaz.
        var sourceDates: [String: Date] = [:]
        for c in claims {
            guard !c.text.trimmed.isEmpty else { throw MarkaError.validation(L("Boş iddia eklenemez.")) }
            if let sid = c.sourceId {
                guard let s = try Source.fetchOne(db, key: sid) else {
                    throw MarkaError.validation(LF("İddianın kaynağı bulunamadı: %@", sid))
                }
                guard s.brandId == brandId else { throw MarkaError.brandScope }
                sourceDates[sid] = s.capturedAt
            } else if actor == .ai {
                throw MarkaError.validation(LF("AI iddiası kaynaksız olamaz: “%@”", c.text))
            }
        }
        var page: WikiPage
        if let pageId {
            guard let p = try WikiPage.fetchOne(db, key: pageId) else { throw MarkaError.notFound(pageId) }
            guard p.brandId == brandId else { throw MarkaError.brandScope }
            page = p
        } else {
            var slug = Self.slug(cleanTitle)
            if slug.isEmpty { slug = "sayfa" }
            if let existing = try WikiPage.filter(Column("brandId") == brandId && Column("slug") == slug).fetchOne(db) {
                page = existing
            } else {
                page = WikiPage(brandId: brandId, kind: kind, title: cleanTitle, slug: slug)
                try page.insert(db)
            }
        }
        let number = (try Int.fetchOne(db, sql: "SELECT MAX(number) FROM wikiRevision WHERE pageId = ?", arguments: [page.id]) ?? 0) + 1
        let state: RevisionState = actor == .ai ? .proposed : .approved
        let revision = WikiRevision(pageId: page.id, brandId: brandId, number: number, body: body, note: note, state: state,
                                    actor: actor, decidedAt: state == .approved ? Date() : nil,
                                    basedOnRevisionId: page.currentRevisionId)
        try revision.insert(db)
        for c in claims {
            try WikiClaim(revisionId: revision.id, brandId: brandId, text: c.text.trimmed, sourceId: c.sourceId,
                          sourceDate: c.sourceId.flatMap { sourceDates[$0] }, status: c.status, flagNote: c.flagNote).insert(db)
        }
        for target in links {
            guard let tp = try WikiPage.filter(Column("brandId") == brandId && (Column("id") == target || Column("slug") == target)).fetchOne(db),
                  tp.id != page.id else { continue }
            try WikiLink(fromPageId: page.id, toPageId: tp.id).insert(db, onConflict: .ignore)
        }
        try audit(db, actor: actor, brandId: brandId, entity: "wikiRevision", entityId: revision.id, action: "create",
                  before: WikiRevision?.none, after: revision)
        if state == .approved { try activate(db, revision: revision, page: page, actor: actor) }
        return revision
    }

    private func activate(_ db: Database, revision: WikiRevision, page: WikiPage, actor: Actor) throws {
        var p = try WikiPage.fetchOne(db, key: page.id) ?? page
        if let old = p.currentRevisionId, old != revision.id {
            try db.execute(sql: "UPDATE wikiRevision SET state = ? WHERE id = ? AND state = ?",
                           arguments: [RevisionState.superseded.rawValue, old, RevisionState.approved.rawValue])
        }
        let beforePage = p
        p.currentRevisionId = revision.id
        let statuses = try String.fetchAll(db, sql: "SELECT status FROM wikiClaim WHERE revisionId = ?", arguments: [revision.id])
        p.status = statuses.contains(ClaimStatus.conflict.rawValue) ? .conflict : statuses.contains(ClaimStatus.stale.rawValue) ? .stale : .current
        p.updatedAt = Date()
        try p.update(db)
        try audit(db, actor: actor, brandId: p.brandId, entity: "wikiPage", entityId: p.id, action: "activate", before: beforePage, after: p)
    }

    public func approveRevision(_ revisionId: String) throws {
        try writer.write { db in
            guard var r = try WikiRevision.fetchOne(db, key: revisionId) else { throw MarkaError.notFound(revisionId) }
            guard r.state == .proposed else { throw MarkaError.validation(L("Yalnızca önerilen sürüm onaylanabilir.")) }
            guard let page = try WikiPage.fetchOne(db, key: r.pageId) else { throw MarkaError.notFound(r.pageId) }
            let before = r
            r.state = .approved
            r.decidedAt = Date()
            try r.update(db)
            try audit(db, actor: .user, brandId: r.brandId, entity: "wikiRevision", entityId: r.id, action: "approve", before: before, after: r)
            try activate(db, revision: r, page: page, actor: .user)
            try db.execute(sql: "UPDATE aiProposal SET status = ?, decidedAt = ? WHERE kind = ? AND resultEntityId = ? AND status = ?",
                           arguments: [ProposalStatus.applied.rawValue, Date(), ProposalKind.wikiRevision.rawValue, r.id, ProposalStatus.pending.rawValue])
        }
    }

    public func rejectRevision(_ revisionId: String) throws {
        try writer.write { db in
            guard var r = try WikiRevision.fetchOne(db, key: revisionId) else { throw MarkaError.notFound(revisionId) }
            guard r.state == .proposed else { throw MarkaError.validation(L("Yalnızca önerilen sürüm reddedilebilir.")) }
            let before = r
            r.state = .rejected
            r.decidedAt = Date()
            try r.update(db)
            try audit(db, actor: .user, brandId: r.brandId, entity: "wikiRevision", entityId: r.id, action: "reject", before: before, after: r)
            try db.execute(sql: "UPDATE aiProposal SET status = ?, decidedAt = ? WHERE kind = ? AND resultEntityId = ? AND status = ?",
                           arguments: [ProposalStatus.rejected.rawValue, Date(), ProposalKind.wikiRevision.rawValue, r.id, ProposalStatus.pending.rawValue])
            // Hiç onaylı sürümü olmayan, yalnızca bu öneriyle açılmış sayfa kalmasın.
            if let page = try WikiPage.fetchOne(db, key: r.pageId), page.currentRevisionId == nil {
                let others = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wikiRevision WHERE pageId = ? AND state = ?",
                                              arguments: [page.id, RevisionState.proposed.rawValue]) ?? 0
                if others == 0 { try page.delete(db) }
            }
        }
    }

    /// Önceki bir sürüme döner: içeriği kopyalayan yeni onaylı sürüm oluşturur (geçmiş silinmez).
    @discardableResult
    public func revertPage(_ pageId: String, to revisionId: String) throws -> WikiRevision {
        try writer.write { db in
            guard let page = try WikiPage.fetchOne(db, key: pageId) else { throw MarkaError.notFound(pageId) }
            guard let target = try WikiRevision.fetchOne(db, key: revisionId), target.pageId == pageId else {
                throw MarkaError.notFound(revisionId)
            }
            let oldClaims = try WikiClaim.filter(Column("revisionId") == target.id).fetchAll(db)
            return try writeWikiRevision(db, brandId: page.brandId, pageId: pageId, kind: page.kind, title: page.title,
                                         body: target.body,
                                         claims: oldClaims.map { WikiClaimInput(text: $0.text, sourceId: $0.sourceId, status: $0.status, flagNote: $0.flagNote) },
                                         links: [], note: LF("%d. sürüme dönüldü", target.number), actor: .user)
        }
    }

    /// Onaylı sürümdeki bir iddiayı işaretler (çelişki/eskimiş) veya işareti kaldırır.
    public func flagClaim(_ claimId: String, status: ClaimStatus, note: String, actor: Actor = .user) throws {
        try writer.write { db in
            guard var c = try WikiClaim.fetchOne(db, key: claimId) else { throw MarkaError.notFound(claimId) }
            let before = c
            c.status = status
            c.flagNote = note
            try c.update(db)
            try audit(db, actor: actor, brandId: c.brandId, entity: "wikiClaim", entityId: c.id, action: "flag", before: before, after: c)
            if let rev = try WikiRevision.fetchOne(db, key: c.revisionId), var page = try WikiPage.fetchOne(db, key: rev.pageId),
               page.currentRevisionId == rev.id {
                let statuses = try String.fetchAll(db, sql: "SELECT status FROM wikiClaim WHERE revisionId = ?", arguments: [rev.id])
                page.status = statuses.contains(ClaimStatus.conflict.rawValue) ? .conflict : statuses.contains(ClaimStatus.stale.rawValue) ? .stale : .current
                try page.update(db)
            }
        }
    }

    // MARK: Arama

    /// FTS5 araması. `brandId` nil ise tüm markalar (yalnızca Genel Bakış / Tüm Markalar kapsamı).
    public func search(_ query: String, brandId: String?, limit: Int = 30) throws -> [SearchHit] {
        let q = Self.ftsQuery(query)
        guard !q.isEmpty else { return [] }
        return try read { db in
            var hits: [SearchHit] = []
            let brandFilter = brandId == nil ? "" : "AND s.brandId = ?"
            var args: [any DatabaseValueConvertible] = [q]
            if let brandId { args.append(brandId) }
            args.append(limit)
            let terms = Self.searchTerms(query)
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.brandId, s.title, s.body
                FROM sourceFts JOIN source s ON s.rowid = sourceFts.rowid
                WHERE sourceFts MATCH ? AND s.archivedAt IS NULL \(brandFilter)
                ORDER BY bm25(sourceFts, 3.0, 1.0) LIMIT ?
                """, arguments: StatementArguments(args))
            hits += rows.map { SearchHit(kind: .source, id: $0["id"], brandId: $0["brandId"], title: $0["title"],
                                         snippet: Self.snippet($0["body"] ?? "", terms: terms)) }
            let wikiRows = try Row.fetchAll(db, sql: """
                SELECT p.id, p.brandId, p.title, r.body
                FROM wikiFts JOIN wikiRevision r ON r.rowid = wikiFts.rowid JOIN wikiPage p ON p.currentRevisionId = r.id
                WHERE wikiFts MATCH ? \(brandId == nil ? "" : "AND p.brandId = ?")
                ORDER BY bm25(wikiFts) LIMIT ?
                """, arguments: StatementArguments(args))
            hits += wikiRows.map { SearchHit(kind: .wiki, id: $0["id"], brandId: $0["brandId"], title: $0["title"],
                                             snippet: Self.snippet($0["body"] ?? "", terms: terms)) }
            // Başlık eşleşmesi de ara (FTS'e girmeyen sayfa başlıkları).
            let like = "%\(query.trimmed)%"
            var titleQuery = WikiPage.filter(Column("title").like(like)).filter(Column("currentRevisionId") != nil)
            if let brandId { titleQuery = titleQuery.filter(Column("brandId") == brandId) }
            let titleRows = try titleQuery.limit(limit).fetchAll(db)
            for p in titleRows where !hits.contains(where: { $0.id == p.id }) {
                hits.append(SearchHit(kind: .wiki, id: p.id, brandId: p.brandId, title: p.title, snippet: ""))
            }
            return hits
        }
    }

    /// Kullanıcı girdisini güvenli FTS5 sorgusuna çevirir: her sözcük önek araması, özel karakterler temizlenir.
    static func ftsQuery(_ raw: String) -> String {
        searchTerms(raw).map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// Arama ve dizin için ortak normalleştirme: Türkçe küçük harf, "ı" → "i", aksansız.
    static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR")).replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
    }

    static func searchTerms(_ raw: String) -> [String] {
        normalize(raw).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Özgün metinden, ilk eşleşen terimin çevresini gösteren kısa özet.
    static func snippet(_ text: String, terms: [String], radius: Int = 70) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let chars = Array(flat)
        guard !chars.isEmpty else { return "" }
        // Normalleştirme karakter sayısını korur (tek karakter → tek karakter), bu yüzden konumlar eşleşir.
        let norm = Array(normalize(flat))
        var hit = 0
        if norm.count == chars.count, let term = terms.first(where: { !$0.isEmpty }) {
            let t = Array(term)
            if t.count <= norm.count {
                for i in 0...(norm.count - t.count) where Array(norm[i..<(i + t.count)]) == t { hit = i; break }
            }
        }
        let start = max(0, hit - radius)
        let end = min(chars.count, hit + radius)
        return (start > 0 ? "…" : "") + String(chars[start..<end]).trimmingCharacters(in: .whitespaces) + (end < chars.count ? "…" : "")
    }

    // MARK: Denetim (lint)

    public func wikiLint(brandId: String, today: Date = Date(), staleAfterDays: Int = 180) throws -> [WikiLintIssue] {
        try read { db in
            var issues: [WikiLintIssue] = []
            let pages = try WikiPage.filter(Column("brandId") == brandId).fetchAll(db)
            for page in pages {
                let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wikiRevision WHERE pageId = ? AND state = ?",
                                               arguments: [page.id, RevisionState.proposed.rawValue]) ?? 0
                if pending > 0 {
                    issues.append(WikiLintIssue(kind: .pendingProposal, pageId: page.id, pageTitle: page.title,
                                                detail: LF("%d öneri onay bekliyor", pending)))
                }
                guard let rid = page.currentRevisionId else { continue }
                for c in try WikiClaim.filter(Column("revisionId") == rid).fetchAll(db) {
                    if c.sourceId == nil {
                        issues.append(WikiLintIssue(kind: .unsourcedClaim, pageId: page.id, pageTitle: page.title, detail: c.text))
                    } else if let s = try Source.fetchOne(db, key: c.sourceId!), s.archivedAt != nil {
                        issues.append(WikiLintIssue(kind: .archivedSource, pageId: page.id, pageTitle: page.title, detail: c.text))
                    }
                    switch c.status {
                    case .conflict: issues.append(WikiLintIssue(kind: .conflict, pageId: page.id, pageTitle: page.title, detail: "\(c.text) — \(c.flagNote)"))
                    case .stale: issues.append(WikiLintIssue(kind: .stale, pageId: page.id, pageTitle: page.title, detail: "\(c.text) — \(c.flagNote)"))
                    case .current:
                        if let d = c.sourceDate, today.timeIntervalSince(d) > Double(staleAfterDays) * 86400 {
                            issues.append(WikiLintIssue(kind: .possiblyStale, pageId: page.id, pageTitle: page.title, detail: c.text))
                        }
                    }
                }
            }
            return issues
        }
    }
}
