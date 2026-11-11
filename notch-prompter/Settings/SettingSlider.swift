import SwiftUI

// MARK: - Slider Component
struct SettingSlider: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var isPercentage: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if unit == "%" && !isPercentage {
                    Text(value * 10, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else if isPercentage {
                    Text(value, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(Int(value)) \(unit)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
