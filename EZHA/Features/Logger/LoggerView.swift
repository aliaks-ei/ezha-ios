import EZHAKit
import PhotosUI
import SwiftUI

/// The logger sheet for one date.
struct LoggerView: View {
  var date: DateKey
  @Environment(AppModel.self) private var appModel
  @State private var model: LoggerModel?

  var body: some View {
    NavigationStack {
      if let model {
        LoggerContent(model: model)
      } else {
        ProgressView()
      }
    }
    .task {
      guard model == nil else { return }
      let model = LoggerModel(date: date, appModel: appModel)
      await model.restore()
      self.model = model
    }
    // Swipe-down would discard the meal without asking, so it is off while there is input.
    .interactiveDismissDisabled(
      model?.isEstimating == true || model?.isSaving == true || model?.hasInput == true)
  }
}

private struct LoggerContent: View {
  @Bindable var model: LoggerModel
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var photoItem: PhotosPickerItem?
  @State private var isPhotosPresented = false
  @State private var isCameraPresented = false
  @State private var isScannerPresented = false
  @State private var isLibraryPresented = false
  @State private var consentAction: (() -> Void)?
  @State private var isClearConfirmPresented = false
  @State private var isDiscardConfirmPresented = false
  @State private var labelFields = MacroFieldsModel()
  @FocusState private var isTextFocused: Bool
  @State private var isKeyboardVisible = false

