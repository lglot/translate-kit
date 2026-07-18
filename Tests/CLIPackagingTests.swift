import Foundation
import XCTest

final class CLIPackagingTests: XCTestCase {
    func testMakefileBuildsAndPackagesTKitAuxiliaryExecutable() throws {
        let makefileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Makefile")
        let makefile = try String(contentsOf: makefileURL, encoding: .utf8)

        XCTAssertTrue(makefile.contains("swift build --product tkit"))
        XCTAssertTrue(makefile.contains("Contents/MacOS/tkit"))
        XCTAssertTrue(makefile.contains("$(APP_BUNDLE)/Contents/MacOS/tkit"))
        XCTAssertTrue(makefile.contains("run-cli:"))
    }
}
