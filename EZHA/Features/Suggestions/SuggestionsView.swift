import EZHAKit
import SwiftUI

/// AI meal ideas that fit the remaining macros of the selected day.
struct SuggestionsView: View {
  @Environment(AppModel.self) private var appModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mealType = SuggestionRules.MealType.meal
  @State private var prepMinutes = SuggestionRules.defaultPrepMinutes
  @State private var notes = ""
  @State private var suggestions: [MealSuggestion] = []
  @State private var remainingAtRequest = MacroTotals.zero
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var refreshedAt = Date.now
  @State private var consentAction: (() -> Void)?

  private var date: DateKey { appModel.selectedDate }
  private var bundle: DayBundle? { appModel.dayStore.merged(date) }
  private var remaining: MacroTotals? {
    bundle.map { Macros.remaining(goals: $0.goals, totals: $0.totals) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          if let hint = bundle.flatMap({ SuggestionRules.targetsHint(goals: $0.goals) }) {
            Label(hint, systemImage: "info.circle")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          form
          actions
          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Color.danger)
              .font(.subheadline)
          }
          results
        }
        .padding()
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(Color.canvas)
      .navigationTitle("Suggestions")
      .navigationSubtitle(date.label(today: appModel.today))
      .task(id: date) {
        await appModel.dayStore.load(date)
        refreshedAt = .now
      }
      .onChange(of: date) {
        suggestions = []
        errorMessage = nil
      }
      .sheet(
        isPresented: Binding(get: { consentAction != nil }, set: { if !$0 { consentAction = nil } })
      ) {
        let action = consentAction
        AIConsentSheet { action?() }
      }
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Remaining").font(.headline)
        Spacer()
        TimelineView(.periodic(from: .now, by: 30)) { _ in
          Text("as of \(refreshedAt, format: .relative(presentation: .named))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button("Refresh", systemImage: "arrow.clockwise") {
          Task {
            await appModel.dayStore.load(date, force: true)
            refreshedAt = .now
          }
        }
        .labelStyle(.iconOnly)
        .frame(width: 44, height: 44)
      }
      let values = remaining ?? .zero
      HStack(spacing: 8) {
        StatTile(title: "kcal", value: values.calories, color: .brandPrimary)
        StatTile(title: "Protein", value: values.protein, unit: "g", color: .brandSecondary)
        StatTile(title: "Carbs", value: values.carbs, unit: "g", color: .brandAccent)
        StatTile(title: "Fat", value: values.fat, unit: "g", color: .brandPrimary)
      }
      .redacted(reason: remaining == nil ? .placeholder : [])
    }
  }

  // MARK: Form

  private var form: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Meal type", selection: $mealType) {
        ForEach(SuggestionRules.MealType.allCases) { type in
          Text(type == .meal ? "Meal" : "Snack").tag(type)
        }
      }
      .pickerStyle(.segmented)
      Stepper(value: $prepMinutes, in: 5...240, step: 5) {
        HStack {
          Text("Max prep")
          Spacer()
          TextField("Minutes", value: $prepMinutes, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 56)
            .monospacedDigit()
          Text("min").foregroundStyle(.secondary)
        }
      }
      .onChange(of: prepMinutes) { _, value in
        let clamped = SuggestionRules.clampPrep(value)
        if clamped != value { prepMinutes = clamped }
      }
      TextField(
        "Notes", text: $notes,
        prompt: Text("Restrictions or preferences, e.g. no peanuts, dairy-free"), axis: .vertical
      )
      .lineLimit(1...4)
    }
    .padding()
    .background(Color.surface, in: .rect(cornerRadius: 20, style: .continuous))
  }

  private var actions: some View {
    HStack(spacing: 12) {
      Button {
        request(variation: nil)
      } label: {
        Label("Get suggestions", systemImage: "sparkles")
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .disabled(isLoading || remaining == nil)
      .accessibilityIdentifier("getSuggestions")

      if !suggestions.isEmpty {
        Menu {
          Button("Other options", systemImage: "shuffle") {
            request(variation: SuggestionRules.differentOptions)
          }
          Button("Regenerate by ingredients", systemImage: "carrot") {
            request(variation: SuggestionRules.adjustIngredientsNote(notes))
          }
          .disabled(notes.trimmingCharacters(in: .whitespaces).isEmpty)
          Button("Regenerate by time", systemImage: "timer") {
            request(variation: SuggestionRules.adjustPrepNote(prepMinutes))
          }
        } label: {
          Label("More", systemImage: "ellipsis")
            .frame(minHeight: 36)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(isLoading)
      }
    }
  }

  // MARK: Results

  @ViewBuilder
  private var results: some View {
    if isLoading {
      ForEach(0..<3, id: \.self) { _ in
        SuggestionCard(suggestion: PreviewData.suggestions[0], remaining: .example, onLog: {})
          .redacted(reason: .placeholder)
          .shimmerBorder(true)
      }
      .accessibilityLabel("Loading suggestions")
    } else if suggestions.isEmpty {
      howItWorks
    } else {
      ForEach(suggestions) { suggestion in
        SuggestionCard(suggestion: suggestion, remaining: remainingAtRequest) {
          logThis(suggestion)
        }
        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        .scrollTransition { content, phase in
          content
            .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.95)
            .opacity(phase.isIdentity ? 1 : 0.6)
        }
      }
    }
  }

  private var howItWorks: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("How it works").font(.headline)
      Label("We use what is left of your day's calories and macros.", systemImage: "chart.pie")
      Label(
        "Pick a meal or snack, the time you have, and any preferences.",
        systemImage: "slider.horizontal.3")
      Label("Get 3 ideas, then log one to estimate it in the logger.", systemImage: "sparkles")
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.surface, in: .rect(cornerRadius: 20, style: .continuous))
  }

  private func request(variation: String?) {
    let action = {
      Task { await fetch(variation: variation) }
      return
    }
    if appModel.isAIConsentGiven { action() } else { consentAction = action }
  }

  private func fetch(variation: String?) async {
    guard let remaining else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let result = try await appModel.clients.ai.suggestions(
        SuggestionsRequest(
          remaining: remaining, mealType: mealType,
          maxPrepMinutes: SuggestionRules.clampPrep(prepMinutes), ingredientNotes: notes,
          variationNote: variation))
      remainingAtRequest = remaining
      withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4)) {
        suggestions = result
      }
    } catch {
      errorMessage = LoggerModel.message(for: error)
    }
  }

  private func logThis(_ suggestion: MealSuggestion) {
    appModel.loggerPrefill = SuggestionRules.loggerText(for: suggestion)
    appModel.selectedTab = .today
    appModel.isLoggerRequested = true
  }
}

