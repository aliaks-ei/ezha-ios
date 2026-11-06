import EZHAKit
import SwiftUI

/// "Log again" (PET-107): choose the day and change the amounts, then save a copy of the entry.
/// Nothing is saved until the user taps the log button.
struct LogAgainSheet: View {
  var entry: DayEntry
  /// Called after the copy is saved, before this sheet closes.
  var onLogged: () -> Void = {}
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var items: [LogItem]
  @State private var date: DateKey?
  @State private var isSaving = false
  @State private var isCalendarPresented = false
  @State private var errorMessage: String?

  init(entry: DayEntry, onLogged: @escaping () -> Void = {}) {
    self.entry = entry
    self.onLogged = onLogged
    _items = State(initialValue: LogAgain.items(from: entry))
  }

  /// Today by default. Future days are not allowed.
  private var targetDate: DateKey { min(date ?? appModel.today, appModel.today) }
  private var isValid: Bool { !isSaving && LogAgain.isValid(items) }

  var body: some View {
    let totals = LogItemMath.totals(items)
    NavigationStack {
      Form {
        Section {
          LabeledContent("Day") {
            Button(targetDate.titleLabel(today: appModel.today)) { isCalendarPresented = true }
              .accessibilityIdentifier("logAgainDay")
              .accessibilityHint("Chooses the day to log to")
              .popover(isPresented: $isCalendarPresented) { calendar }
          }
        }
        Section {
          ForEach($items) { $item in
            itemRow($item)
          }
        } header: {
          Text("Items")
        } footer: {
          Text(
            "Total: \(totals.calories, format: .number.precision(.fractionLength(0))) kcal · P \(totals.protein, format: .number.precision(.fractionLength(0)))g · C \(totals.carbs, format: .number.precision(.fractionLength(0)))g · F \(totals.fat, format: .number.precision(.fractionLength(0)))g"
          )
          .monospacedDigit()
          .contentTransition(.numericText(value: totals.calories))
          .animation(.smooth, value: totals)
          .accessibilityIdentifier("logAgainTotal")
        }
        if items.isEmpty {
          Section { Text("This meal has no items with an amount.").foregroundStyle(.secondary) }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(Color.danger) }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Log again")
      .navigationSubtitle(entry.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
            .disabled(isSaving)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { hideKeyboard() }
            .labelStyle(.iconOnly)
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          Task { await log() }
        } label: {
          Group {
            if isSaving {
              ProgressView()
            } else {
              Text(
                targetDate == appModel.today
                  ? "Log to Today" : "Log to \(targetDate.label(today: appModel.today))")
            }
          }
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isValid)
        .padding()
        .accessibilityIdentifier("logAgainButton")
      }
    }
    .interactiveDismissDisabled(isSaving)
    .presentationDetents(
      dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
  }

  /// Same calendar as Today: closes when a day is picked. Future days are not allowed.
  private var calendar: some View {
    DatePicker(
      "Day",
      selection: Binding(
        get: { targetDate.date() },
        set: {
          date = DateKey($0)
          isCalendarPresented = false
        }),
      in: ...appModel.today.date(),
      displayedComponents: .date
    )
    .datePickerStyle(.graphical)
    .labelsHidden()
    .padding()
    .frame(minWidth: 320)
    .presentationCompactAdaptation(.popover)
  }

  private func itemRow(_ item: Binding<LogItem>) -> some View {
    let value = item.wrappedValue
    let macros = LogItemMath.macros(value)
    return VStack(alignment: .leading, spacing: 6) {
      Text(value.name).font(.body.weight(.medium))
      ViewThatFits(in: .horizontal) {
        HStack {
          itemMacros(macros)
          Spacer()
          gramsField(item)
        }
        VStack(alignment: .leading, spacing: 6) {
          itemMacros(macros)
          gramsField(item)
        }
      }
      if let error = NumericInput.portionError(value.gramsText, unit: value.unit) {
        Text(error).font(.footnote).foregroundStyle(Color.danger)
      }
    }
  }

  private func itemMacros(_ macros: MacroTotals) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      KcalText(value: macros.calories).font(.subheadline)
        .contentTransition(.numericText(value: macros.calories))
      MacroLine(macros: macros).font(.caption).foregroundStyle(.secondary)
    }
    .animation(.smooth, value: macros)
  }

  private func gramsField(_ item: Binding<LogItem>) -> some View {
    let value = item.wrappedValue
    return GramsField(
      text: item.gramsText,
      onStep: { delta in
        item.wrappedValue.gramsText = LogItemMath.step(value.gramsText, by: delta).text
      },
      onFocusLost: {},
      unit: value.unit.label,
      accessibilityName: String(localized: "Portion of \(value.name) in \(value.unit.spokenName)"))
  }

  private func hideKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }

  private func log() async {
    isSaving = true
    defer { isSaving = false }
    let target = targetDate
    let payload = LogAgain.payload(from: entry, items: items, date: target)
    do {
      let result = try await appModel.dayStore.log(payload)
      appModel.showToast(toastText(result, date: target))
      onLogged()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Names the day when the copy is not on the shown day.
  private func toastText(_ result: DayStore.LogResult, date: DateKey) -> String {
    let isShownDay = date == appModel.selectedDate
    let day = date.label(today: appModel.today)
    switch (result, isShownDay) {
    case (.saved, true): return String(localized: "Meal logged.")
    case (.saved, false): return String(localized: "Meal logged to \(day).")
    case (_, true): return String(localized: "Saved on this device. Totals update after syncing.")
    case (_, false):
      return String(localized: "Saved on this device for \(day). Totals update after syncing.")
    }
  }
}

#Preview {
  LogAgainSheet(entry: PreviewData.entries[0])
    .environment(AppModel(clients: .preview, inMemory: true))
}
