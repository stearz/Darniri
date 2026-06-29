import SwiftUI

struct SettingsPage<Content: View>: View {
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        Form {
            if let subtitle {
                Section {
                    SettingsCaption(subtitle)
                }
            }

            content()
        }
        .formStyle(.grouped)
    }
}

struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct SettingsValueText: View {
    let text: String
    var width: CGFloat = 56

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
            .accessibilityHidden(true)
    }
}

struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    var valueWidth: CGFloat = 56

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range, step: step) {
                    Text(label)
                }
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(valueText)

                SettingsValueText(text: valueText, width: valueWidth)
            }
        }
    }
}

struct ResetIconButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.uturn.backward.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(title)
    }
}

