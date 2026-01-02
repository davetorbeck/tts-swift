import XCTest

@testable import tts

final class TTSAppTests: XCTestCase {
    func testAppSupportDirStable() {
        let dir1 = KokoroRunner.appSupportDirForTests()
        let dir2 = KokoroRunner.appSupportDirForTests()
        XCTAssertEqual(dir1, dir2)
        XCTAssertTrue(dir1.path.contains("tts-swift"))
    }
}
