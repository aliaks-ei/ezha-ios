import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button that opens the logger.
struct LogMealControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.aliaksei.ezha.log-meal") {
      ControlWidgetButton(action: OpenLoggerIntent()) {
        Label("Log meal", systemImage: "fork.knife")
      }
    }
    .displayName("Log meal")
    .description("Opens EZHA on the logger.")
  }
}
