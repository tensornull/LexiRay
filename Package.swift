// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "LexiRayOperations",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "lexiray-ops", targets: ["LexiRayOps"])
  ],
  targets: [
    .target(name: "LexiRayOpsCore"),
    .executableTarget(name: "LexiRayOps", dependencies: ["LexiRayOpsCore"]),
    .testTarget(name: "LexiRayOpsCoreTests", dependencies: ["LexiRayOpsCore"])
  ]
)
