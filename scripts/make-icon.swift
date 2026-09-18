// Uygulama simgesi: sakin açık yüzey, koyu çalışma alanı, tek turuncu durum ışığı.
import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 180, cornerHeight: 180, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.25).cgColor)
ctx.addPath(bodyPath)
ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.92, blue: 0.90, alpha: 1).cgColor)
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// Üç yatay kayıt çizgisi (kaynak → iş → rapor)
let lineColor = NSColor(srgbRed: 0.22, green: 0.22, blue: 0.23, alpha: 1).cgColor
for (i, w) in [520.0, 420.0, 300.0].enumerated() {
    let y = 630 - CGFloat(i) * 120
    let r = CGRect(x: 250, y: y, width: CGFloat(w), height: 44)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setFillColor(lineColor)
    ctx.fillPath()
}
// Durum ışığı
ctx.setFillColor(NSColor(srgbRed: 0.85, green: 0.38, blue: 0.12, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: 640, y: 358, width: 110, height: 110))
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
