import EZHAKit
import SwiftUI

/// The selected day: target, remaining macros, and logged meals.
struct TodayView: View {
  var openLogger: (DateKey?) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCalendarPresented = false

  var body: some View {
    let date = appModel.selectedDate
    NavigationStack {
      // New identity per day, so the sheets and scroll position of one day do not carry over.
      DayContent(date: date, openLogger: openLogger)
        .id(date)
        .background {
          // One full-screen layer, so the bar area and the content share the same gradient.
          BrandBackground(intensity: 0.18)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            .background(Color.canvas)
            .ignoresSafeArea()
        }
        // The bar shows `dayTitle` instead; the title still names the screen for accessibility.
        .navigationTitle(date.titleLabel(today: appModel.today))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) { dayTitle(date) }
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

  /// "‹  Sat, Oct 4  ›". Buttons, not a swipe, so row swipe actions do not change the day.
  private func dayTitle(_ date: DateKey) -> some View {
    HStack(spacing: 4) {
      dayButton("Previous day", systemImage: "chevron.left", id: "previousDay") {
        goTo(date.adding(days: -1))
      }
      Text(date.titleLabel(today: appModel.today))
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("dayTitle")
      dayButton("Next day", systemImage: "chevron.right", id: "nextDay") {
        goTo(date.adding(days: 1))
      }
      .disabled(date >= appModel.today)
    }
    .fontWeight(.semibold)
    // The bar has a fixed height: larger sizes would clip.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private func dayButton(
    _ title: LocalizedStringKey, systemImage: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
    .buttonStyle(.borderless)
    .accessibilityIdentifier(id)
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
          SummaryCard(
            goals: bundle.goals, totals: bundle.totals, fiber: FiberSummary.day(bundle.entries)
          ) {
            TargetButton(bundle: bundle, isToday: isToday) { isTargetSheetPresented = true }
          }
        }
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
    // One spacing scale (8 / 16 / 24): 8 under the bar, 24 between blocks. The first section
    // and the "Logged meals" header already add their own top padding, so these values are
    // smaller than the gaps they make.
    .contentMargins(.top, 0, for: .scrollContent)
    .listSectionSpacing(10)
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
        }
      }
    } header: {
      EntriesHeader(eaten: bundle.entries.isEmpty ? nil : bundle.totals.calories)
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
/// With `fiber`, a fiber line closes the card.
struct SummaryCard<Header: View>: View {
  var goals: MacroTotals
  var totals: MacroTotals
  var fiber: FiberSummary?
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
      if let fiber {
        FiberLine(summary: fiber).padding(.top, 8)
      }
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

/// "Fiber        18 g eaten". No bar and no "left": fiber has no goal (PET-115).
/// Some foods without fiber data: "≥ 14 g eaten" and a note. No data at all: "Not known", never 0.
struct FiberLine: View {
  var summary: FiberSummary

  private var grams: String? {
    summary.grams.map { $0.formatted(.number.precision(.fractionLength(0))) }
  }

  private var note: String? {
    guard summary.grams != nil else { return String(localized: "These meals have no fiber data") }
    switch summary.unknownMeals {
    case 0: return nil
    case 1: return String(localized: "1 meal has no fiber data")
    default: return String(localized: "\(summary.unknownMeals) meals have no fiber data")
    }
  }

  private var title: some View {
    Text("Fiber").font(.subheadline.weight(.semibold))
  }

  @ViewBuilder private var value: some View {
    if let grams {
      let number = Text(summary.isComplete ? "\(grams) g" : "≥ \(grams) g")
        .fontWeight(.semibold)
        .foregroundStyle(Color.primary)
      Text("\(number) \(Text("eaten").foregroundStyle(.secondary))")
        .font(.subheadline)
        .fontDesign(.rounded)
        .monospacedDigit()
    } else {
      Text("Not known")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var accessibilityValue: String {
    guard let grams else { return String(localized: "Not known. \(note ?? "")") }
    let amount =
      summary.isComplete
      ? String(localized: "\(grams) grams eaten")
      : String(localized: "At least \(grams) grams eaten")
    return [amount, note].compactMap { $0 }.joined(separator: ". ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      // Side by side when it fits; stacked at large text sizes.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          title.fixedSize()
          Spacer()
          value.fixedSize()
        }
        VStack(alignment: .leading, spacing: 2) {
          title
          value
        }
      }
      if let note {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 12)
    .overlay(alignment: .top) { Divider() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Fiber")
    .accessibilityValue(accessibilityValue)
    .accessibilityIdentifier("fiberLine")
  }
}

/// "Logged meals          640 kcal eaten". The total shows only when there are meals.
private struct EntriesHeader: View {
  var eaten: Double?
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if typeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 2) {
        title
        total
      }
      .textCase(nil)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        title
        Spacer(minLength: 0)
        total
      }
      .textCase(nil)
    }
  }

  private var title: some View {
    Text("Logged meals")
      .font(.title3.weight(.semibold))
      // Color.primary: header text is secondary by default, and `.primary` follows that.
      .foregroundStyle(Color.primary)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var total: some View {
    if let eaten {
      let value = Text(eaten, format: .number.precision(.fractionLength(0)))
        .fontWeight(.semibold)
        .fontDesign(.rounded)
        .foregroundStyle(Color.primary)
      Text("\(value) kcal eaten")
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }
}

/// A logged meal: title and kcal, then macros and time. Pending rows show "Waiting to sync".
/// At accessibility sizes each pair stacks, so nothing truncates.
struct EntryRow: View {
  var entry: DayEntry
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let stacked = typeSize.isAccessibilitySize
    let line =
      stacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    VStack(alignment: .leading, spacing: 4) {
      line {
        Text(entry.title)
          .font(.body.weight(.semibold))
          .lineLimit(stacked ? nil : 2)
          .frame(maxWidth: .infinity, alignment: .leading)
        kcal
          .fixedSize()
      }
      line {
        MacroDots(macros: entry.entry.macros)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let time = entry.entry.createdAt {
          Text(time, format: .dateTime.hour().minute())
            .fontDesign(.rounded)
            .monospacedDigit()
            .fixedSize()
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      if entry.isPending {
        // Not a Label: in a List row the icon gets its own column and moves the separator.
        HStack(spacing: 4) {
          Image(systemName: "clock.arrow.circlepath")
            .accessibilityHidden(true)
          Text("Waiting to sync")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.brandPrimary)
      }
    }
    .padding(.vertical, 2)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }

  /// "520 kcal": the number leads, the unit is smaller and secondary.
  private var kcal: some View {
    let value = Text(entry.entry.calories, format: .number.precision(.fractionLength(0)))
      .font(.body.weight(.semibold))
    let unit = Text("kcal")
      .font(.footnote.weight(.medium))
      .foregroundStyle(.secondary)
    return Text("\(value) \(unit)")
      .fontDesign(.rounded)
      .monospacedDigit()
  }
}

/// "● P 35 g  ● C 56 g  ● F 14 g". Dot colors match the summary card bars.
private struct MacroDots: View {
  var macros: MacroTotals
  @ScaledMetric(relativeTo: .subheadline) private var dot: CGFloat = 7
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
      : AnyLayout(HStackLayout(spacing: 10))
    layout { parts }
      .fontDesign(.rounded)
      .monospacedDigit()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        Text(
          "Protein \(macros.protein, format: .number.precision(.fractionLength(0))) grams, carbs \(macros.carbs, format: .number.precision(.fractionLength(0))) grams, fat \(macros.fat, format: .number.precision(.fractionLength(0))) grams"
        ))
  }

  @ViewBuilder private var parts: some View {
    part("P \(macros.protein, format: .number.precision(.fractionLength(0))) g", .brandSecondary)
    part("C \(macros.carbs, format: .number.precision(.fractionLength(0))) g", .brandAccent)
    part("F \(macros.fat, format: .number.precision(.fractionLength(0))) g", .brandPrimary)
  }

  private func part(_ label: LocalizedStringKey, _ color: Color) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: dot, height: dot)
      Text(label)
        .fixedSize()
    }
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
