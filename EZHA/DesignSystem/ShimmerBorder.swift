import EZHAKit
import SwiftUI

/// A slow moving brand `MeshGradient` drawn as a border. Off with Reduce Motion.
struct ShimmerBorder: ViewModifier {
  var isActive: Bool
  var cornerRadius: CGFloat = 20
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.overlay {
      if isActive {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
          if reduceMotion {
            shape.strokeBorder(Color.brandPrimary, lineWidth: 2)
          } else {
            TimelineView(.animation) { context in
              let t = context.date.timeIntervalSinceReferenceDate
              let x = Float(0.5 + 0.45 * sin(t * 1.2))
              let y = Float(0.5 + 0.45 * cos(t * 0.9))
              MeshGradient(
                width: 3, height: 3,
                points: [
                  [0, 0], [0.5, 0], [1, 0], [0, 0.5], [x, y], [1, 0.5], [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                  .brandSecondary, .brandPrimary, .brandAccent, .brandPrimary, .white,
                  .brandSecondary, .brandAccent, .brandSecondary, .brandPrimary,
                ]
              )
              .mask(shape.strokeBorder(lineWidth: 3))
            }
          }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
      }
    }
  }
}

extension View {
  func shimmerBorder(_ isActive: Bool, cornerRadius: CGFloat = 20) -> some View {
    modifier(ShimmerBorder(isActive: isActive, cornerRadius: cornerRadius))
  }
}
