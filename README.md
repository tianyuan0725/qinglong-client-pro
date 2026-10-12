# 青龙客户端 Pro (QinglongClientPro)

原生 SwiftUI 编写的 **iOS 青龙面板客户端**，用于在手机上管理你自己的青龙面板：
定时任务的运行 / 停止 / 启停 / 置顶 / 日志查看，环境变量管理，多面板切换，系统信息概览。

> 适配青龙 2.x OpenAPI（[whyour/qinglong](https://github.com/whyour/qinglong)）。
> 所有面板地址与凭证仅保存在本机 Keychain，不经过任何第三方服务器。

---

## ✨ 功能

| 模块 | 说明 |
|------|------|
| 多面板管理 | 添加 / 编辑 / 删除多个青龙面板，可设默认面板自动连接 |
| 双认证方式 | ① 面板账号密码（`/api/user/login`）② 开放 API Client ID/Secret（`/api/apps/token` → `/open/*`） |
| 概览 | 青龙版本、CPU / 内存 / 磁盘占用、运行时长、任务与变量统计、运行中任务列表 |
| 定时任务 | 搜索、运行、停止、启用 / 禁用、置顶、新增 / 编辑 / 删除、实时日志（运行中自动刷新） |
| 环境变量 | 搜索、新增 / 编辑 / 删除、启用 / 禁用、值默认打码可一键显示 |
| 安全 | 凭证存 Keychain；变量值默认遮蔽；支持 HTTP 内网面板（已放开 ATS） |

## 📁 项目结构

```
QinglongClientPro/
├── project.yml                     # XcodeGen 工程描述
├── .github/workflows/build.yml     # GitHub Actions 云构建 unsigned IPA
└── QinglongClientPro/
    ├── Info.plist                  # 已放开 ATS（支持 http 内网面板）
    ├── Assets.xcassets/            # AppIcon（青龙盘钟图标）+ AccentColor
    ├── App/                        # App 入口 + RootView
    ├── Core/
    │   ├── Models.swift            # CronTask / EnvVar / SystemInfo / Connection
    │   ├── APIClient.swift         # 青龙 REST 客户端（双认证）
    │   ├── PanelSession.swift      # 单面板会话（数据 + 变更操作）
    │   ├── ConnectionStore.swift   # 多面板存储（Keychain）
    │   ├── KeychainHelper.swift    # Keychain 封装
    │   └── AppState.swift          # 全局状态 / 主题
    └── Views/                      # 连接管理、概览、任务、变量、日志、设置
```

---

## 🛠 本地构建（需要 Mac + Xcode 15+）

```bash
brew install xcodegen
cd QinglongClientPro
xcodegen generate
open QinglongClientPro.xcodeproj
```

在 Xcode 中选择你的开发团队后 Run 即可（本工程默认 `CODE_SIGNING_ALLOWED=NO`，
真机调试时请临时打开签名或改用下面的云构建 IPA + 巨魔安装）。

## ☁️ GitHub Actions 云构建（推荐，无需 Mac）

仓库自带工作流 `.github/workflows/build.yml`，push 到 `main` / `master` 或手动
`workflow_dispatch` 即可在 macOS runner 上产出 **免签名 IPA**：

1. 把本项目推到你的 GitHub 仓库
2. Actions → **Build Unsigned IPA** → 运行
3. 在 Artifacts 下载 `QinglongClientPro-ipa`

```bash
git init && git add -A && git commit -m "feat: 青龙客户端 Pro v1.0"
gh repo create qinglong-client-pro --private --source=. --push
# 或手动:
# git remote add origin git@github.com:<你的用户名>/qinglong-client-pro.git && git push -u origin main
```

## 📲 TrollStore / 巨魔安装

产出的 IPA 为免签名构建，直接适配 TrollStore（CoreTrust 漏洞永久签）：

1. 设备已装 TrollStore（巨魔）
2. 用「文件」或 Safari 打开下载的 `QinglongClientPro.ipa` → 分享到 TrollStore
3. 安装后即可永久使用，无需 7 天重签、无需开发者账号

其他签名方式（AltStore / SideStore / 证书自签）同样适用。

---

## 🔌 对接你的青龙面板

1. 青龙面板 → **系统设置 → 应用设置 → 添加应用**，勾选「定时任务 / 环境变量」等权限，
   拿到 **Client ID / Client Secret**（推荐，权限可控）
2. 或直接用面板登录账号密码
3. App 内点 **+** 添加面板：填地址（如 `1.2.3.4:5700`）、选认证方式、填凭证

> 内网 / HTTP 面板可直接连接（Info.plist 已配置 `NSAllowsArbitraryLoads`）。

## 📜 许可

仅供学习与自用，请仅连接你自己拥有权限的青龙面板。
