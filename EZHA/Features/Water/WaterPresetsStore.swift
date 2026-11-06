import EZHAKit
import Foundation
import Observation

/// Quick-add water presets, kept on this device. The first two show on Today.
@MainActor
@Observable
final class WaterPresetsStore {
  private(set) var presets: [WaterPreset]

  @ObservationIgnored private let defaults: UserDefaults?
  private static let key = "waterPresets"

  /// `defaults` nil keeps the presets in memory only, for previews and the UI harness.
  init(defaults: UserDefaults? = .standard) {
    self.defaults = defaults
    if let data = defaults?.data(forKey: Self.key),
      let stored = try? JSONDecoder().decode([WaterPreset].self, from: data), !stored.isEmpty
    {
      presets = stored
    } else {
      presets = WaterPreset.defaults
    }
  }

  var quickAdd: [WaterPreset] { Array(presets.prefix(Water.quickAddCount)) }

  func replace(with presets: [WaterPreset]) {
    self.presets = presets.isEmpty ? WaterPreset.defaults : presets
    if let data = try? JSONEncoder().encode(self.presets) {
      defaults?.set(data, forKey: Self.key)
    }
  }
}
