import SwiftUI

/// The two channels show real measured audio signal levels. No decorative bars are
/// generated when playback is paused, silent, or has reached the end of a queue.
@MainActor
struct StereoLevelMeter: View {
    @ObservedObject var meters: PlaybackMeters
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var width: CGFloat = 90

    var body: some View {
        VStack(spacing: 3) {
            channel("L", level: meters.levels.left)
            channel("R", level: meters.levels.right)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stereo audio levels")
        .accessibilityValue("Left \(Int(meters.levels.left * 100)) percent, right \(Int(meters.levels.right * 100)) percent")
    }

    private func channel(_ label: String, level: Double) -> some View {
        HStack(spacing: 5) {
            Text(label).font(WispType.readout(14)).foregroundStyle(.secondary).frame(width: 9)
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<16) { index in
                        Rectangle()
                            .fill(index >= 14 ? WispSurface.amber : WispSurface.cyan)
                            .opacity(level > Double(index) / 16 ? 0.9 : 0.10)
                            .frame(width: max(1, (geometry.size.width - 30) / 16))
                    }
                }
            }.frame(height: 3)
        }
        .frame(height: 9)
        .animation(reduceMotion ? nil : .linear(duration: 0.075), value: level)
    }
}
