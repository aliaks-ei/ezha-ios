import EZHAKit
import SwiftUI

/// Create or edit a daily target. Name required, four numeric fields, and an optional water
/// target in ml or l.
struct TargetEditorSheet: View {
  var target: DailyTarget?
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var name: String
  @State private var macros: MacroFieldsModel
  @State private var hasWaterTarget: Bool
  @State private var waterText: String
  @State private var waterUnit: WaterUnit
  @State private var errorMessage: String?
  @State private var isSaving = false

  init(target: DailyTarget?) {
    self.target = target
    _name = State(initialValue: target?.name ?? "")
    _macros = State(
      initialValue: target.map { MacroFieldsModel(values: $0.macros) } ?? MacroFieldsModel())
    // A new target suggests the default water target. An existing one keeps what it has.
    let water = target == nil ? Water.defaultTargetMl : target?.waterTargetMl
    _hasWaterTarget = State(initialValue: water != nil)
    _waterText = State(
      initialValue: Macros.format(water ?? Water.defaultTargetMl, maxFractionDigits: 0))
    _waterUnit = State(initialValue: .ml)
  }

  private var waterMl: Double? { Water.targetMillilitres(waterText, unit: waterUnit) }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty && macros.values != nil && !isSaving
      && (!hasWaterTarget || waterMl != nil)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .textInputAutocapitalization(.words)
        }
        Section {
          MacroFields(model: $macros)
        } footer: {
          Text("Macros add up to \(Macros.format(macros.macroCalories, maxFractionDigits: 0)) kcal")
        }
        waterSection
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(Color.danger) }
        }
      }
      .navigationTitle(target == nil ? "New target" : "Edit target")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(!canSave)
            .accessibilityIdentifier("targetSave")
        }
      }
    }
    .presentationDetents([.large])
  }

  private var waterSection: some View {
    Section {
      Toggle("Daily water target", isOn: $hasWaterTarget)
        .accessibilityIdentifier("waterTargetToggle")
      if hasWaterTarget {
        let layout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
          : AnyLayout(HStackLayout(spacing: 12))
        layout {
          Text("Target")
          if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
          TextField("Water target", text: $waterText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fontDesign(.rounded)
            .monospacedDigit()
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 100)
            .accessibilityIdentifier("waterTargetField")
          Picker("Water unit", selection: $waterUnit) {
            Text(WaterUnit.ml.title).tag(WaterUnit.ml)
            Text(WaterUnit.l.title).tag(WaterUnit.l)
          }
          .pickerStyle(.segmented)
          .fixedSize()
          .accessibilityIdentifier("waterTargetUnit")
        }
        .onChange(of: waterUnit) { old, new in convert(from: old, to: new) }
      }
    } header: {
      Text("Water")
    } footer: {
      waterFooter
    }
  }

  @ViewBuilder private var waterFooter: some View {
    if !hasWaterTarget {
      Text("No water target. Today shows only how much water you drink.")
    } else if let ml = waterMl {
      Text(
        "Saved as \(Water.format(ml)). \(Water.format(Water.defaultTargetMl)) is a common daily goal. Water does not change calories or macros."
      )
    } else {
      Text(Water.targetError(waterText, unit: waterUnit) ?? "")
        .foregroundStyle(Color.danger)
        .accessibilityIdentifier("waterTargetError")
    }
  }

  /// Keeps the same amount when the unit changes: "2000" ml becomes "2" l.
  private func convert(from old: WaterUnit, to new: WaterUnit) {
    guard let value = parseNumberInput(waterText) else { return }
    let ml = value * old.millilitres
    waterText = Macros.format(ml / new.millilitres, maxFractionDigits: new == .l ? 2 : 0)
  }

  private func save() async {
    guard let values = macros.values else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      try await appModel.targetsStore.save(
        id: target?.id, name: name.trimmingCharacters(in: .whitespaces), macros: values,
        water: .set(hasWaterTarget ? waterMl : nil))
      dismiss()
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }
}
