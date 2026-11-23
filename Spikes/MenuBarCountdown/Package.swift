// swift-tools-version: 6.2
// Phase 0 spike (D-25, D-24). Throwaway: delete once DECISIONS.md "Phase 0 results" is filled in.
import PackageDescription

let package = Package(
    name: "Spike",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "Spike")]
)
