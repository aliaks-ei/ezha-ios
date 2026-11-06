import EZHAKit
import SwiftUI

/// Add a custom amount in any unit, or edit an entry. Saves millilitres through the outbox.
struct WaterEntrySheet: View {
  var date: DateKey
  /// Nil adds a new entry.
  var entry: WaterEntry?

  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var amount: String
  @State private var unit: WaterUnit = .ml
  @State private var time: Date
  @FocusState private var isAmountFocused: Bool

  init(date: DateKey, entry: WaterEntry? = nil) {
    self.date = date
    self.entry = entry
    _amount = State(
      initialValue: entry.map { Macros.format($0.amountMl, maxFractionDigits: 0) } ?? "")
    _time = State(initialValue: entry?.createdAt ?? .now)
  }

  private var millilitres: Double? { Water.millilitres(amount, unit: unit) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
          layout {
            TextField("Amount", text: $amount)
              .keyboardType(.decimalPad)
              .font(.largeTitle.weight(.bold))
              .fontDesign(.rounded)
              .monospacedDigit()
              .focused($isAmountFocused)
              .accessibilityIdentifier("waterAmountField")
            Picker("Unit", selection: $unit) {
              ForEach(WaterUnit.allCases) { unit in
                Text(unit.title).tag(unit)
              }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("waterUnitPicker")
          }
        } header: {
          Text("Amount")
        } footer: {
          footer
        }

        Section {
          DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("waterTimePicker")
        }

        if let entry {
          Section {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
              .foregroundStyle(Color.danger)
              .accessibilityIdentifier("waterDelete")
          }
        } else {
          presets
        }
      }
      .navigationTitle(entry == nil ? "Add water" : "Edit water")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(entry == nil ? "Add" : "Save") { save() }
            .disabled(millilitres == nil)
            .accessibilityIdentifier("waterSave")
        }
      }
      .onAppear { if entry == nil { isAmountFocused = true } }
    }
    .presentationDetents([.large])
  }

  @ViewBuilder private var footer: some View {
    if let ml = millilitres {
      if unit != .ml {
        VStack(alignment: .leading, spacing: 2) {
          Text("= \(Water.format(ml))")
            .fontWeight(.semibold)
          if let definition = unit.definition { Text(definition) }
        }
        .fontDesign(.rounded)
        .monospacedDigit()
        .accessibilityIdentifier("waterConversion")
      } else {
        Text("Water is saved in millilitres.")
      }
    } else if !amount.trimmingCharacters(in: .whitespaces).isEmpty {
      Text(Water.amountError(amount, unit: unit) ?? "")
        .foregroundStyle(Color.danger)
        .accessibilityIdentifier("waterAmountError")
    } else if let definition = unit.definition {
      Text(definition)
    }
  }

  private var presets: some View {
    Section {
      ForEach(appModel.waterPresets.presets) { preset in
        Button {
          amount = Macros.format(preset.amountMl, maxFractionDigits: 0)
          unit = .ml
        } label: {
          HStack {
            Image(systemName: "drop.fill")
              .foregroundStyle(Color.water)
              .accessibilityHidden(true)
            Text(preset.name)
              .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Text(Water.format(preset.amountMl))
              .fontDesign(.rounded)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          .frame(minHeight: 44)
          .contentShape(.rect)
        }
        .accessibilityLabel("\(preset.name), \(Water.format(preset.amountMl))")
        .accessibilityHint("Fills the amount")
      }
    } header: {
      HStack {
        Text("Presets")
        Spacer()
        NavigationLink("Edit") { WaterPresetsView() }
          .font(.subheadline.weight(.semibold))
          .accessibilityLabel("Edit presets")
          .accessibilityIdentifier("waterEditPresets")
      }
      .textCase(nil)
    } footer: {
      Text("Tap a preset to fill the amount. The first two show on Today.")
    }
  }

  /// The selected day at the chosen time, so entries sort by the time the user picked.
  private var createdAt: Date {
    let calendar = Calendar.current
    let parts = calendar.dateComponents([.hour, .minute], from: time)
    return calendar.date(
      bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: date.date())
      ?? time
  }

  private func save() {
    guard let ml = millilitres else { return }
    let store = appModel.dayStore
    let appModel = appModel
    if var entry {
      entry.amountMl = ml
      entry.createdAt = createdAt
      entry.isPending = false
      Task {
        do {
          try await store.saveWater(entry)
        } catch {
          appModel.showToast(error.localizedDescription)
        }
      }
    } else {
      let new = WaterEntry(date: date, amountMl: ml, createdAt: createdAt)
      Task { await WaterActions.add(new, appModel: appModel) }
    }
    dismiss()
  }

  private func delete(_ entry: WaterEntry) {
    let appModel = appModel
    dismiss()
    WaterActions.delete(entry, appModel: appModel)
  }
}

/// Actions shared by the water card, the entries sheet, and the entry sheet.
@MainActor
enum WaterActions {
  /// Queues the entry and shows "Added 250 ml of water" with "Undo".
  static func add(_ entry: WaterEntry, appModel: AppModel) async {
    do {
      let undo = try await appModel.dayStore.addWater(entry)
      appModel.showToast(
        String(localized: "Added \(Water.format(entry.amountMl)) of water"),
        actionTitle: String(localized: "Undo")
      ) {
        Task { await undo() }
      }
    } catch {
      appModel.showToast(error.localizedDescription)
    }
  }

