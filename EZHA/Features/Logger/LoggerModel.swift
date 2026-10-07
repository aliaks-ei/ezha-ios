import EZHAKit
import Foundation
import Observation

/// Everything in a logger draft. Saved per date, without the photo bytes.
struct LoggerState: Codable, Equatable {
  /// The entry id. Also names the photo in storage, so a new photo gets a new id.
  var entryId = UUID()
  var text = ""
  var isLabel = false
  var labelGramsText = ""
  var photoId: String?
  var pendingImagePath: String?
  var items: [LogItem] = []
  var lastAnalyzed: AnalyzeGate.Fingerprint?
  var estimateUsedPhoto = false
  var estimateUsedText = false
  var aiItemsFromLabel = false
  var aiFoodName: String?
  var saveToLibrary = false
  var mealName = ""
  var isMealNameEdited = false
  var selectedLibraryFoodName: String?
  var usedMealIds: [UUID] = []
  var lastValidByItem: [UUID: String] = [:]
  var lastValidByFood: [UUID: String] = [:]

  var isEmpty: Bool { self == LoggerState(entryId: entryId) }
}

/// One logger sheet, bound to a date.
@MainActor
@Observable
final class LoggerModel {
  enum Stage: Equatable {
    case uploading
    case reading
    case finalizing

    var text: String {
      switch self {
      case .uploading: String(localized: "Uploading photo…")
      case .reading: String(localized: "Reading your meal…")
      case .finalizing: String(localized: "Finalizing…")
      }
    }
  }

  var state = LoggerState() {
    didSet { if state != oldValue { scheduleDraftSave() } }
  }
  var imageData: Data? {
    didSet { if imageData != oldValue { scheduleDraftSave() } }
  }
  private(set) var stage: Stage?
  var errorMessage: String?
  private(set) var isSaving = false
  /// The library item being added from "Add from library", while its ingredients load.
  private(set) var quickAddingId: UUID?
  /// Incremented after each estimate, for the item insert animation and haptics.
  private(set) var estimateCount = 0

  let date: DateKey
  @ObservationIgnored private let appModel: AppModel
  @ObservationIgnored private var estimateTask: Task<Void, Never>?
  @ObservationIgnored private var draftTask: Task<Void, Never>?
  @ObservationIgnored private var firstUnsavedChange: Date?
  @ObservationIgnored private var isRestoring = true

  init(date: DateKey, appModel: AppModel) {
    self.date = date
    self.appModel = appModel
  }

  // MARK: Derived state

  var fingerprint: AnalyzeGate.Fingerprint {
    AnalyzeGate.Fingerprint(text: state.text, photoId: state.photoId, isLabel: state.isLabel)
  }

  var primaryAction: AnalyzeGate.PrimaryAction {
    AnalyzeGate.primaryAction(current: fingerprint, lastAnalyzed: state.lastAnalyzed)
  }

  var isStale: Bool {
    AnalyzeGate.isStale(current: fingerprint, lastAnalyzed: state.lastAnalyzed)
  }

  var isEstimating: Bool { stage != nil }
  /// Text, a photo, or items. Closing asks before discarding them.
  var hasInput: Bool { !state.isEmpty || imageData != nil }
  var totals: MacroTotals { LogItemMath.totals(state.items) }
  var hasAIItems: Bool { state.items.contains { $0.origin == .ai } }
  var showsLabelOverrides: Bool { state.aiItemsFromLabel && hasAIItems }

  var suggestedMealName: String {
    LibraryDrafts.suggestedName(
      selectedLibraryFoodName: state.selectedLibraryFoodName,
      itemNames: state.items.map(\.name), descriptionText: state.text,
      aiFoodName: state.aiFoodName) ?? ""
  }

  /// The meal name shown in the field: the suggestion until the user edits it.
  var mealName: String {
    get { state.isMealNameEdited ? state.mealName : suggestedMealName }
    set {
      state.mealName = newValue
      state.isMealNameEdited = true
    }
  }

  // MARK: Drafts

  /// Restores the draft for this date, or applies a "Log this" prefill.
  func restore() async {
    if let draft = try? await appModel.sync.draftStore.load(date),
      let saved = try? JSONDecoder.ezha.decode(LoggerState.self, from: draft.state)
    {
      state = saved
      imageData = draft.imageData
    }
    if let prefill = appModel.loggerPrefill {
      appModel.loggerPrefill = nil
      if state.text.isEmpty { state.text = prefill }
    }
    isRestoring = false
  }

