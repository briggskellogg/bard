import AppKit
import CoreText
import SwiftUI

/// Shared family typography: Clay's readable sans for controls and song lists,
/// Pearls' editorial serif for page headings, and monospaced numeric readouts.
enum WispType {
    /// Safe to call at launch or repeatedly; registration occurs once per process.
    static func registerFonts() {
        _ = registeredNames
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let points = max(11, size)
        let bold = [.semibold, .bold, .heavy, .black].contains(weight)
        return font(bold ? "PPNeueMontreal-Bold" : "PPNeueMontreal-Regular",
                    size: points, fallback: .system(size: points, weight: weight))
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let points = max(17, size * 0.86)
        return font("PPNeueYork-NormalExtrabold", size: points,
                    fallback: .system(size: points, weight: .bold))
    }

    static func readout(_ size: CGFloat) -> Font {
        .system(size: max(11, size * 0.72), weight: .regular, design: .monospaced)
    }

    private static func usesMedium(_ weight: Font.Weight) -> Bool {
        [.medium, .semibold, .bold, .heavy, .black].contains(weight)
    }

    private static func font(_ name: String, size: CGFloat, fallback: Font) -> Font {
        guard registeredNames.contains(name) else { return fallback }
        return .custom(name, fixedSize: size)
    }

    private static let registeredNames: Set<String> = {
        let faces: [(file: String, ext: String, postScriptName: String)] = [
            ("PPNeueMontreal-Regular", "ttf", "PPNeueMontreal-Regular"),
            ("PPNeueMontreal-Bold", "ttf", "PPNeueMontreal-Bold"),
            ("IBMPlexMono-Regular", "ttf", "IBMPlexMono-Regular"),
            ("IBMPlexMono-Medium", "ttf", "IBMPlexMono-Medium"),
            ("PPNeueYork-NormalLight", "otf", "PPNeueYork-NormalLight"),
            ("PPNeueYork-NormalMedium", "otf", "PPNeueYork-NormalMedium"),
            ("PPNeueYork-NormalExtrabold", "otf", "PPNeueYork-NormalExtrabold"),
            ("PPHatton-Light", "otf", "PPHatton-Light"),
            ("PPHatton-Medium", "otf", "PPHatton-Medium"),
            ("PPNeueBit-Regular", "ttf", "PPNeueBit-Regular")
        ]
        var names = Set<String>()
        for face in faces {
            if let url = resourceURL(face.file, extension: face.ext) {
                // Process scope leaves the user's installed font collection untouched.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            if NSFont(name: face.postScriptName, size: 14) != nil {
                names.insert(face.postScriptName)
            }
        }
        return names
    }()

    private static func resourceURL(_ name: String, extension ext: String) -> URL? {
        WispResources.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
    }
}