/// A compact remaining value: "1,460 kcal".
private struct StatTile: View {
  var title: LocalizedStringKey
  var value: Double
  var unit: LocalizedStringKey?
  var color: Color

  var body: some View {
    VStack(spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text(value, format: .number.precision(.fractionLength(0)))
          .font(.title3.weight(.bold))
          .fontDesign(.rounded)
          .monospacedDigit()
          .foregroundStyle(value < 0 ? Color.danger : Color.primary)
          .contentTransition(.numericText(value: value))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
      }
      Text(title)
        .font(.caption)
        .foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, minHeight: 56)
    .background(Color.surface, in: .rect(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// Title, kcal, description, macros, warning, notes, and "Log this".
private struct SuggestionCard: View {
  var suggestion: MealSuggestion
  var remaining: MacroTotals
  var onLog: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(suggestion.title).font(.headline)
        Spacer()
        KcalText(value: suggestion.calories.rounded())
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Color.brandPrimary.opacity(0.15), in: .capsule)
      }
      Text(suggestion.description).font(.subheadline)
      MacroLine(macros: suggestion.macros.rounded)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if let warning = SuggestionRules.exceedWarning(suggestion.macros, remaining: remaining) {
        VStack(alignment: .leading, spacing: 2) {
          Text(warning).foregroundStyle(Color.danger)
          Text(SuggestionRules.hint).foregroundStyle(.secondary)
        }
        .font(.footnote)
      }
      if let notes = suggestion.notes, !notes.isEmpty {
        Text(notes).font(.footnote).foregroundStyle(.secondary)
      }
      Button("Log this", systemImage: "plus.circle", action: onLog)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Log \(suggestion.title)")
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.surface, in: .rect(cornerRadius: 20, style: .continuous))
  }
}

#Preview {
  SuggestionsView()
    .environment(AppModel(clients: .preview, inMemory: true))
}
