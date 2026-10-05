import EZHAKit
import SwiftUI

/// `Canvas` with a slow `MeshGradient` of the brand colors. Static with Reduce Motion.
/// `intensity` is the gradient opacity: full screen on Auth, low on Today.
struct BrandBackground: View {
  var intensity: Double = 1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color.canvas
      if reduceMotion {
        mesh(phase: 0)
      } else {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
          mesh(phase: context.date.timeIntervalSinceReferenceDate / 6)
        }
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  private func mesh(phase: Double) -> some View {
    let x = Float(0.5 + 0.12 * sin(phase))
    let y = Float(0.5 + 0.1 * cos(phase * 0.8))
    return MeshGradient(
      width: 3, height: 3,
      points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [x, y], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
      ],
      colors: [
        .brandSecondary, .brandPrimary, .brandAccent,
        .brandPrimary, .brandSecondary, .brandPrimary,
        .canvas, .canvas, .canvas,
      ]
    )
    .opacity(intensity)
  }
}

#Preview {
  BrandBackground()
}
