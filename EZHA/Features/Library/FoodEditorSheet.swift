import EZHAKit
import PhotosUI
import SwiftUI

/// Manual food fields: name, unit type, serving, and macros per 100 g.
struct FoodFormModel: Equatable {
  var name = ""
  var unitType = FoodUnitType.per100g
  var servingGrams = ""
  var servingUnit = ""
  var macros = MacroFieldsModel()

  init() {}

  init(food: SavedFood) {
    name = food.name
    unitType = food.unitType
    servingGrams = food.servingSize.map { Macros.format($0, maxFractionDigits: 1) } ?? ""
    servingUnit = food.servingUnit ?? ""
    macros = MacroFieldsModel(values: Macros.resolvedPer100g(food))
  }

  var draft: Result<SavedFoodDraft, LibraryDraftError> {
    LibraryDrafts.manualDraft(
      .init(
        name: name, unitType: unitType, servingGrams: parseNumberInput(servingGrams),
        servingUnit: servingUnit, per100g: macros.optionalValues))
  }
}

struct FoodFormFields: View {
  @Binding var model: FoodFormModel

  var body: some View {
    Section {
      TextField("Name", text: $model.name)
        .textInputAutocapitalization(.sentences)
      Picker("Unit", selection: $model.unitType) {
        Text("Per 100 g").tag(FoodUnitType.per100g)
        Text("Per serving").tag(FoodUnitType.perServing)
      }
      .pickerStyle(.segmented)
      if model.unitType == .perServing {
        LabeledContent("Serving size") {
          HStack(spacing: 4) {
            TextField("Grams", text: $model.servingGrams)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .monospacedDigit()
            Text("g").foregroundStyle(.secondary)
          }
        }
        TextField("Serving unit (e.g. cup)", text: $model.servingUnit)
      }
    }
    Section {
      MacroFields(model: $model.macros)
    } header: {
      Text("Nutrition per 100 g")
    } footer: {
      if model.unitType == .perServing, case .success(let draft) = model.draft {
        let serving = draft.perServing
        Text(
          "Per serving: \(serving.calories, format: .number.precision(.fractionLength(0))) kcal · P \(serving.protein, format: .number.precision(.fractionLength(0...1)))g · C \(serving.carbs, format: .number.precision(.fractionLength(0...1)))g · F \(serving.fat, format: .number.precision(.fractionLength(0...1)))g"
        )
        .monospacedDigit()
      }
    }
  }
}

/// Saves a draft as a new food, asking Update existing / Create new on a name match.
@MainActor
@Observable
final class FoodSaver {
  var pending: (existing: SavedFood, draft: SavedFoodDraft)?
  var errorMessage: String?
  var isSaving = false

  /// Returns true when saved. Returns false when a duplicate needs a choice or saving failed.
  func save(_ draft: SavedFoodDraft, store: LibraryStore) async -> Bool {
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      if let existing = try await store.findDuplicate(draft.name) {
        pending = (existing, draft)
        return false
      }
      _ = try await store.insert(draft)
      return true
    } catch {
      errorMessage = OnlineError.message(for: error)
      return false
    }
  }

  func resolve(
    _ pending: (existing: SavedFood, draft: SavedFoodDraft), update: Bool, store: LibraryStore
  ) async -> Bool {
    self.pending = nil
    isSaving = true
    defer { isSaving = false }
    do {
      if update {
        try await store.update(pending.existing.id, pending.draft)
      } else {
        _ = try await store.insert(pending.draft)
      }
      return true
    } catch {
      errorMessage = OnlineError.message(for: error)
      return false
    }
  }
}

extension View {
  /// The duplicate name dialog (5.7).
  func duplicateDialog(_ saver: FoodSaver, store: LibraryStore, onSaved: @escaping () -> Void)
    -> some View
  {
    confirmationDialog(
      "\(saver.pending?.existing.name ?? "") is already in your library",
      isPresented: Binding(
        get: { saver.pending != nil }, set: { if !$0 { saver.pending = nil } }),
      titleVisibility: .visible,
      presenting: saver.pending
    ) { pending in
      Button("Update existing") {
        Task { if await saver.resolve(pending, update: true, store: store) { onSaved() } }
      }
      Button("Create new") {
        Task { if await saver.resolve(pending, update: false, store: store) { onSaved() } }
      }
      Button("Cancel", role: .cancel) {}
    }
  }
}

/// Edit an existing food.
struct FoodEditorSheet: View {
  var food: SavedFood
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var form: FoodFormModel
  @State private var errorMessage: String?
  @State private var isSaving = false

  init(food: SavedFood) {
    self.food = food
    _form = State(initialValue: FoodFormModel(food: food))
  }

  var body: some View {
    NavigationStack {
      Form {
        FoodFormFields(model: $form)
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(Color.danger) }
        }
      }
      .navigationTitle("Edit food")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }.disabled(isSaving)
        }
      }
    }
  }

  private func save() async {
    switch form.draft {
    case .failure(let error):
      errorMessage = error.message
    case .success(let draft):
      isSaving = true
      defer { isSaving = false }
      do {
        try await appModel.libraryStore.update(food.id, draft)
        dismiss()
      } catch {
        errorMessage = OnlineError.message(for: error)
      }
    }
  }
}

