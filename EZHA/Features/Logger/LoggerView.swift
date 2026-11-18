import EZHAKit
import PhotosUI
import SwiftUI

/// The logger sheet for one date.
struct LoggerView: View {
  var date: DateKey
  var drafts: LoggerDraftAccess?
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
    .onGeometryChange(for: Bool.self) {
      $0.size.height < 700
    } action: {
      isShortSheet = $0
    }
    .task {
      guard model == nil else { return }
      let model = LoggerModel(date: date, appModel: appModel, drafts: drafts)
      await model.restore()
      self.model = model
    }
    // Swipe-down would discard the meal without asking, so it is off while there is input.
    .interactiveDismissDisabled(
      model?.hasInput == true || model?.isSaving == true || model?.isClosing == true
    )
    .onDisappear { model?.stopBackgroundWork() }
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
  @State private var photoTarget = PhotoTarget.food
  @State private var expandedId: UUID?
  @State private var isPhotosPresented = false
  @State private var isCameraPresented = false
  @State private var isScannerPresented = false
  @State private var isLibraryPresented = false
  @State private var consentAction: (() -> Void)?
  @State private var isDiscardConfirmPresented = false
  @State private var isEditingSource = false
  @FocusState private var isTextFocused: Bool
  @State private var isKeyboardVisible = false

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 600
      ScrollViewReader { scroll in
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
          .disabled(model.isSaving || model.isClosing)
          .frame(maxWidth: 600, alignment: .leading)
          .padding(.horizontal, 24)
          .padding(.top, isEntryVisible ? 24 : compact ? 20 : 40)
          .padding(.bottom, compact ? 12 : 24)
          .frame(maxWidth: .infinity)
        }
        .onChange(of: isKeyboardVisible) { _, visible in
          guard visible, isTextFocused, dynamicTypeSize.isAccessibilitySize else { return }
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard isTextFocused, isKeyboardVisible else { return }
            scroll.scrollTo("composerInput", anchor: .bottom)
          }
        }
        .task(id: model.state.text) {
          guard isTextFocused, isKeyboardVisible, dynamicTypeSize.isAccessibilitySize else {
            return
          }
          try? await Task.sleep(for: .milliseconds(100))
          guard !Task.isCancelled, isTextFocused, isKeyboardVisible else { return }
          scroll.scrollTo("composerInput", anchor: .bottom)
        }
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
      if dynamicTypeSize.isAccessibilitySize {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { hideKeyboard() }
            .labelStyle(.iconOnly)
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Close", systemImage: "xmark") { close() }
          .disabled(model.isSaving || model.isClosing)
      }
      if model.hasInput {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            if !model.state.items.isEmpty {
              Button("Edit description", systemImage: "square.and.pencil") {
                isEditingSource = true
              }
            }
            Button("Discard draft", systemImage: "trash", role: .destructive) {
              isDiscardConfirmPresented = true
            }
          } label: {
            Label("Meal actions", systemImage: "ellipsis")
          }
          .accessibilityIdentifier("mealActions")
          .disabled(model.isEstimating || model.isSaving || model.isClosing)
        }
      }
    }
    .safeAreaInset(edge: .bottom) { bottomBar }
    .navigationDestination(isPresented: $isLibraryPresented) {
      LibraryPickerView { items, foodName, mealIds in
        model.addLibraryItems(items, foodName: foodName, mealIds: mealIds)
        isEditingSource = false
      } onDescribe: { text in
        model.appendDescription(text)
        isEditingSource = true
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
      let target = photoTarget
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          await attach(data, to: target)
        }
      }
    }
    .fullScreenCover(isPresented: $isCameraPresented) {
      let target = photoTarget == .label ? PhotoTarget.food : photoTarget
      CameraPicker { data in Task { await attach(data, to: target) } }
        .ignoresSafeArea()
    }
    .fullScreenCover(isPresented: $isScannerPresented) {
      DocumentScanner { data in Task { await attachAndEstimate(data, isLabel: true) } }
        .ignoresSafeArea()
    }
    .aiConsentAlert($consentAction)
    .alert("Discard this draft?", isPresented: $isDiscardConfirmPresented) {
      Button("Discard draft", role: .destructive) { discardAndClose() }
      Button("Keep editing", role: .cancel) {}
    } message: {
      Text(
        model.isRestaurant
          ? "The description, photos, and items are removed."
          : "The description, photo, and items are removed.")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { Task { await model.saveDraftNow() } }
    }
    .sensoryFeedback(.success, trigger: model.estimateCount)
    .onChange(of: model.estimateCount) { _, _ in
      isEditingSource = false
      hideKeyboard()
      expandedId = nil
    }
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
            Text(item.unit.format(item.grams, maxFractionDigits: 0))
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
      Text(model.isRestaurant ? "Restaurant meal" : "What did you eat?")
        .font(.title2.weight(.semibold))

      if model.isRestaurant {
        restaurantPanel
      } else if !dynamicTypeSize.isAccessibilitySize {
        sourceTiles
      }

      HStack(alignment: .bottom, spacing: 4) {
        TextField(
          "What did you eat?", text: $model.state.text,
          prompt: Text(
            model.isRestaurant
              ? "Add details (optional), e.g. shared the fries"
              : model.imageData == nil
                ? "Or describe it, e.g. 150 g chicken and rice" : "Add details (optional)"),
          axis: .vertical
        )
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...10 : 2...6)
        .focused($isTextFocused)
        .accessibilityIdentifier("mealText")
        .padding(.vertical, 16)
        if !model.isRestaurant {
          Button("Choose from Photos", systemImage: "photo.on.rectangle") {
            pickPhoto(.food)
          }
          .labelStyle(.iconOnly)
          .font(.title3)
          .frame(minWidth: 44, minHeight: 44)
          .padding(.bottom, 6)
          .accessibilityIdentifier("attachPhotos")
        }
      }
      .padding(.leading, 16)
      .padding(.trailing, 6)
      .background(Color.canvas, in: .rect(cornerRadius: 12))
      .disabled(model.isEstimating)
      .id("composerInput")

      if dynamicTypeSize.isAccessibilitySize && !model.isRestaurant { sourceTiles }

      if !model.isRestaurant, let data = model.imageData, let image = UIImage(data: data) {
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

  /// The four ways to start: a food photo, a nutrition label, a saved food, or a restaurant meal.
  /// A 2 × 2 grid, or one column at accessibility sizes.
  private var sourceTiles: some View {
    let columns =
      dynamicTypeSize.isAccessibilitySize
      ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
    return LazyVGrid(columns: columns, spacing: 12) {
      sourceTile("Photo of food", systemImage: "camera", id: "attachCamera") {
        if CameraPicker.isAvailable {
          photoTarget = .food
          isCameraPresented = true
        } else {
          pickPhoto(.food)
        }
      }
      sourceTile("Scan label", systemImage: "doc.text.viewfinder", id: "attachScan") {
        runAI {
          if DocumentScanner.isAvailable {
            isScannerPresented = true
          } else {
            pickPhoto(.label)
          }
        }
      }
      sourceTile("Saved foods", systemImage: "books.vertical", id: "attachLibrary") {
        isLibraryPresented = true
      }
      sourceTile("Restaurant", systemImage: "fork.knife", id: "attachRestaurant") {
        model.startRestaurant()
      }
    }
    .disabled(model.isEstimating)
  }

  // MARK: Restaurant

  /// Two photos, what was ordered and what is left. Only the difference is logged.
  private var restaurantPanel: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 12))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    return VStack(alignment: .leading, spacing: 12) {
      Text("Add a photo of what you ordered and one of what's left. Only what you ate is logged.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      layout {
        restaurantSlot(
          "What you ordered", image: model.imageData, target: .before, id: "restaurantBefore")
        restaurantSlot(
          "What's left", image: model.leftoverImageData, target: .after, id: "restaurantAfter")
      }
      Button {
        model.exitRestaurant()
      } label: {
        Label("Other ways to log", systemImage: "chevron.backward")
          .font(.subheadline)
          .frame(minHeight: 44)
      }
      .accessibilityIdentifier("exitRestaurant")
    }
    .disabled(model.isEstimating)
  }

  @ViewBuilder
  private func restaurantSlot(
    _ title: LocalizedStringKey, image data: Data?, target: PhotoTarget, id: String
  ) -> some View {
    if let data, let image = UIImage(data: data) {
      VStack(alignment: .leading, spacing: 6) {
        Color.clear
          .frame(height: 140)
          .frame(maxWidth: .infinity)
          .overlay {
            Image(uiImage: image).resizable().scaledToFill()
          }
          .clipShape(.rect(cornerRadius: 12))
          .accessibilityElement()
          .accessibilityLabel(Text(title))
          .accessibilityAddTraits(.isImage)
          .accessibilityIdentifier(id)
          .overlay(alignment: .topTrailing) {
            Button("Remove photo", systemImage: "xmark.circle.fill") {
              if target == .before { model.removePhoto() } else { model.removeLeftoverPhoto() }
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.6))
            .frame(width: 44, height: 44)
            .accessibilityIdentifier("\(id)Remove")
          }
        Text(title)
          .font(.subheadline.weight(.medium))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      let tile = VStack(spacing: 8) {
        Image(systemName: target == .before ? "takeoutbag.and.cup.and.straw" : "fork.knife")
          .font(.title2)
          .foregroundStyle(Color.brandPrimary)
        Text(title)
          .font(.subheadline.weight(.medium))
          .multilineTextAlignment(.center)
        Text("Add photo")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 140)
      .padding(.horizontal, 8)
      .foregroundStyle(.primary)
      .background(Color.canvas, in: .rect(cornerRadius: 12))
      .contentShape(.rect(cornerRadius: 12))
      Group {
        if CameraPicker.isAvailable {
          Menu {
            Button("Take photo", systemImage: "camera") {
              photoTarget = target
              isCameraPresented = true
            }
            Button("Choose from Photos", systemImage: "photo.on.rectangle") { pickPhoto(target) }
          } label: {
            tile
          }
        } else {
          Button {
            pickPhoto(target)
          } label: {
            tile
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(title))
      .accessibilityHint("Adds a photo")
      .accessibilityIdentifier(id)
    }
  }

  private func sourceTile(
    _ title: LocalizedStringKey, systemImage: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
          VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(Color.brandPrimary)
            Text(title).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, minHeight: 88)
          .padding(.vertical, 8)
        }
      }
      .foregroundStyle(.primary)
      .background(Color.canvas, in: .rect(cornerRadius: 12))
      .contentShape(.rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  private func pickPhoto(_ target: PhotoTarget) {
    photoTarget = target
    isPhotosPresented = true
  }

  /// A photo starts the estimate at once; text typed before it is included.
  private func attachAndEstimate(_ data: Data, isLabel: Bool) async {
    if await model.attachPhoto(data, isLabel: isLabel) { runAI(model.estimate) }
  }

  /// A restaurant meal estimates once both photos are attached.
  private func attach(_ data: Data, to target: PhotoTarget) async {
    switch target {
    case .food: await attachAndEstimate(data, isLabel: false)
    case .label: await attachAndEstimate(data, isLabel: true)
    case .before:
      if await model.attachPhoto(data, isLabel: false), model.canEstimate {
        runAI(model.estimate)
      }
    case .after:
      if await model.attachLeftoverPhoto(data), model.canEstimate { runAI(model.estimate) }
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
        let day = appModel.dayStore.merged(model.date)
        // While "Log meal" saves, the day already holds this entry; count it once.
        let eaten = day?.totals(excluding: model.state.entryId) ?? .zero
        let isStacked = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(
              model.hasInvalidEdits
                ? "Last valid total"
                : isStacked ? "Total" : model.hasAIItems ? "Estimated total" : "Meal total"
            )
            .foregroundStyle(.secondary)
            KcalText(value: model.totals.calories).font(.headline)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("reviewTotal")
          if let day {
            DayImpact(
              goals: day.goals, eaten: eaten, meal: model.totals,
              isCompact: isShortSheet || isKeyboardVisible || isStacked,
              isStacked: isStacked)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      if model.hasInvalidEdits {
        Text("Correct the highlighted values before logging.")
          .font(.footnote)
          .foregroundStyle(Color.danger)
          .accessibilityIdentifier("invalidEdits")
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
      // Accessibility sizes use the native keyboard toolbar to leave the full row for the action.
      HStack(spacing: 8) {
        Button(action: primary) {
          Group {
            if model.isSaving {
              ProgressView()
            } else if model.isEstimating {
              ProgressView()
            } else if model.primaryAction == .estimate || model.state.items.isEmpty {
              Text(dynamicTypeSize.isAccessibilitySize ? "Estimate" : "Estimate nutrition")
            } else if isEntryVisible {
              Text("Review meal")
            } else {
              Text("Log meal")
            }
          }
          .font(.headline)
          .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
          .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(dynamicTypeSize.isAccessibilitySize ? .regular : .large)
        .disabled(isPrimaryDisabled)
        .accessibilityIdentifier("loggerPrimary")
        .accessibilityLabel(primaryAccessibilityLabel)
        if isKeyboardVisible && !dynamicTypeSize.isAccessibilitySize {
          Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { hideKeyboard() }
            .labelStyle(.iconOnly)
            .font(.headline)
            .frame(minWidth: 44, minHeight: 44)
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
    if model.isEstimating || model.isSaving || model.isClosing { return true }
    if model.primaryAction == .estimate || model.state.items.isEmpty {
      return !model.canEstimate
    }
    return model.hasInvalidEdits || AnalyzeGate.logBlockReason(model.state.items) != nil
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

  private var primaryAccessibilityLabel: String {
    if model.isSaving { return String(localized: "Saving meal") }
    if model.isEstimating { return String(localized: "Estimating nutrition") }
    if model.primaryAction == .estimate || model.state.items.isEmpty {
      return String(localized: "Estimate nutrition")
    }
    return isEntryVisible ? String(localized: "Review meal") : String(localized: "Log meal")
  }

  /// Close starts the next meal fresh: it discards the input, after a confirmation when there is any.
  private func close() {
    hideKeyboard()
    if model.hasInput {
      isDiscardConfirmPresented = true
    } else {
      discardAndClose()
    }
  }

  private func discardAndClose() {
    Task { if await model.clearDraft() { dismiss() } }
  }

  private func hideKeyboard() {
    isTextFocused = false
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

/// Where a picked or taken photo goes.
private enum PhotoTarget {
  case food
  case label
  /// Restaurant meal: what was ordered.
  case before
  /// Restaurant meal: what is left.
  case after
}

/// The day after this meal (PET-111): a calorie bar with this meal as its own segment, the
/// calories before → after against the target, and macro chips. Over a target always shows an
/// icon and the word "over", never color alone. With no target, only the day's totals show.
private struct DayImpact: View {
  var goals: MacroTotals
  var eaten: MacroTotals
  var meal: MacroTotals
  /// Keyboard up, short sheet or accessibility text: no "before →", and only macros that go over.
  var isCompact: Bool
  /// Accessibility text sizes: no bar, and the calorie line stacks.
  var isStacked: Bool

  private var after: MacroTotals { eaten + meal }
  private var hasTarget: Bool { goals.calories > 0 }
  /// Rounded, so the text never says "0 over".
  private var caloriesLeft: Double { (goals.calories - after.calories).rounded() }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if hasTarget && !isStacked {
        ImpactBar(
          goal: goals.calories, eaten: eaten.calories, meal: meal.calories, color: .brandPrimary)
      }
      calorieLine
      macroChips
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dayImpact")
  }

  private var calorieLine: some View {
    let layout =
      isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    return layout {
      progressText
      if hasTarget {
        if !isStacked { Spacer(minLength: 0) }
        balanceText.layoutPriority(1)
      }
    }
    .font(.subheadline)
    .fontDesign(.rounded)
    .monospacedDigit()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Calories after this meal")
    .accessibilityValue(calorieValue)
    .accessibilityIdentifier("dayRemaining")
  }

  /// "1,240 → 1,610 of 2,000 kcal", or "Today 1,240 → 1,610 kcal" with no target.
  private var progressText: Text {
    let before = Text("\(Self.format(eaten.calories)) →").foregroundStyle(.secondary)
    let total = Text(Self.format(after.calories)).fontWeight(.semibold)
    guard hasTarget else {
      let today = Text("Today").foregroundStyle(.secondary)
      let unit = Text("kcal").foregroundStyle(.secondary)
      return Text("\(today) \(before) \(total) \(unit)")
    }
    let goal = Text("of \(Self.format(goals.calories)) kcal").foregroundStyle(.secondary)
    return isCompact ? Text("\(total) \(goal)") : Text("\(before) \(total) \(goal)")
  }

  @ViewBuilder private var balanceText: some View {
    if caloriesLeft < 0 {
      Self.overText("\(Self.format(-caloriesLeft)) over")
    } else {
      Text("\(Text(Self.format(caloriesLeft)).fontWeight(.semibold)) left")
    }
  }

  private var calorieValue: String {
    guard hasTarget else {
      return String(
        localized:
          "\(Self.format(after.calories)) kilocalories today, \(Self.format(eaten.calories)) before this meal"
      )
    }
    let balance =
      caloriesLeft < 0
      ? String(localized: "\(Self.format(-caloriesLeft)) over")
      : String(localized: "\(Self.format(caloriesLeft)) left")
    return String(
      localized:
        "\(Self.format(after.calories)) of \(Self.format(goals.calories)) kilocalories, \(balance)"
    )
  }

  @ViewBuilder private var macroChips: some View {
    let shown = isCompact ? macros.filter(\.isOver) : macros
    if !shown.isEmpty {
      FlowLayout(spacing: 6) {
        ForEach(shown) { MacroChip(macro: $0) }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Macros after this meal")
      .accessibilityValue(macroValue(shown))
      .accessibilityIdentifier("dayMacros")
    }
  }

  /// Over macros first, so VoiceOver reads what needs attention before the rest.
  private func macroValue(_ shown: [ImpactMacro]) -> String {
    let over = shown.filter(\.isOver).map {
      String(localized: "\($0.title) \(Self.format($0.over)) grams over.")
    }
    let rest = shown.filter { !$0.isOver }.map {
      $0.goal > 0
        ? String(
          localized: "\($0.title) \(Self.format($0.total)) of \(Self.format($0.goal)) grams.")
        : String(localized: "\($0.title) \(Self.format($0.total)) grams.")
    }
    return (over + rest).joined(separator: " ")
  }

  private var macros: [ImpactMacro] {
    [
      ImpactMacro(
        title: String(localized: "Protein"), goal: goals.protein, eaten: eaten.protein,
        meal: meal.protein),
      ImpactMacro(
        title: String(localized: "Carbs"), goal: goals.carbs, eaten: eaten.carbs,
        meal: meal.carbs),
      ImpactMacro(
        title: String(localized: "Fat"), goal: goals.fat, eaten: eaten.fat, meal: meal.fat),
    ]
  }

  static func overText(_ text: String) -> Text {
    Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(text)")
      .fontWeight(.semibold)
      .foregroundStyle(Color.danger)
  }

  static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }
}

private struct ImpactMacro: Identifiable {
  var title: String
  var goal: Double
  var eaten: Double
  var meal: Double
  var id: String { title }
  var total: Double { eaten + meal }
  /// Rounded grams over the goal; 0 with no goal.
  var over: Double { goal > 0 ? max(0, (total - goal).rounded()) : 0 }
  var isOver: Bool { over > 0 }
}

/// "Protein 71/140 g", or an outlined "⚠ Protein 11 g over".
private struct MacroChip: View {
  var macro: ImpactMacro

  var body: some View {
    Group {
      if macro.isOver {
        DayImpact.overText("\(macro.title) \(DayImpact.format(macro.over)) g over")
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .overlay(Capsule().strokeBorder(Color.danger, lineWidth: 1.5))
      } else {
        let total = Text(DayImpact.format(macro.total)).fontWeight(.semibold)
        Text("\(macro.title) \(total)\(goalText)")
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.track.opacity(0.5), in: .capsule)
      }
    }
    .font(.caption)
    .fontDesign(.rounded)
    .monospacedDigit()
  }

  private var goalText: Text {
    macro.goal > 0
      ? Text("/\(DayImpact.format(macro.goal)) g").foregroundStyle(.secondary)
      : Text(" g").foregroundStyle(.secondary)
  }
}

/// Eaten so far (solid), this meal (striped) and the part over the goal (striped danger color,
/// after a goal mark). The bar scales to the larger of the goal and the day after this meal.
private struct ImpactBar: View {
  var goal: Double
  var eaten: Double
  var meal: Double
  var color: Color

  var body: some View {
    GeometryReader { geometry in
      let total = eaten + meal
      let scale = max(goal, total, 1)
      let eatenIn = min(eaten, goal)
      let mealIn = max(0, min(total, goal) - eaten)
      let over = max(0, total - goal)
      // 2 pt gaps between the parts come out of the width, so the parts stay on the track.
      let gaps = CGFloat([eatenIn, mealIn, over].filter { $0 > 0 }.count - 1)
      let width = max(0, geometry.size.width - 2 * max(gaps, 0))
      HStack(spacing: 0) {
        Rectangle().fill(color).frame(width: width * eatenIn / scale)
        Stripes(color: color)
          .frame(width: width * mealIn / scale)
          .padding(.leading, eatenIn > 0 && mealIn > 0 ? 2 : 0)
        Stripes(color: .danger)
          .frame(width: width * over / scale)
          .padding(.leading, over > 0 ? 2 : 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.track)
      .clipShape(.capsule)
      .overlay(alignment: .leading) {
        if over > 0 {
          // The goal mark sits in the gap before the over part and reaches past the bar.
          Capsule()
            .fill(Color.primary)
            .frame(width: 2, height: 14)
            .offset(x: width * CGFloat(goal / scale) + 2 * max(gaps - 1, 0))
        }
      }
    }
    .frame(height: 8)
    .accessibilityHidden(true)
  }
}

/// Diagonal stripes on a light fill of the color: this meal, or the part over the goal.
private struct Stripes: View {
  var color: Color

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.4)))
      var path = Path()
      var x = -size.height
      while x < size.width {
        path.move(to: CGPoint(x: x, y: size.height))
        path.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += 5
      }
      context.stroke(path, with: .color(color), lineWidth: 2.5)
    }
    .frame(height: 8)
  }
}
