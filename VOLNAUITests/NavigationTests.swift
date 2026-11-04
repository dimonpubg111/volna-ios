import XCTest

final class NavigationTests: XCTestCase {
    func testNativeNavigationSearchAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Зимові вечори.\nТеплі історії."].waitForExistence(timeout: 15))
        attach(app, name: "01-home")
        app.tabBars.buttons["ТБ"].tap()
        let search = app.textFields["Пошук каналу"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("ТЕТ\n")
        XCTAssertTrue(app.buttons["Дивитися ТЕТ"].waitForExistence(timeout: 5))
        attach(app, name: "02-television")
        app.tabBars.buttons["Фільми"].tap()
        XCTAssertTrue(app.textFields["Назва, жанр або рік"].waitForExistence(timeout: 5))
        attach(app, name: "03-films")
        app.tabBars.buttons["Налаштування"].tap()
        XCTAssertTrue(app.switches["Легкий сніг"].exists || app.staticTexts["Легкий сніг"].exists)
        let playbackSettings = app.buttons["Якість, звук і субтитри"]
        for _ in 0..<8 {
            if playbackSettings.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(playbackSettings.isHittable)
        playbackSettings.tap()
        XCTAssertTrue(app.navigationBars["Налаштування відео"].waitForExistence(timeout: 5))
        app.buttons["Готово"].tap()
        XCTAssertTrue(app.navigationBars["Налаштування"].waitForExistence(timeout: 5))
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