  var body: some View {
    List {
      Section {
        composer
      }
      .listRowBackground(Color.clear)
      // No insets: the card is as wide as the list sections below it.
      .listRowInsets(EdgeInsets())

      if let error = model.errorMessage {
        Section {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.danger)
          if model.primaryAction == .estimate && !model.isEstimating {
            Button("Try again") { runAI(model.estimate) }
          }
        }
      }

      provisionalSection

      if !model.state.items.isEmpty && !model.isEstimating {
        reviewQuestionSection
        reviewSections
      }

      quickAddSection
    }
    .listSectionSpacing(.compact)
    .contentMargins(.top, 8, for: .scrollContent)
    .scrollDismissesKeyboard(.interactively)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4),
      value: model.state.items.map(\.id)
    )
    .navigationTitle("Log meal")
    .navigationSubtitle(model.date.label(today: appModel.today))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close", systemImage: "xmark") { close() }
      }
    }
    .safeAreaInset(edge: .bottom) { bottomBar }
    .navigationDestination(isPresented: $isLibraryPresented) {
      LibraryPickerView { items, foodName, mealIds in
        model.addLibraryItems(items, foodName: foodName, mealIds: mealIds)
      }
    }
    .photosPicker(isPresented: $isPhotosPresented, selection: $photoItem, matching: .images)
    .onChange(of: photoItem) { _, item in
      guard let item else { return }
      photoItem = nil
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          await model.attachPhoto(data, isLabel: false)
        }
      }
    }
    .fullScreenCover(isPresented: $isCameraPresented) {
      CameraPicker { data in Task { await model.attachPhoto(data, isLabel: false) } }
        .ignoresSafeArea()
    }
    .fullScreenCover(isPresented: $isScannerPresented) {
      DocumentScanner { data in Task { await model.attachPhoto(data, isLabel: true) } }
        .ignoresSafeArea()
    }
    .aiConsentAlert($consentAction)
    .confirmationDialog(
      "Clear this draft?", isPresented: $isClearConfirmPresented, titleVisibility: .visible
    ) {
      Button("Clear draft", role: .destructive) { Task { await model.clearDraft() } }
    } message: {
      Text("The description, photo, and items are removed.")
    }
    .confirmationDialog(
      "Discard this meal?", isPresented: $isDiscardConfirmPresented, titleVisibility: .visible
    ) {
      Button("Discard meal", role: .destructive) { discardAndClose() }
      Button("Keep editing", role: .cancel) {}
    } message: {
      Text("The description, photo, and items are removed.")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { Task { await model.saveDraftNow() } }
    }
    .sensoryFeedback(.success, trigger: model.estimateCount)
    .task { await appModel.libraryStore.load() }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    {
      _ in isKeyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
    {
      _ in isKeyboardVisible = false
    }
  }

  @ViewBuilder
  private var provisionalSection: some View {
    if model.isEstimating && !model.provisionalItems.isEmpty {
      Section {
        ForEach(Array(model.provisionalItems.enumerated()), id: \.offset) { _, item in
          LabeledContent(item.name) {
            Text("\(Macros.format(item.grams, maxFractionDigits: 0)) g")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
      } header: {
        Text("Foods found")
      } footer: {
        Text("Still checking nutrition…")
      }
    }

  }

  @ViewBuilder
  private var reviewQuestionSection: some View {
    if !model.isStale, let review = model.state.review, let item = model.reviewItem {
      Section {
        Text(review.question)
        if review.kind == "portion" {
          LabeledContent("Grams eaten") {
            GramsField(
              text: Binding(get: { item.gramsText }, set: { model.setGrams(item.id, $0) }),
              onStep: { model.step(item.id, by: $0) },
              onFocusLost: { model.gramsFocusLost(item.id) })
          }
          Button("Use this amount") { model.confirmReviewPortion() }
            .disabled(LogItemMath.validGrams(item.gramsText) == nil)
            .accessibilityIdentifier("confirmPortion")
        } else {
          TextField(
            "Add a detail",
            text: Binding(
              get: { model.state.reviewAnswer ?? "" },
              set: { model.state.reviewAnswer = $0 })
          )
          .accessibilityIdentifier("reviewAnswer")
          Button("Update estimate") { runAI(model.answerReview) }
            .disabled(
              (model.state.reviewAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ?? true))
        }
        Button("Keep estimate") { model.dismissReview() }
          .foregroundStyle(.secondary)
      } header: {
        Text("One detail to check")
      }
    }
  }

  // MARK: Composer

  private var composer: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField(
        "What did you eat?", text: $model.state.text,
        prompt: Text(
          model.imageData == nil
            ? "Describe your meal, e.g. 150 g chicken and rice" : "Add details (optional)"),
        axis: .vertical
      )
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3...10 : 2...6)
      .focused($isTextFocused)
      .disabled(model.isEstimating)
      .accessibilityIdentifier("mealText")

      attachments

      if let data = model.imageData, let image = UIImage(data: data) {
        photoPreview(image)
      }

      if let stage = model.stage {
        HStack(spacing: 8) {
          Image(systemName: "sparkles")
            .foregroundStyle(Color.brandPrimary)
            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
          Text(stage.text)
            .font(.subheadline.weight(.medium))
            .contentTransition(.opacity)
            .animation(.easeInOut, value: stage)
          Spacer()
          Button("Cancel") { model.cancelEstimate() }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .padding(12)
    .background(Color.surface, in: .rect(cornerRadius: 20, style: .continuous))
    .shimmerBorder(model.isEstimating)
    .animation(.smooth, value: model.isEstimating)
  }

  /// Camera, Photos, and Scan label. Library items are in the "Add from library" section.
  private var attachments: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { attachmentButtons(compact: true) }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) { attachmentButtons(compact: false) }
      }
    }
    .disabled(model.isEstimating)
  }

  @ViewBuilder
  private func attachmentButtons(compact: Bool) -> some View {
    if CameraPicker.isAvailable {
      attachmentButton("Camera", systemImage: "camera", id: "attachCamera", compact: compact) {
        isCameraPresented = true
      }
    }
    attachmentButton(
      "Photos", systemImage: "photo.on.rectangle", id: "attachPhotos", compact: compact
    ) {
      isPhotosPresented = true
    }
    if DocumentScanner.isAvailable {
      attachmentButton(
        "Scan label", systemImage: "doc.text.viewfinder", id: "attachScan", compact: compact
      ) {
        runAI { isScannerPresented = true }
      }
    }
  }

  private func attachmentButton(
    _ title: LocalizedStringKey, systemImage: String, id: String, compact: Bool,
    action: @escaping () -> Void
  ) -> some View {
    AttachmentButton(title: title, systemImage: systemImage, fills: compact, action: action)
      .accessibilityIdentifier(id)
  }

  // MARK: Add from library

  /// Recently used library items not yet in the meal. One tap adds an item.
  @ViewBuilder
  private var quickAddSection: some View {
    let store = appModel.libraryStore
    let addedFoods = Set(model.state.items.compactMap(\.linkedFoodId))
    let foods = store.sortedFoods
      .filter { !addedFoods.contains($0.id) && !model.state.usedMealIds.contains($0.id) }
      .prefix(5)
    if !store.foods.isEmpty && !model.isEstimating {
      Section {
        ForEach(foods) { food in
          Button {
            Task { await model.quickAdd(food) }
          } label: {
            QuickAddRow(food: food, isLoading: model.quickAddingId == food.id)
          }
          .buttonStyle(.plain)
          .disabled(model.quickAddingId != nil)
        }
        Button {
          isLibraryPresented = true
        } label: {
          Label("Search library", systemImage: "magnifyingglass")
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("attachLibrary")
      } header: {
        Text("Add from library")
      }
    }
  }

  private func photoPreview(_ image: UIImage) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: 96, height: 96)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityLabel("Meal photo")
        .overlay(alignment: .topTrailing) {
          Button("Remove photo", systemImage: "xmark.circle.fill") { model.removePhoto() }
            .labelStyle(.iconOnly)
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.6))
            .frame(width: 44, height: 44)
            .offset(x: 14, y: -14)
            .disabled(model.isEstimating)
        }
      Toggle("Nutrition label", isOn: $model.state.isLabel)
        .disabled(model.isEstimating)
      if model.state.isLabel {
        LabeledContent("Grams eaten") {
          TextField("Optional", text: $model.state.labelGramsText)
            .accessibilityIdentifier("labelGrams")
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
        }
      }
    }
  }

  // MARK: Review

  @ViewBuilder
  private var reviewSections: some View {
    Section {
      ForEach(Array(model.state.items.enumerated()), id: \.element.id) { index, item in
        ItemCard(model: model, item: item, index: index)
      }
      .onDelete { offsets in
        for offset in offsets { model.removeItem(model.state.items[offset].id) }
      }
    } header: {
      Text("Review meal")
    } footer: {
      if model.hasAIItems {
        Text("Estimated nutrition. Adjust quantities before logging.")
      }
    }

    if model.showsLabelOverrides {
      Section {
        MacroFields(model: $labelFields)
        Button("Apply") {
          if let values = labelFields.values { model.applyLabelOverride(values) }
        }
        .disabled(labelFields.values == nil)
      } header: {
        Text("Label values for this portion")
      }
      .onAppear(perform: syncLabelFields)
      .onChange(of: model.state.items) { syncLabelFields() }
    }

    Section {
      let totals = model.totals
      Text(
        "Total: \(totals.calories, format: .number.precision(.fractionLength(0))) kcal · P \(totals.protein, format: .number.precision(.fractionLength(0)))g · C \(totals.carbs, format: .number.precision(.fractionLength(0)))g · F \(totals.fat, format: .number.precision(.fractionLength(0)))g"
      )
      .font(.subheadline.weight(.semibold))
      .fontDesign(.rounded)
      .monospacedDigit()
      Toggle("Save this meal to Library", isOn: $model.state.saveToLibrary)
      if model.state.saveToLibrary {
        TextField("Meal name", text: $model.mealName)
      }
      Button("Clear draft", role: .destructive) { isClearConfirmPresented = true }
    }
  }

  private func syncLabelFields() {
    if let display = model.labelDisplayMacros {
      labelFields = MacroFieldsModel(values: display.rounded)
    }
  }

  // MARK: Bottom bar

  private var bottomBar: some View {
    VStack(spacing: 8) {
      if model.isStale {
        Text("Your photo or description changed. Update the estimate before logging.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      // The keyboard button sits in this row, not in a keyboard toolbar, so the two never overlap.
      HStack(spacing: 8) {
        Button(action: primary) {
          Group {
            if model.isSaving {
              ProgressView()
            } else if model.primaryAction == .estimate {
              Label("Estimate nutrition", systemImage: "sparkles")
            } else {
              // Short label when the full one does not fit on one line (large text).
              ViewThatFits(in: .horizontal) {
                Text(
                  "Log meal · \(model.totals.calories, format: .number.precision(.fractionLength(0))) kcal"
                )
                .monospacedDigit()
                .fixedSize()
                Text("Log meal").fixedSize()
              }
            }
          }
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(isPrimaryDisabled)
        .accessibilityIdentifier("loggerPrimary")
        if isKeyboardVisible {
          Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { hideKeyboard() }
            .labelStyle(.iconOnly)
            .font(.headline)
            .frame(minWidth: 36, minHeight: 36)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .transition(.opacity)
        }
      }
      .animation(.smooth(duration: 0.2), value: isKeyboardVisible)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  private var isPrimaryDisabled: Bool {
    if model.isEstimating || model.isSaving { return true }
    if model.primaryAction == .estimate { return false }
    return model.state.items.isEmpty
  }

  private func primary() {
    hideKeyboard()
    if model.primaryAction == .estimate {
      runAI(model.estimate)
      return
    }
    Task {
      if await model.log() {
        dismiss()
      }
    }
  }

  /// Runs an AI action, asking for consent first when needed.
  private func runAI(_ action: @escaping () -> Void) {
    if appModel.isAIConsentGiven {
      action()
    } else {
      consentAction = action
    }
  }

  /// Close starts the next meal fresh: it discards the input, after a confirmation when there is any.
  private func close() {
    model.cancelEstimate()
    if model.hasInput {
      isDiscardConfirmPresented = true
    } else {
      discardAndClose()
    }
  }

  private func discardAndClose() {
    Task {
      await model.clearDraft()
      dismiss()
    }
  }

  private func hideKeyboard() {
    isTextFocused = false
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

/// A library item with an add button: "Greek yogurt" / "Per 100g · 59 kcal".
private struct QuickAddRow: View {
  var food: SavedFood
  var isLoading: Bool

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(food.name).lineLimit(2)
        Text(LibraryFilter.subtitle(food))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
      if isLoading {
        ProgressView()
      } else {
        Image(systemName: "plus.circle.fill")
          .font(.title2)
          .foregroundStyle(Color.brandPrimary)
      }
    }
    .frame(minHeight: 44)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Add \(food.name)")
    .accessibilityValue(LibraryFilter.subtitle(food))
  }
}

/// One item: name, grams with stepper, live macros, and remove.
private struct ItemCard: View {
  var model: LoggerModel
  var item: LogItem
  var index: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isVisible = false

  var body: some View {
    let macros = LogItemMath.macros(item)
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(item.name).font(.body.weight(.medium))
        Spacer()
        KcalText(value: macros.calories).font(.subheadline.weight(.semibold))
        Button {
          model.removeItem(item.id)
        } label: {
          Image(systemName: "xmark")
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Remove \(item.name)")
      }
      let macroLine = MacroLine(macros: macros)
        .font(.caption)
        .foregroundStyle(.secondary)
      let grams = GramsField(
        text: Binding(get: { item.gramsText }, set: { model.setGrams(item.id, $0) }),
        onStep: { model.step(item.id, by: $0) },
        onFocusLost: { model.gramsFocusLost(item.id) })
      if dynamicTypeSize.isAccessibilitySize {
        macroLine
        grams
      } else {
        HStack {
          macroLine
          Spacer()
          grams
        }
      }
      if item.origin == .ai && !item.aiNotes.isEmpty {
        DisclosureGroup("Estimate details") {
          Text(item.aiNotes)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .accessibilityIdentifier("estimateDetails\(index)")
      }
      if item.isNutritionMissing {
        Text("Nutrition is missing. Remove this item to log the rest of your meal.")
          .font(.footnote)
          .foregroundStyle(Color.danger)
      }
    }
    .opacity(isVisible ? 1 : 0)
    .offset(y: isVisible || reduceMotion ? 0 : 12)
    .onAppear {
      withAnimation(
        reduceMotion
          ? .easeInOut(duration: 0.2) : .spring(duration: 0.4).delay(Double(index) * 0.05)
      ) { isVisible = true }
    }
  }
}
