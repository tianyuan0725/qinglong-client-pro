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
    /// 延迟自动尝试验证的任务（冷启动/回前台用）。
    private var autoAuthTask: Task<Void, Never>?

    init() {
        // 启动即锁定（若开启）：保证首帧就是解锁页，不会闪现下层登录页。
        // 冷启动的锁定只在这里触发一次；.active 里绝不重复上锁，否则面容
        // 对话框消失带来的 .active 会立刻重新锁定，陷入反复扫脸死循环。
        // （冷启动瞬间窗口尚未就绪，立即 evaluatePolicy 会稳定失败，故延迟自动验证。）
        if enabled, biometryAvailable {
            isLocked = true
            scheduleAutoAuthenticate()
        }
    }

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

    /// 回前台：重新锁定并延迟尝试验证。
    func lockOnForegroundIfEnabled() {
        guard enabled, biometryAvailable else { return }
        isLocked = true
        errorMessage = nil
        scheduleAutoAuthenticate()
    }

    /// 延迟 0.5s 自动尝试验证（等窗口就绪）；失败不影响，用户可点解锁页按钮重试。
    private func scheduleAutoAuthenticate() {
        autoAuthTask?.cancel()
        autoAuthTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self, self.isLocked, self.enabled else { return }
            await self.authenticate(reason: "使用\(self.biometryName)解锁 APP")
        }
    }

    /// App 进入后台时调用。
    func handleDidEnterBackground() {
        wentToBackground = true
    }

    /// App 变为活跃时调用：仅「从后台回来」需要重新锁定。
    /// 冷启动锁定已在 init() 完成；面容对话框验证成功后消失同样会产生一次
    /// .active，若按 !isLocked 重新上锁就会反复弹面容（v2.0.4 修复的死循环）。
    func handleDidBecomeActive() {
        guard enabled, biometryAvailable else { return }
        if wentToBackground {
            wentToBackground = false
            lockOnForegroundIfEnabled()
        }
    }

    // MARK: - 验证

    /// 执行生物识别验证。成功则解除遮罩；失败保留遮罩并展示错误。
    /// 注意：失败/取消路径绝不主动置 isLocked = true —— 验证时遮罩本来就在，
    /// 而「验证成功后迟到的系统取消/错误」若强制上锁，会把已解锁的用户
    /// 重新锁回去，造成反复扫脸（v2.0.4）。
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
            } else if isLocked {
                errorMessage = "验证未通过，请重试"
            }
        } catch {
            if isLocked {
                errorMessage = errorMessageText(error)
            }
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

/// 应用锁遮罩 —— 应用锁定时全屏显示（下层内容常驻仅被隐藏，不出现面板登录页），
/// 验证通过后自动消失，露出下层的主界面/登录页。
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
