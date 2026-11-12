import SwiftUI

/// The prompter's outline: the content with rounded bottom corners, and at
/// the top a concave curve on each side ("shoulders") that runs into the
/// screen's top edge, so the panel reads as part of the notch.
struct NotchShape: Shape {
    /// How far each shoulder reaches past the content on either side.
    static let shoulder: CGFloat = 18
    /// The window sits this far above the screen's top edge, so no gap shows
    /// under the notch. The shoulders start below it, so their curves meet
    /// the visible edge flush.
    static let hiddenTop: CGFloat = 4
    var bottomRadius: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        let s = Self.shoulder
        let top = rect.minY + Self.hiddenTop
        let r = min(bottomRadius, (rect.width - 2 * s) / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addArc(tangent1End: CGPoint(x: rect.maxX - s, y: top),
                    tangent2End: CGPoint(x: rect.maxX - s, y: rect.maxY), radius: s)
        path.addArc(tangent1End: CGPoint(x: rect.maxX - s, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX + s, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX + s, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX + s, y: rect.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX + s, y: top),
                    tangent2End: CGPoint(x: rect.minX, y: top), radius: s)
        path.closeSubpath()
        return path
    }

    /// The window's frame for a content frame: wider by a shoulder each side.
    static func windowFrame(forContent content: CGRect) -> CGRect {
        content.insetBy(dx: -shoulder, dy: 0)
    }
}

/// Wraps the prompter's content in the notch outline. The content paints its
/// own background; only the two shoulder corners are filled here, so a
/// see-through background is never painted twice.
struct NotchPanel<Content: View>: View {
    @Environment(Preferences.self) private var preferences
    @ViewBuilder var content: Content

    var body: some View {
        let s = NotchShape.shoulder
        let fill = preferences.prompterTheme.backgroundColor.opacity(preferences.backgroundOpacity)
        content
            .padding(.horizontal, s)
            .background(alignment: .top) {
                HStack(spacing: 0) {
                    fill.frame(width: s, height: s + NotchShape.hiddenTop)
                    Spacer(minLength: 0)
                    fill.frame(width: s, height: s + NotchShape.hiddenTop)
                }
                .allowsHitTesting(false)
            }
            .clipShape(NotchShape())
    }
}
