import EZHAKit
import SwiftUI
import UIKit

/// Eat out: menu pages, the request, and the dishes that came back.
/// Pages stay when the date changes, because they belong to the restaurant, not the day.
@MainActor @Observable
final class MenuSuggestionsModel {
  struct Page: Identifiable {
    let id = UUID()
    let jpeg: Data
    let thumbnail: UIImage?
  }

  var pages: [Page] = []
  var suggestions: [MealSuggestion] = []
  var isLoading = false
  var isAddingPage = false
  var hasRequested = false
  var errorMessage: String?
  @ObservationIgnored private var requestId = UUID()

  var canAddPages: Bool { pages.count < SuggestionRules.maxMenuPhotos }
  var pagesLeft: Int { SuggestionRules.maxMenuPhotos - pages.count }

  init(pages: [Page] = [], suggestions: [MealSuggestion] = []) {
    self.pages = pages
    self.suggestions = suggestions
    hasRequested = !suggestions.isEmpty
  }

  /// Menus are text, so pages keep the larger label size.
  func add(_ raw: Data) async {
    guard canAddPages else { return }
    isAddingPage = true
    defer { isAddingPage = false }
    do {
      let jpeg = try await ImageProcessing.jpeg(from: raw, forLabel: true)
      guard canAddPages else { return }
      let thumbnail = UIImage(data: jpeg)?.preparingThumbnail(of: CGSize(width: 160, height: 200))
      pages.append(Page(jpeg: jpeg, thumbnail: thumbnail))
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func remove(_ id: Page.ID) {
    pages.removeAll { $0.id == id }
  }

  /// Results are for one day's remaining macros. Pages stay.
  func resetResults() {
    requestId = UUID()
    suggestions = []
    hasRequested = false
    errorMessage = nil
    isLoading = false
  }

  func fetch(
    client: AIClient, remaining: MacroTotals, mealType: SuggestionRules.MealType,
    preferences: String, variation: String?, animation: Animation
  ) async {
    guard !pages.isEmpty else { return }
    let id = UUID()
    requestId = id
    isLoading = true
    hasRequested = true
    errorMessage = nil
    do {
      let result = try await client.menuSuggestions(
        MenuSuggestionsRequest(
          remaining: remaining, mealType: mealType, preferences: preferences,
          variationNote: variation, photos: pages.map(\.jpeg)))
      guard requestId == id else { return }
      withAnimation(animation) { suggestions = result }
    } catch {
      guard requestId == id else { return }
      errorMessage = LoggerModel.message(for: error)
    }
    isLoading = false
  }
}

/// Where a menu page comes from. The scanner straightens and sharpens printed pages.
enum MenuPageSource: CaseIterable, Identifiable {
  case scan, camera, photos
  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .scan: "Scan menu"
    case .camera: "Take photo"
    case .photos: "Choose from Photos"
    }
  }

  var systemImage: String {
    switch self {
    case .scan: "doc.viewfinder"
    case .camera: "camera"
    case .photos: "photo.on.rectangle"
    }
  }

  /// Photos is always available; the Simulator has no camera or scanner.
  static var available: [MenuPageSource] {
    allCases.filter {
      switch $0 {
      case .scan: DocumentScanner.isAvailable
      case .camera: CameraPicker.isAvailable
      case .photos: true
      }
    }
  }
}

