import SwiftUI

// MARK: - Layout Tab
struct LayoutTabView: View {
    @Environment(Preferences.self) private var preferences
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Window")
                    .font(.system(size: 13, weight: .medium))
                
                SettingSlider(
                    label: "Width",
                    value: Binding(
                        get: { Double(preferences.prompterWidth) },
                        set: { preferences.prompterWidth = CGFloat($0) }
                    ),
                    range: Double(preferences.prompterWidthRange.lowerBound)...Double(preferences.prompterWidthRange.upperBound),
                    step: 10,
                    unit: "px"
                )
                
                SettingSlider(
                    label: "Height",
                    value: Binding(
                        get: { Double(preferences.prompterHeight) },
                        set: { preferences.prompterHeight = CGFloat($0) }
                    ),
                    range: Double(preferences.prompterHeightRange.lowerBound)...Double(preferences.prompterHeightRange.upperBound),
                    step: 10,
                    unit: "px"
                )
                
                Divider()
                
                Text("Position")
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Horizontal alignment")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(PrompterHorizontalAlignment.allCases, id: \.self) { alignment in
                            Button {
                                preferences.horizontalAlignment = alignment
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: alignment.icon)
                                        .font(.system(size: 16))
                                    Text(alignment.displayName)
                                        .font(.system(size: 11))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    preferences.horizontalAlignment == alignment 
                                        ? Color.accentColor.opacity(0.15) 
                                        : Color(NSColor.controlBackgroundColor)
                                )
                                .foregroundStyle(
                                    preferences.horizontalAlignment == alignment 
                                        ? Color.accentColor 
                                        : .primary
                                )
                                .contentShape(Rectangle())
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(
                                            preferences.horizontalAlignment == alignment 
                                                ? Color.accentColor 
                                                : Color.primary.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Text("Choose the horizontal position of the prompter on screen")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                Divider()
                
                Text("Display")
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screen")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: Bindable(preferences).selectedScreenIndex) {
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                            Text("\(screen.localizedName) (\(index + 1))").tag(index)
                        }
                    }
                    .labelsHidden()
                }
                
                Text("Choose which screen the prompter appears on")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}
