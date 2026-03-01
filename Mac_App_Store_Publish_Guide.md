# Mac App Store 发布完整指南 (Local)

这篇文档详细记录了将此 macOS 应用程序（Claude Usage Monitor）打包并上架到 Mac App Store 的本地准备工作，按照苹果的审核要求，需确保 Bundle Identifier 设置正确，并开启了应用沙盒 (App Sandbox)，硬化运行时 (Hardened Runtime) 等。

## 前提条件
1. 拥有付费的 Apple Developer 账号并加入了 Apple Developer Program。
2. 已在 Mac 上的 Xcode 中登录开发者账号，并在 `Xcode > Settings > Accounts` 中成功下载了 Certificates, Identifiers & Profiles。

---

## 步骤 1：检查并确认 Xcode 基本配置

确保在 Xcode 中选中项目目标 `ClaudeUsageMonitor`，并点击 **General** 和 **Signing & Capabilities** 选项卡检查以下属性。

### General (常规) 属性：
- **Identity:**
  - **App Category (应用类别)**: 需要选择一个适合的类别（例如：`Utilities` 或 `Developer Tools`）。
- **Version 与 Build:**
  - **Version (版本, `MARKETING_VERSION`)**: 填入应用版本，如 `1.0`。
  - **Build (构建版本, `CURRENT_PROJECT_VERSION`)**: 填入构建号，如 `1`。如果被拒重新上传，需递增 Build（例如改为 `2`）。

### Signing & Capabilities (签名与能力):
勾选 **Automatically manage signing**，选择您的 Team (个人开发者通常是带有您的名字的团队标识)。确认已选择：
- **Bundle Identifier (`PRODUCT_BUNDLE_IDENTIFIER`)**: `com.claudeusagemonitor.app`

---

## 步骤 2：配置安全性设置 (非常关键)

Mac App Store **强制要求** 应用开启 Hardened Runtime 和 App Sandbox。当前我们已经通过代码完成了配置。

### 1. Hardened Runtime (强化运行时)
在 `project.pbxproj` 中的配置已开启：
- **Key**: `ENABLE_HARDENED_RUNTIME`
- **Value**: `YES`

*(您在 Xcode 中可以在 Signing & Capabilities 内看到 "Hardened Runtime" 的标志。无需额外勾选选项，除非您的应用使用特定功能（例如 JIT、内存保护等）。)*

### 2. App Sandbox (应用沙盒)
在您的 `ClaudeUsageMonitor/ClaudeUsageMonitor.entitlements` 文件中，我们已经添加了以下关键配置以请求沙盒环境与必要的网络权限：

```xml
<dict>
    <!-- [必选] 开启 Mac App Store 沙盒环境 -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- [已具备] 允许发出的网络连接请求（客户端），Claude API 所需 -->
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
```

详细 Entitlements 字段：
- **Key**: `com.apple.security.app-sandbox` 
  - **Value**: `<true/>` (Boolean) - 表明应用在沙盒内运行。
- **Key**: `com.apple.security.network.client`
  - **Value**: `<true/>` (Boolean) - 允许外发网络请求（调用 Anthropic API 必须开启这个）。

---

## 步骤 3：App Icon (图标配置)
在上传 App Store 之前，务必确保 `ClaudeUsageMonitor/Assets.xcassets` 中的 `AppIcon` 包含了所有需要的 Mac Icon 尺寸。Mac App Store 要求有最高分辨率可达 1024x1024 (1x) 的图标集。

目前根目录下有一个 `menu-page.png`，如果您有设计好的正方形 Logo，请将其添加到 Xcode 的 `Assets.xcassets/AppIcon` 中。

---

## 步骤 4：归档发布版本 (Archive)

代码、权限和功能确认无误后：
1. 在 Xcode 顶部的设备/模拟器下拉列表中，选择 `Any Mac (Apple Silicon, Intel)`。不能选择"My Mac"。
2. 在顶部菜单栏点击 **Product** -> **Archive** (归档)。
3. Xcode 会执行构建。成功后将自动打开 **Organizer** 窗口。

---

## 步骤 5：验证与上传 (Distribute App)

在 **Organizer** 窗口内，执行以下步骤：
1. 选中刚刚归档完成的版本号。
2. 点击右侧的 **Distribute App**。
3. **Select a method of distribution**：选择 **App Store Connect**。
4. **Select a destination**：选择 **Upload**。
5. 后续直接选择默认的 Next。Xcode 将会自动与 App Store Connect 通信，创建相关授权文件，并完成自动签名 (Automatically manage signing 会处理所需的 Mac App Distribution 证书和 Provisioning Profile)。
6. 检查信息无误后，点击 **Upload**。上传成功后你会看到提示界面。

## 待完成事项（线上部分 - App Store Connect）:
上传成功十多分钟后，您可以登录苹果官方开发者平台的 [App Store Connect](https://appstoreconnect.apple.com/) 来补充应用信息：
1. 上传高清 Mac App 截图 (包含所有功能点：登录、查询等界面)。
2. 提供一段隐私声明网址 (Privacy Policy URL) 和 支持页面 (Support URL)。
3. 为您的软件提交审核。

**小贴士：** 提交前检查代码不包含未捕获的崩溃，且状态栏的菜单应用可以正常点击**退出 (Quit)** 功能。苹果在审核时如果发现无法正常使用退出按钮，会以此为理由被拒。
