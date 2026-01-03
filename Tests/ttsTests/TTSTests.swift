import KeyboardShortcuts
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

final class KeyboardShortcutTests: XCTestCase {
    func testSpeakSelectedTextShortcutNameExists() {
        let name = KeyboardShortcuts.Name.speakSelectedText
        XCTAssertEqual(name.rawValue, "speakSelectedText")
    }

    func testDefaultShortcutIsControlCommandA() {
        let defaultShortcut = KeyboardShortcuts.Name.speakSelectedText.defaultShortcut
        XCTAssertNotNil(defaultShortcut)
        XCTAssertEqual(defaultShortcut?.key, .a)
        XCTAssertTrue(defaultShortcut?.modifiers.contains(.command) ?? false)
        XCTAssertTrue(defaultShortcut?.modifiers.contains(.control) ?? false)
    }

    func testShortcutCanBeSetAndRetrieved() {
        let testShortcut = KeyboardShortcuts.Shortcut(.b, modifiers: [.option, .command])
        KeyboardShortcuts.setShortcut(testShortcut, for: .speakSelectedText)

        let retrieved = KeyboardShortcuts.getShortcut(for: .speakSelectedText)
        XCTAssertEqual(retrieved?.key, .b)
        XCTAssertTrue(retrieved?.modifiers.contains(.option) ?? false)
        XCTAssertTrue(retrieved?.modifiers.contains(.command) ?? false)

        KeyboardShortcuts.reset(.speakSelectedText)
    }

    func testShortcutResetRestoresDefault() {
        let customShortcut = KeyboardShortcuts.Shortcut(.z, modifiers: [.shift, .command])
        KeyboardShortcuts.setShortcut(customShortcut, for: .speakSelectedText)

        KeyboardShortcuts.reset(.speakSelectedText)

        let afterReset = KeyboardShortcuts.getShortcut(for: .speakSelectedText)
        XCTAssertEqual(afterReset?.key, .a)
        XCTAssertTrue(afterReset?.modifiers.contains(.control) ?? false)
        XCTAssertTrue(afterReset?.modifiers.contains(.command) ?? false)
    }
}
