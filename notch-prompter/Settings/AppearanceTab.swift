import SwiftUI

// MARK: - Appearance Tab
struct AppearanceTabView: View {
    @Environment(Preferences.self) private var preferences

    private let installedFontFamilies = NSFontManager.shared.availableFontFamilies

    // The style buttons only apply to the system font.
    private func isSelected(_ design: Font.Design) -> Bool {
        !preferences.fontChoice.isCustom && preferences.fontDesign == design
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Script")
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Style")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach([Font.Design.default, .serif, .rounded, .monospaced], id: \.self) { design in
                            Button {
                                preferences.fontDesign = design
                                if preferences.fontChoice.isCustom {
                                    preferences.fontChoice = .automatic
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(design.icon)
                                        .font(design.previewFont)
                                    Text(design.displayLocalizedName)
                                        .font(.system(size: 11))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    isSelected(design) 
                                        ? Color.accentColor.opacity(0.15) 
                                        : Color(NSColor.controlBackgroundColor)
                                )
                                .foregroundStyle(
                                    isSelected(design) 
                                        ? Color.accentColor 
                                        : .primary
                                )
                                .contentShape(Rectangle())
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(
                                            isSelected(design) 
                                                ? Color.accentColor 
                                                : Color.primary.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("Font", selection: Bindable(preferences).fontChoice) {
                        Text("Automatic").tag(PrompterFontChoice.automatic)
                        Text("System").tag(PrompterFontChoice.system)
                        Divider()
                        ForEach(installedFontFamilies, id: \.self) { family in
                            Text(family).tag(PrompterFontChoice.custom(family))
                        }
                    }
                    .font(.system(size: 12))

                    Text("Automatic uses a Nastaliq font for Urdu and the style above for everything else.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                SettingSlider(
                    label: "Size",
                    value: Bindable(preferences).fontSize,
                    range: 8...80,
                    step: 1,
                    unit: "pt"
                )
                
                SettingSlider(
                    label: "Line spacing",
                    value: Bindable(preferences).lineHeight,
                    range: 0...20,
                    step: 1,
                    unit: "pt"
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alignment")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(PrompterTextAlignment.allCases, id: \.self) { alignment in
                            Button {
                                preferences.textAlignment = alignment
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
                                    preferences.textAlignment == alignment 
                                        ? Color.accentColor.opacity(0.15) 
                                    : Color(NSColor.controlBackgroundColor)
                                )
                                .foregroundStyle(
                                    preferences.textAlignment == alignment 
                                        ? Color.accentColor 
                                        : .primary
                                )
                                .contentShape(Rectangle())
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(
                                            preferences.textAlignment == alignment 
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
                
                Divider()
                
                Text("Theme")
                    .font(.system(size: 13, weight: .medium))
                
                Picker("", selection: Bindable(preferences).prompterTheme) {
                    ForEach(PrompterTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                SettingSlider(
                    label: "Background opacity",
                    value: Bindable(preferences).backgroundOpacity,
                    range: 0.2...1.0,
                    step: 0.05,
                    unit: "",
                    isPercentage: true
                )
                Text("Lower it to see what is behind the prompter. The text stays solid.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Divider()
                
                Text("Fade Effects")
                    .font(.system(size: 13, weight: .medium))
                
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Bindable(preferences).enableTopFade)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    VStack(alignment: .leading) {
                        Text("Top fade")
                            .font(.system(size: 13))
                        Text("Fade out content at the top of the prompter")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if preferences.enableTopFade {
                    SettingSlider(
                        label: "Height",
                        value: Bindable(preferences).topFadeHeight,
                        range: 10...150,
                        step: 5,
                        unit: "px"
                    )
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Bindable(preferences).enableBottomFade)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    VStack(alignment: .leading) {
                        Text("Bottom fade")
                            .font(.system(size: 13))
                        Text("Fade out content at the bottom of the prompter")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if preferences.enableBottomFade {
                    SettingSlider(
                        label: "Height",
                        value: Bindable(preferences).bottomFadeHeight,
                        range: 10...150,
                        step: 5,
                        unit: "px"
                    )
                }
            }
            .padding(16)
        }
    }
}
