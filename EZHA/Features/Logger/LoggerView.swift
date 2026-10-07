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
  @Environment(\.colorScheme) private var colorScheme
  @State private var photoItem: PhotosPickerItem?
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
      case .nutrition:
        LoggerNutritionDetails(model: model) {
          isEditingSource = true
        }
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
    .onChange(of: model.estimateCount) { _, _ in
      isEditingSource = false
      hideKeyboard()
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
      .padding(16)
      .background(Color.canvas, in: .rect(cornerRadius: 12))

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
    .animation(.smooth, value: model.isEstimating)
  }

  /// Entry tools stay quiet and are hidden after estimation.
  private var attachments: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 20) { attachmentButtons }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 20) { attachmentButtons }
      }
    }
    .disabled(model.isEstimating)
  }

  @ViewBuilder
  private var attachmentButtons: some View {
    if CameraPicker.isAvailable {
      entryButton("Camera", systemImage: "camera", id: "attachCamera") {
        isCameraPresented = true
      }
    }
    entryButton(
      "Photos", systemImage: "photo.on.rectangle", id: "attachPhotos"
    ) {
      isPhotosPresented = true
    }
    entryButton("Library", systemImage: "books.vertical", id: "attachLibrary") {
      isLibraryPresented = true
    }
    if DocumentScanner.isAvailable {
      Menu {
        Button("Scan label", systemImage: "doc.text.viewfinder") {
          runAI { isScannerPresented = true }
        }
        .accessibilityIdentifier("attachScan")
      } label: {
        Label("More input options", systemImage: "ellipsis")
          .labelStyle(.iconOnly)
          .frame(minWidth: 44, minHeight: 44)
      }
    }
  }

  private func entryButton(
    _ title: LocalizedStringKey, systemImage: String, id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.subheadline)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 44)
    }
    .buttonStyle(.borderless)
    .accessibilityIdentifier(id)
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

  private func reviewContent(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 12 : 28) {
      ForEach(Array(model.state.items.enumerated()), id: \.element.id) { index, item in
        LoggerReviewItem(model: model, item: item, index: index, compact: compact)
        if index < model.state.items.count - 1 {
          Divider()
        }
      }
      if model.state.items.count == 1 {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text(model.hasAIItems ? "Estimated total" : "Meal total")
            .font(.subheadline)
            .foregroundStyle(Color.ink.opacity(0.7))
          KcalText(value: model.totals.calories)
            .font(compact ? .title.weight(.semibold) : .largeTitle.weight(.semibold))
            .accessibilityIdentifier("reviewTotal")
        }
      }
      VStack(spacing: 0) {
        Divider()
        NavigationLink(value: LoggerDestination.nutrition) {
          HStack(spacing: 12) {
            Text("Nutrition & estimate details")
              .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .frame(minHeight: compact ? 44 : 56)
          .padding(.vertical, compact ? 0 : 4)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nutritionDetails")
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
  }

  // MARK: Bottom bar

  private var bottomBar: some View {
    VStack(spacing: 8) {
      if !isEntryVisible && model.state.items.count > 1 {
        HStack {
          Text(model.hasAIItems ? "Estimated total" : "Meal total")
            .foregroundStyle(.secondary)
          Spacer()
          KcalText(value: model.totals.calories).font(.headline)
        }
        .accessibilityIdentifier("reviewTotal")
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
