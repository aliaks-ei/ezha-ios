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
  var review: Estimate.Review?
  var reviewItemId: UUID?
  var reviewAnswer: String?
  /// A clarification's prior draft, retained across relaunch until the new estimate succeeds.
  var clarificationBaseline: Data?
  var nutritionEdits: [UUID: [String: String]]?

  var isEmpty: Bool { self == LoggerState(entryId: entryId) }
}

/// Draft operations are injectable so storage failures can be exercised without losing user data.
struct LoggerDraftAccess {
  var load: (DateKey) async throws -> (state: Data, imageData: Data?)?
  var save: (DateKey, Data, Data?) async throws -> Void
  var delete: (DateKey) async throws -> Void

  static func live(_ store: DraftStore) -> Self {
    Self(
      load: { try await store.load($0) },
      save: { try await store.save($0, state: $1, imageData: $2) },
      delete: { try await store.delete($0) })
  }
}

/// One logger sheet, bound to a date.
@MainActor
@Observable
final class LoggerModel {
  enum Stage: Equatable {
    case uploading
    case reading
    case checking
    case finalizing

    var text: String {
      switch self {
      case .uploading: String(localized: "Uploading photo…")
      case .reading: String(localized: "Reading your meal…")
      case .checking: String(localized: "Checking details…")
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
  private(set) var isClosing = false
  private var savedState: LoggerState?
  private var savedImageData: Data?
  /// The library item being added from "Add from library", while its ingredients load.
  private(set) var quickAddingId: UUID?
  /// Incremented after each estimate, for the item insert animation and haptics.
  private(set) var estimateCount = 0
  private(set) var provisionalItems: [Estimate.Item] = []
  /// Retained while a clarification is being estimated, so a failed request is reversible.
  private var previousEstimate: LoggerState?

  let date: DateKey
  @ObservationIgnored private let appModel: AppModel
  @ObservationIgnored private let drafts: LoggerDraftAccess
  @ObservationIgnored private var estimateTask: Task<Void, Never>?
  @ObservationIgnored private var uploadTask: Task<String, any Error>?
  @ObservationIgnored private var attachmentId = UUID()
  @ObservationIgnored private var estimateId = UUID()
  @ObservationIgnored private var draftTask: Task<Void, Never>?
  @ObservationIgnored private var firstUnsavedChange: Date?
  @ObservationIgnored private var isRestoring = true

  init(date: DateKey, appModel: AppModel, drafts: LoggerDraftAccess? = nil) {
    self.date = date
    self.appModel = appModel
    self.drafts = drafts ?? .live(appModel.sync.draftStore)
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
  /// Text, a photo, or items kept when the sheet closes.
  var hasInput: Bool { !state.isEmpty || imageData != nil }
  var isDraftSaved: Bool {
    !isRestoring && savedState == state && savedImageData == imageData
  }
  var hasInvalidEdits: Bool {
    state.items.contains { NumericInput.portionError($0.gramsText) != nil }
      || (state.nutritionEdits ?? [:]).values.contains {
        $0.values.contains { NumericInput.nutritionError($0) != nil }
      }
  }
  var totals: MacroTotals { state.items.reduce(.zero) { $0 + macros(for: $1) } }

  /// An invalid visible portion keeps the last valid calculation, clearly labeled by the view.
  func macros(for item: LogItem) -> MacroTotals {
    var valid = item
    if NumericInput.portionError(item.gramsText) != nil {
      valid.gramsText =
        state.lastValidByItem[item.id]
        ?? Macros.format(item.baseGrams > 0 ? item.baseGrams : 100, maxFractionDigits: 1)
    }
    return LogItemMath.macros(valid)
  }
  var hasAIItems: Bool { state.items.contains { $0.origin == .ai } }
  var canRestorePreviousEstimate: Bool {
    guard let previousEstimate else { return false }
    return !isEstimating && !isSaving && previousEstimate.photoId == state.photoId
      && previousEstimate.isLabel == state.isLabel
  }

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
    if let draft = try? await drafts.load(date),
      let saved = try? JSONDecoder.ezha.decode(LoggerState.self, from: draft.state)
    {
      state = saved
      imageData = draft.imageData
      previousEstimate = saved.clarificationBaseline.flatMap {
        try? JSONDecoder.ezha.decode(LoggerState.self, from: $0)
      }
    }
    for item in state.items where state.lastValidByItem[item.id] == nil {
      if NumericInput.portionError(item.gramsText) == nil {
        state.lastValidByItem[item.id] = item.gramsText
      }
    }
    savedState = state
    savedImageData = imageData
    if let prefill = appModel.loggerPrefill {
      appModel.loggerPrefill = nil
      if state.text.isEmpty { state.text = prefill }
    }
    isRestoring = false
    if !isDraftSaved { scheduleDraftSave() }
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
    guard !isRestoring else { return false }
    draftTask?.cancel()
    firstUnsavedChange = nil
    let snapshot = state
    let photo = imageData
    do {
      if snapshot.isEmpty && photo == nil {
        try await drafts.delete(date)
      } else {
        try await drafts.save(date, JSONEncoder.ezha.encode(snapshot), photo)
      }
      savedState = snapshot
      savedImageData = photo
      return true
    } catch {
      return false
    }
  }

  func stopBackgroundWork() {
    cancelEstimate()
    uploadTask?.cancel()
    uploadTask = nil
    attachmentId = UUID()
  }

  @discardableResult
  func clearDraft() async -> Bool {
    isClosing = true
    defer { isClosing = false }
    stopBackgroundWork()
    draftTask?.cancel()
    do {
      try await drafts.delete(date)
    } catch {
      errorMessage = String(localized: "Your draft could not be discarded. Try again.")
      return false
    }
    cancelEstimate()
    uploadTask?.cancel()
    uploadTask = nil
    attachmentId = UUID()
    isRestoring = true
    state = LoggerState()
    previousEstimate = nil
    imageData = nil
    errorMessage = nil
    isRestoring = false
    draftTask?.cancel()
    firstUnsavedChange = nil
    savedState = state
    savedImageData = nil
    return true
  }

  // MARK: Photo

  /// Returns true when the photo is attached.
  @discardableResult
  func attachPhoto(_ raw: Data, isLabel: Bool) async -> Bool {
    uploadTask?.cancel()
    uploadTask = nil
    let attachment = UUID()
    attachmentId = attachment
    do {
      let jpeg = try await ImageProcessing.jpeg(from: raw, forLabel: isLabel)
      guard attachmentId == attachment else { return false }
      imageData = jpeg
      state.photoId = UUID().uuidString
      state.pendingImagePath = nil
      state.entryId = UUID()
      state.isLabel = isLabel
      errorMessage = nil
      // Once consent is given, storage upload can overlap with entering the description.
      if appModel.isAIConsentGiven {
        let entryId = state.entryId
        let photoId = state.photoId
        uploadTask = Task { [weak self] in
          guard let self else { throw CancellationError() }
          do {
            let path = try await uploadPhoto(jpeg, entryId: entryId)
            try Task.checkCancellation()
            if state.photoId == photoId { state.pendingImagePath = path }
            return path
          } catch {
            if state.photoId == photoId { uploadTask = nil }
            throw error
          }
        }
      }
      return true
    } catch {
      if attachmentId == attachment { errorMessage = error.localizedDescription }
      return false
    }
  }

  func removePhoto() {
    attachmentId = UUID()
    uploadTask?.cancel()
    uploadTask = nil
    imageData = nil
    state.photoId = nil
    state.pendingImagePath = nil
    state.isLabel = false
    state.labelGramsText = ""
  }

  // MARK: Estimate

  func estimate() {
    guard fingerprint.hasInput, !isEstimating, !isClosing else { return }
    errorMessage = nil
    provisionalItems = []
    let currentEstimateId = UUID()
    estimateId = currentEstimateId
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
      if estimateId == currentEstimateId {
        stage = nil
        provisionalItems = []
      }
    }
  }

  private func runEstimate(isLabel: Bool) async throws -> Estimate {
    try Task.checkCancellation()
    let clients = appModel.clients
    var imagePath = state.pendingImagePath
    if let imageData, imagePath == nil {
      stage = .uploading
      do {
        if let uploadTask {
          imagePath = try await uploadTask.value
        } else {
          imagePath = try await uploadPhoto(imageData, entryId: state.entryId)
        }
      } catch {
        try Task.checkCancellation()
        // A failed background upload is retried once when the user requests analysis.
        imagePath = try await uploadPhoto(imageData, entryId: state.entryId)
      }
      try Task.checkCancellation()
      state.pendingImagePath = imagePath
    }
    stage = .reading
    let request = EstimateRequest(
      text: state.text, items: nil, imagePath: imageData == nil ? nil : imagePath,
      inputType: EntryPayload.analyzeInputType(hasPhoto: imageData != nil, isLabelPhoto: isLabel))
    var result: Estimate?
    for try await event in clients.ai.estimateStream(request) {
      try Task.checkCancellation()
      switch event {
      case .status(let value):
        stage =
          value == "finalizing" ? .finalizing : value == "checking_details" ? .checking : .reading
      case .result(let estimate): result = estimate
      case .item(let index, let item):
        if index == provisionalItems.count { provisionalItems.append(item) }
      case .reset: provisionalItems = []
      case .delta, .uploading: break
      }
    }
    guard let result else { throw AIError.message("Analysis returned an invalid response.") }
    if isLabel && result.nutritionBasis != .per100g {
      throw AIError.message(
        "Label analysis needs the updated backend. Enter values per 100 g manually.")
    }
    return result
  }

  private func uploadPhoto(_ data: Data, entryId: UUID) async throws -> String {
    do {
      return try await appModel.clients.logging.uploadImage(data, entryId)
    } catch  where "\(error)".localizedCaseInsensitiveContains("already exists") {
      let userId = appModel.user?.id.uuidString.lowercased() ?? ""
      return "\(userId)/\(entryId.uuidString.lowercased()).jpg"
    }
  }

  private func apply(
    _ estimate: Estimate, fingerprint: AnalyzeGate.Fingerprint, isLabel: Bool, labelGrams: Double?
  ) {
    let newItems =
      isLabel
      ? LogItemMath.fromLabelEstimate(estimate, grams: labelGrams)
      : LogItemMath.fromEstimate(estimate)
    let oldAIIds = state.items.filter { $0.origin == .ai }.map(\.id)
    for id in oldAIIds { state.nutritionEdits?[id] = nil }
    state.items = LogItemMath.replacingAIItems(in: state.items, with: newItems)
    state.review = estimate.review
    state.reviewItemId = estimate.review.flatMap {
      newItems.indices.contains($0.itemIndex) ? newItems[$0.itemIndex].id : nil
    }
    state.reviewAnswer = nil
    state.lastAnalyzed = fingerprint
    state.estimateUsedPhoto = fingerprint.photoId != nil
    state.estimateUsedText = !fingerprint.text.isEmpty
    state.aiItemsFromLabel = isLabel
    state.aiFoodName = estimate.foodName
    for item in newItems { state.lastValidByItem[item.id] = item.gramsText }
    estimateCount += 1
    previousEstimate = nil
    state.clarificationBaseline = nil
  }

  func cancelEstimate() {
    estimateId = UUID()
    estimateTask?.cancel()
    estimateTask = nil
    stage = nil
    provisionalItems = []
  }

  var reviewItem: LogItem? {
    state.items.first { $0.id == state.reviewItemId }
  }

  func confirmReviewPortion() {
    guard !isStale, let id = state.reviewItemId,
      let index = state.items.firstIndex(where: { $0.id == id }),
      LogItemMath.validGrams(state.items[index].gramsText) != nil
    else { return }
    state.items[index].aiNotes = state.items[index].aiNotes.replacingOccurrences(
      of: "Portion weight estimated.", with: "Portion weight confirmed by user.")
    // Keep the confirmed weight as context for a later ingredient/identity correction.
    let item = state.items[index]
    state.text += "\n\(item.name): \(item.gramsText) g eaten."
    state.lastAnalyzed = fingerprint
    state.estimateUsedText = true
    dismissReview()
  }

  func answerReview() {
    guard let review = state.review,
      let answer = state.reviewAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
      !answer.isEmpty
    else {
      return
    }
    guard let itemId = state.reviewItemId else { return }
    refineItem(itemId, detail: "\(review.question) \(answer)")
  }

  /// Corrections retain the current portion as context and replace only AI items on success.
  func refineItem(_ id: UUID, detail: String) {
    guard !isEstimating, !isSaving, !isStale,
      !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let item = state.items.first(where: { $0.id == id }), item.origin == .ai
    else { return }
    previousEstimate = state
    state.clarificationBaseline = try? JSONEncoder.ezha.encode(state)
    state.text +=
      "\n\(item.name): \(item.gramsText) g eaten. \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
    dismissReview()
    estimate()
  }

  func restorePreviousEstimate() {
    guard canRestorePreviousEstimate, let previousEstimate else { return }
    state = previousEstimate
    self.previousEstimate = nil
    errorMessage = nil
  }

  func dismissReview() {
    state.review = nil
    state.reviewItemId = nil
    state.reviewAnswer = nil
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

  /// Adds a food the Library did not have to the description, for an AI estimate.
  func appendDescription(_ text: String) {
    let current = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    state.text = current.isEmpty ? text : "\(current)\n\(text)"
  }

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
    state.nutritionEdits?[id] = nil
    if state.reviewItemId == id { dismissReview() }
  }

  func setGrams(_ id: UUID, _ text: String) {
    guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
    state.items[index].gramsText = text
    if NumericInput.portionError(text) == nil {
      state.lastValidByItem[id] = text
      if let food = state.items[index].linkedFoodId, state.items[index].origin == .libraryFood {
        state.lastValidByFood[food] = text
      }
    }
  }

  /// Commits an editor's valid weight and preserves confirmed AI quantities for later corrections.
  @discardableResult
  func updatePortion(_ id: UUID, grams text: String) -> Bool {
    guard !isEstimating, !isSaving, let grams = parseNumberInput(text), grams.isFinite,
      grams > 0, grams <= LogItemMath.maxGrams,
      let item = state.items.first(where: { $0.id == id })
    else { return false }
    let wasStale = isStale
    setGrams(id, Macros.format(grams, maxFractionDigits: 1))
    if state.reviewItemId == id && state.review?.kind == "portion" {
      confirmReviewPortion()
    } else if item.origin == .ai && !wasStale {
      state.text +=
        "\n\(item.name): \(state.items.first { $0.id == id }?.gramsText ?? text) g eaten."
      state.lastAnalyzed = fingerprint
      state.estimateUsedText = true
    }
    return true
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

  /// Invalid text stays visible until corrected, including after keyboard dismissal.
  func gramsFocusLost(_ id: UUID) {
    guard let item = state.items.first(where: { $0.id == id }),
      NumericInput.portionError(item.gramsText) == nil,
      let grams = parseNumberInput(item.gramsText)
    else { return }
    setGrams(id, Macros.format(grams, maxFractionDigits: 1))
  }

  func nutritionText(_ item: LogItem, _ field: String, value: Double) -> String {
    state.nutritionEdits?[item.id]?[field] ?? Macros.format(value, maxFractionDigits: 1)
  }

  func setNutritionText(
    _ id: UUID, _ field: String, _ keyPath: WritableKeyPath<MacroTotals, Double>, _ text: String
  ) {
    var edits = state.nutritionEdits ?? [:]
    edits[id, default: [:]][field] = text
    state.nutritionEdits = edits
    if NumericInput.nutritionError(text) == nil, let value = parseNumberInput(text) {
      setPer100g(id, keyPath, value)
    }
  }

  /// Sets one per-100 g value. The item keeps its grams and is stored per 100 g from now on.
  func setPer100g(_ id: UUID, _ keyPath: WritableKeyPath<MacroTotals, Double>, _ value: Double) {
    guard value.isFinite, value >= 0,
      let index = state.items.firstIndex(where: { $0.id == id })
    else { return }
    var per100g = state.items[index].per100g
    per100g[keyPath: keyPath] = value
    state.items[index].macroBasis = .per100g
    state.items[index].baseGrams = 100
    state.items[index].base = per100g
  }

  // MARK: Log

  /// Logs the meal. Returns true when the sheet should close.
  func log() async -> Bool {
    guard !isSaving, !isEstimating, !isClosing else { return false }
    guard !hasInvalidEdits else {
      errorMessage = String(localized: "Correct the highlighted values before logging.")
      return false
    }
    guard primaryAction != .estimate else {
      errorMessage = AnalyzeGate.staleMessage
      return false
    }
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
      let libraryIngredients = LogItemMath.mealIngredients(from: state.items)
      let libraryName = mealName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Meal"
      let alreadySavedToLibrary = state.saveToLibrary
      if !(await clearDraft()) {
        notices.append(
          String(localized: "Meal logged. Its draft could not be cleared; try discarding it again.")
        )
      }
      if alreadySavedToLibrary {
        appModel.showToast(notices.joined(separator: " "))
      } else {
        appModel.showToast(
          notices.joined(separator: " "), actionTitle: String(localized: "Save to Library")
        ) { [weak appModel] in
          guard let appModel else { return }
          Task {
            do {
              try await appModel.libraryStore.saveMeal(
                id: nil, name: libraryName, ingredients: libraryIngredients)
              appModel.showToast(String(localized: "Meal saved to Library."))
            } catch {
              appModel.showToast(
                String(localized: "The library copy could not be saved. Your meal log is kept."))
            }
          }
        }
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}
