
项目名称

Claude Usage Menu Bar Monitor (macOS)

项目目标

开发一个 macOS 菜单栏应用（Menu Bar App），实时显示：

当前使用百分比（例如 CC-42%）



一、功能需求
1️⃣ 菜单栏实时显示

菜单栏显示格式：

示例：

CC-42%


要求：

10分钟刷新一次

占用空间尽量小

2️⃣ 下拉菜单内容

点击菜单栏图标后显示：

当前使用百分比

本周期已使用token


Reset 时间（5小时reset时候）

手动刷新按钮

设置

退出

3️⃣ 数据来源

使用 Anthropic API 查询 usage / billing 信息。

工程师需要：

根据 API key 拉取当前周期使用量


4️⃣ 登录机制

首次启动：

弹出 API Key 输入框

验证 API Key 是否有效

成功后存入 macOS Keychain

之后自动使用

支持：

在设置中更换 API Key

登出（删除 Keychain）

安全要求：

API Key 必须存储在 macOS Keychain

不得明文写入文件

5️⃣ 自动刷新机制

默认：

每 10分钟刷新一次

可在设置中选择：

30 秒

60 秒

5 分钟

网络错误时：

显示 ⚠ 或灰色状态

不崩溃

二、技术要求

推荐技术栈：

Swift + SwiftUI + AppKit

类型：

MenuBarApp（使用 NSStatusBar）

必须：

无 Dock 图标（LSUIElement = true）

支持 Apple Silicon + Intel

macOS 13+

三、界面要求

菜单栏文本：

简洁

不超过 12 个字符

自动适配深色模式

示例：

72% | 5d
85%
12% ⚠

四、异常处理

必须处理：

API Key 无效（401）

网络断开

API 限流

JSON 解析失败

出错时：

菜单栏显示：

--% ⚠

五、打包与发布

工程师需提供：

Xcode 工程源码

Release 版本 .app

生成 .dmg 安装包

发布流程：

Developer ID 签名

Notarization

生成 dmg

用户拖拽到 Applications 安装

六、用户使用流程

下载 dmg

拖拽到 Applications

首次打开

输入 API Key

菜单栏开始显示百分比

七、验收标准

菜单栏实时显示百分比

能正确计算 reset 时间

自动刷新稳定

重启后仍保持登录状态

API Key 安全存储
