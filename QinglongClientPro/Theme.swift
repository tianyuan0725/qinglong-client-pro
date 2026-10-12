import SwiftUI

/// 青龙客户端 Pro 设计系统 —— 视觉令牌对齐参考客户端「青龙客户端 3.0.0」(work.newtab.ql)。
/// 品牌色从参考 IPA 资源精确取色：品牌绿 #20B54F、登录蓝点 #4992FF、
/// Profile 渐变 #A3E8AC→#73D397→#CCF5EC→#F6F6F6、白色圆角卡片。

// MARK: - 品牌色

/// 品牌绿（青龙主题色）#20B54F —— 来自参考 App 精确取色。
let qlBrandGreen = Color(red: 0x20 / 255, green: 0xB5 / 255, blue: 0x4F / 255)

/// 品牌绿按压态（略深）。
let qlBrandGreenDark = Color(red: 0x1A / 255, green: 0x9A / 255, blue: 0x43 / 255)

/// 登录页蓝点 / 主按钮蓝 #4992FF —— 来自 login_bg.png 点阵取样。
let qlBlue = Color(red: 0x49 / 255, green: 0x92 / 255, blue: 0xFF / 255)

/// 品牌绿浅色底（选中态背景 / 标签底）。
let qlBrandGreenLight = Color(red: 0xE2 / 255, green: 0xF6 / 255, blue: 0xE9 / 255)

/// 功能图标彩色（参考 App 宫格配色）。
enum QLPalette {
    static let green  = Color(red: 0x2E / 255, green: 0xB5 / 255, blue: 0x66 / 255)
    static let blue   = Color(red: 0x49 / 255, green: 0x92 / 255, blue: 0xFF / 255)
    static let orange = Color(red: 0xFF / 255, green: 0x9B / 255, blue: 0x45 / 255)
    static let purple = Color(red: 0x9A / 255, green: 0x6B / 255, blue: 0xF5 / 255)
    static let teal   = Color(red: 0x2A / 255, green: 0xBE / 255, blue: 0xB8 / 255)
    static let red    = Color(red: 0xF5 / 255, green: 0x53 / 255, blue: 0x3D / 255)
    static let indigo = Color(red: 0x5B / 255, green: 0x6C / 255, blue: 0xFF / 255)
    static let pink   = Color(red: 0xF5 / 255, green: 0x6C / 255, blue: 0xA8 / 255)
}

// MARK: - 渐变

/// Profile 头部渐变（参考 App icon_other_bg.png 取样：#A3E8AC→#73D397→#CCF5EC→#F6F6F6）。
let qlProfileGradient = LinearGradient(
    colors: [
        Color(red: 0xA3 / 255, green: 0xE8 / 255, blue: 0xAC / 255),
        Color(red: 0x73 / 255, green: 0xD3 / 255, blue: 0x97 / 255),
        Color(red: 0xCC / 255, green: 0xF5 / 255, blue: 0xEC / 255),
        Color(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF6 / 255),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// 登录页主背景渐变（浅绿白）。
let qlLoginGradient = LinearGradient(
    colors: [
        Color(red: 0xF0 / 255, green: 0xFB / 255, blue: 0xF3 / 255),
        Color.white,
    ],
    startPoint: .top,
    endPoint: .bottom
)

/// 品牌按钮渐变。
let qlBrandButtonGradient = LinearGradient(
    colors: [qlBrandGreen, qlBrandGreenDark],
    startPoint: .leading,
    endPoint: .trailing
)

// MARK: - 排版

/// 页面大标题（参考 App 标题字重）。
let qlTitleFont = Font.system(size: 22, weight: .bold)

/// 卡片标题。
let qlCardTitleFont = Font.system(size: 16, weight: .semibold)

/// 列表主文案。
let qlBodyFont = Font.system(size: 15)

/// 列表辅助文案。
let qlCaptionFont = Font.system(size: 12)

// MARK: - 组件样式

/// 参考 App 标准白色圆角卡片（14pt 圆角、极淡阴影）。
struct QLCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

extension View {
    /// 套用参考 App 白色圆角卡片样式。
    func qlCard(cornerRadius: CGFloat = 14, padding: CGFloat = 14) -> some View {
        modifier(QLCard(cornerRadius: cornerRadius, padding: padding))
    }
}

/// 参考 App 宫格入口项（图标 + 文字，图标彩色描边风格）。
struct QLGridItem: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 品牌胶囊标签（如「全功能免费」「运行中」）。
struct QLPill: View {
    let text: String
    var color: Color = qlBrandGreen
    var filled: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(filled ? color : color.opacity(0.12), in: Capsule())
    }
}

/// 品牌主按钮（绿色渐变、按压态）。
struct QLPrimaryButton: View {
    var title: String
    var busy: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                if busy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(disabled ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(qlBrandButtonGradient))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled || busy)
    }
}

/// 参考 App 次级按钮（浅灰底圆角）。
struct QLSecondaryButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
