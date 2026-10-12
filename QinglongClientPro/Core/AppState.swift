import SwiftUI

/// App-wide UI state shared across views.
@MainActor
final class AppState: ObservableObject {
    /// Currently opened panel; nil means we are on the connection list.
    /// didSet 记住上次进入的面板：冷启动/重装（UserDefaults 丢失）后，
    /// 解锁时可直接恢复，不必每次手动从连接列表点选（v2.0.3 反馈）。
    /// 注意：退出面板（置 nil）时不清除，否则下次启动无法恢复。
    @Published var selected: Connection? {
        didSet {
            if let conn = selected { lastConnectionId = conn.id }
        }
    }

    /// Whether the user prefers a forced color scheme.
    @AppStorage("qlpro_colorScheme") var colorSchemeRaw: String = "system" // system | light | dark
    /// Id of the panel to open automatically on launch.
    @AppStorage("qlpro_defaultConnection") var defaultConnectionId: String = ""
    /// Id of the last opened panel; restored on launch when no explicit default is set.
    /// 与 Keychain 中的面板列表相互独立：即使重装丢失了默认设置，
    /// 只要还记得上次面板就能直接进入（单面板时更有兜底，见 RootView）。
    @AppStorage("qlpro_lastConnectionId") var lastConnectionId: String = ""
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
