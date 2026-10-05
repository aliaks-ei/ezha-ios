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
    .interactiveDismissDisabled(model?.isEstimating == true || model?.isSaving == true)
  }
}

private struct LoggerContent: View {
  @Bindable var model: LoggerModel
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var photoItem: PhotosPickerItem?
  @State private var isPhotosPresented = false
  @State private var isCameraPresented = false
  @State private var isScannerPresented = false
  @State private var isLibraryPresented = false
  @State private var consentAction: (() -> Void)?
  @State private var isClearConfirmPresented = false
  @State private var isDraftAlertPresented = false
  @State private var labelFields = MacroFieldsModel()
  @State private var logged = 0
  @FocusState private var isTextFocused: Bool

  var body: some View {
    List {
      Section {
        composer
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

      if let error = model.errorMessage {
        Section {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.danger)
          if model.primaryAction == .estimate && !model.isEstimating {
            Button("Try again") { runAI(model.estimate) }
          }
        }
      }

      if !model.state.items.isEmpty {
        reviewSections
      }
    }
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
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { hideKeyboard() }
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
    .sheet(
      isPresented: Binding(
        get: { consentAction != nil }, set: { if !$0 { consentAction = nil } })
    ) {
      let action = consentAction
      AIConsentSheet { action?() }
    }
    .confirmationDialog(
      "Clear this draft?", isPresented: $isClearConfirmPresented, titleVisibility: .visible
    ) {
      Button("Clear draft", role: .destructive) { Task { await model.clearDraft() } }
    } message: {
      Text("The description, photo, and items are removed.")
    }
    .alert("Your draft could not be saved", isPresented: $isDraftAlertPresented) {
      Button("Keep editing", role: .cancel) {}
      Button("Close anyway", role: .destructive) { dismiss() }
    } message: {
      Text("Closing now loses this draft.")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { Task { await model.saveDraftNow() } }
    }
    .sensoryFeedback(.success, trigger: logged)
    .sensoryFeedback(.success, trigger: model.estimateCount)
  }

  // MARK: Composer

  private var composer: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 4) {
        Text("What did you eat?").font(.headline)
        if model.imageData != nil {
          Text("(optional)").font(.subheadline).foregroundStyle(.secondary)
        }
      }
      TextField(
        "What did you eat?", text: $model.state.text,
        prompt: Text("e.g. 150g chicken, rice and a little olive oil"), axis: .vertical
      )
      .lineLimit(2...6)
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
    .padding()
    .background(Color.surface, in: .rect(cornerRadius: 20, style: .continuous))
    .shimmerBorder(model.isEstimating)
    .animation(.smooth, value: model.isEstimating)
  }

  private var attachments: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) { attachmentButtons(compact: true) }
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
    attachmentButton(
      "Library", systemImage: "books.vertical", id: "attachLibrary", compact: compact
    ) {
      isLibraryPresented = true
    }
  }

  private func attachmentButton(
    _ title: LocalizedStringKey, systemImage: String, id: String, compact: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: systemImage).font(.title3)
        Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
      }
      .frame(maxWidth: compact ? .infinity : nil, minHeight: 44)
      .padding(.horizontal, compact ? 0 : 8)
    }
    .buttonStyle(.glass)
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
      Button(action: primary) {
        Group {
          if model.isSaving {
            ProgressView()
          } else if model.primaryAction == .estimate {
            Label("Estimate nutrition", systemImage: "sparkles")
          } else {
            Text(
              "Log meal · \(model.totals.calories, format: .number.precision(.fractionLength(0))) kcal"
            )
            .monospacedDigit()
          }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .disabled(isPrimaryDisabled)
      .accessibilityIdentifier("loggerPrimary")
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
        logged += 1
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

  private func close() {
    model.cancelEstimate()
    Task {
      if await model.saveDraftNow() {
        dismiss()
      } else {
        isDraftAlertPresented = true
      }
    }
  }

  private func hideKeyboard() {
    isTextFocused = false
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

/// One item: name, grams with stepper, live macros, and remove.
private struct ItemCard: View {
  var model: LoggerModel
  var item: LogItem
  var index: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isVisible = false

  var body: some View {
    let macros = LogItemMath.macros(item)
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(item.name).font(.body.weight(.medium))
        Spacer()
        KcalText(value: macros.calories).font(.subheadline.weight(.semibold))
        Button("Remove \(item.name)", systemImage: "xmark") { model.removeItem(item.id) }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 44)
      }
      HStack {
        MacroLine(macros: macros)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        GramsField(
          text: Binding(get: { item.gramsText }, set: { model.setGrams(item.id, $0) }),
          onStep: { model.step(item.id, by: $0) },
          onFocusLost: { model.gramsFocusLost(item.id) })
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