  /// Saves 400 ms after the last change, and at most 1.2 s after the first unsaved one.
  private func scheduleDraftSave() {
    guard !isRestoring else { return }
    let now = Date.now
    let first = firstUnsavedChange ?? now
    firstUnsavedChange = first
    let delay = max(0, min(0.4, 1.2 - now.timeIntervalSince(first)))
    draftTask?.cancel()
    draftTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      _ = await self?.saveDraftNow()
    }
  }

  /// Returns false when the draft could not be saved.
  @discardableResult
  func saveDraftNow() async -> Bool {
    draftTask?.cancel()
    firstUnsavedChange = nil
    do {
      if state.isEmpty && imageData == nil {
        try await appModel.sync.draftStore.delete(date)
      } else {
        try await appModel.sync.draftStore.save(
          date, state: JSONEncoder.ezha.encode(state), imageData: imageData)
      }
      return true
    } catch {
      return false
    }
  }

  func clearDraft() async {
    cancelEstimate()
    isRestoring = true
    state = LoggerState()
    imageData = nil
    errorMessage = nil
    isRestoring = false
    draftTask?.cancel()
    firstUnsavedChange = nil
    try? await appModel.sync.draftStore.delete(date)
  }

  // MARK: Photo

  func attachPhoto(_ raw: Data, isLabel: Bool) async {
    do {
      let jpeg = try await ImageProcessing.jpeg(from: raw)
      imageData = jpeg
      state.photoId = UUID().uuidString
      state.pendingImagePath = nil
      state.entryId = UUID()
      if isLabel { state.isLabel = true }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func removePhoto() {
    imageData = nil
    state.photoId = nil
    state.pendingImagePath = nil
    state.isLabel = false
    state.labelGramsText = ""
  }

  // MARK: Estimate

  func estimate() {
    guard fingerprint.hasInput, !isEstimating else { return }
    errorMessage = nil
    let fingerprint = fingerprint
    let isLabel = state.isLabel
    let labelGrams = parseNumberInput(state.labelGramsText)
    stage = imageData != nil && state.pendingImagePath == nil ? .uploading : .reading
    estimateTask = Task { [weak self] in
      guard let self else { return }
      do {
        let estimate = try await runEstimate(isLabel: isLabel)
        guard !Task.isCancelled else { return }
        apply(estimate, fingerprint: fingerprint, isLabel: isLabel, labelGrams: labelGrams)
      } catch {
        if !Task.isCancelled && !(error is CancellationError) {
          errorMessage = Self.message(for: error)
        }
      }
      stage = nil
    }
  }

  private func runEstimate(isLabel: Bool) async throws -> Estimate {
    let clients = appModel.clients
    var imagePath = state.pendingImagePath
    if let imageData, imagePath == nil {
      stage = .uploading
      do {
        imagePath = try await clients.logging.uploadImage(imageData, state.entryId)
      } catch  where "\(error)".localizedCaseInsensitiveContains("already exists") {
        // A previous attempt uploaded the same file before it could record the path.
        let userId = appModel.user?.id.uuidString.lowercased() ?? ""
        imagePath = "\(userId)/\(state.entryId.uuidString.lowercased()).jpg"
      }
      state.pendingImagePath = imagePath
    }
    stage = .reading
    let request = EstimateRequest(
      text: state.text, items: nil, imagePath: imageData == nil ? nil : imagePath,
      inputType: EntryPayload.analyzeInputType(hasPhoto: imageData != nil, isLabelPhoto: isLabel))
    var result: Estimate?
    for try await event in clients.ai.estimateStream(request) {
      switch event {
      case .status(let value): stage = value == "finalizing" ? .finalizing : .reading
      case .result(let estimate): result = estimate
      case .delta, .uploading: break
      }
    }
    guard let result else { throw AIError.message("Analysis returned an invalid response.") }
    return result
  }

  private func apply(
    _ estimate: Estimate, fingerprint: AnalyzeGate.Fingerprint, isLabel: Bool, labelGrams: Double?
  ) {
    let newItems =
      isLabel
      ? LogItemMath.fromLabelEstimate(estimate, grams: labelGrams)
      : LogItemMath.fromEstimate(estimate)
    state.items = LogItemMath.replacingAIItems(in: state.items, with: newItems)
    state.lastAnalyzed = fingerprint
    state.estimateUsedPhoto = fingerprint.photoId != nil
    state.estimateUsedText = !fingerprint.text.isEmpty
    state.aiItemsFromLabel = isLabel
    state.aiFoodName = estimate.foodName
    for item in newItems { state.lastValidByItem[item.id] = item.gramsText }
    estimateCount += 1
  }

  func cancelEstimate() {
    estimateTask?.cancel()
    estimateTask = nil
    stage = nil
  }

  static func message(for error: any Error) -> String {
    if isNetworkError(error) {
      return String(
        localized: "You're offline. Estimates need a connection. Library meals can still be logged."
      )
    }
    return error.localizedDescription
  }

  // MARK: Items

  func addLibraryItems(_ items: [LogItem], foodName: String?, mealIds: [UUID]) {
    state.items.append(contentsOf: items)
    for item in items {
      state.lastValidByItem[item.id] = item.gramsText
      if let food = item.linkedFoodId, item.origin == .libraryFood {
        state.lastValidByFood[food] = item.gramsText
      }
    }
    if state.selectedLibraryFoodName == nil { state.selectedLibraryFoodName = foodName }
    state.usedMealIds.append(contentsOf: mealIds.filter { !state.usedMealIds.contains($0) })
  }

  /// Adds one library food (default grams) or meal (its ingredients) to the meal.
  func quickAdd(_ food: SavedFood) async {
    errorMessage = nil
    guard food.isMeal else {
      addLibraryItems([LogItemMath.fromSavedFood(food)], foodName: food.name, mealIds: [])
      return
    }
    quickAddingId = food.id
    defer { quickAddingId = nil }
    do {
      let items = LogItemMath.fromSavedMeal(try await appModel.libraryStore.ingredients(for: food))
      guard !items.isEmpty, !items.contains(where: \.isNutritionMissing) else {
        errorMessage = String(localized: "\(food.name) has missing nutrition. Choose another item.")
        return
      }
      addLibraryItems(items, foodName: food.name, mealIds: [food.id])
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }

  func removeItem(_ id: UUID) {
    state.items.removeAll { $0.id == id }
  }

  func setGrams(_ id: UUID, _ text: String) {
    guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
    state.items[index].gramsText = text
    if LogItemMath.validGrams(text) != nil {
      state.lastValidByItem[id] = text
      if let food = state.items[index].linkedFoodId, state.items[index].origin == .libraryFood {
        state.lastValidByFood[food] = text
      }
    }
  }

  /// Returns true when the step reached 5000 g.
  @discardableResult
  func step(_ id: UUID, by delta: Double) -> Bool {
    guard let item = state.items.first(where: { $0.id == id }) else { return false }
    let result = LogItemMath.step(item.gramsText, by: delta)
    setGrams(id, result.text)
    errorMessage = result.hitMax ? LogItemMath.maxGramsMessage : nil
    return result.hitMax
  }

  /// Restores the last valid grams when a field loses focus with invalid text.
  func gramsFocusLost(_ id: UUID) {
    guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
    let item = state.items[index]
    let restored = LogItemMath.restoredGramsText(
      for: item, lastValidByItem: state.lastValidByItem, lastValidByFood: state.lastValidByFood)
    if restored != item.gramsText { state.items[index].gramsText = restored }
    if (parseNumberInput(restored) ?? 0) > LogItemMath.maxGrams {
      state.items[index].gramsText = Macros.format(LogItemMath.maxGrams, maxFractionDigits: 1)
      errorMessage = LogItemMath.maxGramsMessage
    }
  }

  /// Display macros of the first AI item at its current grams.
  var labelDisplayMacros: MacroTotals? {
    state.items.first { $0.origin == .ai }.map(LogItemMath.macros)
  }

  /// Label overrides: edited display macros at the current grams become per 100 g.
  func applyLabelOverride(_ edited: MacroTotals) {
    guard let index = state.items.firstIndex(where: { $0.origin == .ai }) else { return }
    let item = state.items[index]
    state.items[index] = LogItemMath.applyingEditedLabelMacros(
      to: item, edited: edited, grams: LogItemMath.validGrams(item.gramsText))
  }

  // MARK: Log

  /// Logs the meal. Returns true when the sheet should close.
  func log() async -> Bool {
    if let reason = AnalyzeGate.logBlockReason(state.items) {
      errorMessage = reason
      return false
    }
    errorMessage = nil
    isSaving = true
    defer { isSaving = false }
    let hasAI = hasAIItems
    let sources = UsedSources(
      usedPhoto: hasAI && state.estimateUsedPhoto, usedText: hasAI && state.estimateUsedText,
      usedLibrary: state.items.contains { $0.origin != .ai })
    let payload = EntryPayload.build(
      entryId: state.entryId, date: date,
      imagePath: sources.usedPhoto ? state.pendingImagePath : nil, items: state.items,
      sources: sources, isLabelPhoto: state.aiItemsFromLabel, extraUsedFoodIds: state.usedMealIds)
    do {
      let result = try await appModel.dayStore.log(payload)
      appModel.libraryStore.markUsed(payload.usedFoodIds)
      var notices = [
        result == .saved
          ? String(localized: "Meal logged.")
          : String(localized: "Saved on this device. Totals update after syncing.")
      ]
      if state.saveToLibrary {
        do {
          try await appModel.libraryStore.saveMeal(
            id: nil, name: mealName.trimmingCharacters(in: .whitespaces).nonEmpty ?? "Meal",
            ingredients: LogItemMath.mealIngredients(from: state.items))
        } catch {
          notices.append(
            String(localized: "The library copy could not be saved. Your meal log is kept."))
        }
      }
      await clearDraft()
      appModel.showToast(notices.joined(separator: " "))
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}
