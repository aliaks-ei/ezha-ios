// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "EZHAKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "EZHAKit", targets: ["EZHAKit"])
  ],
  dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.3")
  ],
  targets: [
    .target(
      name: "EZHAKit",
      dependencies: [.product(name: "Supabase", package: "supabase-swift")],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "EZHAKitTests", dependencies: ["EZHAKit"]),
  ]
)
