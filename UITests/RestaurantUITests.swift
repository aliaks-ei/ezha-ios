import XCTest

/// Restaurant meals: a photo of what was ordered and one of what is left; only the eaten
/// difference is logged. Scenarios are in `LoggerFixtures.state` ("restaurant…").
@MainActor
final class RestaurantUITests: HarnessTestCase {
  override func launch(_ scenario: String, dark: Bool = false, large: Bool = false) {
    super.launch(scenario, dark: dark, large: large)
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
  }

  func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

  func testRestaurantTileShowsTwoPhotoSlots() {
    launch("entry")
    XCTAssertTrue(element("attachRestaurant").waitForExistence(timeout: 5))
    capture("restaurant-entry-tiles")
    element("attachRestaurant").tap()
    XCTAssertTrue(element("restaurantBefore").waitForExistence(timeout: 5))
    XCTAssertTrue(element("restaurantAfter").exists)
    XCTAssertFalse(element("attachCamera").exists)
    // Both photos are needed before the estimate.
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    capture("restaurant-empty-light")
    element("exitRestaurant").tap()
    XCTAssertTrue(element("attachCamera").waitForExistence(timeout: 5))
    launch("restaurant", dark: true)
    XCTAssertTrue(element("restaurantBefore").waitForExistence(timeout: 5))
    capture("restaurant-empty-dark")
    launch("restaurant", large: true)
    XCTAssertTrue(element("restaurantAfter").waitForExistence(timeout: 5))
    capture("restaurant-empty-large-text")
  }

  func testRestaurantEstimateLogsOnlyWhatWasEaten() {
    launch("restaurantPhotos")
    XCTAssertTrue(element("restaurantBeforeRemove").waitForExistence(timeout: 5))
    XCTAssertTrue(element("restaurantAfterRemove").exists)
    XCTAssertTrue(app.buttons["loggerPrimary"].isEnabled)
    capture("restaurant-photos-light")
    app.buttons["loggerPrimary"].tap()
    XCTAssertTrue(app.buttons["foodRow0"].waitForExistence(timeout: 10))
    // The fixture answers only a restaurant request, so these amounts prove it was sent.
    XCTAssertTrue(
      element("servedAmount0").label.contains("Served about 250 g · 70 g left"),
      element("servedAmount0").label)
    XCTAssertTrue(element("servedAmount2").label.contains("Served about 80 g"))
    // 180 g steak + 60 g fries + 80 g salad: 524 + 187 + 16 kcal, not what was served.
    XCTAssertTrue(
      element("reviewTotal").label.contains("727"), element("reviewTotal").label)
    capture("restaurant-review-light")
    launch("restaurantReview", dark: true)
    XCTAssertTrue(app.buttons["foodRow0"].waitForExistence(timeout: 10))
    capture("restaurant-review-dark")
    launch("restaurantReview", large: true)
    XCTAssertTrue(element("servedAmount0").waitForExistence(timeout: 10))
    capture("restaurant-review-large-text")
  }

  func testRemovingThePhotoOfWhatIsLeftBlocksTheEstimate() {
    launch("restaurantPhotos")
    XCTAssertTrue(element("restaurantAfterRemove").waitForExistence(timeout: 5))
    element("restaurantAfterRemove").tap()
    XCTAssertTrue(element("restaurantAfter").waitForExistence(timeout: 5))
    XCTAssertFalse(element("restaurantAfterRemove").exists)
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    launch("restaurantPhotos", dark: true)
    XCTAssertTrue(element("restaurantBeforeRemove").waitForExistence(timeout: 5))
    capture("restaurant-photos-dark")
    launch("restaurantPhotos", large: true)
    XCTAssertTrue(element("restaurantBeforeRemove").waitForExistence(timeout: 5))
    capture("restaurant-photos-large-text")
  }
}
