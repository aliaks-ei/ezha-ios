import XCTest

/// Regression coverage for the eleven approved UI/UX recommendations.
@MainActor
final class UXImprovementUITests: HarnessTestCase {
  private func ready(_ scenario: String = "review", dark: Bool = false, large: Bool = false) {
    launch(scenario, dark: dark, large: large)
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
  }

  private func replace(_ field: XCUIElement, with text: String) {
    XCTAssertTrue(field.isHittable)
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    let old = field.value as? String ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
  }

  private var portion: XCUIElement {
    app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Portion of'")).firstMatch
  }
  private var descriptionField: XCUIElement {
    app.textViews["mealText"].exists ? app.textViews["mealText"] : app.textFields["mealText"]
  }
  private func hideKeyboardIfVisible() {
    let button = app.buttons["Hide keyboard"]
    if button.waitForExistence(timeout: 1), button.isHittable { button.tap() }
  }
  /// Close with input asks first; "Keep editing" leaves the meal as it was.
  private func closeAndKeepEditing() {
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(app.alerts["Discard this draft?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Keep editing"].tap()
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 5))
  }
  private func closeAndDiscard() {
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(app.alerts["Discard this draft?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Discard draft"].tap()
    XCTAssertTrue(app.buttons["Open logger"].waitForExistence(timeout: 5))
    app.buttons["Open logger"].tap()
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
  }

  func testReviewIsFocusedAndDetailsRemainEditableInAllAppearances() {
    for variant in ["light", "dark", "large-text"] {
      ready(dark: variant == "dark", large: variant == "large-text")
      XCTAssertFalse(app.textFields["per100g-calories0"].exists)
      XCTAssertTrue(app.buttons["adjustFood0"].exists)
      XCTAssertTrue(app.buttons["loggerPrimary"].isEnabled)
      capture("ux-review-\(variant)")
      app.buttons["foodRow0"].tap()
      XCTAssertTrue(app.textFields["per100g-calories0"].waitForExistence(timeout: 5))
      let field = app.textFields["per100g-calories0"]
      XCTAssertGreaterThanOrEqual(field.frame.height, 44)
      XCTAssertGreaterThanOrEqual(field.frame.width, 44)
      XCTAssertTrue(field.label.contains("per 100 grams"))
      capture("ux-nutrition-details-\(variant)")
    }
  }

  func testInvalidPortionStaysVisibleAndBlocksLoggingUntilCorrected() {
    ready()
    let region = app.descendants(matching: .any)["portionInputRegion"].firstMatch
    XCTAssertGreaterThanOrEqual(region.frame.height + 0.000_001, 44)
    XCTAssertGreaterThanOrEqual(region.frame.width + 0.000_001, 44)
    region.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.05)).tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    hideKeyboardIfVisible()
    for invalid in ["", "-5", "abc", "99999"] {
      replace(portion, with: invalid)
      XCTAssertTrue(
        app.staticTexts["portionError0"].waitForExistence(timeout: 3)
          || app.descendants(matching: .any)["portionError0"].exists)
      XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    }
    capture("ux-invalid-portion-keyboard")
    hideKeyboardIfVisible()
    XCTAssertEqual(portion.value as? String, "99999")
    XCTAssertTrue(app.descendants(matching: .any)["reviewTotal"].label.contains("Last valid total"))
    closeAndKeepEditing()
    XCTAssertEqual(portion.value as? String, "99999")
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    replace(portion, with: "150,5")
    hideKeyboardIfVisible()
    XCTAssertTrue(app.buttons["loggerPrimary"].isEnabled)
    capture("ux-portion-corrected")
  }

  func testInvalidNutritionCannotBeHiddenOrDismissedAway() {
    ready()
    app.buttons["foodRow0"].tap()
    let field = app.textFields["per100g-calories0"]
    replace(field, with: "-1")
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    app.buttons["Hide keyboard"].tap()
    XCTAssertEqual(field.value as? String, "-1")
    capture("ux-invalid-nutrition")
    app.buttons["foodRow0"].tap()
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    closeAndKeepEditing()
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    app.buttons["foodRow0"].tap()
    XCTAssertEqual(field.value as? String, "-1")
    replace(field, with: "200,5")
    app.buttons["Hide keyboard"].tap()
    XCTAssertTrue(app.buttons["loggerPrimary"].isEnabled)
    capture("ux-nutrition-corrected")
  }

  func testCloseAsksAndDiscardsPhotoDescriptionAndItems() {
    ready("photoDraft")
    XCTAssertTrue(app.images["Meal photo"].waitForExistence(timeout: 5))
    app.buttons["Close"].firstMatch.tap()
    XCTAssertTrue(app.alerts["Discard this draft?"].waitForExistence(timeout: 5))
    capture("ux-close-discard-confirmation")
    app.alerts.buttons["Keep editing"].tap()
    XCTAssertTrue(app.images["Meal photo"].exists)
    closeAndDiscard()
    XCTAssertFalse(app.images["Meal photo"].exists)
    XCTAssertFalse((descriptionField.value as? String ?? "").contains("Chicken breast"))
    ready("review")
    closeAndDiscard()
    XCTAssertFalse(app.buttons["foodRow0"].exists)
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
  }

  func testDiscardIsExplicitAndCancellationKeepsDraft() {
    ready()
    app.buttons["mealActions"].tap()
    app.buttons["Discard draft"].tap()
    XCTAssertTrue(app.alerts["Discard this draft?"].waitForExistence(timeout: 5))
    capture("ux-discard-confirmation")
    app.alerts.buttons["Keep editing"].tap()
    XCTAssertTrue(app.buttons["foodRow0"].exists)
    app.buttons["mealActions"].tap()
    app.buttons["Discard draft"].tap()
    app.alerts.buttons["Discard draft"].tap()
    XCTAssertTrue(app.buttons["Open logger"].waitForExistence(timeout: 5))
    app.buttons["Open logger"].tap()
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    XCTAssertFalse(app.buttons["foodRow0"].exists)
  }

  func testClosingCancelsEstimateAndIgnoresLateResult() {
    ready("slowEstimate")
    replace(descriptionField, with: "Chicken 100 g")
    app.buttons["loggerPrimary"].tap()
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    closeAndDiscard()
    XCTAssertTrue(app.buttons["foodRow0"].waitForNonExistence(timeout: 4))
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
  }

  func testDirtyNewFoodAndExistingFoodRequireDiscardChoice() {
    launch("libraryTab")
    XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 10))
    app.buttons["addToLibrary"].tap()
    let name = app.textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    replace(name, with: "My new food")
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(app.alerts["Discard this food?"].waitForExistence(timeout: 5))
    capture("ux-new-food-discard-guard")
    app.alerts.buttons["Keep editing"].tap()
    XCTAssertEqual(name.value as? String, "My new food")
    app.buttons["Cancel"].firstMatch.tap()
    app.alerts.buttons["Discard changes"].tap()
    app.staticTexts["Greek yogurt"].firstMatch.tap()
    XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 5))
    app.buttons["editButton"].tap()
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    replace(name, with: "Edited yogurt")
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
    capture("ux-food-edit-discard-guard")
    app.alerts.buttons["Keep editing"].tap()
    XCTAssertEqual(name.value as? String, "Edited yogurt")
  }

  func testDirtyMealRequiresDiscardChoice() {
    launch("libraryTab")
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    search.typeText("overnight")
    let meal = app.staticTexts["Overnight oats"].firstMatch
    XCTAssertTrue(meal.waitForExistence(timeout: 5))
    meal.tap()
    XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 5))
    app.buttons["editButton"].tap()
    let name = app.textFields["Meal name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    replace(name, with: "Edited oats")
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
    capture("ux-meal-edit-discard-guard")
    app.alerts.buttons["Keep editing"].tap()
    XCTAssertEqual(name.value as? String, "Edited oats")
  }

  func testSelectionsCanBeReviewedAndRemovedWhileSearchHasNoMatch() {
    ready("entry")
    app.buttons["attachLibrary"].tap()
    let yogurt = app.staticTexts["Greek yogurt"].firstMatch
    XCTAssertTrue(yogurt.waitForExistence(timeout: 5))
    yogurt.tap()
    let search = app.searchFields.firstMatch
    if !search.exists {
      if app.buttons["Search"].firstMatch.exists {
        app.buttons["Search"].firstMatch.tap()
      } else {
        app.swipeDown()
      }
    }
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("dragon fruit")
    XCTAssertTrue(app.buttons["describeWithAI"].waitForExistence(timeout: 5))
    let review = app.buttons["reviewSelection"]
    capture("ux-selection-no-match")
    XCTAssertTrue(review.isHittable)
    review.tap()
    XCTAssertTrue(app.navigationBars["Selected foods"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Greek yogurt"].firstMatch.exists)
    capture("ux-selected-foods-during-search")
    app.buttons["removeSelection-Greek yogurt"].tap()
    XCTAssertTrue(app.navigationBars["Selected foods"].waitForNonExistence(timeout: 5))
    XCTAssertFalse(app.buttons["addSelected"].exists)
    XCTAssertTrue(app.buttons["describeWithAI"].exists)
  }

  func testLogMealIsAnActionFromEveryDestinationAndReturnsToOrigin() {
    launch("shell")
    XCTAssertTrue(app.buttons["Library"].firstMatch.waitForExistence(timeout: 10))
    for tab in ["Today", "Suggestions", "Library", "Settings"] {
      app.buttons[tab].firstMatch.tap()
      let log = app.tabBars.buttons["Log meal"]
      XCTAssertTrue(log.waitForExistence(timeout: 5))
      XCTAssertTrue(log.isHittable)
      capture("ux-shell-\(tab.lowercased())")
      log.tap()
      XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
      app.buttons["Close"].firstMatch.tap()
      XCTAssertTrue(log.waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons[tab].firstMatch.isSelected)
    }
  }

  func testAuthAndEntryAtAX5KeepProvidersAndEstimateReachable() {
    app.launchEnvironment["HARNESS_TEXT_SIZE"] = "AX5"
    launch("auth", large: true)
    XCTAssertTrue(app.buttons["googleSignIn"].waitForExistence(timeout: 10))
    if !app.buttons["emailSignIn"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["googleSignIn"].isHittable)
    XCTAssertTrue(app.buttons["emailSignIn"].isHittable)
    capture("ux-auth-ax5")
    ready("entry", large: true)
    let field = descriptionField
    if !field.isHittable { app.swipeUp() }
    replace(field, with: "Chicken 100 g")
    XCTAssertTrue(app.buttons["loggerPrimary"].isHittable)
    let inputIsVisible = NSPredicate { _, _ in
      field.frame.maxY <= self.app.buttons["loggerPrimary"].frame.minY
    }
    expectation(for: inputIsVisible, evaluatedWith: nil)
    waitForExpectations(timeout: 3)
    XCTAssertTrue(app.buttons["Hide keyboard"].isHittable)
    capture("ux-entry-ax5-keyboard")
    app.buttons["Hide keyboard"].tap()
    capture("ux-entry-ax5")
    app.launchEnvironment["HARNESS_TEXT_SIZE"] = nil
  }

  func testOnboardingAndSuggestionsLabelsAndHelpInAllAppearances() {
    for variant in ["light", "dark", "large-text"] {
      launch("onboarding", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.staticTexts["startingTargetExplanation"].waitForExistence(timeout: 10))
      capture("ux-onboarding-\(variant)")
      launch("suggestions", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.buttons["getSuggestions"].waitForExistence(timeout: 10))
      app.swipeUp()
      XCTAssertTrue(app.staticTexts["Preferences (optional)"].firstMatch.exists)
      let notes =
        app.textFields["suggestionPreferences"].exists
        ? app.textFields["suggestionPreferences"] : app.textViews["suggestionPreferences"]
      if !notes.isHittable { app.swipeUp() }
      replace(notes, with: "No peanuts")
      XCTAssertTrue(notes.label.contains("Preferences"))
      capture("ux-suggestions-\(variant)-keyboard")
      app.swipeUp()
      capture("ux-suggestions-\(variant)")
    }
  }

  func testSuggestionsLoadingEmptyFailureAndResults() {
    for scenario in [
      "suggestionsLoading", "suggestions", "suggestionsFailure", "suggestionsResults",
    ] {
      launch(scenario)
      let get = app.buttons["getSuggestions"]
      XCTAssertTrue(get.waitForExistence(timeout: 10))
      get.tap()
      switch scenario {
      case "suggestionsLoading":
        XCTAssertFalse(get.isEnabled)
        capture("ux-suggestions-loading")
        XCTAssertTrue(app.staticTexts["suggestionsEmpty"].waitForExistence(timeout: 10))
      case "suggestions":
        XCTAssertTrue(app.staticTexts["suggestionsEmpty"].waitForExistence(timeout: 5))
        capture("ux-suggestions-empty")
      case "suggestionsFailure":
        XCTAssertTrue(
          app.staticTexts["Could not get suggestions. Try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(get.isEnabled)
        capture("ux-suggestions-failure")
      default:
        XCTAssertTrue(
          app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch
            .waitForExistence(timeout: 5))
        capture("ux-suggestions-results")
      }
    }
  }
  func testLibraryEditorAppearances() {
    for scenario in ["addFood", "foodEditor", "mealEditor"] {
      for variant in ["light", "dark", "large-text"] {
        launch(scenario, dark: variant == "dark", large: variant == "large-text")
        let field = scenario == "mealEditor" ? "Meal name" : "Name"
        XCTAssertTrue(app.textFields[field].waitForExistence(timeout: 10))
        if scenario == "mealEditor" {
          XCTAssertTrue(app.textFields["Ingredient"].firstMatch.waitForExistence(timeout: 5))
        }
        capture("ux-\(scenario)-\(variant)")
      }
    }
  }

  func testAX5LandscapeEntryKeyboardKeepsActionsReachable() throws {
    app.launchEnvironment["HARNESS_TEXT_SIZE"] = "AX5"
    defer {
      XCUIDevice.shared.orientation = .portrait
      app.launchEnvironment["HARNESS_TEXT_SIZE"] = nil
    }
    ready("entry", large: true)
    guard app.windows.firstMatch.frame.width >= 500 else {
      throw XCTSkip("iPhone supports portrait only; landscape is verified on iPad.")
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    let rotated = NSPredicate { _, _ in
      self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
    }
    expectation(for: rotated, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
    let field = descriptionField
    if !field.isHittable { app.swipeUp() }
    replace(field, with: "Chicken 100 g")
    XCTAssertTrue(app.buttons["loggerPrimary"].isHittable)
    capture("ux-entry-ax5-landscape-keyboard")
    let dismissal = app.buttons.matching(
      NSPredicate(
        format:
          "label == 'Hide keyboard' OR label == 'Dismiss keyboard' OR label == 'Hide Keyboard'"))
    XCTAssertTrue(dismissal.allElementsBoundByIndex.contains { $0.isHittable })
  }

  func testOverTargetRemainsReadableAndNeutralInAllAppearances() {
    for variant in ["light", "dark", "large-text"] {
      launch("todayOver", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.staticTexts["kcal over"].waitForExistence(timeout: 10))
      capture("ux-over-target-\(variant)")
    }
  }

  func testSwipeDoesNotDismissMealWithInput() {
    ready()
    let bar = app.navigationBars["Review meal"]
    let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
    let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94))
    start.press(forDuration: 0.05, thenDragTo: end)
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Chicken breast"].exists)
  }

}
