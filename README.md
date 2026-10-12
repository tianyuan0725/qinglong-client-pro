# 青龙客户端 Pro (QinglongClientPro)

原生 SwiftUI 编写的 **iOS 青龙面板客户端**，视觉与功能全面对标参考客户端
「青龙客户端 3.0.0」，用于在手机上管理你自己的青龙面板：
定时任务的运行 / 停止 / 启停 / 置顶 / 日志查看，环境变量管理，脚本管理，
依赖管理，订阅管理，多面板切换，系统信息概览。

> 适配青龙 2.x OpenAPI（[whyour/qinglong](https://github.com/whyour/qinglong)）。
> 所有面板地址与凭证仅保存在本机 Keychain，不经过任何第三方服务器。

---

## ✨ 功能

| 模块 | 说明 |
|------|------|
| 多面板管理 | 添加 / 编辑 / 删除多个青龙面板，可设默认面板自动连接，历史账号一键切换 |
| 双认证方式 | ① 面板账号密码（`/api/user/login`）② 开放 API Client ID/Secret（`/api/apps/token` → `/open/*`） |
| 会话保持 | 面板 token 存 Keychain，冷启动/解锁后自动恢复会话无需重登；应用锁锁定期间会话不销毁 |
| 两步验证 | 面板开启 2FA 时自动跳验证码页（`PUT /api/user/two-factor/login`） |
| FaceID 应用锁 | 启动 / 回前台需生物识别验证（`LocalAuthentication`），锁定时全屏单一解锁界面 |
| 主题 | 浅色 / 深色 / 跟随系统 |
| 概览 | 青龙版本、CPU / 内存 / 磁盘占用、运行时长、任务与变量统计、运行中任务列表 |
| 定时任务 | 搜索、运行、停止、启用 / 禁用、置顶、新增 / 编辑 / 删除、实时日志（运行中自动刷新） |
| 环境变量 | 搜索、新增 / 编辑 / 删除、启用 / 禁用、值默认打码可一键显示 |
| 脚本管理 | 目录浏览 / 编辑 / 运行 / 重命名 / 删除、多选批量操作、下载到本机、历史版本恢复、一键添加到任务 |
| 依赖管理 | Node / Python / Linux 依赖增删改、扫描缺失依赖一键补装 |
| 订阅管理 | 订阅增删改、运行、日志 |
| 配置文件 | 配置文件浏览 / 编辑 |
| 应用设置 | OpenAPI 应用（Client ID/Secret）管理 |
| 系统通知 | 发送系统通知测试、当前通知方式查看 / 编辑（23 种渠道）、多渠道通知配置管理（旧版面板） |
| 系统设置 | 标题 / 时区 / 日志清理 / 并发 / 代理 / 镜像、通知渠道、系统日志 |
| 文件备份 | 本机 JSON 备份（脚本+配置）、面板数据 zip 导出 / 导入、iCloud 备份管理（分享面板存储到 iCloud 云盘） |
| 更新 | App 更新检查（GitHub Releases）、青龙服务端版本检查 + 一键升级 |
| 安全 | 凭证存 Keychain；变量值默认遮蔽；支持 HTTP 内网面板（已放开 ATS） |

> 原参考 App 的 VIP 功能（多账号、扫描依赖、字体大小、文件备份、账号排序）全部免费。

## 📁 项目结构

```
QinglongClientPro/
├── project.yml                     # XcodeGen 工程描述
├── .github/workflows/build.yml     # GitHub Actions 云构建 unsigned IPA
└── QinglongClientPro/
    ├── Info.plist                  # 已放开 ATS + FaceID 用途 + 文件共享
    ├── Assets.xcassets/            # AppIcon（青龙盘钟图标）+ AccentColor
    ├── App/                        # App 入口 + RootView
    ├── AppLockManager.swift        # FaceID 应用锁
    ├── UpdateChecker.swift         # GitHub Releases 更新检查
    ├── Theme.swift                 # 设计系统（品牌色 / 渐变 / 组件）
    ├── Core/
    │   ├── Models.swift            # CronTask / EnvVar / SystemInfo / Connection / ...
    │   ├── APIClient.swift         # 青龙 REST 客户端（双认证 + 2FA + 新接口）
    │   ├── PanelSession.swift      # 单面板会话（数据 + 变更操作）
    │   ├── ConnectionStore.swift   # 多面板存储（Keychain）
    │   ├── KeychainHelper.swift    # Keychain 封装
    │   └── AppState.swift          # 全局状态 / 主题
    └── Views/                      # 登录页、连接管理、任务、变量、脚本、我的等
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
