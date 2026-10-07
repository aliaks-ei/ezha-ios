import SwiftUI

/// An icon over a one-line title: Camera, Photos, Scan label.
/// Tinted bordered style: these buttons sit in content, and glass is for navigation (guide 7.1).
struct AttachmentButton: View {
  var title: LocalizedStringKey
  var systemImage: String
  /// Fills the row width when the buttons share one row.
  var fills = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: systemImage).font(.title3)
        Text(title).font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
      }
      .frame(maxWidth: fills ? .infinity : nil, minHeight: 48)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.roundedRectangle(radius: 14))
  }
}
