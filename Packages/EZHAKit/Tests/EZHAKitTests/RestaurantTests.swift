import Foundation
import Testing

@testable import EZHAKit

/// Restaurant meals: the photo of what was served, the photo of what is left, eaten amounts.
struct RestaurantTests {
  @Test func estimateItemsCarryTheServedAmountIntoLogItems() throws {
    let estimate = try Estimate.parse(
      Data(
        """
        {"totals":{"calories":524,"protein":36,"carbs":0,"fat":40},"source":"food_photo","notes":"",
         "items":[{"name":"Steak","grams":180,"served_amount":250,"calories":524,"protein":36,
                   "carbs":0,"fat":40},
                  {"name":"Salad","grams":80,"served_amount":-3,"calories":16,"protein":1,
                   "carbs":3,"fat":0}]}
        """.utf8))
    #expect(estimate.items[0].servedAmount == 250)
    // An invalid served amount is unknown, not an error.
    #expect(estimate.items[1].servedAmount == nil)
    let items = LogItemMath.fromEstimate(estimate)
    #expect(items[0].gramsText == "180")
    #expect(items[0].servedAmount == 250)
    #expect(items[1].servedAmount == nil)
  }

  @Test func logItemsAndFingerprintsFromOlderDraftsStillDecode() throws {
    let item = LogItem(
      name: "Rice", gramsText: "100", macroBasis: .per100g, baseGrams: 100, base: .zero,
      origin: .ai, servedAmount: 200)
    var json = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    #expect(json["servedAmount"] as? Double == 200)
    json["servedAmount"] = nil
    let decoded = try JSONDecoder().decode(
      LogItem.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.servedAmount == nil)

    let fingerprint = try JSONDecoder().decode(
      AnalyzeGate.Fingerprint.self, from: Data(#"{"text":"","photoId":"a","isLabel":false}"#.utf8))
    #expect(fingerprint.leftoverPhotoId == nil)
    // A new photo of what is left makes the estimate stale.
    let analyzed = AnalyzeGate.Fingerprint(
      text: "", photoId: "a", isLabel: false, leftoverPhotoId: "b")
    let changed = AnalyzeGate.Fingerprint(
      text: "", photoId: "a", isLabel: false, leftoverPhotoId: "c")
    #expect(AnalyzeGate.isStale(current: changed, lastAnalyzed: analyzed))
    #expect(!AnalyzeGate.isStale(current: analyzed, lastAnalyzed: analyzed))
  }

  @Test func requestsSendThePhotoOfWhatIsLeftOnlyForRestaurantMeals() throws {
    func json(_ request: EstimateRequest) throws -> [String: Any] {
      try #require(
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }
    let restaurant = try json(
      EstimateRequest(
        text: "shared the fries", items: nil, imagePath: "u/before.jpg",
        leftoverImagePath: "u/after.jpg", inputType: EntryPayload.restaurantInputType))
    #expect(restaurant["imagePath"] as? String == "u/before.jpg")
    #expect(restaurant["leftoverImagePath"] as? String == "u/after.jpg")
    #expect(restaurant["inputType"] as? String == "restaurant_photos")
    let photo = try json(
      EstimateRequest(text: nil, items: nil, imagePath: "u/p.jpg", inputType: "food_photo"))
    #expect(photo["leftoverImagePath"] == nil)
  }

  @Test func draftsKeepThePhotoOfWhatIsLeft() async throws {
    let store = DraftStore(modelContainer: try LocalStore.makeContainer(inMemory: true))
    let date = try #require(DateKey("2026-11-18"))
    try await store.save(
      date, state: Data("{}".utf8), imageData: Data([1]), leftoverImageData: Data([2]))
    var draft = try #require(try await store.load(date))
    #expect(draft.imageData == Data([1]))
    #expect(draft.leftoverImageData == Data([2]))
    // Saving without it, as older callers do, clears it.
    try await store.save(date, state: Data("{}".utf8), imageData: Data([1]))
    draft = try #require(try await store.load(date))
    #expect(draft.leftoverImageData == nil)
  }
}
