import SwiftUI

/// Dims the script by distance from the reading line: lines already read
/// sit at 22%, the line at the reading position at full strength, upcoming
/// lines at 55%. The top and bottom fade settings switch each side's dimming
/// on or off, and their heights set how long each side's transition is.
struct ReadingFocusMask: View {
    @Environment(Preferences.self) private var preferences
    /// Height kept clear along the bottom for the status row and progress
    /// line; the text fades out above it instead of running underneath.
    var reservedBottom: CGFloat = 0

    /// How far down the reading line sits: the top padding plus the blank
    /// first line, the same inset Call Assist uses.
    static func focusTop(fontSize: Double, lineHeight: Double) -> CGFloat {
        32 + lineBlock(fontSize: fontSize, lineHeight: lineHeight)
    }

    static func lineBlock(fontSize: Double, lineHeight: Double) -> CGFloat {
        fontSize * 1.3 + lineHeight
    }

    var body: some View {
        GeometryReader { geo in
            LinearGradient(stops: Self.stops(height: geo.size.height, reservedBottom: reservedBottom,
                                             preferences: preferences),
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// Opacity stops down the panel, in order, as fractions of its height.
    static func stops(height: CGFloat, reservedBottom: CGFloat = 0, preferences: Preferences) -> [Gradient.Stop] {
        guard height > 0 else { return [.init(color: .white, location: 0)] }
        let line = lineBlock(fontSize: preferences.fontSize, lineHeight: preferences.lineHeight)
        let top = focusTop(fontSize: preferences.fontSize, lineHeight: preferences.lineHeight)
        let bottom = top + line
        var points: [(y: CGFloat, alpha: Double)] = []
        if preferences.enableTopFade {
            points += [(0, 0.22), (max(0, top - preferences.topFadeHeight), 0.22)]
        } else {
            points += [(0, 1)]
        }
        points += [(top, 1), (bottom, 1)]
        // The text ends this far up, fading out over the strip above it, so
        // lines are not cut off at the edge or run under the controls.
        let end = height - reservedBottom
        let edge: CGFloat = 24
        if preferences.enableBottomFade {
            points += [(bottom + preferences.bottomFadeHeight, 0.55), (end - edge, 0.55), (end, 0)]
        } else if reservedBottom > 0 {
            points += [(end - edge, 1), (end, 0)]
        } else {
            points += [(height, 1)]
        }
        if end < height { points += [(height, 0)] }
        var last: CGFloat = 0
        return points.map { point in
            last = max(last, min(point.y / height, 1))
            return .init(color: .white.opacity(point.alpha), location: last)
        }
    }
}

/// A thin line along the bottom showing how far through the script it is.
struct ProgressLine: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color.opacity(0.85))
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}

/// Shown when paused or hovered: slower, play and faster, and the speed.
/// While voice activation listens it shows the mic level instead.
struct StatusRow: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Playback.self) private var playback
    @Environment(ShortcutGuide.self) private var guide

    var body: some View {
        let color = preferences.prompterTheme.textColor
        ZStack {
            if playback.isListening, let monitor = playback.audioMonitor {
                LevelMeter(monitor: monitor, threshold: Double(preferences.audioThreshold), color: color)
            } else {
                HStack(spacing: 8) {
                    RoundButton(symbol: "minus", help: "Slower (⌃⌥←)", color: color) {
                        playback.decreaseSpeed()
                        guide.usedMouse(for: .slower)
                    }
                    playButton(color: color)
                    RoundButton(symbol: "plus", help: "Faster (⌃⌥→)", color: color) {
                        playback.increaseSpeed()
                        guide.usedMouse(for: .faster)
                    }
                }
                HStack {
                    Spacer()
                    Text("Speed \(Int(preferences.speed))")
                        .font(.system(size: 12))
                        .foregroundStyle(color.opacity(0.62))
                        .monospacedDigit()
                }
            }
        }
        .frame(height: 36)
    }

    private func playButton(color: Color) -> some View {
        let voice = preferences.voiceActivation
        let symbol = voice ? "mic.fill" : (playback.isPlaying ? "pause.fill" : "play.fill")
        let help = voice ? "Start listening (⌃⌥P)" : (playback.isPlaying ? "Pause (⌃⌥P)" : "Play (⌃⌥P)")
        return Button {
            playback.togglePlayback()
            guide.usedMouse(for: .playPause)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(preferences.prompterTheme.backgroundColor)
                .frame(width: 34, height: 34)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Five bars lit by the mic level, green once it is loud enough to scroll.
private struct LevelMeter: View {
    @ObservedObject var monitor: AudioMonitor
    let threshold: Double
    let color: Color
    private static let heights: [CGFloat] = [6, 12, 16, 9, 5]

    var body: some View {
        let level = min(max(Double(monitor.rmsLevel) / 0.1, 0), 1)
        let lit = Int((level * 5).rounded())
        let heard = Double(monitor.rmsLevel) > threshold
        let active = Color(red: 0.37, green: 0.88, blue: 0.56)
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 11))
                .foregroundStyle(heard ? active : color.opacity(0.62))
            HStack(spacing: 3) {
                ForEach(Self.heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(index < lit ? active : color.opacity(0.25))
                        .frame(width: 3, height: Self.heights[index])
                }
            }
            .frame(height: 16)
            Text("Scrolling while you speak")
                .font(.system(size: 12))
                .foregroundStyle(color.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the prompter shrinks to when there is nothing to read: "Done" at
/// the end of the script, or "No script" with an empty library.
struct PrompterPill: View {
    enum Kind { case finished, noScript }
    @Environment(Preferences.self) private var preferences
    let kind: Kind

    var body: some View {
        let color = preferences.prompterTheme.textColor
        HStack(spacing: 8) {
            switch kind {
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(red: 0.12, green: 0.54, blue: 0.3))
                Text("Done").foregroundStyle(color)
                Text("·  ⌃⌥P again").foregroundStyle(color.opacity(0.62))
            case .noScript:
                Image(systemName: "doc.text").foregroundStyle(color.opacity(0.62))
                Text("No script").foregroundStyle(color)
                Text("·  ⌃⌥O to load").foregroundStyle(color.opacity(0.62))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .accessibilityElement(children: .combine)
    }
}
