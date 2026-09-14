// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FollowScriptCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FollowScriptCore", targets: ["FollowScriptCore"])
    ],
    targets: [
        .target(
            name: "FollowScriptCore",
            path: "FollowScript",
            exclude: [
                "App", "Assets.xcassets", "Info.plist", "ScriptEditor", "Settings", "Speech", "Teleprompter"
            ],
            sources: ["Models", "Alignment"]
        ),
        .testTarget(
            name: "FollowScriptCoreTests",
            dependencies: ["FollowScriptCore"],
            path: "FollowScriptTests",
            exclude: ["MockSpeechRecognitionServiceTests.swift"],
            sources: [
                "AlignmentClusterTests.swift",
                "AlignmentFixtures.swift",
                "ScriptAlignmentEngineTests.swift",
                "ScriptTokenizerTests.swift",
                "SpeechRecognitionSegmentAssemblerTests.swift",
                "StreamingASRAlignmentTests.swift"
            ]
        )
    ]
)
