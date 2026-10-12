import SwiftUI

/// 「我的」页面：对齐参考客户端布局，原 VIP 功能全部免费。
struct ProfileView: View {
    @EnvironmentObject var session: PanelSession
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var appLock: AppLockManager
    @EnvironmentObject var updater: UpdateChecker
    @State private var showFontSheet = false
    @State private var showPanelManager = false
    @State private var panelManagerSortMode = false
    @State private var showUpdateSheet = false
    @State private var showThemeSheet = false
    @State private var showServerUpdateAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    serverUpdateBanner
                    headerCard
                    quickAccessCard
                    settingsCard
                    multiAccountCard
                    freeFeaturesCard
                    basicFunctionsCard
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFontSheet) { FontSizeSheet() }
            .sheet(isPresented: $showPanelManager) {
                ConnectionListView(startInSortMode: panelManagerSortMode)
            }
            .sheet(isPresented: $showUpdateSheet) {
                UpdateSheet()
                    .environmentObject(updater)
            }
            .sheet(isPresented: $showThemeSheet) {
                ThemeSheet(selection: $appState.colorSchemeRaw)
            }
            .alert("青龙服务端发现新版本", isPresented: $showServerUpdateAlert) {
                Button("取消", role: .cancel) { }
                Button("立即升级") {
                    Task { _ = await session.updatePanelSystem() }
                }
            } message: {
                Text("服务端当前 v\(session.panelInfo?.version ?? "—")，最新版 v\(session.serverUpdate?.lastVersion ?? "—")。升级后面板服务会重启，期间无法连接。")
            }
            .task {
                await session.loadCurrentUser()
                if session.serverUpdate == nil {
                    session.serverUpdate = await session.checkServerUpdate()
                }
                if updater.updateNotifyEnabled, updater.latestVersion == nil {
                    await updater.check()
                }
            }
        }
    }

    // MARK: - 服务端版本提示条（对齐参考 App「青龙服务端发现新版本」）

    @ViewBuilder
    private var serverUpdateBanner: some View {
        if let update = session.serverUpdate, update.hasNewVersion {
            Button { showServerUpdateAlert = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("青龙服务端发现新版本")
                            .font(.subheadline.weight(.semibold))
                        Text("当前 v\(session.panelInfo?.version ?? "—") → 最新 v\(update.lastVersion ?? "—")，点击升级")
                            .font(.caption2)
                            .opacity(0.9)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(QLPalette.orange, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 头部（面板信息，渐变卡片）

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(qlBrandGreen)
                    .frame(width: 56, height: 56)
                Text("青龙")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(session.connection.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    StatusPill(text: "全功能免费", color: qlBrandGreen)
                }
                Text(session.connection.baseURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let user = session.currentUser?.username, !user.isEmpty {
                    Text("账号 \(user) · 青龙 v\(session.panelInfo?.version ?? "—")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(qlProfileGradient, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 快捷入口（订阅 / 脚本 / 依赖）

    private var quickAccessCard: some View {
        HStack(spacing: 0) {
            navItem(title: "订阅管理", icon: "arrow.down.circle", color: qlBrandGreen) {
                SubscriptionListView()
            }
            navItem(title: "脚本管理", icon: "doc.text", color: .blue) {
                ScriptListView()
            }
            navItem(title: "依赖管理", icon: "square.stack.3d.up", color: .orange) {
                DependencyListView()
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 设置（主题 / FaceID / 检查更新）

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "moon.circle", color: .indigo, title: "主题", value: themeLabel) {
                showThemeSheet = true
            }
            Divider().padding(.leading, 46)
            NavigationLink {
                SystemSettingsView()
                    .environmentObject(session)
                    .environmentObject(appState)
                    .environmentObject(store)
                    .environmentObject(appLock)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "faceid")
                        .font(.system(size: 17))
                        .foregroundStyle(.green)
                        .frame(width: 26)
                    Text("Face ID 解锁")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(appLock.enabled ? "已开启" : "已关闭")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            Divider().padding(.leading, 46)
            settingsRow(
                icon: "arrow.down.circle",
                color: .blue,
                title: "检查更新",
                value: updater.checking ? "检查中…" : (updater.hasUpdate ? "有新版本 v\(updater.latestVersion ?? "")" : "已是最新")
            ) {
                Task { await updater.check(); showUpdateSheet = true }
            }
        }
        .qlCard(padding: 4)
    }

    private var themeLabel: String {
        switch appState.colorSchemeRaw {
        case "light": return "浅色"
        case "dark": return "深色"
        default: return "跟随系统"
        }
    }

    private func settingsRow(icon: String, color: Color, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(color)
                    .frame(width: 26)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 多账号（原 SVIP，现免费）

    private var multiAccountCard: some View {
        Button {
            panelManagerSortMode = false
            showPanelManager = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "infinity")
                    .font(.system(size: 24))
                    .foregroundStyle(qlBrandGreen)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("多账号数")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("已添加 \(store.connections.count) 个面板，无限添加、一键切换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 免费功能（原 VIP 四项）

    private var freeFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("免费功能")
                    .font(.headline)
                Spacer()
                Text("原 VIP 已全部解锁")
                    .font(.caption)
                    .foregroundStyle(qlBrandGreen)
            }
            HStack(spacing: 0) {
                navItem(title: "扫描依赖", icon: "doc.text.magnifyingglass", color: .purple) {
                    DependencyScanView()
                }
                Button {
                    showFontSheet = true
                } label: {
                    gridLabel(title: "字体大小", icon: "textformat.size", color: .blue)
                }
                .buttonStyle(.plain)
                navItem(title: "文件备份", icon: "arrow.up.doc", color: .teal) {
                    BackupView()
                }
                Button {
                    panelManagerSortMode = true
                    showPanelManager = true
                } label: {
                    gridLabel(title: "账号排序", icon: "arrow.up.arrow.down", color: .orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 基础功能（8 宫格）

    private var basicFunctionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("基础功能")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 18) {
                GridRow {
                    navItem(title: "任务日志", icon: "doc.text", color: .blue) { TaskLogView() }
                    navItem(title: "登录日志", icon: "person.text.rectangle", color: .indigo) { LoginLogView() }
                    navItem(title: "应用设置", icon: "gearshape", color: .gray) { AppListView() }
                    navItem(title: "通知设置", icon: "envelope", color: .red) { NotifySettingsView() }
                }
                GridRow {
                    navItem(title: "修改密码", icon: "lock", color: .orange) { ChangePasswordView() }
                    navItem(title: "日志设置", icon: "clock.arrow.circlepath", color: .teal) { LogSettingsView() }
                    navItem(title: "系统设置", icon: "gearshape.2", color: .blue) { SystemSettingsView() }
                    navItem(title: "关于软件", icon: "info.circle", color: .gray) { AboutView() }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(spacing: 10) {
            Text("青龙客户端 Pro · 功能与网页版一致 · 全部免费")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                appState.selected = nil
            } label: {
                Text("退出当前面板")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 组件

    private func navItem<D: View>(title: String, icon: String, color: Color,
                                  @ViewBuilder dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            gridLabel(title: title, icon: icon, color: color)
        }
    }

    private func gridLabel(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 21))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 主题选择弹窗（白色 / 黑色 / 跟随系统）。
struct ThemeSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    private let options: [(key: String, label: String, icon: String)] = [
        ("light", "浅色", "sun.max"),
        ("dark", "深色", "moon"),
        ("system", "跟随系统", "circle.lefthalf.filled"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options, id: \.key) { opt in
                        Button {
                            selection = opt.key
                            dismiss()
                        } label: {
                            HStack {
                                Label(opt.label, systemImage: opt.icon)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selection == opt.key {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(qlBrandGreen)
                                }
                            }
                        }
                    }
                } header: {
                    Text("选择主题")
                }
            }
            .navigationTitle("主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 检查更新弹窗（对齐参考 App「App更新通知」）。
struct UpdateSheet: View {
    @EnvironmentObject var updater: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if updater.checking {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("正在检查更新…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if updater.hasUpdate {
                    List {
                        Section {
                            HStack {
                                Text("当前版本")
                                Spacer()
                                Text("v\(updater.currentVersion)").foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("最新版本")
                                Spacer()
                                Text("v\(updater.latestVersion ?? "—")")
                                    .foregroundStyle(qlBrandGreen)
                            }
                        }
                        Section("更新内容") {
                            Text(updater.releaseNotes?.isEmpty == false ? updater.releaseNotes! : "暂无更新说明")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Section {
                            if let url = updater.releaseURL {
                                Link(destination: url) {
                                    Label("前往 GitHub 下载 IPA", systemImage: "arrow.down.circle")
                                }
                            }
                        }
                    }
                } else if let error = updater.error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(QLPalette.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("重试") { Task { await updater.check() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(qlBrandGreen)
                        Text("已是最新版本 v\(updater.currentVersion)")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("检查更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

/// 全局字号设置（原 VIP 功能，现免费）。
struct FontSizeSheet: View {
    @AppStorage("qlpro_fontScale") private var scale: String = "standard"
    @Environment(\.dismiss) private var dismiss

    private struct Option: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private let options: [Option] = [
        Option(key: "small", label: "小"),
        Option(key: "standard", label: "标准"),
        Option(key: "large", label: "大"),
        Option(key: "xLarge", label: "特大"),
        Option(key: "xxLarge", label: "超大"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(options) { opt in
                        Button {
                            scale = opt.key
                            dismiss()
                        } label: {
                            HStack {
                                Text(opt.label)
                                    .foregroundStyle(.primary)
                                    .font(.system(size: previewSize(opt.key)))
                                Spacer()
                                if scale == opt.key {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(qlBrandGreen)
                                }
                            }
                        }
                    }
                } header: {
                    Text("选择字号")
                } footer: {
                    Text("调整后全局生效，包括任务、变量、脚本等所有页面。")
                }
            }
            .navigationTitle("字体大小")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func previewSize(_ key: String) -> CGFloat {
        switch key {
        case "small": return 13
        case "standard": return 15
        case "large": return 17
        case "xLarge": return 19
        default: return 21
        }
    }
}
