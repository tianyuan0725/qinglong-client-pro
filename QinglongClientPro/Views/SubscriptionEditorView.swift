import SwiftUI

struct SubscriptionEditorView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let editing: Subscription?

    @State private var alias = ""
    @State private var type = "public-repo"
    @State private var url = ""
    @State private var scheduleType = "crontab"
    @State private var schedule = ""
    @State private var intervalUnit = "day"
    @State private var intervalValue = 1
    @State private var branch = ""
    @State private var extensions = ""
    @State private var whitelist = ""
    @State private var blacklist = ""
    @State private var subBefore = ""
    @State private var subAfter = ""
    @State private var proxy = ""
    @State private var autoAdd = true
    @State private var autoDel = false
    @State private var dependences = ""

    init(editing: Subscription?) {
        self.editing = editing
        if let s = editing {
            _alias = State(initialValue: s.alias)
            _type = State(initialValue: s.type.isEmpty ? "public-repo" : s.type)
            _url = State(initialValue: s.url)
            _scheduleType = State(initialValue: s.scheduleType.isEmpty ? "crontab" : s.scheduleType)
            _schedule = State(initialValue: s.schedule)
            _branch = State(initialValue: s.branch)
            _extensions = State(initialValue: s.extensions)
            _whitelist = State(initialValue: s.whitelist)
            _blacklist = State(initialValue: s.blacklist)
            _subBefore = State(initialValue: s.subBefore)
            _subAfter = State(initialValue: s.subAfter)
            _proxy = State(initialValue: s.proxy)
            _autoAdd = State(initialValue: s.autoAddCron == 1)
            _autoDel = State(initialValue: s.autoDelCron == 1)
            _dependences = State(initialValue: s.dependences)
        }
    }

    private var canSave: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty &&
        !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("别名（必填）", text: $alias)
                    Picker("类型", selection: $type) {
                        Text("公开仓库").tag("public-repo")
                        Text("私有仓库").tag("private-repo")
                        Text("文件").tag("file")
                    }
                    TextField("订阅地址（必填）", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("执行周期") {
                    Picker("方式", selection: $scheduleType) {
                        Text("Crontab").tag("crontab")
                        Text("间隔").tag("interval")
                    }
                    .pickerStyle(.segmented)
                    if scheduleType == "crontab" {
                        TextField("Crontab 表达式，如 0 0 * * *", text: $schedule)
                    } else {
                        HStack {
                            Stepper("\(intervalValue)", value: $intervalValue, in: 1...365)
                            Picker("单位", selection: $intervalUnit) {
                                Text("分钟").tag("minute")
                                Text("小时").tag("hour")
                                Text("天").tag("day")
                                Text("周").tag("week")
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                Section("高级（可留空）") {
                    TextField("分支", text: $branch)
                    TextField("扩展名（逗号分隔）", text: $extensions)
                    TextField("白名单", text: $whitelist)
                    TextField("黑名单", text: $blacklist)
                    TextField("拉取前命令", text: $subBefore)
                    TextField("拉取后命令", text: $subAfter)
                    TextField("代理地址", text: $proxy)
                    TextField("依赖（逗号分隔）", text: $dependences)
                }
                Section("自动管理任务") {
                    Toggle("自动添加任务", isOn: $autoAdd)
                    Toggle("自动删除任务", isOn: $autoDel)
                }
            }
            .navigationTitle(editing == nil ? "新建订阅" : "编辑订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard canSave else { return }
                        Task {
                            let payload = buildPayload()
                            let ok: Bool = editing == nil
                                ? await session.createSubscription(payload)
                                : await session.updateSubscription(payload)
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSave || session.isBusy)
                }
            }
        }
    }

    private func buildPayload() -> [String: Any] {
        var p: [String: Any] = [
            "type": type,
            "url": url.trimmingCharacters(in: .whitespaces),
            "alias": alias.trimmingCharacters(in: .whitespaces),
            "schedule_type": scheduleType,
            "autoAddCron": autoAdd,
            "autoDelCron": autoDel
        ]
        if scheduleType == "crontab" {
            p["schedule"] = schedule.trimmingCharacters(in: .whitespaces)
        } else {
            p["interval_schedule"] = ["type": intervalUnit, "value": intervalValue] as [String: Any]
        }
        let map: [(String, String)] = [
            ("branch", branch), ("extensions", extensions), ("whitelist", whitelist),
            ("blacklist", blacklist), ("sub_before", subBefore), ("sub_after", subAfter),
            ("proxy", proxy), ("dependences", dependences)
        ]
        for (k, v) in map {
            let t = v.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { p[k] = t }
        }
        if let s = editing { p["id"] = s._id }
        return p
    }
}
