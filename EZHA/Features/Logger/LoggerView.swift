import EZHAKit
import SwiftUI

/// Placeholder until Phase 7.
struct LoggerView: View {
  var date: DateKey
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Text("Logger")
        .navigationTitle("Log meal")
        .toolbar { Button("Close", systemImage: "xmark") { dismiss() } }
    }
  }
}
