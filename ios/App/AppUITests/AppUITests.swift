import XCTest

final class AppUITests: XCTestCase {

    let rawDir = "/Users/davidpitchkhadze/halacha-yomit-ios/appstore/screenshots/raw_framed"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Low-level helpers

    func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Don't Allow", "אפשר", "אל תאפשר", "OK", "אישור"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 1.5) {
                btn.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    // Broad accessibility-tree search across the WHOLE app, not just webviews: the native
    // tab bar, settings sheet, and stats sheet are siblings of the webview hierarchy, not
    // nested inside it, so a search scoped to app.webViews can never find them.
    func anyElement(_ app: XCUIApplication, contains text: String) -> XCUIElement {
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func exactElement(_ app: XCUIApplication, label: String) -> XCUIElement {
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func button(_ app: XCUIApplication, contains text: String) -> XCUIElement {
        return app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func tapNormalized(_ app: XCUIApplication, dx: CGFloat, dy: CGFloat) {
        dismissSystemAlerts()
        app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
    }

    func waitTap(_ element: XCUIElement, timeout: TimeInterval = 12) {
        _ = element.waitForExistence(timeout: timeout)
        dismissSystemAlerts()
        if element.exists && element.isHittable {
            element.tap()
        } else if element.exists {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func freshLaunch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.5)
        dismissSystemAlerts()
        return app
    }

    func waitForHome(_ app: XCUIApplication) -> XCUIElement {
        let learnBtn = button(app, contains: "ללמוד")
        _ = learnBtn.waitForExistence(timeout: 15)
        dismissSystemAlerts()
        if !learnBtn.exists {
            _ = learnBtn.waitForExistence(timeout: 10)
        }
        Thread.sleep(forTimeInterval: 1.5)
        return learnBtn
    }

    // Tapping the very top of the screen triggers iOS's native "scroll to top" gesture on
    // whatever the topmost scroll view is (works for WKWebView's internal scroll view too).
    // swipeDown() is a belt-and-suspenders fallback in case a page disables scrollsToTop.
    func scrollToTop(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        Thread.sleep(forTimeInterval: 0.3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        Thread.sleep(forTimeInterval: 0.3)
        app.swipeDown()
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.4)
    }

    func debugSave(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let safe = name.replacingOccurrences(of: "/", with: "_")
        do {
            try shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/dbg_\(safe).png"))
            print("DBG-SAVED \(name)")
        } catch {
            print("DBG-SAVE-FAILED \(name): \(error)")
        }
    }

    // Pauses the flow at a named checkpoint. Always writes a cheap internal debug screenshot
    // (XCUIScreen, no macOS Screen Recording permission needed) so navigation can be verified
    // independently of the external bezel capture. When EXTERNAL_CAPTURE=1 is set in the test
    // environment, it additionally does a file-handshake wait so an outside `screencapture -l`
    // process (which DOES need Screen Recording permission, and can see the real Simulator
    // window chrome/bezel that XCUIScreen never does) can grab the frame at the right instant.
    func checkpoint(_ app: XCUIApplication, _ name: String) {
        dismissSystemAlerts()
        debugSave(app, name)
        let useExternal = ProcessInfo.processInfo.environment["EXTERNAL_CAPTURE"] == "1"
        if useExternal {
            let safe = name.replacingOccurrences(of: "/", with: "_")
            let readyPath = "/tmp/shot_\(safe).ready"
            let donePath = "/tmp/shot_\(safe).done"
            try? FileManager.default.removeItem(atPath: donePath)
            FileManager.default.createFile(atPath: readyPath, contents: nil)
            print("CHECKPOINT-READY \(name)")
            let deadline = Date().addingTimeInterval(60)
            while !FileManager.default.fileExists(atPath: donePath) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
            try? FileManager.default.removeItem(atPath: donePath)
            try? FileManager.default.removeItem(atPath: readyPath)
            print("CHECKPOINT-DONE \(name)")
        } else {
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    // MARK: - App-specific navigation

    func openGear(_ app: XCUIApplication, ariaLabel: String) {
        dismissSystemAlerts()
        let el = exactElement(app, label: ariaLabel)
        if el.waitForExistence(timeout: 3), el.isHittable {
            el.tap()
            // The native sheet's presentation animation (slide-up + blur material fade-in)
            // is still visibly mid-transition at 1.2s in captured screenshots -- give it more
            // time to fully settle before any checkpoint screenshot is taken.
            Thread.sleep(forTimeInterval: 2.5)
            return
        }
        // Fallback: the two gear buttons sit top-left of the home header.
        tapNormalized(app, dx: ariaLabel.contains("הגדרות") ? 0.08 : 0.19, dy: 0.06)
        Thread.sleep(forTimeInterval: 2.5)
    }

    // Sets the native theme picker inside the already-open Settings sheet. "auto"/"light"/"dark".
    // NOTE: these are label-only SwiftUI buttons with no accessibilityIdentifier, so
    // app.buttons[label] (an IDENTIFIER-based subscript) never matches them — must use a
    // label NSPredicate instead.
    func setThemeInOpenSettings(_ app: XCUIApplication, to value: String) {
        let label = value == "dark" ? "כהה" : (value == "light" ? "בהיר" : "אוטומטי")
        let el = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if el.waitForExistence(timeout: 3), el.isHittable {
            el.tap()
        } else {
            // Segmented control fallback coordinates (auto/light/dark, left-to-right on screen
            // even though the app content is RTL — UISegmentedControl lays out LTR). Verified
            // via hierarchy dump: segmented control sits at y:575.7 of 956 (dy≈0.60–0.63).
            let dx: CGFloat = value == "auto" ? 0.2356 : (value == "light" ? 0.5 : 0.7644)
            tapNormalized(app, dx: dx, dy: 0.63)
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    func closeNativeSheet(_ app: XCUIApplication) {
        let closeBtn = app.buttons.matching(NSPredicate(format: "label == %@", "סגור")).firstMatch
        if closeBtn.waitForExistence(timeout: 3), closeBtn.isHittable {
            closeBtn.tap()
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    func setTheme(_ app: XCUIApplication, to value: String) {
        openGear(app, ariaLabel: "הגדרות")
        setThemeInOpenSettings(app, to: value)
        closeNativeSheet(app)
    }

    // Native bottom TabBar button, found by exact label and tapped with a select-state
    // verification + retry loop (a bare .tap() was observed to sometimes have zero visual
    // effect even when exists/hittable both report true).
    func tapTab(_ app: XCUIApplication, label: String) {
        dismissSystemAlerts()
        let tabBtn = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard tabBtn.waitForExistence(timeout: 5) else {
            print("WARN tapTab '\(label)' not found at all")
            return
        }
        for attempt in 0..<3 {
            if tabBtn.isSelected { break }
            if tabBtn.isHittable {
                tabBtn.tap()
            } else {
                tabBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            Thread.sleep(forTimeInterval: 1.2)
            if tabBtn.isSelected { break }
            if attempt == 2 {
                print("WARN tapTab '\(label)' may not have switched (isSelected=\(tabBtn.isSelected))")
            }
        }
        Thread.sleep(forTimeInterval: 1.0)
    }

    func openReaderFromHome(_ app: XCUIApplication) {
        let learnBtn = button(app, contains: "ללמוד")
        waitTap(learnBtn)
        Thread.sleep(forTimeInterval: 2.0)
    }

    func leaveReaderToHome(_ app: XCUIApplication) {
        dismissSystemAlerts()
        let back = exactElement(app, label: "חזרה")
        if back.waitForExistence(timeout: 3), back.isHittable {
            back.tap()
        } else {
            tapNormalized(app, dx: 0.9, dy: 0.05)
        }
        Thread.sleep(forTimeInterval: 1.2)
    }

    // Taps the wax-seal checkbox that marks the current halacha as "למדתי" (learned).
    func markCurrentHalachaLearned(_ app: XCUIApplication) {
        dismissSystemAlerts()
        let chk = app.webViews.checkBoxes.firstMatch
        if chk.waitForExistence(timeout: 3), chk.isHittable {
            chk.tap()
            Thread.sleep(forTimeInterval: 0.6)
            return
        }
        // Fallback: the seal sits mid-screen between the prev/next chevrons, roughly
        // 2/3 down the halacha card. Verified/adjusted empirically via debug screenshots.
        tapNormalized(app, dx: 0.5, dy: 0.66)
        Thread.sleep(forTimeInterval: 0.6)
    }

    func tapNextHalacha(_ app: XCUIApplication) {
        dismissSystemAlerts()
        let next = exactElement(app, label: "הבא")
        if next.waitForExistence(timeout: 3), next.isHittable {
            next.tap()
            Thread.sleep(forTimeInterval: 0.6)
            return
        }
        tapNormalized(app, dx: 0.1, dy: 0.66)
        Thread.sleep(forTimeInterval: 0.6)
    }

    func typeInSearch(_ app: XCUIApplication, query: String) {
        dismissSystemAlerts()
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            // Tapping the SearchField element directly (.tap() or element-relative
            // .press(forDuration:)/.coordinate(withNormalizedOffset:)) never focuses the
            // underlying WKWebView input here -- no keyboard appears, and typeText throws
            // "Neither element nor any descendant has keyboard focus". A tap built from a RAW
            // app-window coordinate (not element-relative) at the same screen position DOES
            // focus it. Confirmed empirically via a dedicated probe test that tried both.
            var gotKeyboard = false
            for _ in 0..<4 {
                let frame = field.frame
                let rawPoint = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                rawPoint.tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 2) {
                    gotKeyboard = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
            if gotKeyboard {
                field.typeText(query)
            } else {
                // Last resort: type via the app itself, which succeeds as long as SOME
                // element somewhere has focus (even if our keyboard-presence check raced it).
                app.typeText(query)
            }
            Thread.sleep(forTimeInterval: 2.5)
            return
        }
        // Fallback: coordinate-press approach (kept in case the search UI isn't a real
        // XCUIElement searchField on some screen states).
        let searchFieldCoord = CGVector(dx: 0.5, dy: 0.157)
        app.coordinate(withNormalizedOffset: searchFieldCoord).press(forDuration: 0.1)
        var gotKeyboard = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        if !gotKeyboard {
            app.coordinate(withNormalizedOffset: searchFieldCoord).press(forDuration: 0.1)
            gotKeyboard = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        }
        if !gotKeyboard {
            for dy in [0.147, 0.167, 0.175] {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).press(forDuration: 0.1)
                if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
                    gotKeyboard = true
                    break
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
        app.typeText(query)
        Thread.sleep(forTimeInterval: 2.5)
    }

    func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["search"].exists {
            app.keyboards.buttons["search"].tap()
        } else if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        } else if app.keyboards.buttons["done"].exists {
            app.keyboards.buttons["done"].tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
        Thread.sleep(forTimeInterval: 1.0)
    }

    // MARK: - The one real flow

    func testIpadRotation() throws {
        let app = freshLaunch()
        _ = waitForHome(app)
        dismissSystemAlerts()
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        var shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/verify/ipad_rotation_portrait.png"))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/verify/ipad_rotation_landscape.png"))
        XCUIDevice.shared.orientation = .portrait
        print("ROTATION-SAVED")
    }

    func testCaptureEightFramedScreenshots() throws {
        let app = freshLaunch()
        _ = waitForHome(app)

        // 1) Force a deterministic starting theme (light) before anything else.
        setTheme(app, to: "light")

        // 2) picker_framed.png — "כל הפרשיות", light
        tapTab(app, label: "כל הפרשיות")
        scrollToTop(app)
        checkpoint(app, "picker_framed")

        // back to week tab before opening the reader
        tapTab(app, label: "השבוע")

        // 3) reader_framed.png — Bereshit opening, light (nothing learned yet => opens at #1)
        openReaderFromHome(app)
        scrollToTop(app)
        checkpoint(app, "reader_framed")

        // 4) dark/reader_framed.png — same screen, dark.
        // setTheme needs the home screen's gear icon, which does not exist inside the reader,
        // so we must leave to home first, switch theme there, then re-enter the reader (it
        // reopens at the same halacha since nothing has been marked learned yet at this point).
        leaveReaderToHome(app)
        setTheme(app, to: "dark")
        openReaderFromHome(app)
        scrollToTop(app)
        checkpoint(app, "dark/reader_framed")

        // 5) dark/week_framed.png
        leaveReaderToHome(app)
        tapTab(app, label: "השבוע")
        scrollToTop(app)
        checkpoint(app, "dark/week_framed")

        // 6) dark/topics_framed.png
        tapTab(app, label: "לפי נושא")
        scrollToTop(app)
        checkpoint(app, "dark/topics_framed")

        // 7) dark/search_framed.png
        tapTab(app, label: "חיפוש")
        typeInSearch(app, query: "ברכת המזון")
        dismissKeyboard(app)
        Thread.sleep(forTimeInterval: 1.0)
        checkpoint(app, "dark/search_framed")

        // 8) mark 8 halachot as learned (now that the pretty reader shots are already taken)
        tapTab(app, label: "השבוע")
        openReaderFromHome(app)
        scrollToTop(app)
        for _ in 0..<8 {
            markCurrentHalachaLearned(app)
            tapNextHalacha(app)
        }
        leaveReaderToHome(app)

        // 9) dark/settings_framed.png — native sheet open, dark
        openGear(app, ariaLabel: "הגדרות")
        checkpoint(app, "dark/settings_framed")
        closeNativeSheet(app)

        // 10) dark/stats_framed.png — native sheet open, dark, real progress
        openGear(app, ariaLabel: "ההתקדמות שלי")
        checkpoint(app, "dark/stats_framed")
        closeNativeSheet(app)

        print("FLOW-COMPLETE")
    }
}
