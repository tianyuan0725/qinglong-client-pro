import SwiftUI

/// App-wide UI state shared across views.
@MainActor
final class AppState: ObservableObject {
    /// Currently opened panel; nil means we are on the connection list.
    @Published var selected: Connection?

    /// Whether the user prefers a forced color scheme.
    @AppStorage("qlpro_colorScheme") var colorSchemeRaw: String = "system" // system | light | dark
    /// Id of the panel to open automatically on launch.
    @AppStorage("qlpro_defaultConnection") var defaultConnectionId: String = ""
    /// 全局字号（原 VIP 功能，现免费）：small / standard / large / xLarge / xxLarge。
    @AppStorage("qlpro_fontScale") var fontScale: String = "standard"

    var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var contentSizeCategory: ContentSizeCategory {
        switch fontScale {
        case "small": return .small
        case "large": return .large
        case "xLarge": return .extraLarge
        case "xxLarge": return .extraExtraLarge
        default: return .medium
        }
    }
}
