import EZHAKit
import PhotosUI
import SwiftUI

/// The logger sheet for one date.
struct LoggerView: View {
  var date: DateKey
  @Environment(AppModel.self) private var appModel
  @State private var model: LoggerModel?
  @State private var isShortSheet = false

  var body: some View {
    NavigationStack {
      if let model {
        LoggerContent(model: model, isShortSheet: isShortSheet)
      } else {
        ProgressView()
      }
    }
    .onGeometryChange(for: Bool.self) { $0.size.height < 700 } action: { isShortSheet = $0 }
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
  /// A compact iPhone: the day balance shows as one line.
  var isShortSheet: Bool
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @State private var photoItem: PhotosPickerItem?
  @State private var isPhotoLabel = false
  @State private var expandedId: UUID?
  @State private var isPhotosPresented = false
  @State private var isCameraPresented = false
  @State private var isScannerPresented = false
  @State private var isLibraryPresented = false
  @State private var consentAction: (() -> Void)?
  @State private var isClearConfirmPresented = false
  @State private var isDiscardConfirmPresented = false
  @State private var isEditingSource = false
  @FocusState private var isTextFocused: Bool
  @State private var isKeyboardVisible = false

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 600
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(Color.danger)
              .font(.subheadline)
              .accessibilityIdentifier("loggerError")
          }
          if isEntryVisible {
            composer
            provisionalSection
          } else {
            reviewContent(compact: compact)
          }
        }
        .disabled(model.isSaving)
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, isEntryVisible ? 24 : compact ? 20 : 40)
        .padding(.bottom, compact ? 12 : 24)
        .frame(maxWidth: .infinity)
      }
    }
    .background(Color.surface)
    .scrollDismissesKeyboard(.interactively)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4),
      value: model.state.items.map(\.id)
    )
    .navigationTitle(isEntryVisible ? "Add meal" : "Review meal")
    .navigationSubtitle(model.date.label(today: appModel.today))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close", systemImage: "xmark") { close() }
          .disabled(model.isSaving)
      }
      if model.hasInput {
        ToolbarItem(placement: .secondaryAction) {
          Menu {
            if !model.state.items.isEmpty {
              Button("Edit description", systemImage: "square.and.pencil") {
                isEditingSource = true
              }
            }
            Button("Clear draft", systemImage: "trash", role: .destructive) {
              isClearConfirmPresented = true
            }
          } label: {
            Label("Meal actions", systemImage: "ellipsis")
          }
          .disabled(model.isEstimating || model.isSaving)
        }
      }
    }
    .safeAreaInset(edge: .bottom) { bottomBar }
    .navigationDestination(isPresented: $isLibraryPresented) {
      LibraryPickerView { items, foodName, mealIds in
        model.addLibraryItems(items, foodName: foodName, mealIds: mealIds)
        isEditingSource = false
      }
    }
    .navigationDestination(for: LoggerDestination.self) { destination in
      switch destination {
      case .portion(let id):
        LoggerPortionEditor(model: model, itemId: id)
      case .food(let id):
        LoggerFoodEditor(model: model, itemId: id, runAI: runAI)
      }
    }
    .photosPicker(isPresented: $isPhotosPresented, selection: $photoItem, matching: .images)
    .onChange(of: photoItem) { _, item in
      guard let item else { return }
      photoItem = nil
      let isLabel = isPhotoLabel
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          await attachAndEstimate(data, isLabel: isLabel)
        }
      }
    }
    .fullScreenCover(isPresented: $isCameraPresented) {
      CameraPicker { data in Task { await attachAndEstimate(data, isLabel: false) } }
        .ignoresSafeArea()
    }
    .fullScreenCover(isPresented: $isScannerPresented) {
      DocumentScanner { data in Task { await attachAndEstimate(data, isLabel: true) } }
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
    .onChange(of: model.estimateCount) { _, _ in
      isEditingSource = false
      hideKeyboard()
      expandSingleItem()
    }
    .onAppear(perform: expandSingleItem)
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

  private var isEntryVisible: Bool {
    model.state.items.isEmpty || model.isEstimating || model.primaryAction == .estimate
      || isEditingSource
  }

  @ViewBuilder
  private var provisionalSection: some View {
    if model.isEstimating && !model.provisionalItems.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Foods found").font(.headline)
        ForEach(Array(model.provisionalItems.enumerated()), id: \.offset) { _, item in
          LabeledContent(item.name) {
            Text("\(Macros.format(item.grams, maxFractionDigits: 0)) g")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
        Text("Still checking nutrition…")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }

  }

  // MARK: Composer

  private var composer: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("What did you eat?")
        .font(.title2.weight(.semibold))

      sourceTiles

      HStack(alignment: .bottom, spacing: 4) {
        TextField(
          "What did you eat?", text: $model.state.text,
          prompt: Text(
            model.imageData == nil
              ? "Or describe it, e.g. 150 g chicken and rice" : "Add details (optional)"),
          axis: .vertical
        )
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3...10 : 2...6)
        .focused($isTextFocused)
        .accessibilityIdentifier("mealText")
        .padding(.vertical, 16)
        Button("Choose from Photos", systemImage: "photo.on.rectangle") {
          pickPhoto(isLabel: false)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(minWidth: 44, minHeight: 44)
        .padding(.bottom, 6)
        .accessibilityIdentifier("attachPhotos")
      }
      .padding(.leading, 16)
      .padding(.trailing, 6)
      .background(Color.canvas, in: .rect(cornerRadius: 12))
      .disabled(model.isEstimating)

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
    .animation(.smooth, value: model.isEstimating)
  }

  /// The three ways to start: a food photo, a nutrition label, or a saved food.
  private var sourceTiles: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    return layout {
      sourceTile("Photo of food", systemImage: "camera", id: "attachCamera") {
        if CameraPicker.isAvailable { isCameraPresented = true } else { pickPhoto(isLabel: false) }
      }
      sourceTile("Scan label", systemImage: "doc.text.viewfinder", id: "attachScan") {
        runAI {
          if DocumentScanner.isAvailable { isScannerPresented = true } else { pickPhoto(isLabel: true) }
        }
      }
      sourceTile("Saved foods", systemImage: "books.vertical", id: "attachLibrary") {
        isLibraryPresented = true
      }
    }
    .disabled(model.isEstimating)
  }

  private func sourceTile(
    _ title: LocalizedStringKey, systemImage: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.title2)
          .foregroundStyle(Color.brandPrimary)
        Text(title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, minHeight: 88)
      .padding(.vertical, 8)
      .background(Color.canvas, in: .rect(cornerRadius: 16))
      .contentShape(.rect(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  private func pickPhoto(isLabel: Bool) {
    isPhotoLabel = isLabel
    isPhotosPresented = true
  }

  /// A photo starts the estimate at once; text typed before it is included.
  private func attachAndEstimate(_ data: Data, isLabel: Bool) async {
    if await model.attachPhoto(data, isLabel: isLabel) { runAI(model.estimate) }
  }

  private func expandSingleItem() {
    if model.state.items.count == 1 { expandedId = model.state.items.first?.id }
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
      if model.state.isLabel {
        Text("Nutrition label")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: Review

  private func reviewContent(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 12 : 20) {
      ForEach(Array(model.state.items.enumerated()), id: \.element.id) { index, item in
        LoggerReviewItem(
          model: model, item: item, index: index, isExpanded: expandedId == item.id
        ) {
          expandedId = expandedId == item.id ? nil : item.id
        }
        Divider()
      }
      Button {
        isEditingSource = true
      } label: {
        Label("Add food", systemImage: "plus")
          .frame(minHeight: 44)
      }
      .accessibilityIdentifier("addFood")
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: expandedId)
  }

  // MARK: Bottom bar

  private var bottomBar: some View {
    VStack(spacing: 8) {
      if !isEntryVisible {
        let day = appModel.dayStore.merged(model.date).flatMap { $0.goals.calories > 0 ? $0 : nil }
        VStack(alignment: .leading, spacing: 8) {
          let stacked = dynamicTypeSize.isAccessibilitySize
          (stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline)))
          {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(model.hasAIItems ? "Estimated total" : "Meal total")
                .foregroundStyle(.secondary)
              KcalText(value: model.totals.calories).font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reviewTotal")
            if !stacked { Spacer(minLength: 8) }
            if let day {
              DayImpact.remaining(
                day.goals.calories, day.totals.calories + model.totals.calories, unit: "kcal"
              )
              .font(.subheadline.weight(.semibold))
              .accessibilityLabel("Calories after this meal")
            }
          }
          if let day {
            DayImpact(
              goals: day.goals, eaten: day.totals, meal: model.totals,
              isCompact: isShortSheet || isKeyboardVisible || dynamicTypeSize.isAccessibilitySize)
          }
        }
      }
      if model.isStale {
        Text("Your photo or description changed. Update the estimate before logging.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      if model.canRestorePreviousEstimate {
        Button("Use previous estimate") {
          model.restorePreviousEstimate()
          isEditingSource = false
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("restoreEstimate")
      }
      // The keyboard button sits in this row, not in a keyboard toolbar, so the two never overlap.
      HStack(spacing: 8) {
        Button(action: primary) {
          Group {
            if model.isSaving {
              ProgressView()
            } else if model.isEstimating {
              ProgressView()
            } else if model.primaryAction == .estimate || model.state.items.isEmpty {
              Label("Estimate nutrition", systemImage: "sparkles")
            } else if isEntryVisible {
              Text("Review meal")
            } else {
              Text("Log meal")
            }
          }
          .font(.headline)
          .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
          .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
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
    .frame(maxWidth: 600)
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(Color.surface)
    .overlay(alignment: .top) { if !isEntryVisible { Divider() } }
  }

  private var isPrimaryDisabled: Bool {
    if model.isEstimating || model.isSaving { return true }
    if model.primaryAction == .estimate || model.state.items.isEmpty {
      return !model.fingerprint.hasInput
    }
    return AnalyzeGate.logBlockReason(model.state.items) != nil
  }

  private func primary() {
    hideKeyboard()
    if model.primaryAction == .estimate || model.state.items.isEmpty {
      runAI(model.estimate)
      return
    }
    if isEntryVisible {
      isEditingSource = false
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

/// The day's balance after this meal: a calorie bar, then protein, carbs and fat.
private struct DayImpact: View {
  var goals: MacroTotals
  var eaten: MacroTotals
  var meal: MacroTotals
  var isCompact: Bool

  var body: some View {
    Group {
      if isCompact {
        let over = macros.filter { $0.goal > 0 && $0.eaten + $0.meal > $0.goal }
        if !over.isEmpty {
          Text(
            over.map { "\($0.title) \(Self.format($0.eaten + $0.meal - $0.goal)) g over" }
              .joined(separator: " · ")
          )
          .font(.footnote)
          .foregroundStyle(Color.danger)
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } else {
        VStack(spacing: 10) {
          ImpactBar(
            goal: goals.calories, eaten: eaten.calories, meal: meal.calories, color: .brandPrimary)
          HStack(alignment: .top, spacing: 16) {
            ForEach(macros, id: \.title) { macro in
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                  Text(macro.title).foregroundStyle(.secondary).lineLimit(1)
                  Spacer(minLength: 0)
                  Self.remaining(macro.goal, macro.eaten + macro.meal, unit: "g")
                    .fontWeight(.semibold)
                    .layoutPriority(1)
                }
                ImpactBar(
                  goal: macro.goal, eaten: macro.eaten, meal: macro.meal, color: macro.color)
              }
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(macro.title)
              .accessibilityValue(
                Self.remainingText(macro.goal, macro.eaten + macro.meal, unit: "grams"))
            }
          }
          .font(.caption)
        }
      }
    }
    .accessibilityIdentifier("dayImpact")
  }

  private var macros: [(title: String, goal: Double, eaten: Double, meal: Double, color: Color)] {
    [
      (String(localized: "Protein"), goals.protein, eaten.protein, meal.protein, .brandSecondary),
      (String(localized: "Carbs"), goals.carbs, eaten.carbs, meal.carbs, .brandAccent),
      (String(localized: "Fat"), goals.fat, eaten.fat, meal.fat, .brandPrimary),
    ]
  }

  static func remaining(_ goal: Double, _ total: Double, unit: String) -> some View {
    Text(remainingText(goal, total, unit: unit))
      .fontDesign(.rounded)
      .monospacedDigit()
      .foregroundStyle(total > goal ? Color.danger : Color.primary)
  }

  private static func remainingText(_ goal: Double, _ total: Double, unit: String) -> String {
    total > goal
      ? String(localized: "\(format(total - goal)) \(unit) over")
      : String(localized: "\(format(goal - total)) \(unit) left")
  }

  private static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }
}

/// Eaten so far (solid) and this meal (light) on the day's track. Over the goal, the meal part is red.
private struct ImpactBar: View {
  var goal: Double
  var eaten: Double
  var meal: Double
  var color: Color

  var body: some View {
    GeometryReader { geometry in
      let scale = max(goal, eaten + meal, 1)
      HStack(spacing: 0) {
        Rectangle().fill(color).frame(width: geometry.size.width * eaten / scale)
        Rectangle()
          .fill(eaten + meal > goal ? Color.danger : color.opacity(0.4))
          .frame(width: geometry.size.width * meal / scale)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.track)
      .clipShape(.capsule)
    }
    .frame(height: 6)
    .accessibilityHidden(true)
  }
}
