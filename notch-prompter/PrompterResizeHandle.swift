import SwiftUI

/// A strip along the prompter's bottom edge: drag it to change the height.
/// The window keeps its top under the notch, so only the bottom moves.
struct PrompterResizeHandle: View {
    @ObservedObject var viewModel: PrompterViewModel
    @State private var startHeight: CGFloat?

    /// Same limits as the Height slider in Settings.
    static let heightRange: ClosedRange<CGFloat> = 80...500

    var body: some View {
        VStack {
            Spacer()
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(
                    // Window coordinates: the top of the window stays put while
                    // it grows, so the drag distance is the change in height.
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = startHeight ?? viewModel.prompterHeight
                            startHeight = start
                            viewModel.isResizing = true
                            let height = start + drag.translation.height
                            viewModel.prompterHeight = min(max(height, Self.heightRange.lowerBound),
                                                           Self.heightRange.upperBound).rounded()
                        }
                        .onEnded { _ in
                            startHeight = nil
                            viewModel.isResizing = false
                        }
                )
        }
    }
}
