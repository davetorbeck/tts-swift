import XCTest

@testable import tts

final class TTSAppTests: XCTestCase {
    func testAppSupportDirStable() {
        let dir1 = KokoroRunner.appSupportDirForTests()
        let dir2 = KokoroRunner.appSupportDirForTests()
        XCTAssertEqual(dir1, dir2)
        XCTAssertTrue(dir1.path.contains("tts-swift"))
    }

    func testRunProcessBadExecutableFails() {
        let result = KokoroRunner.runProcessForTests(
            executable: "/usr/bin/does-not-exist", arguments: [])
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testRunnerErrorMessages() {
        let error = KokoroRunner.RunnerError.failedExit(code: 1, stderr: "boom")
        XCTAssertTrue((error.errorDescription ?? "").contains("boom"))
    }

    func testVoiceListParserRejectsInvalidJSON() {
        XCTAssertThrowsError(try KokoroRunner.decodeVoicesForTests("not-json"))
    }
}
