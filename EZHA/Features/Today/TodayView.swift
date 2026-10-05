import EZHAKit
import SwiftUI

/// The selected day: target, remaining macros, and logged meals.
struct TodayView: View {
  var openLogger: (DateKey?) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var direction = Edge.trailing
  @State private var isCalendarPresented = false
  @State private var bounce = 0

  var body: some View {
    @Bindable var appModel = appModel
    let date = appModel.selectedDate
    NavigationStack {
      ZStack {
        DayContent(date: date, changeDay: changeDay, openLogger: openLogger)
          .id(date)
          .transition(reduceMotion ? .opacity : .push(from: direction))
      }
      .background(alignment: .top) {
        BrandBackground(intensity: 0.18)
          .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
      }
      .background(Color.canvas)
      .navigationTitle(date.titleLabel(today: appModel.today))
      .toolbar {
        if date != appModel.today {
          ToolbarItem(placement: .topBarLeading) {
            Button("Today") { goTo(appModel.today) }
              .buttonStyle(.glass)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Choose day", systemImage: "calendar") { isCalendarPresented = true }
            .popover(isPresented: $isCalendarPresented) { calendar }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Log meal", systemImage: "plus") { openLogger(date) }
        }
      }
      .task(id: date) { await appModel.dayStore.load(date) }
      .sensoryFeedback(.selection, trigger: date)
      .sensoryFeedback(.impact(weight: .light), trigger: bounce)
    }
  }

  private var calendar: some View {
    @Bindable var appModel = appModel
    return VStack(spacing: 8) {
      DatePicker(
        "Day",
        selection: Binding(
          get: { appModel.selectedDate.date() },
          set: {
            goTo(DateKey($0))
            isCalendarPresented = false
          }),
        in: ...appModel.today.date(),
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .labelsHidden()
      Button("Today") {
        goTo(appModel.today)
        isCalendarPresented = false
      }
      .buttonStyle(.glass)
    }
    .padding()
    .frame(minWidth: 320)
    .presentationCompactAdaptation(.popover)
  }

  private func changeDay(_ delta: Int) {
    let current = appModel.selectedDate
    if delta > 0 {
      guard current < appModel.today else {
        bounce += 1
        return
      }
      goTo(current.next(today: appModel.today))
    } else {
      goTo(current.previous())
    }
  }

  private func goTo(_ date: DateKey) {
    let target = min(date, appModel.today)
    guard target != appModel.selectedDate else { return }
    direction = target < appModel.selectedDate ? .leading : .trailing
    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) {
      appModel.selectedDate = target
    }
  }
}

/// The list for one day.
private struct DayContent: View {
  var date: DateKey
  var changeDay: (Int) -> Void
  var openLogger: (DateKey?) -> Void

  @Environment(AppModel.self) private var appModel
  @State private var isTargetSheetPresented = false
  @State private var detail: DayEntry?

  private var store: DayStore { appModel.dayStore }

  var body: some View {
    let bundle = store.merged(date)
    let state = store.state(for: date)
    let isToday = date == appModel.today
    List {
      if case .failed(let message) = state {
        Section {
          ErrorBanner(message: message) { Task { await store.load(date, force: true) } }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }

      if let bundle {
        Section {
          TargetRow(bundle: bundle, isToday: isToday) { isTargetSheetPresented = true }
        }
        .listRowBackground(Color.surface)
        Section {
          SummaryCard(goals: bundle.goals, totals: bundle.totals, isToday: isToday)
        }
        .listRowBackground(Color.surface)
        .gesture(swipe)
        entriesSection(bundle)
      } else if state == .loading || state == .idle {
        placeholder
      } else {
        Section {
          ContentUnavailableView(
            "Nothing to show", systemImage: "wifi.slash",
            description: Text("Connect to the internet to load this day."))
        }
        .listRowBackground(Color.clear)
      }
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      await appModel.sync.run()
      await store.load(date, force: true)
    }
    .sheet(isPresented: $isTargetSheetPresented) {
      if let bundle { TargetSheet(date: date, bundle: bundle) }
    }
    .sheet(item: $detail) { entry in
      EntryDetailSheet(entry: entry)
    }
  }

  private var swipe: some Gesture {
    DragGesture(minimumDistance: 30)
      .onEnded { value in
        guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
          abs(value.translation.width) > 60
        else { return }
        changeDay(value.translation.width > 0 ? -1 : 1)
      }
  }

  @ViewBuilder
  private func entriesSection(_ bundle: DayBundle) -> some View {
    let pending = bundle.entries.filter(\.isPending).count
    Section {
      if bundle.entries.isEmpty {
        ContentUnavailableView(
          "Nothing logged yet", systemImage: "fork.knife",
          description: Text("Tap Log meal to add your first meal.")
        )
        .listRowBackground(Color.clear)
        .gesture(swipe)
      } else {
        ForEach(bundle.entries) { entry in
          Button {
            detail = entry
          } label: {
            EntryRow(entry: entry)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              EntryActions.delete(entry, appModel: appModel)
            }
          }
          .contextMenu {
            Button("Log again", systemImage: "arrow.counterclockwise") {
              EntryActions.logAgain(entry, appModel: appModel)
            }
            Button("Save as meal", systemImage: "books.vertical") {
              EntryActions.saveAsMeal(entry, appModel: appModel)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
              EntryActions.delete(entry, appModel: appModel)
            }
          }
          .listRowBackground(Color.surface)
        }
      }
    } header: {
      HStack {
        Text("Logged meals")
        Spacer()
        Text("\(bundle.entries.count)")
          .monospacedDigit()
      }
    } footer: {
      if pending > 0 {
        Text(
          pending == 1
            ? "Includes 1 meal waiting to sync" : "Includes \(pending) meals waiting to sync")
      }
    }
  }