/// Thumbnails of the menu pages, with an add button while fewer than four.
struct MenuPagesRow: View {
  var model: MenuSuggestionsModel
  var sources = MenuPageSource.available
  var pick: (MenuPageSource) -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// At accessibility sizes the add control is a full-width button under the thumbnails.
  private var isWide: Bool { dynamicTypeSize.isAccessibilitySize }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Menu photos").font(.subheadline.weight(.medium))
      if !model.pages.isEmpty || !isWide {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
              thumbnail(page, number: index + 1)
            }
            if model.canAddPages && !isWide {
              addButton
            }
          }
          .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
      }
      if model.canAddPages && isWide {
        addButton
      }
      Text(
        "Add up to \(SuggestionRules.maxMenuPhotos) pages. We'll pick dishes that fit what's left today."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var addButton: some View {
    Group {
      if sources.count > 1 {
        Menu {
          ForEach(sources) { source in
            Button(source.title, systemImage: source.systemImage) { pick(source) }
          }
        } label: {
          addTile
        }
      } else {
        Button {
          pick(sources.first ?? .photos)
        } label: {
          addTile
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(model.isAddingPage)
    .accessibilityLabel(model.pages.isEmpty ? "Add menu photo" : "Add menu page")
    .accessibilityIdentifier("addMenuPage")
  }

  private var addTile: some View {
    let layout =
      isWide
      ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 6))
    return layout {
      if model.isAddingPage {
        ProgressView()
      } else {
        Image(systemName: model.pages.isEmpty ? "menucard" : "plus")
          .font(.title2)
          .foregroundStyle(Color.brandPrimary)
      }
      Text(model.pages.isEmpty ? "Add menu" : "Add page")
        .font(.footnote.weight(.medium))
        .multilineTextAlignment(isWide ? .leading : .center)
    }
    .frame(width: isWide ? nil : 88, height: isWide ? nil : 110)
    .frame(maxWidth: isWide ? .infinity : nil, minHeight: 44, alignment: .leading)
    .padding(isWide ? 12 : 0)
    .foregroundStyle(.primary)
    .background(Color.surface, in: .rect(cornerRadius: 12, style: .continuous))
    .contentShape(.rect(cornerRadius: 12))
  }

  private func thumbnail(_ page: MenuSuggestionsModel.Page, number: Int) -> some View {
    ZStack(alignment: .topTrailing) {
      Group {
        if let image = page.thumbnail {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
        }
      }
      .frame(width: 88, height: 110)
      .background(Color.surface)
      .clipShape(.rect(cornerRadius: 12, style: .continuous))
      .accessibilityLabel("Menu page \(number)")

      Button {
        withAnimation(.smooth) { model.remove(page.id) }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .black.opacity(0.6))
          .font(.title3)
          .frame(width: 44, height: 44)
          .contentShape(.rect)
      }
      .offset(x: 8, y: -8)
      .accessibilityLabel("Remove menu page \(number)")
      .accessibilityIdentifier("removeMenuPage")
    }
    .padding(.top, 6)
    .padding(.trailing, 6)
  }
}

/// One dish: section, name, kcal and macros, what it does to the day, a tip, and +.
struct MenuDishRow: View {
  var suggestion: MealSuggestion
  var impact: String?
  var onAdd: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    // At accessibility sizes + goes under the text, so the text keeps the full width.
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    layout {
      VStack(alignment: .leading, spacing: 4) {
        if let section = suggestion.menuSection, !section.isEmpty {
          Text(section)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        Text(suggestion.title).font(.headline)
        FlowLayout(spacing: 6) {
          kcal
          macros
        }
        .font(.subheadline)
        if let impact {
          Text(impact)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("menuDishImpact")
        }
        if let tip = suggestion.orderTip, !tip.isEmpty {
          Label(tip, systemImage: "lightbulb")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

      Button(action: onAdd) {
        Image(systemName: "plus.circle.fill")
          .font(.title)
          .foregroundStyle(Color.brandPrimary)
          .frame(width: 44, height: 44)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Log \(suggestion.title)")
      .accessibilityIdentifier("logMenuDish")
    }
    .padding(.vertical, 10)
  }

  private var kcal: some View {
    KcalText(value: suggestion.calories.rounded()).fontWeight(.semibold)
  }

  private var macros: some View {
    MacroLine(macros: suggestion.macros.rounded).foregroundStyle(.secondary)
  }
}

#Preview {
  ScrollView {
    VStack(alignment: .leading) {
      MenuPagesRow(model: MenuSuggestionsModel(), pick: { _ in })
      ForEach(PreviewData.menuSuggestions) { dish in
        MenuDishRow(suggestion: dish, impact: "Leaves 170 kcal · Protein goal reached") {}
        Divider()
      }
    }
    .padding()
  }
}
