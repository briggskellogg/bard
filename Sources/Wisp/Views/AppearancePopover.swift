import SwiftUI

@MainActor
struct AppearanceMenu: View {
    @Bindable private var theme = WispTheme.shared
    var iconSize: CGFloat = 12
    var height: CGFloat = 28

    var body: some View {
        Menu {
            Picker("Appearance", selection: $theme.brightness) {
                ForEach(WispBrightness.allCases) { brightness in
                    Text(brightness.title).tag(brightness)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: iconSize, weight: .regular))
                .frame(width: 22, height: height).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(WispSurface.mutedText)
        .tint(WispSurface.mutedText)
        .help("Appearance: \(theme.brightness.title)")
        .accessibilityLabel("Appearance")
        .accessibilityValue(theme.brightness.title)
    }
}
