import LocalAuthentication
import SwiftUI

/// FaceID / TouchID 应用锁 —— 对齐参考客户端的「使用Face ID解锁APP」。
/// - 开关持久化在 AppStorage，开启后：冷启动 + 每次回前台都需要验证
/// - 验证失败可重试；设备未设置生物识别时自动降级关闭
@MainActor
final class AppLockManager: ObservableObject {
    /// 是否启用应用锁（开关）。
    @AppStorage("qlpro_appLockEnabled") var enabled: Bool = false {
        didSet { if !enabled { isLocked = false } }
    }

    /// 当前是否处于锁定遮罩状态。
    @Published var isLocked = false
    /// 最近一次验证错误信息（展示在遮罩上）。
    @Published var errorMessage: String?
    /// 是否正在验证中（按钮 loading）。
    @Published var authenticating = false

    private let context = LAContext()

    // MARK: - 能力探测

    /// 设备是否支持生物识别（FaceID / TouchID）。
    var biometryAvailable: Bool {
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 生物识别类型（用于文案：面容 ID / 触控 ID）。
    var biometryName: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "生物识别"
        }
        switch ctx.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "Optics ID"
        case .none: return "生物识别"
        @unknown default: return "生物识别"
        }
    }

    /// 开关副标题（跟随设备能力动态变化）。
    var switchSubtitle: String {
        biometryAvailable
            ? "打开 APP 时需使用\(biometryName)验证身份"
            : "当前设备未设置生物识别，无法开启"
    }

    // MARK: - 生命周期钩子

    /// 上次是否经历过后台（用于区分冷启动与回前台）。
    private var wentToBackground = false

    /// 冷启动：若开启则立即锁定并验证。
    func lockIfNeededOnLaunch() {
        guard enabled, biometryAvailable else { return }
        isLocked = true
        Task { await authenticate(reason: "使用\(biometryName)解锁 APP") }
    }

    /// 回前台：重新锁定并验证。
    func lockOnForegroundIfEnabled() {
        guard enabled, biometryAvailable else { return }
        isLocked = true
        errorMessage = nil
        Task { await authenticate(reason: "使用\(biometryName)解锁 APP") }
    }

    /// App 进入后台时调用。
    func handleDidEnterBackground() {
        wentToBackground = true
    }

    /// App 变为活跃时调用：冷启动直接锁；从后台回来也锁。
    func handleDidBecomeActive() {
        guard enabled, biometryAvailable else { return }
        if wentToBackground {
            wentToBackground = false
            lockOnForegroundIfEnabled()
        } else if !isLocked {
            lockIfNeededOnLaunch()
        }
    }

    // MARK: - 验证

    /// 执行生物识别验证。成功则解除遮罩；失败保留遮罩并展示错误。
    func authenticate(reason: String) async {
        guard !authenticating else { return }
        authenticating = true
        errorMessage = nil
        defer { authenticating = false }

        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        // 允许回退到系统密码（连续失败后）。
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if ok {
                isLocked = false
                errorMessage = nil
            } else {
                errorMessage = "验证未通过，请重试"
            }
        } catch {
            isLocked = true
            errorMessage = errorMessageText(error)
        }
    }

    /// 用户主动关闭开关时解除锁定。
    func disable() {
        enabled = false
        isLocked = false
    }

    private func errorMessageText(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case LAError.authenticationFailed.rawValue:
            return "验证失败，请重试"
        case LAError.userCancel.rawValue, LAError.appCancel.rawValue:
            return "已取消验证"
        case LAError.biometryLockout.rawValue:
            return "尝试次数过多，请先用系统密码解锁后重试"
        case LAError.biometryNotAvailable.rawValue:
            return "生物识别不可用，请在系统设置中开启"
        default:
            return ns.localizedDescription
        }
    }
}

/// 应用锁遮罩 —— 覆盖在 Tab 页之上的全屏锁界面（参考 App 解锁卡片样式）。
struct AppLockOverlay: View {
    @EnvironmentObject var lock: AppLockManager

    var body: some View {
        ZStack {
            // 半透明模糊背景
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                // 青龙 logo 卡片（与登录页一致的品牌卡片）
                ZStack {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(qlBrandGreen)
                        .frame(width: 108, height: 108)
                        .shadow(color: qlBrandGreen.opacity(0.35), radius: 16, x: 0, y: 8)
                    Text("青龙")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    Text("青龙客户端已锁定")
                        .font(.title3.weight(.bold))
                    Text("使用\(lock.biometryName)验证身份后继续")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let error = lock.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(QLPalette.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                QLPrimaryButton(
                    title: "解锁",
                    busy: lock.authenticating,
                    action: { Task { await lock.authenticate(reason: "使用\(lock.biometryName)解锁 APP") } }
                )
                .padding(.horizontal, 56)
                Spacer()
                Text("青龙客户端 Pro")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 30)
            }
        }
        .transition(.opacity)
    }
}