  /// Hides the entry at once, deletes it after the undo window, and offers "Undo".
  static func delete(_ entry: WaterEntry, appModel: AppModel) {
    Task {
      guard let undo = await appModel.dayStore.deleteWaterWithUndo(entry) else { return }
      appModel.showToast(
        String(localized: "Water entry deleted"), actionTitle: String(localized: "Undo")
      ) {
        Task { await undo() }
      }
    }
  }
}

/// The day's water entries: tap to edit, swipe to delete.
struct WaterEntriesSheet: View {
  var date: DateKey

  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var editing: WaterEntry?
  @State private var isAdding = false

  var body: some View {
    @Bindable var appModel = appModel
    let bundle = appModel.dayStore.merged(date)
    let water = bundle?.water ?? []
    NavigationStack {
      List {
        if let bundle {
          Section {
            WaterCard(
              drunk: bundle.waterTotal, target: bundle.waterTargetMl, presets: [], add: { _ in },
              addOther: {}, setTarget: {}, isCompact: true)
          }
        }
        Section {
          if water.isEmpty {
            ContentUnavailableView(
              "No water yet", systemImage: "drop",
              description: Text("Add water from Today or with the plus button."))
          } else {
            ForEach(water) { entry in
              Button {
                editing = entry
              } label: {
                WaterRow(entry: entry)
              }
              .buttonStyle(.plain)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                  WaterActions.delete(entry, appModel: appModel)
                }
              }
              .accessibilityHint("Edit the amount or time")
            }
          }
        } header: {
          Text("Entries")
        } footer: {
          if !water.isEmpty {
            Text("Tap an entry to change the amount or time. Swipe left to delete.")
          }
        }
      }
      .navigationTitle("Water")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Add water", systemImage: "plus") { isAdding = true }
            .accessibilityIdentifier("waterListAdd")
        }
      }
      .sheet(item: $editing) { entry in
        WaterEntrySheet(date: date, entry: entry)
      }
      .sheet(isPresented: $isAdding) {
        WaterEntrySheet(date: date)
      }
      // The root toast is under this sheet.
      .overlay { ToastOverlay(toast: $appModel.toast) }
    }
    .presentationDetents([.large])
  }
}

/// "💧 250 ml        8:05 AM". Pending entries show "Waiting to sync".
struct WaterRow: View {
  var entry: WaterEntry
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let line =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    line {
      HStack(spacing: 10) {
        Image(systemName: "drop.fill")
          .foregroundStyle(Color.water)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(Water.format(entry.amountMl))
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
          if entry.isPending {
            HStack(spacing: 4) {
              Image(systemName: "clock.arrow.circlepath")
                .accessibilityHidden(true)
              Text("Waiting to sync")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.brandPrimary)
          }
        }
      }
      .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
      if let time = entry.createdAt {
        Text(time, format: .dateTime.hour().minute())
          .font(.subheadline)
          .fontDesign(.rounded)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .frame(minHeight: 44)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("waterRow")
  }
}

/// Rename, reorder, add, and delete quick-add presets. The first two show on Today.
struct WaterPresetsView: View {
  @Environment(AppModel.self) private var appModel
  @State private var rows: [Row] = []
  @State private var didLoad = false

  struct Row: Identifiable, Equatable {
    var id: UUID
    var name: String
    var amount: String
  }

  var body: some View {
    List {
      Section {
        ForEach($rows) { $row in
          HStack(spacing: 12) {
            TextField("Name", text: $row.name)
              .accessibilityIdentifier("waterPresetName")
            TextField("Amount", text: $row.amount)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
              .fontDesign(.rounded)
              .monospacedDigit()
              .frame(maxWidth: 90)
              .accessibilityLabel("Amount for \(row.name), millilitres")
            Text("ml").foregroundStyle(.secondary)
          }
          .frame(minHeight: 44)
        }
        .onDelete { rows.remove(atOffsets: $0) }
        .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
        Button("Add preset", systemImage: "plus") {
          rows.append(Row(id: UUID(), name: String(localized: "Glass"), amount: "250"))
        }
        .accessibilityIdentifier("waterAddPreset")
      } footer: {
        Text("Amounts are in millilitres. The first two presets show on Today. Drag to reorder.")
      }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle("Presets")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      guard !didLoad else { return }
      didLoad = true
      rows = appModel.waterPresets.presets.map {
        Row(id: $0.id, name: $0.name, amount: Macros.format($0.amountMl, maxFractionDigits: 0))
      }
    }
    .onChange(of: rows) { save() }
  }

  /// Keeps rows with a name and an amount from 1 ml to 10 l.
  private func save() {
    let presets = rows.compactMap { row -> WaterPreset? in
      let name = row.name.trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, let ml = Water.millilitres(row.amount, unit: .ml) else { return nil }
      return WaterPreset(id: row.id, name: name, amountMl: ml)
    }
    appModel.waterPresets.replace(with: presets)
  }
}
