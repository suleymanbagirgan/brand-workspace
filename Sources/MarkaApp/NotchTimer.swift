import AppKit
import MarkaCore
import SwiftUI

/// Süre biçimi: 07:05 ya da 1:07:05.
enum Timecode {
    static func string(_ t: TimeInterval) -> String {
        let s = Int(t), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

/// Çentik zamanlayıcısı: çentiği olan MacBook'ta, çalışan zamanlayıcıyı çentikten sarkan küçük siyah bir "ada" olarak gösterir.
/// macOS çentiğe uygulama yerleştirmek için resmî bir API vermez (Dinamik Ada yalnızca iPhone'dadır); bu pencere, çentiğin hemen altında
/// duran kenarsız, tıklamayı kabul eden ama uygulamayı öne getirmeyen bir paneldir. Çentiksiz ekranda gösterilmez (menü çubuğu sayacı kalır).
@MainActor
final class NotchTimerController {
    static let shared = NotchTimerController()
    private var panel: NSPanel?

    /// Çentiği olan ekran (üst güvenli alan > 0).
    private var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }

    func update(app: AppModel) {
        guard app.runningTimer != nil, app.showNotchTimer, !app.notchDismissed, let screen = notchScreen,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { hide(); return }
        let notchWidth = right.minX - left.maxX
        let width = notchWidth + 44, height = screen.safeAreaInsets.top + 46
        let frame = NSRect(x: (left.maxX + right.minX) / 2 - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        if panel == nil {
            let p = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isMovable = false
            p.contentView = NSHostingView(rootView: NotchTimerView(topInset: screen.safeAreaInsets.top).environment(app))
            panel = p
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

/// Menü çubuğu alanına taşabilmesi için çerçeve kısıtlamasını kaldıran panel.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private struct NotchTimerView: View {
    @Environment(AppModel.self) private var app
    let topInset: CGFloat
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)   // fiziksel çentiğin bulunduğu üst şerit
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.35, blue: 0.3)).frame(width: 7, height: 7).opacity(pulse ? 1 : 0.35)
                    .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.runningTask?.title ?? L("Zamanlayıcı")).font(Design.Font.small.weight(.medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Text(Timecode.string(app.elapsed)).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
                Spacer(minLength: 4)
                Button { app.notchDismissed = true } label: {
                    Image(systemName: "chevron.up").font(Design.Icon.small.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain).help(L("Çentikten gizle (sayaç sürer)")).accessibilityLabel(L("Çentikten gizle"))
                Button { app.stopTimer() } label: {
                    Image(systemName: "stop.fill").font(Design.Icon.small.weight(.bold)).foregroundStyle(.black)
                        .frame(width: 24, height: 24).background(Circle().fill(.white))
                }
                .buttonStyle(.plain).help(L("Zamanlayıcıyı durdur")).accessibilityLabel(L("Zamanlayıcıyı durdur"))
            }
            .padding(.horizontal, 16).frame(height: 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchShape().fill(Color.black))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LF("%1$@, %2$@", app.runningTask?.title ?? L("Zamanlayıcı"), Timecode.string(app.elapsed)))
    }
}
