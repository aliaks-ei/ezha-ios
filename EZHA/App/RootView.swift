import EZHAKit
import SwiftUI

struct RootView: View {
  var body: some View {
    ZStack {
      Color.canvas.ignoresSafeArea()
      VStack(spacing: 12) {
        Image(systemName: "fork.knife")
          .font(.largeTitle)
          .foregroundStyle(Color.brandPrimary)
        Text("EZHA")
          .font(.largeTitle.bold())
          .fontDesign(.rounded)
          .foregroundStyle(Color.ink)
        Text(SupabaseConfig.load().url.host() ?? "")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview {
  RootView()
}
