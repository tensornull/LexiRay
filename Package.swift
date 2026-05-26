// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "LexiRayDependencies",
  platforms: [
    .macOS(.v15)
  ],
  products: [],
  dependencies: [
    .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")
  ]
)
