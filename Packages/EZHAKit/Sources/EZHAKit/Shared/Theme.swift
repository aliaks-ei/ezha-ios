import SwiftUI

/// Brand color tokens (guide 7.2). Shared by the app and the widget.
extension Color {
  public static let brandPrimary = Color("BrandPrimary", bundle: .module)
  public static let brandSecondary = Color("BrandSecondary", bundle: .module)
  public static let brandAccent = Color("BrandAccent", bundle: .module)
  public static let canvas = Color("Canvas", bundle: .module)
  public static let surface = Color("Surface", bundle: .module)
  public static let ink = Color("Ink", bundle: .module)
  public static let track = Color("Track", bundle: .module)
  public static let danger = Color("Danger", bundle: .module)
}
