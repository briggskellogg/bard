// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "WispCore", targets: ["WispCore"])]
var targets: [Target] = [
    .target(name: "WispCore"),
    .testTarget(name: "WispCoreTests", dependencies: ["WispCore"])
]

#if os(macOS)
products.append(.executable(name: "Wisp", targets: ["Wisp"]))
targets.append(.target(name: "WispAudioAtomics", publicHeadersPath: "include"))
targets.append(.executableTarget(
    name: "Wisp",
    dependencies: ["WispCore", "WispAudioAtomics"],
    // Retain the former instrument's source for future work without shipping it.
    exclude: ["InstrumentStore.swift", "InstrumentPhrase.swift", "Views/InstrumentView.swift"],
    resources: [.copy("Resources/wisp-mark.png"), .copy("Resources/wisp-insignia.png"),
                .copy("Resources/mixtape-cover.png"), .copy("Resources/maker-mark.png"),
                .copy("Resources/Fonts"), .copy("Resources/Icons")]
))
#endif

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5],
    cLanguageStandard: .c11
)
