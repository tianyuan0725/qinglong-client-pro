import SwiftUI
import LocalAuthentication

struct PanelTabView: View {
    let connection: Connection
    @StateObject private var session: PanelSession
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var appLock: AppLockManager

    init(connection: Connection) {
        self.connection = connection
        _session = StateObject(wrappedValue: PanelSession(connection: connection))
    }

    var body: some View {
        Group {
            if session.isAuthenticated {
                TabView {
                    CronListView()
                        .tabItem { Label("定时任务", systemImage: "list.bullet.rectangle") }
                    EnvListView()
                        .tabItem { Label("环境变量", systemImage: "key") }
                    ConfigListView()
                        .tabItem { Label("配置文件", systemImage: "folder") }
                    ProfileView()
                        .tabItem { Label("我的", systemImage: "person.crop.circle") }
                }
                .tint(qlBrandGreen)
                .environmentObject(session)
                .overlay { if session.isBusy { LoadingOverlay() } }
                .errorToast($session.lastError)
            } else {
                LoginView()
                    .environmentObject(session)
                    .environmentObject(appState)
                    .environmentObject(store)
                    .environmentObject(appLock)
            }
        }
        .task { await session.login() }
    }
}

/// 登录页 —— 视觉对齐参考客户端：蓝色点阵波浪背景 + 品牌绿青龙 logo 卡片 +
/// 圆角输入框 + 历史账号 + 两步验证码页。
struct LoginView: View {
    @EnvironmentObject var session: PanelSession
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var appLock: AppLockManager

    @State private var username = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @FocusState private var focusedField: Field?

    private enum Field { case username, password, code }

    var body: some View {
        ZStack {
            // 蓝色点阵波浪背景（参考 App login_bg.png 风格）
            DotWaveBackground()
                .ignoresSafeArea()
            qlLoginGradient.ignoresSafeArea().opacity(0.65)

            ScrollView {
                VStack(spacing: 0) {
                    logoArea
                        .padding(.top, 56)
                        .padding(.bottom, 34)
                    if session.needsTwoFactor {
                        twoFactorCard
                    } else {
                        credentialsCard
                    }
                    historySection
                        .padding(.top, 22)
                    Spacer(minLength: 30)
                    footer
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            username = session.connection.username
            password = session.connection.password
        }
    }

    // MARK: - Logo 区

    private var logoArea: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(qlBrandGreen)
                    .frame(width: 84, height: 84)
                    .shadow(color: qlBrandGreen.opacity(0.4), radius: 18, x: 0, y: 9)
                Text("青龙")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 4) {
                Text(session.connection.name)
                    .font(.title2.weight(.bold))
                Text(session.connection.baseURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: - 账号密码卡片

    private var credentialsCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    SecureField("密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await session.login() } }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = session.authError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .lineLimit(3)
                }
                .foregroundStyle(QLPalette.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            QLPrimaryButton(title: "登 录", action: { Task { await session.login() } })

            // FaceID 按钮（开启应用锁时才出现）
            if appLock.enabled, appLock.biometryAvailable {
                Button {
                    Task { await appLock.authenticate(reason: "使用\(appLock.biometryName)解锁 APP") }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appLock.biometryTypeIcon)
                        Text("使用\(appLock.biometryName)解锁")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(qlBrandGreen)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    // MARK: - 两步验证卡片

    private var twoFactorCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 30))
                    .foregroundStyle(qlBrandGreen)
                Text("两步验证")
                    .font(.headline)
                Text("请输入身份验证器（Authenticator）中的 6 位动态验证码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("6 位验证码", text: $twoFactorCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .code)
                    .submitLabel(.go)
                    .onSubmit { Task { await session.loginWithTwoFactor(code: twoFactorCode) } }
                    .onChange(of: twoFactorCode) { v in
                        if v.count > 6 { twoFactorCode = String(v.prefix(6)) }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            if let error = session.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(QLPalette.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            QLPrimaryButton(
                title: "验证并登录",
                action: { Task { await session.loginWithTwoFactor(code: twoFactorCode) } }
            )
            .disabled(twoFactorCode.count != 6)

            Button {
                session.needsTwoFactor = false
                session.authError = nil
                twoFactorCode = ""
            } label: {
                Text("返回账号密码登录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    // MARK: - 历史账号

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.connections.count > 1 {
                Text("历史账号")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.connections) { conn in
                            Button {
                                appState.selected = conn
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "server.rack")
                                        .font(.caption2)
                                    Text(conn.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    conn.id == session.connection.id
                                        ? qlBrandGreenLight
                                        : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(conn.id == session.connection.id ? qlBrandGreen : .primary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(spacing: 6) {
            Text("青龙客户端 Pro")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("账号密码仅保存在本机 Keychain")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// 蓝色点阵波浪背景 —— 参考 App login_bg.png（#4992FF 圆点阵 + 波浪曲线）。
struct DotWaveBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let dotColor = Color(red: 0x49 / 255, green: 0x92 / 255, blue: 0xFF / 255)
            let spacing: CGFloat = 26
            let dotSize: CGFloat = 3.2
            let width = Double(size.width)
            var row = 0
            var y: CGFloat = spacing * 0.5
            while y < size.height + spacing {
                let rowOffset: CGFloat = (row % 2 == 0) ? 0 : spacing / 2
                var x: CGFloat = spacing * 0.5 + rowOffset
                while x < size.width + spacing {
                    // 波浪偏移：正弦曲线，中部偏高、两端偏低
                    let phase = Double(x) / width * Double.pi * 2.2 - Double(row) * 0.55
                    let wave = sin(phase)
                    let dy = wave * 26
                    // 靠近波浪中心线透明度更高，边缘渐隐
                    let distFromWave = abs(wave)
                    let alpha = max(0.08, 0.5 - distFromWave * 0.55)
                    let center = CGPoint(x: x, y: y + dy)
                    let rect = CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2,
                                      width: dotSize, height: dotSize)
                    ctx.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(alpha)))
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
    }
}

/// 应用锁生物识别类型图标（FaceID / TouchID）。
extension AppLockManager {
    var biometryTypeIcon: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "lock"
        }
        switch ctx.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock"
        @unknown default: return "lock"
        }
    }
}
