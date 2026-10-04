import CoreGraphics
import Foundation
// Verilen PID'ye ait en büyük normal pencerenin kimliğini yazar (yalnız o pencereyi yakalamak için).
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? -1
let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
var best: (Int, CGFloat)?
for w in list {
    guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
          (w[kCGWindowLayer as String] as? Int) == 0,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat],
          let n = w[kCGWindowNumber as String] as? Int else { continue }
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if best == nil || area > best!.1 { best = (n, area) }
}
if let best { print(best.0) }
