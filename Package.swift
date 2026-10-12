// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "My CRM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "My CRM",
            targets: ["My CRM"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "12.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "My CRM",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: ".",
                                exclude: [
                        "build",
                        "dmg_staging",
                        "My CRMUITests",
                        "My CRMTests",
                        "Tests",

                        "README.md",
                        "build_app.sh",
                        "build_drop_test.sh",
                        "build_and_setup.sh",
                        "Package.swift",
                        "Package.swift.backup",
                        ".git",
                        ".DS_Store",
                        "Documentation",
                        "Temp Files for Reference (to Delete)",
                        "test_results",
                        "My CRM Installer.dmg",
                        "My CRM Installer_v1.0.0.dmg",
                        "build_run.log",
                        "mycrm_root_certs.pem",
                        "Features/ContentView.swift",
                        "Resources/mycrm.brand.json",
                        "Settings/AppSettingsView.swift",
                        "My CRM/My_CRM.entitlements",
                        "Resources/Assets.xcassets",
                        "App/Feature Groups/iMessage Server Scraper/Resources",
                        "App/Feature Groups/iMessage Server Scraper/MacOS",
                        "App/Info.plist",
                        "drop_test_build",
                        "DropTestApp.swift",
                        "create_signing_cert.sh",
                        "create_codesign_cert.sh",
                        "fix_database_lock_manual.sh",
                        "verify_data_import.sh",
                        "verify_distribution.sh",
                        "remote_diagnosis_and_fix.sh",
                        "setup_certificate.sh",
                        "setup_permissions.sh",
                        "setup_ssh_key.sh",
                        "cleanup_mycrm.sh",
                        "check_io_error_causes.sh",
                        "diagnose_remote_live.sh",
                        "diagnose_remote_database.sh",
                        "create_dmg.sh",
                        "create_dmg_simple.sh",
                        "My CRM.xcodeproj.backup"
                    ],
            sources: [
                "App",
                "Core", 
                "State",
                "UI"
            ],
            resources: [
                .copy("Resources/quick_send_helper.sh")
            ]
        ),
        .testTarget(
            name: "MyCRMTests",
            dependencies: [
                "My CRM",
                "Quick",
                "Nimble"
            ],
            path: "Tests",
            exclude: [
                "README.md",
                "run_tests.sh",
                "FuzzyMatcherTests.swift",
                "DragDropTests.swift"
            ],
            sources: [
                "UnitTests/SimpleXCTests.swift",
                "UnitTests/GroupManagementTests.swift",
                "UnitTests/DragDropGroupTests.swift",
                "UnitTests/GroupOperationsTests.swift",
                "UnitTests/GroupDatabaseTests.swift",
                "UnitTests/ContactBarToGroupsBarDragDropTests.swift"
            ]
        )
    ]
)
