import XCTest

final class CadenceSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCapturePrimaryScreensInDemoMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode"]
        app.launch()

        let screenshotDir = ProcessInfo.processInfo.environment["CADENCE_SCREENSHOT_DIR"]

        func capture(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let screenshotDir, !screenshotDir.isEmpty {
                let url = URL(fileURLWithPath: screenshotDir).appendingPathComponent("\(name).png")
                try? shot.pngRepresentation.write(to: url)
            }
        }

        // 1. Home feed
        XCTAssertTrue(app.staticTexts["Cadence"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Speed dial"].waitForExistence(timeout: 5))
        capture("01-home")

        // 2. Scroll Home to Mixed For You
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Mixed for you"].waitForExistence(timeout: 5))
        capture("02-home-mixes")

        // 3. Open Discover Mix detail
        app.staticTexts["Discover Mix"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play Mix"].waitForExistence(timeout: 5))
        capture("03-mix-detail")

        // 4. Open Now Playing via MiniPlayer
        app.buttons["Play Mix"].tap()
        if app.staticTexts["Iceberg"].firstMatch.waitForExistence(timeout: 3) {
            app.staticTexts["Iceberg"].firstMatch.tap()
        } else if app.staticTexts["Nuit Blanche"].firstMatch.waitForExistence(timeout: 3) {
            app.staticTexts["Nuit Blanche"].firstMatch.tap()
        }
        if app.buttons["Lyrics"].waitForExistence(timeout: 5) {
            capture("04-now-playing")
            app.buttons["Lyrics"].tap()
            capture("05-now-playing-lyrics")
            app.swipeDown()
        }

        // 5. Mixes & Radio tab
        app.tabBars.buttons["Mixes"].tap()
        XCTAssertTrue(app.staticTexts["Mixes & Radio"].waitForExistence(timeout: 5))
        capture("06-radio-tab")

        // 6. Library tab
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))
        capture("07-library-tab")

        // 7. Search tab
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Search"].waitForExistence(timeout: 5))
        capture("08-search-tab")
    }
}
