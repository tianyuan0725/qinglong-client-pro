import SwiftUI

/// 本地通知设置页（v2.0.7 新增）。
///
/// 用户反馈「系统通知好了，但软件里找不到相关设置」——原设置藏在「系统设置」页中部，
/// 这里做成独立页面并从「我的」页与「系统设置」页都能进入，选项也更细：
/// 总开关 / 任务开始 / 任务完成 / 权限状态 / 测试。
struct LocalNotifySettingsView: View {
    @EnvironmentObject var notify: AppNotifyManager

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $notify.enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("任务运行本地通知")
                        Text(notify.enabled ? "开启后，任务开始/完成时弹出系统通知" : "已关闭，不会发送任何本地通知")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("总开关")
            } footer: {
                Text("本地通知即苹果系统弹窗（与微信收到消息的横幅效果相同），App 在前台也会弹出。")
            }

            if notify.enabled {
                Section {
                    Toggle(isOn: $notify.notifyOnStart) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("任务开始时通知")
                            Text("点「运行」或面板到点自动执行时提醒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $notify.notifyOnFinish) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("任务完成时通知")
                            Text("轮询检测到任务运行结束后提醒（最长 10 分钟）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("通知时机")
                }
            }

            Section {
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(notify.authorized ? "已允许" : "未允许")
                        .foregroundStyle(notify.authorized ? .green : .red)
                }
                if !notify.authorized {
                    Button {
                        notify.requestAuthorization()
                    } label: {
                        Label("请求通知权限", systemImage: "bell.badge")
                    }
                    Button {
                        notify.openSystemSettings()
                    } label: {
                        Label("前往苹果设置开启", systemImage: "gear")
                    }
                }
                Button {
                    Task { @MainActor in
                        notify.notify(title: "青龙客户端 Pro", body: "这是一条本地测试通知")
                    }
                } label: {
                    Label("发送测试本地通知", systemImage: "paperplane")
                }
            } header: {
                Text("权限与测试")
            } footer: {
                Text("若系统权限被拒绝，请到「苹果设置 → 通知 → 青龙客户端 Pro」中允许通知。")
            }
        }
        .navigationTitle("通知设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
