import EZHAKit
import SwiftUI

/// One logged meal: items, photo, and actions.
struct EntryDetailSheet: View {
  var entry: DayEntry
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var imageURL: URL?

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 6) {
            KcalText(value: entry.entry.calories).font(.title2.bold())
            MacroLine(macros: entry.entry.macros).font(.subheadline)
            Text(subtitle)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          if entry.entry.imagePath != nil {
            AsyncImage(url: imageURL) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Rectangle().fill(Color.track).overlay { ProgressView() }
            }
            .frame(height: 180)
            .clipShape(.rect(cornerRadius: 16))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .accessibilityLabel("Meal photo")
          }
        }
        Section("Items") {
          ForEach(entry.items) { item in
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                MacroLine(macros: item.macros)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 2) {
                KcalText(value: item.calories).font(.subheadline.weight(.semibold))
                Text("\(item.grams, format: .number.precision(.fractionLength(0...1))) g")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
              }
            }
            .accessibilityElement(children: .combine)
          }
        }
        Section {
          Button("Log again", systemImage: "arrow.counterclockwise") {
            EntryActions.logAgain(entry, appModel: appModel)
            dismiss()
          }
          Button("Save as meal", systemImage: "books.vertical") {
            EntryActions.saveAsMeal(entry, appModel: appModel)
            dismiss()
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            EntryActions.delete(entry, appModel: appModel)
            dismiss()
          }
          .disabled(false)
        }
      }
      .navigationTitle(entry.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }
      .task {
        guard let path = entry.entry.imagePath else { return }
        imageURL = try? await appModel.clients.day.imageURL(path)
      }
    }
    .presentationDetents([.medium, .large])
  }

  /// "8:30 AM · AI: photo · AI 80%"
  private var subtitle: String {
    var parts: [String] = []
    if let time = entry.entry.createdAt { parts.append(time.formatted(.dateTime.hour().minute())) }
    parts.append(entry.sourceLabel)
    if let confidence = entry.entry.aiConfidence, entry.entry.aiSource != .library {
      parts.append(String(localized: "AI \(Int((confidence * 100).rounded()))%"))
    }
    if entry.isPending { parts.append(String(localized: "Waiting to sync")) }
    return parts.joined(separator: " · ")
  }
}

#Preview {
  EntryDetailSheet(entry: PreviewData.entries[0])
    .environment(AppModel(clients: .preview, inMemory: true))
}
