import SwiftUI

/// A short message with an optional action, shown at the bottom for 4 s.
struct ToastMessage: Identifiable, Equatable {
  let id = UUID()
  var text: String
  var actionTitle: String?
  var action: (@MainActor () -> Void)?

  static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

/// A glass capsule overlay. Auto-dismisses and is announced to VoiceOver.
struct ToastOverlay: View {
  @Binding var toast: ToastMessage?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack {
      Spacer()
      if let toast {
        HStack(spacing: 12) {
          Text(toast.text)
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
          if let title = toast.actionTitle, let action = toast.action {
            Button(title) {
              action()
              self.toast = nil
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .task(id: toast.id) {
          AccessibilityNotification.Announcement(toast.text).post()
          try? await Task.sleep(for: .seconds(4))
          if self.toast?.id == toast.id { self.toast = nil }
        }
      }
    }
    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4), value: toast)
  }
}
