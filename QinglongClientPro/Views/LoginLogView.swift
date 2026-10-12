import SwiftUI

/// 登录日志（GET /api/user/login-log）。
struct LoginLogView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        List {
            ForEach(session.loginLogs) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(entry.isSuccess ? Color.green : Color.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.ip ?? "未知 IP")
                            .font(.body.weight(.medium))
                        Text("\(entry.timeText) · \(entry.address ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let p = entry.platform, !p.isEmpty {
                            Text(p)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    StatusPill(text: entry.isSuccess ? "成功" : "失败",
                               color: entry.isSuccess ? .green : .red)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("登录日志")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.loadLoginLogs() }
        .task { await session.loadLoginLogs() }
        .overlay {
            if session.loginLogs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无登录记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
