import GRDB
/// Uygulama sürümünün **tek kaynağı**. `scripts/version.sh` bu satırı okur; Info.plist, dmg adı,
/// yedek manifesti ve Codex istemci bilgisi buradan türer. Biçim `X.Y.Z` olmalı (betik denetler).
public enum MarkaCoreVersion { public static let string = "0.2.1" }
