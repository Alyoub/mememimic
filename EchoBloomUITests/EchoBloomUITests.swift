import XCTest

/// Character display names in lineup order (mirrors CharacterKind in the app).
enum CharacterNames {
    static let last = "Viking"
}

final class EchoBloomUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Plays a full three-player, three-round match with demo takes and checks every step
    /// of the loop: crew → packs → (handoff → turn → reveal) × players → recap → podium.
    func testCompleteLocalMatchUsingDemoTakes() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        snap("01-home", app)
        tap("Play", in: app)

        XCTAssertTrue(app.staticTexts["Your crew"].waitForExistence(timeout: 5))
        tap("Add player", in: app)
        // New players automatically receive the first character nobody else is using.
        XCTAssertTrue(app.buttons["Sand Ninja"].isSelected)
        tap("Save Player 2", in: app)
        tap("Add player", in: app)
        XCTAssertTrue(app.buttons["Classy"].isSelected)
        snap("02-crew", app)
        tap("Pick sound packs", in: app)

        XCTAssertTrue(app.staticTexts["Sound packs"].waitForExistence(timeout: 5))
        snap("03-packs", app)
        tap("Start the match", in: app)

        for round in 1...3 {
            for player in 1...3 {
                XCTAssertTrue(app.staticTexts["ROUND \(round) OF 3"].waitForExistence(timeout: 5))
                if round == 1 && player == 1 { snap("04-handoff", app) }
                tapID("handoff.go", in: app)

                XCTAssertTrue(app.buttons["Play the sound"].waitForExistence(timeout: 5))
                if round == 1 && player == 1 {
                    snap("05-turn", app)
                    tap("Play the sound", in: app)
                    XCTAssertTrue(app.buttons["Record your take"].waitForExistence(timeout: 5))
                    snap("06-turn-ready", app)
                }
                tap("Demo take", in: app)

                XCTAssertTrue(app.staticTexts["DEMO SCORE"].waitForExistence(timeout: 5))
                if round == 1 && player == 1 { sleep(1); snap("07-reveal", app) }
                tapID("reveal.next", in: app)
            }
            XCTAssertTrue(app.staticTexts["Round \(round) complete".uppercased()].waitForExistence(timeout: 5))
            if round == 1 { sleep(1); snap("08-recap", app) }
            tapID("recap.next", in: app)
        }

        XCTAssertTrue(app.staticTexts["FINAL RESULTS"].waitForExistence(timeout: 5))
        sleep(2)
        snap("09-podium", app)
        XCTAssertTrue(app.buttons["Rematch"].exists)
        XCTAssertTrue(app.buttons["Change crew"].exists)
    }

    /// The launch splash animates in, then hands over to the home screen.
    func testSplashLeadsToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-show-splash"]
        app.launch()
        // launch() returns once the app settles, so the splash may already be mid-way.
        snap("16-splash", app)
        // The Play button exists underneath the splash, so wait for the splash itself to go.
        let splash = app.descendants(matching: .any)["Echo Bloom. Loading."]
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: splash)
        wait(for: [gone], timeout: 15)
        XCTAssertTrue(app.buttons["Play"].isHittable, "Home screen not usable after the splash")
        sleep(1)
        snap("18-after-splash", app)
    }

    /// The home lineup: arrows and swipes on the stage change the host's character.
    func testHomeCharacterLineup() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let name = app.staticTexts["home.character"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Pirate Gal")
        sleep(4)   // let the 3D stage load
        snap("12-home-pirate-gal", app)

        tap("Next character", in: app)
        XCTAssertEqual(name.label, "Pirate Captain")

        // Swipe on open stage (upper part of the screen), right to left = next.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.32))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.32))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertTrue(NSPredicate(format: "label == 'Soldier'").evaluate(with: name) || name.label == "Soldier")
        sleep(2)
        snap("13-home-soldier", app)

        to.press(forDuration: 0.05, thenDragTo: from)
        XCTAssertEqual(name.label, "Pirate Captain")
        tap("Previous character", in: app)
        tap("Previous character", in: app)
        XCTAssertEqual(name.label, "Kimono Guy")
        sleep(2)
        snap("14-home-wrapped", app)
        tap("Previous character", in: app)
        sleep(2)
        snap("15-home-lineup", app)
    }

    /// The ✕ in a match asks to confirm, then quitting returns to the home screen.
    func testQuitMatchReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        tap("Play", in: app)
        tap("Pick sound packs", in: app)
        tap("Start the match", in: app)
        tapID("handoff.go", in: app)
        XCTAssertTrue(app.buttons["Play the sound"].waitForExistence(timeout: 5))

        tap("Quit match", in: app)
        let confirm = app.buttons["quit.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "Quit confirmation did not appear")
        snap("11-quit-confirm", app)
        // "Keep playing" closes the card and stays in the match.
        app.buttons["quit.cancel"].tap()
        XCTAssertTrue(app.buttons["Play the sound"].waitForExistence(timeout: 3))
        tap("Quit match", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "Did not return to the home screen")
    }

    /// Quitting works from every in-match screen, not only the turn.
    func testQuitFromEachMatchScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        tap("Play", in: app)
        tap("Pick sound packs", in: app)

        func quit(_ screen: String) {
            tap("Quit match", in: app)
            let confirm = app.buttons["quit.confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 3), "No confirmation on \(screen)")
            confirm.tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "Quit from \(screen) did not go home")
            tap("Play", in: app)
            tap("Pick sound packs", in: app)
        }

        tap("Start the match", in: app)
        quit("handoff")

        tap("Start the match", in: app)
        tapID("handoff.go", in: app)
        tap("Demo take", in: app)
        XCTAssertTrue(app.staticTexts["DEMO SCORE"].waitForExistence(timeout: 5))
        quit("reveal")

        tap("Start the match", in: app)
        tapID("handoff.go", in: app)
        tap("Demo take", in: app)
        tapID("reveal.next", in: app)
        XCTAssertTrue(app.buttons["recap.next"].waitForExistence(timeout: 5))
        quit("recap")
    }

    /// Adding a player opens their editor, where a character can be picked.
    func testAddPlayerOpensCharacterPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        tap("Play", in: app)
        XCTAssertTrue(app.staticTexts["1 of 8 players"].exists)
        XCTAssertFalse(app.buttons["Remove Player 1"].exists, "The only player must not be removable")
        tap("Add player", in: app)
        XCTAssertTrue(app.buttons["Sand Ninja"].waitForExistence(timeout: 3), "Character picker did not open for the new player")
        let hostCharacter = app.buttons["Pirate Gal, already chosen"]
        XCTAssertTrue(hostCharacter.exists)
        XCTAssertFalse(hostCharacter.isEnabled, "A character used by another player must be unavailable")
        tap("Classy", in: app)
        XCTAssertTrue(app.buttons["Classy"].isSelected)
        snap("19-editor-open", app)

        // ✓ saves and closes the editor.
        tap("Save Player 2", in: app)
        XCTAssertTrue(app.buttons["Classy"].waitForNonExistence(timeout: 3), "Editor did not close after saving")
        XCTAssertTrue(app.buttons["Change character for Player 2, currently Classy"].exists)
        tap("Remove Player 2", in: app)
        XCTAssertTrue(app.staticTexts["1 of 8 players"].exists)
        XCTAssertFalse(app.buttons["Remove Player 1"].exists, "Removing must stop at one player")
    }

    /// The gear on the home screen opens Settings, and toggles there take effect.
    func testSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        tap("Settings", in: app)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        snap("20-settings", app)

        let sound = app.switches["Sound effects"]
        XCTAssertTrue(sound.waitForExistence(timeout: 3))
        sound.switches.firstMatch.tap()
        tap("Close settings", in: app)
        XCTAssertTrue(app.buttons["Turn sound effects on"].waitForExistence(timeout: 3), "Muting in Settings didn't reach the home screen")
    }

    /// Records a real take through the microphone. The simulator's input is usually
    /// near-silent, so either outcome is fine; what matters is the loop never stalls.
    func testRecordingFinishesAndReturnsControl() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()

        tap("Play", in: app)
        tap("Pick sound packs", in: app)
        tap("Start the match", in: app)
        tapID("handoff.go", in: app)
        tap("Play the sound", in: app)
        tapID("record", in: app)

        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        let scored = app.staticTexts["LOCAL SCORE"]
        let deadline = Date().addingTimeInterval(20)
        var finished = false
        while Date() < deadline {
            // One query each: reading a button's state in a second step races with its
            // label changing ("Stop recording") or the score screen replacing it.
            let readyAgain = NSPredicate(format: "identifier == 'record' AND label == 'Record your take' AND isEnabled == true")
            if app.buttons["reveal.next"].exists || app.buttons.matching(readyAgain).count > 0 {
                finished = true
                break
            }
            _ = scored.waitForExistence(timeout: 0.5)
        }
        snap("10-after-recording", app)
        XCTAssertTrue(finished, "Recording never handed control back")
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing button: \(label)")
        XCTAssertTrue(button.isHittable, "Button is not hittable: \(label)")
        button.tap()
    }

    private func tapID(_ id: String, in app: XCUIApplication) {
        let button = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing button: \(id)")
        button.tap()
    }

    private func snap(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
