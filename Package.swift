// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GeradorDocumentos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GeradorDocumentos", targets: ["GeradorDocumentos"]),
        .library(name: "DocxTemplateKit", targets: ["DocxTemplateKit"]),
    ],
    targets: [
        .target(name: "DocxTemplateKit"),
        .executableTarget(
            name: "GeradorDocumentos",
            dependencies: ["DocxTemplateKit"]
        ),
        .testTarget(
            name: "DocxTemplateKitTests",
            dependencies: ["DocxTemplateKit"]
        ),
    ]
)
