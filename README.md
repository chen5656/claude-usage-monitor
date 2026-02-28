# Claude Usage Monitor (macOS)

![Claude Usage Monitor Icon](claude_usage_monitor_icon.png)

A sleek, lightweight macOS menu bar application to monitor your Anthropic Claude API usage and billing in real-time. Stay informed about your token consumption and rate-limit windows without ever leaving your workflow.

## 🚀 Features

- **Real-time Monitoring**: Displays your current usage percentage (e.g., `CC-42%`) directly in the macOS menu bar.
- **Detailed Insights**: View token counts, total usage, and the exact time until your rate-limit resets in a clean dropdown menu.
- **Secure by Design**: Your OAuth tokens are stored securely in the **macOS Keychain**, never in plain text.
- **Robust Error Handling**: Visual indicators (`--% ⚠`) alert you to network or API issues without interrupting your experience.
- **Native Experience**: Built with Swift and SwiftUI for macOS 13+, supporting both Apple Silicon and Intel Macs.
- **Minimal Footprint**: Resides entirely in the menu bar with no Dock clutter.

## 📸 Interface

| Feature | Description |
| :--- | :--- |
| **Menu Bar Text** | Shows compact usage percentage (e.g., `72% \| 5h`). |
| **Dropdown Menu** | Detailed token stats, Reset Timer, Manual Refresh, and Log Out. |

## 🛠 Installation

1. **Download**: Obtain the latest `.dmg` from the releases page (or build from source).
2. **Launch**: Open the app. On first launch, you will be redirected to log in securely via your browser using Anthropic OAuth.
3. **Monitor**: Watch your credits live in your menu bar!

## 🏗 Development

### Build from Source

You can build the project using Xcode or the command line:

```bash
# Build using xcodebuild
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Technology Stack
- **Language**: Swift
- **UI Framework**: SwiftUI & AppKit
- **Security**: macOS Keychain Services
- **API**: Anthropic API (Usage/Billing endpoints)

## 🔒 Security & Privacy

Privacy is a priority. This application only communicates with the official Anthropic API. Your OAuth tokens are encrypted and stored using **macOS Keychain**, ensuring they are protected by system-level security and remain inaccessible to other applications or plain-text file reads.

---

*Stay productive and keep an eye on your credits with Claude Usage Monitor.*
