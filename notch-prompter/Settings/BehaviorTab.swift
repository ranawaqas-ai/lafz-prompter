import SwiftUI

// MARK: - Behavior Tab
struct BehaviorTabView: View {
    @Environment(Preferences.self) private var preferences
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                SettingSlider(
                    label: "Scroll speed",
                    value: Bindable(preferences).speed,
                    range: 1...100,
                    step: 1,
                    unit: "pt/s"
                )
                
                Divider()
                
                Text("Mouse Interaction")
                    .font(.system(size: 13, weight: .medium))
                
                Toggle(isOn: Bindable(preferences).pauseOnHover) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause on hover")
                            .font(.system(size: 13))
                        Text("Pause scrolling when mouse enters the prompter window")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                
                Toggle(isOn: Bindable(preferences).showHoverControls) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show controls on hover")
                            .font(.system(size: 13))
                        Text("Display controls when hovering")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                
                Toggle(isOn: Bindable(preferences).showProgressBar) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show progress bar")
                            .font(.system(size: 13))
                        Text("Show how far through the script you are, as a line along the bottom")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                
                Divider()
                
                Text("Privacy")
                    .font(.system(size: 13, weight: .medium))
                
                Toggle(isOn: Bindable(preferences).hideFromScreenRecording) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide from screen recordings")
                            .font(.system(size: 13))
                        Text("Prevent the prompter from appearing in screen shares")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(16)
        }
    }
}
