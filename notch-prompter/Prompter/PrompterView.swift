import SwiftUI

struct PrompterView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Playback.self) private var playback
    @Environment(ScriptLibrary.self) private var library

    // Measure content height to stop appropriately
    @State private var contentHeight: CGFloat = 0

    // Tracks whether we paused due to hover and what the previous play state was
    @State private var wasPlayingBeforeHover: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        ScrollablePrompterView(
            models: PrompterModels(preferences: preferences, playback: playback, library: library),
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
            .environment(models.library))
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
    @Binding var contentHeight: CGFloat
    @State private var showControls = false

    var body: some View {
        ZStack {
            preferences.prompterTheme.backgroundColor.opacity(preferences.backgroundOpacity)
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
            
            // Fade overlays
            VStack(spacing: 0) {
                if preferences.enableTopFade {
                    LinearGradient(
                        gradient: Gradient(colors: [preferences.prompterTheme.fadeColor.opacity(preferences.backgroundOpacity), .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: preferences.topFadeHeight)
                    .allowsHitTesting(false)
                }
                
                Spacer()
                
                if preferences.enableBottomFade {
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, preferences.prompterTheme.fadeColor.opacity(preferences.backgroundOpacity)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: preferences.bottomFadeHeight)
                    .allowsHitTesting(false)
                }
            }
            
            // Progress bar on the right side
            if preferences.showProgressBar {
                HStack {
                    Spacer()
                    ProgressBarView(
                        currentOffset: playback.offset,
                        totalHeight: contentHeight,
                        theme: preferences.prompterTheme
                    )
                }
            }
            
            // Hover controls overlay
            if showControls && preferences.showHoverControls {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        // Play
                        if preferences.voiceActivation {
                            Button(action: {
                                playback.togglePlayback()
                            }) {
                                Image(systemName: playback.isListening ? "microphone.circle.fill" : "microphone.slash.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(playback.isListening ? .orange : .white)
                                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .help(playback.isListening ? "Stop listening" : "Start listening")
                        } else {
                            Button(action: {
                                playback.togglePlayback()
                            }) {
                                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                        // SCroll back
                        Button(action: {
                            playback.scrollBack()
                        }) {
                            Image(systemName: "backward.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("Scroll back a few lines")
                        
                        // Settings
                        Button(action: {
                            openSettingsWindow()
                        }) {
                            Image(systemName: "gearshape.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("Open Settings")
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.6))
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    )
                    // Clear of the 24 px resize handle along the bottom edge.
                    .padding(.bottom, 30)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.2), value: showControls)
            }
        }
        .ignoresSafeArea()
        .onHover { hovering in
            withAnimation {
                showControls = hovering
            }
        }
    }
    
    private func openSettingsWindow() {
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
 
        // Try to find existing settings window first
        for window in NSApp.windows {
            // SwiftUI's identifier for the Settings scene window; unlike the
            // title, it does not change with the app name.
            if window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        
        // Simulate the Command+, keyboard shortcut which opens Settings
        let keyDown = NSEvent.keyEvent(
            with: .keyDown,
            location: NSPoint.zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43 // Key code for comma
        )
        
        if let event = keyDown {
            NSApp.postEvent(event, atStart: true)
        }
    }
}
