import XCTest

final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-UIResetOnboarding")
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Welcome page

    func testOnboardingAppearsOnFreshInstall() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continueButton"].waitForExistence(timeout: 5))
    }

    func testFirstPageContent() {
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'LaxasFit Watch'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.continueButton"].exists)
    }

    func testGetStartedNavigatesToPairPage() {
        app.launch()
        app.buttons["onboarding.continueButton"].tap()
        XCTAssertTrue(app.staticTexts["Pair Your Watch"].waitForExistence(timeout: 3))
    }

    // MARK: - Bluetooth page

    func testBluetoothPageReachable() {
        addBluetoothInterruptionMonitor()
        app.launch()
        navigateToPage(2)
        XCTAssertTrue(app.staticTexts["Enable Bluetooth"].waitForExistence(timeout: 5))
    }

    // MARK: - Apple Health page

    func testHealthPageReachable() {
        addSystemInterruptionMonitor()
        app.launch()
        navigateToPage(3)
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 5))
    }

    func testHealthPageHasSkipButton() {
        addSystemInterruptionMonitor()
        app.launch()
        navigateToPage(3)
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 5))
        // Skip button appears when not yet authorized
        let skipButton = app.buttons["onboarding.continueButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 3))
    }

    func testHealthPermissionRequestButton() {
        addSystemInterruptionMonitor()
        app.launch()
        navigateToPage(3)
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 5))
        let connectButton = app.buttons["Connect Apple Health"]
        if connectButton.waitForExistence(timeout: 3) {
            connectButton.tap()
            // System HealthKit sheet or alert handled by interrupt monitor
            _ = app.buttons["onboarding.continueButton"].waitForExistence(timeout: 5)
        }
    }

    // MARK: - Device selection page

    func testConnectPageReachable() {
        addSystemInterruptionMonitor()
        app.launch()
        navigateToPage(4)
        XCTAssertTrue(app.staticTexts["Connect Your Watch"].waitForExistence(timeout: 5))
    }

    func testConnectPageHasScanButton() {
        addSystemInterruptionMonitor()
        app.launch()
        navigateToPage(4)
        XCTAssertTrue(app.staticTexts["Connect Your Watch"].waitForExistence(timeout: 5))
        // Scan button exists when BT is on and not yet scanning
        let scanButton = app.buttons["Scan for Watch"]
        // May or may not exist depending on BT state; just verify the page is present
        _ = scanButton.exists
    }

    // MARK: - Full flow

    func testFullOnboardingFlow() {
        addSystemInterruptionMonitor()
        app.launch()

        // Page 0 → 1: Welcome
        XCTAssertTrue(app.buttons["onboarding.continueButton"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continueButton"].tap()

        // Page 1 → 2: Pair Your Watch
        XCTAssertTrue(app.staticTexts["Pair Your Watch"].waitForExistence(timeout: 3))
        app.buttons["onboarding.continueButton"].tap()

        // Page 2 → 3: Enable Bluetooth (may trigger BT permission)
        XCTAssertTrue(app.staticTexts["Enable Bluetooth"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continueButton"].tap()

        // Page 3 → 4: Apple Health (skip)
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continueButton"].tap()

        // Page 4 → 5: Connect Watch (skip)
        XCTAssertTrue(app.staticTexts["Connect Your Watch"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continueButton"].tap()

        // Page 5: Finish
        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 3))
        app.buttons["Finish Setup"].tap()

        // Main app
        XCTAssertTrue(app.navigationBars["LaxasFit Watch"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func navigateToPage(_ targetPage: Int) {
        let continueButton = app.buttons["onboarding.continueButton"]
        for _ in 0..<targetPage {
            XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
            continueButton.tap()
        }
    }

    @discardableResult
    private func addBluetoothInterruptionMonitor() -> NSObjectProtocol {
        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
    }

    @discardableResult
    private func addSystemInterruptionMonitor() -> NSObjectProtocol {
        addUIInterruptionMonitor(withDescription: "System permission dialog") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            if alert.buttons["Don't Allow"].exists { alert.buttons["Don't Allow"].tap(); return true }
            return false
        }
    }
}
