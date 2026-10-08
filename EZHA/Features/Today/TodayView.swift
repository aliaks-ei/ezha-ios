import EZHAKit
import SwiftUI

/// The selected day: target, remaining macros, and logged meals.
struct TodayView: View {
  var openLogger: (DateKey?) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCalendarPresented = false

  /// Pages from a year back (or the selected day, if older) to today.
  private var days: [DateKey] {
    let today = appModel.today
    let first = min(appModel.selectedDate, today.adding(days: -365))
    return Array(sequence(first: first) { $0 < today ? $0.adding(days: 1) : nil })
  }

  var body: some View {
    @Bindable var appModel = appModel
    let date = appModel.selectedDate
    NavigationStack {
      // Paging view: swipe right for the previous day, left for the next one.
      TabView(selection: $appModel.selectedDate) {
        ForEach(days) { day in
          DayContent(date: day, openLogger: openLogger).tag(day)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background {
        // One full-screen layer, so the bar area and the content share the same gradient.
        BrandBackground(intensity: 0.18)
          .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
          .background(Color.canvas)
          .ignoresSafeArea()
      }
      .navigationTitle(date.titleLabel(today: appModel.today))
      // Large title in the same row as the buttons: saves the separate title row.
      .toolbarTitleDisplayMode(.inlineLarge)
      .toolbar {
        if date != appModel.today {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Today") { goTo(appModel.today) }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Choose day", systemImage: "calendar") { isCalendarPresented = true }
            .popover(isPresented: $isCalendarPresented) { calendar }
        }
      }
      .sensoryFeedback(.selection, trigger: date)
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

  private func goTo(_ date: DateKey) {
    let target = min(date, appModel.today)
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
      appModel.selectedDate = target
    }
  }
}

/// The list for one day.
private struct DayContent: View {
  var date: DateKey
  var openLogger: (DateKey?) -> Void

  @Environment(AppModel.self) private var appModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
          SummaryCard(goals: bundle.goals, totals: bundle.totals) {
            TargetButton(bundle: bundle, isToday: isToday) { isTargetSheetPresented = true }
          }
        }
        .listRowBackground(Color.surface)
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
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15),
      value: bundle?.entries.map(\.id)
    )
    .refreshable {
      await appModel.sync.run()
      await store.load(date, force: true)
    }
    .task { await store.load(date) }
    .sheet(isPresented: $isTargetSheetPresented) {
      if let bundle { TargetSheet(date: date, bundle: bundle) }
    }
    .sheet(item: $detail) { entry in
      EntryDetailSheet(entry: entry)
    }
  }

  @ViewBuilder
  private func entriesSection(_ bundle: DayBundle) -> some View {
    let pending = bundle.entries.filter(\.isPending).count
    Section {
      if bundle.entries.isEmpty {
        ContentUnavailableView {
          Label("Nothing logged yet", systemImage: "fork.knife")
        } description: {
          Text("Log your first meal of the day.")
        } actions: {
          Button("Log meal") { openLogger(date) }
            .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Color.clear)
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
        if !bundle.entries.isEmpty {
          Text(
            "\(bundle.totals.calories, format: .number.precision(.fractionLength(0))) kcal eaten"
          )
          .monospacedDigit()
        }
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
        SummaryCard(goals: PreviewData.day.goals, totals: PreviewData.day.totals) {
          Text(verbatim: "Basic · 2 100 kcal")
        }
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

/// "◎ Basic · 2,100 kcal ›". Opens the target sheet.
private struct TargetButton: View {
  var bundle: DayBundle
  var isToday: Bool
  var action: () -> Void

  var body: some View {
    let name = bundle.target?.name ?? String(localized: "Target")
    let kcal = bundle.goals.calories.formatted(.number.precision(.fractionLength(0)))
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "target")
          .foregroundStyle(Color.brandPrimary)
          .accessibilityHidden(true)
        Text("\(name) · \(kcal) kcal")
          .fontWeight(.semibold)
          .fontDesign(.rounded)
          .monospacedDigit()
          .foregroundStyle(Color.primary)
          .lineLimit(3)
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color(.tertiaryLabel))
          .accessibilityHidden(true)
        Spacer(minLength: 0)
      }
      .font(.subheadline)
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    // Borderless: only this line opens the sheet, not the whole card row.
    .buttonStyle(.borderless)
    .accessibilityLabel(
      isToday ? "Today's target: \(name), \(kcal) kcal" : "Day target: \(name), \(kcal) kcal"
    )
    .accessibilityHint("Changes the target for this day")
  }
}

/// Header, then the ring and three bars. Side by side when there is room, stacked otherwise.
struct SummaryCard<Header: View>: View {
  var goals: MacroTotals
  var totals: MacroTotals
  @ViewBuilder var header: Header

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 20) {
          MacroRing(goal: goals.calories, eaten: totals.calories, diameter: 124)
          bars.frame(minWidth: 170)
        }
        VStack(spacing: 20) {
          MacroRing(goal: goals.calories, eaten: totals.calories)
          bars
        }
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.bottom, 8)
  }

  private var bars: some View {
    VStack(spacing: 12) {
      MacroBar(title: "Protein", goal: goals.protein, eaten: totals.protein, color: .brandSecondary)
      MacroBar(title: "Carbs", goal: goals.carbs, eaten: totals.carbs, color: .brandAccent)
      MacroBar(title: "Fat", goal: goals.fat, eaten: totals.fat, color: .brandPrimary)
    }
  }
}

/// A logged meal: title and kcal, then macros and time. Pending rows show "Waiting to sync".
struct EntryRow: View {
  var entry: DayEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(entry.title)
          .font(.body.weight(.semibold))
          .lineLimit(2)
        Spacer(minLength: 0)
        KcalText(value: entry.entry.calories)
          .font(.subheadline.weight(.semibold))
          .fixedSize()
      }
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        MacroLine(macros: entry.entry.macros)
        Spacer(minLength: 0)
        if let time = entry.entry.createdAt {
          Text(time, format: .dateTime.hour().minute())
            .monospacedDigit()
            .fixedSize()
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      if entry.isPending {
        Label("Waiting to sync", systemImage: "clock.arrow.circlepath")
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.brandPrimary)
      }
    }
    .padding(.vertical, 2)
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