/// Add a food from a photo (AI) or by hand. Both check for duplicates.
struct AddFoodSheet: View {
  enum Mode: Hashable {
    case photo
    case manual
  }

  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var mode = Mode.manual
  @State private var form = FoodFormModel()
  @State private var saver = FoodSaver()
  @State private var photo = PhotoFoodModel()
  @State private var photoItem: PhotosPickerItem?
  @State private var isPhotosPresented = false
  @State private var isCameraPresented = false
  @State private var isScannerPresented = false
  @State private var consentAction: (() -> Void)?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Mode", selection: $mode) {
            Text("Photo").tag(Mode.photo)
            Text("Manual").tag(Mode.manual)
          }
          .pickerStyle(.segmented)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        switch mode {
        case .manual: FoodFormFields(model: $form)
        case .photo: photoSections
        }
        if let error = saver.errorMessage ?? photo.errorMessage {
          Section { Text(error).foregroundStyle(Color.danger) }
        }
      }
      .navigationTitle("Add food")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(
              saver.isSaving || photo.isEstimating || (mode == .photo && photo.estimate == nil)
            )
            .accessibilityIdentifier("saveFood")
        }
      }
      .duplicateDialog(saver, store: appModel.libraryStore) { dismiss() }
      .photosPicker(isPresented: $isPhotosPresented, selection: $photoItem, matching: .images)
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        photoItem = nil
        Task {
          if let data = try? await item.loadTransferable(type: Data.self) {
            await photo.attach(data, isLabel: false)
          }
        }
      }
      .fullScreenCover(isPresented: $isCameraPresented) {
        CameraPicker { data in Task { await photo.attach(data, isLabel: false) } }.ignoresSafeArea()
      }
      .fullScreenCover(isPresented: $isScannerPresented) {
        DocumentScanner { data in Task { await photo.attach(data, isLabel: true) } }
          .ignoresSafeArea()
      }
      .aiConsentAlert($consentAction)
    }
  }

  @ViewBuilder
  private var photoSections: some View {
    Section {
      HStack(spacing: 8) {
        if CameraPicker.isAvailable {
          AttachmentButton(title: "Camera", systemImage: "camera") { isCameraPresented = true }
        }
        AttachmentButton(title: "Photos", systemImage: "photo.on.rectangle") {
          isPhotosPresented = true
        }
        .accessibilityIdentifier("addFoodPhotos")
        if DocumentScanner.isAvailable {
          AttachmentButton(title: "Scan label", systemImage: "doc.text.viewfinder") {
            runAI { isScannerPresented = true }
          }
        }
      }
      if let data = photo.imageData, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(height: 140)
          .clipShape(.rect(cornerRadius: 14))
          .accessibilityLabel("Food photo")
        Toggle("Nutrition label", isOn: $photo.isLabel)
        if photo.isLabel {
          LabeledContent("Grams eaten") {
            TextField("Optional", text: $photo.labelGramsText)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
          }
        }
        Button {
          runAI { Task { await photo.runEstimate(appModel: appModel) } }
        } label: {
          if photo.isEstimating {
            HStack {
              ProgressView()
              Text("Reading your meal…")
            }
          } else {
            Label("Estimate nutrition", systemImage: "sparkles")
          }
        }
        .disabled(photo.isEstimating)
      }
    } header: {
      Text("Photo")
    } footer: {
      Text("Take or choose a photo of the food or its nutrition label.")
    }
    if photo.estimate != nil {
      Section {
        TextField("Name", text: $photo.name)
        MacroFields(model: $photo.display)
      } header: {
        Text(photo.isLabel ? "Nutrition for the grams eaten" : "Nutrition")
      }
    }
  }

  private func runAI(_ action: @escaping () -> Void) {
    if appModel.isAIConsentGiven { action() } else { consentAction = action }
  }

  private func save() async {
    let result: Result<SavedFoodDraft, LibraryDraftError> =
      switch mode {
      case .manual: form.draft
      case .photo:
        LibraryDrafts.photoDraft(
          name: photo.name, display: photo.display.optionalValues, isLabelPhoto: photo.isLabel,
          labelGrams: parseNumberInput(photo.labelGramsText))
      }
    switch result {
    case .failure(let error):
      saver.errorMessage = error.message
    case .success(let draft):
      if await saver.save(draft, store: appModel.libraryStore) { dismiss() }
    }
  }
}

/// Photo mode of Add food: one photo, one estimate, editable display macros.
@MainActor
@Observable
final class PhotoFoodModel {
  var imageData: Data?
  var isLabel = false
  var labelGramsText = ""
  var estimate: Estimate?
  var name = ""
  var display = MacroFieldsModel()
  var isEstimating = false
  var errorMessage: String?
  private var uploadedPath: String?

  func attach(_ raw: Data, isLabel: Bool) async {
    do {
      imageData = try await ImageProcessing.jpeg(from: raw)
      uploadedPath = nil
      estimate = nil
      if isLabel { self.isLabel = true }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func runEstimate(appModel: AppModel) async {
    guard let imageData else { return }
    isEstimating = true
    errorMessage = nil
    defer { isEstimating = false }
    do {
      if uploadedPath == nil {
        uploadedPath = try await appModel.clients.logging.uploadImage(imageData, UUID())
      }
      let request = EstimateRequest(
        text: nil, items: nil, imagePath: uploadedPath,
        inputType: EntryPayload.analyzeInputType(hasPhoto: true, isLabelPhoto: isLabel))
      var result: Estimate?
      for try await event in appModel.clients.ai.estimateStream(request) {
        if case .result(let value) = event { result = value }
      }
      guard let result else { throw AIError.message("Analysis returned an invalid response.") }
      estimate = result
      if name.isEmpty { name = result.foodName ?? "" }
      // Labels are per 100 g. Display them for the grams eaten when given.
      let shown =
        isLabel
        ? LogItemMath.scalePer100g(result.totals, grams: parseNumberInput(labelGramsText))
        : result.totals
      display = MacroFieldsModel(values: shown.rounded)
    } catch {
      errorMessage = LoggerModel.message(for: error)
    }
  }
}

#Preview {
  AddFoodSheet()
    .environment(AppModel(clients: .preview, inMemory: true))
}
