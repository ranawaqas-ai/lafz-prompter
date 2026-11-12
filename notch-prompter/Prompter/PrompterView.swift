import SwiftUI

struct PrompterView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Playback.self) private var playback
    @Environment(ScriptLibrary.self) private var library
    @Environment(ShortcutGuide.self) private var guide

    // Measure content height to stop appropriately
    @State private var contentHeight: CGFloat = 0

    // Tracks whether we paused due to hover and what the previous play state was
    @State private var wasPlayingBeforeHover: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        ScrollablePrompterView(
            models: PrompterModels(preferences: preferences, playback: playback, library: library, guide: guide),
            contentHeight: $contentHeight,
            isHovering: $isHovering,
            wasPlayingBeforeHover: $wasPlayingBeforeHover
        )
    }
}

/// The models the prompter's content reads. The content sits in its own
/// NSHostingView, which the SwiftUI environment does not reach, so they are
/// handed across and put back into its environment.
struct PrompterModels {
    let preferences: Preferences
    let playback: Playback
    let library: ScriptLibrary
    let guide: ShortcutGuide
}

// MARK: Scrollable Prompter View with NSView for scroll events
struct ScrollablePrompterView: NSViewRepresentable {
    let models: PrompterModels
    @Binding var contentHeight: CGFloat
    @Binding var isHovering: Bool
    @Binding var wasPlayingBeforeHover: Bool
    
    func makeNSView(context: Context) -> PrompterHostingView {
        let hostingView = PrompterHostingView(
            models: models,
            contentHeight: $contentHeight,
            isHovering: $isHovering,
            wasPlayingBeforeHover: $wasPlayingBeforeHover
        )
        return hostingView
    }
    
    func updateNSView(_ nsView: PrompterHostingView, context: Context) {
        nsView.updateContent()
    }
}

// MARK: - Custom NSView to handle scroll events
class PrompterHostingView: NSView {
    private let models: PrompterModels
    private var hostingView: NSHostingView<AnyView>!
    private var trackingArea: NSTrackingArea?
    @Binding var contentHeight: CGFloat
    @Binding var isHovering: Bool
    @Binding var wasPlayingBeforeHover: Bool
    
    init(models: PrompterModels,
         contentHeight: Binding<CGFloat>,
         isHovering: Binding<Bool>,
         wasPlayingBeforeHover: Binding<Bool>) {
        self.models = models
        self._contentHeight = contentHeight
        self._isHovering = isHovering
        self._wasPlayingBeforeHover = wasPlayingBeforeHover
        super.init(frame: .zero)
        
        hostingView = NSHostingView(rootView: content(contentHeight: contentHeight))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateContent() {
        hostingView.rootView = content(contentHeight: $contentHeight)
    }

    private func content(contentHeight: Binding<CGFloat>) -> AnyView {
        AnyView(PrompterContentView(contentHeight: contentHeight)
            .environment(models.preferences)
            .environment(models.playback)
            .environment(models.library)
            .environment(models.guide))
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways
        ]
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        handleHoverChange(hovering: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        handleHoverChange(hovering: false)
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Only handle scroll when hovering
        guard isHovering else { return }
        
        // Handle vertical scroll
        let scrollAmount = event.scrollingDeltaY
        let sensitivity: CGFloat = 2.0 // Adjust scroll sensitivity
        
        models.playback.offset = max(0, models.playback.offset - scrollAmount * sensitivity)
    }
    
    private func handleHoverChange(hovering: Bool) {
        let playback = models.playback
        guard models.preferences.pauseOnHover else {
            isHovering = false
            wasPlayingBeforeHover = false
            return
        }

        if hovering {
            isHovering = true
            wasPlayingBeforeHover = playback.isPlaying
            if playback.isPlaying {
                playback.pause()
            }
        } else {
            if isHovering, wasPlayingBeforeHover {
                playback.play()
            }
            isHovering = false
            wasPlayingBeforeHover = false
        }
    }
}

// MARK: - Content View (SwiftUI)
struct PrompterContentView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Playback.self) private var playback
    @Environment(ScriptLibrary.self) private var library
    @Environment(ShortcutGuide.self) private var guide
    @Binding var contentHeight: CGFloat
    @State private var isHovered = false

    var body: some View {
        let theme = preferences.prompterTheme
        ZStack {
            theme.backgroundColor.opacity(preferences.backgroundOpacity)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PrompterTextView()
                        .frame(width: geo.size.width, alignment: .center)
                        .offset(y: -playback.offset)
                        .background(HeightReader(height: $contentHeight))
                    Spacer(minLength: 0)
                }
                .clipped()
                .mask(ReadingFocusMask(reservedBottom: reservedBottom))
                .onChange(of: playback.offset) { _, newValue in
                    if contentHeight > 0, newValue >= contentHeight {
                        // We've scrolled past the end - stop at the end
                        playback.offset = contentHeight
                        playback.finishScript()
                    }
                }
                .onChange(of: library.text) { _, _ in
                    // reset offset when text changes to avoid jump into middle
                    playback.offset = 0
                }
            }
            // Kept laid out while finished, so its measured height stays put.
            .opacity(pill == nil ? 1 : 0)

            if let pill {
                VStack {
                    Spacer()
                    PrompterPill(kind: pill).padding(.bottom, 16)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    if let hint = guide.hint {
                        ShortcutHint(shortcut: hint, color: theme.textColor).transition(.opacity)
                    } else if showsStatusRow {
                        StatusRow().transition(.opacity)
                    }
                    if preferences.showProgressBar {
                        ProgressLine(progress: progress, color: theme.textColor)
                    }
                }
                .padding(.horizontal, 16)
                // The progress line may sit over the bottom resize strip (it
                // takes no clicks); the buttons always stay above its 24 px.
                .padding(.bottom, controlsBottom)
                .animation(.easeInOut(duration: 0.2), value: showsStatusRow)
                .animation(.easeInOut(duration: 0.2), value: guide.hint)
            }
        }
        .ignoresSafeArea()
        .onHover { isHovered = $0 }
    }

    /// Shown in place of the script when there is nothing to read.
    private var pill: PrompterPill.Kind? {
        if library.current == nil { return .noScript }
        return playback.isFinished ? .finished : nil
    }

    /// Paused, listening, or hovered with hover controls on.
    private var showsStatusRow: Bool {
        playback.isListening || !playback.isPlaying || (isHovered && preferences.showHoverControls)
    }

    /// Space under the bottom controls: above the resize strip for the row,
    /// or closer for the progress line, which takes no clicks.
    private var controlsBottom: CGFloat { preferences.showProgressBar ? 12 : 28 }

    /// Bottom padding, plus the progress line, plus the status row above it.
    private var reservedBottom: CGFloat {
        guard pill == nil else { return 0 }
        let rowShown = showsStatusRow || guide.hint != nil
        guard preferences.showProgressBar || rowShown else { return 0 }
        var height = controlsBottom
        if preferences.showProgressBar { height += 3 }
        if rowShown { height += 36 + (preferences.showProgressBar ? 12 : 0) }
        return height
    }

    private var progress: Double {
        contentHeight > 0 ? Double(playback.offset / contentHeight) : 0
    }
}
