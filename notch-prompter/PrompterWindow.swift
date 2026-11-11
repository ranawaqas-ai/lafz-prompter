import AppKit
import SwiftUI
import Combine

final class PrompterWindow {
    private var window: NSWindow!
    private let viewModel: PrompterViewModel
    private var cancellables: Set<AnyCancellable> = []

    @MainActor
    init(viewModel: PrompterViewModel, callAssist: CallAssistController, scripts: ScriptLibrary) {
        self.viewModel = viewModel

        let contentView = PrompterRootView(viewModel: viewModel, callAssist: callAssist)
            // Dropping a script file on the prompter loads it straight away.
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(ScriptImporter.canRead)
                guard !files.isEmpty else { return false }
                scripts.importFiles(files)
                return scripts.importError == nil
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            )).border(Color.black.opacity(0.0), width: 0)

        let hosting = FirstMouseHostingView(rootView: contentView)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true

        // A non-activating panel: clicking or dragging the prompter leaves the
        // app the user is in (a call, an editor) active, and does not bring
        // the Settings window forward with it.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: viewModel.prompterWidth,
                                height: viewModel.prompterHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        window = panel

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = false // true adds a little cool effect, but it's not needed for "Notch" type app
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.contentView = hosting

        viewModel.$prompterWidth
            .combineLatest(viewModel.$prompterHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] width, height in
                self?.resizeWindow(width: width, height: height)
            }
            .store(in: &cancellables)
        
        viewModel.$selectedScreenIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.resizeWindow(width: self.viewModel.prompterWidth, height: self.viewModel.prompterHeight)
            }
            .store(in: &cancellables)
        
        viewModel.$horizontalAlignment
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.resizeWindow(width: self.viewModel.prompterWidth, height: self.viewModel.prompterHeight)
            }
            .store(in: &cancellables)
        
        viewModel.$isPrompterVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.animateShow()
                } else {
                    self?.animateHide()
                }
            }
            .store(in: &cancellables)
        
        // A Call Assist answer is always hidden from screen sharing, whatever
        // the setting says: the other side of the call must not see it.
        viewModel.$hideFromScreenRecording
            .combineLatest(callAssist.$state.map { $0 != .idle })
            .receive(on: RunLoop.main)
            .sink { [weak self] hideFromRecording, assisting in
                self?.updateScreenRecordingVisibility(hideFromRecording || assisting)
            }
            .store(in: &cancellables)
    }

    func show() {
        guard let screen = getSelectedScreen() else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let frame = topCenterFrame(width: viewModel.prompterWidth, height: viewModel.prompterHeight, screen: screen)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizeWindow(width: CGFloat, height: CGFloat) {
        guard let screen = getSelectedScreen() else { return }
        let frame = topCenterFrame(width: width, height: height, screen: screen)

        window.setFrame(frame, display: true, animate: !viewModel.isResizing)
    }
    
    private func getSelectedScreen() -> NSScreen? {
        viewModel.prompterScreen
    }

    private func topCenterFrame(width: CGFloat, height: CGFloat, screen: NSScreen) -> CGRect {
        // Calculate horizontal position based on alignment
        // Convert alignment enum to position: left = 0.0, center = 0.5, right = 1.0
        let alignmentPosition: CGFloat = {
            switch viewModel.horizontalAlignment {
            case .left: return 0.0
            case .center: return 0.5
            case .right: return 1.0
            }
        }()
        
        let padding: CGFloat = 20 // minimum padding from screen edges
        let availableWidth = screen.frame.width - width - (padding * 2)
        let x = screen.frame.minX + padding + (availableWidth * alignmentPosition)
        
        let heightOfBorderTopWithRadiusToHide: CGFloat = 4
        let y = screen.frame.maxY - height + heightOfBorderTopWithRadiusToHide
        // MARK: slight offset to hide border under notch, this probably causes the issue with moving the notch view to another display when another display is on bottom/top
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func updateScreenRecordingVisibility(_ hideFromRecording: Bool) {
        // https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property
        if hideFromRecording {
            window.sharingType = .none
        } else {
            window.sharingType = .readOnly
        }
    }
    
    private let animationSpeed = 0.25
    
    private func animateShow() {
        guard let screen = getSelectedScreen() else { return }
        let finalFrame = topCenterFrame(width: viewModel.prompterWidth, height: viewModel.prompterHeight, screen: screen)

        var startFrame = finalFrame
        startFrame.origin.y = screen.frame.maxY
        
        window.setFrame(startFrame, display: false)
        window.orderFront(nil)
    
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationSpeed
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
        }
    }
    
    private func animateHide() {
        guard let screen = getSelectedScreen() else {
            window.orderOut(nil)
            return
        }
        
        let currentFrame = window.frame
        var targetFrame = currentFrame
        targetFrame.origin.y = screen.frame.maxY
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationSpeed
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
        })
    }
}

/// The prompter panel never becomes key, so every click on it is a "first
/// mouse" click; accepting those lets the hover buttons work in one click.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
