import Foundation
import Testing
@testable import MarkaCore

@Suite struct SurumTests {
    /// Tek sürüm kaynağı: README'deki "Beta X.Y.Z" satırı `MarkaCoreVersion.string` ile aynı olmalı.
    @Test func surumNumarasiXYZBicimindeVeReadmeIleAyni() throws {
        let v = MarkaCoreVersion.string
        #expect(v.split(separator: ".").count == 3 && v.split(separator: ".").allSatisfy { Int($0) != nil })
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("> Beta \(v)."), "README 'Beta \(v).' içermiyor; sürümü değiştirince README'yi de güncelle")
    }
}