  private var placeholder: some View {
    Group {
      Section {
        SummaryCard(goals: PreviewData.day.goals, totals: PreviewData.day.totals, isToday: true)
      }
      Section {
        ForEach(PreviewData.entries) { EntryRow(entry: $0) }
      }
    }
    .redacted(reason: .placeholder)
    .listRowBackground(Color.surface)
    .accessibilityLabel("Loading")
  }
}

/// "TODAY'S TARGET · Basic · 2,100 kcal"
private struct TargetRow: View {
  var bundle: DayBundle
  var isToday: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: "target")
          .foregroundStyle(Color.brandPrimary)
          .font(.title3)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(isToday ? "TODAY'S TARGET" : "DAY TARGET")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(
            "\(bundle.target?.name ?? String(localized: "Target")) · \(bundle.goals.calories, format: .number.precision(.fractionLength(0))) kcal"
          )
          .font(.body.weight(.medium))
          .fontDesign(.rounded)
          .monospacedDigit()
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Changes the target for this day")
  }
}

/// The ring and three bars. Side by side when there is room, stacked otherwise.
struct SummaryCard: View {
  var goals: MacroTotals
  var totals: MacroTotals
  var isToday: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(isToday ? "Remaining today" : "Remaining for this day")
        .font(.headline)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 24) {
          MacroRing(goal: goals.calories, eaten: totals.calories)
          bars.frame(minWidth: 200)
        }
        VStack(spacing: 20) {
          MacroRing(goal: goals.calories, eaten: totals.calories)
          bars
        }
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 8)
  }

  private var bars: some View {
    VStack(spacing: 14) {
      MacroBar(title: "Protein", goal: goals.protein, eaten: totals.protein, color: .brandSecondary)
      MacroBar(title: "Carbs", goal: goals.carbs, eaten: totals.carbs, color: .brandAccent)
      MacroBar(title: "Fat", goal: goals.fat, eaten: totals.fat, color: .brandPrimary)
    }
  }
}

/// A logged meal: kcal, macro line, title, time. Pending rows show "Waiting to sync".
struct EntryRow: View {
  var entry: DayEntry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        KcalText(value: entry.entry.calories)
          .font(.headline)
        MacroLine(macros: entry.entry.macros)
          .font(.subheadline)
        Text(entry.title)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        if entry.isPending {
          Label("Waiting to sync", systemImage: "clock.arrow.circlepath")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.brandPrimary)
        }
      }
      Spacer()
      if let time = entry.entry.createdAt {
        Text(time, format: .dateTime.hour().minute())
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .padding(.vertical, 4)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}

/// An inline error with "Try again". Cached content stays visible below it.
struct ErrorBanner: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color.danger)
        .accessibilityHidden(true)
      Text(message)
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Try again", action: retry)
        .buttonStyle(.bordered)
    }
    .padding()
    .background(Color.danger.opacity(0.1), in: .rect(cornerRadius: 16))
  }
}

extension DayEntry {
  var title: String {
    entry.inputText?.trimmingCharacters(in: .whitespaces).nonEmpty ?? String(localized: "Meal")
  }

  /// library → "Library", text → "AI: text", photos → "AI: photo" / "AI: label".
  var sourceLabel: String {
    switch entry.aiSource {
    case .library: String(localized: "Library")
    case .text: String(localized: "AI: text")
    case .foodPhoto: String(localized: "AI: photo")
    case .labelPhoto: String(localized: "AI: label")
    case .unknown:
      entry.imagePath == nil ? String(localized: "AI: text") : String(localized: "AI: photo")
    }
  }
}

extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}

#Preview {
  TodayView(openLogger: { _ in })
    .environment(AppModel(clients: .preview, inMemory: true))
}
