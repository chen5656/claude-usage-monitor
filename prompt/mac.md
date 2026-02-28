# Claude Usage Monitor — Build Spec

You are building a macOS menu bar application called **Claude Usage Monitor**.
Follow every requirement below exactly. Do not add features, abstractions, or files beyond what is specified.

---

## Tech Stack

- **Language:** Swift 5.0
- **UI:** SwiftUI + AppKit (mixed)
- **Target:** macOS 13.0+
- **Xcode compatibility:** 16.0 (`LastUpgradeCheck = 1600`)
- **External dependencies:** none — zero Swift packages, zero CocoaPods

---

## Project Structure

```
ClaudeUsageMonitor/                       ← Xcode project root
├── .gitignore
├── build_dmg.sh
├── claude_usage_monitor_icon.png         ← source icon (user-supplied large PNG)
├── ClaudeUsageMonitor.xcodeproj/
│   └── project.pbxproj
└── ClaudeUsageMonitor/                   ← target folder
    ├── ClaudeUsageMonitorApp.swift
    ├── AppDelegate.swift
    ├── StatusBarController.swift
    ├── AnthropicService.swift
    ├── KeychainManager.swift
    ├── LoginView.swift
    ├── UsageData.swift
    ├── OAuthManager.swift
    ├── CallbackServer.swift
    ├── OAuthTokens.swift
    ├── OAuthError.swift
    ├── RefreshIntervalView.swift
    ├── Info.plist
    ├── ClaudeUsageMonitor.entitlements
    └── Assets.xcassets/
        ├── Contents.json
        └── AppIcon.appiconset/
            ├── Contents.json
            └── [7 icon PNGs — see §Icon Assets]
```

`.gitignore` contains exactly:
```
.claude/
build/
```

---

## App Behavior

This is a **menu bar-only** app (no Dock icon). On launch it checks the macOS Keychain for a saved OAuth token.

- **If a token exists:** start the auto-refresh timer and immediately fetch usage.
- **If no token:** show the login window.

The status bar button shows a **monospaced** label:

| State   | Label      |
|---------|------------|
| Normal  | `CC-42%`   |
| No data | `CC--`     |
| Error   | `--% ⚠`   |

The percentage comes from the `five_hour` (Session) limit. If that limit is absent, use the first available limit.

### Menu layout (top to bottom)

```
[0..N usage rows — non-clickable labels, inserted dynamically above the separator]
────────────────
Refresh Now                (key: r)
────────────────
[NSHostingView — RefreshIntervalView, 240×58 pt]
────────────────
Log Out
────────────────
Quit                       (key: q)
```

- `menu.autoenablesItems = false`
- Usage rows are `NSMenuItem` with `isEnabled = false`
- `Quit` action is `NSApplication.terminate(_:)` (standard selector)

### Usage row format

```
Session: 42% · resets in 2h 30m
Weekly: 15% · resets in 5d 3h 2m
```

Time formatting rules:
- If `secs > 86400`: show `Xd Yh Zm`
- Else if `secs > 3600`: show `Xh Ym`
- Else: show `Xm`
- If `secs <= 0`: show `· resetting…`
- If `resetsAt` is nil: omit the reset part entirely

When there are no limits, show one disabled item: `"No usage data"`.

### Auto-refresh

- Default interval: **300 seconds** (5 minutes)
- Persisted in `UserDefaults` under key `"refreshInterval"`
- Changed via the in-menu picker
- `Timer.scheduledTimer(withTimeInterval:repeats:)` with `[weak self]` capture
- Invalidated on logout and on `applicationWillTerminate`

### Logout

1. Delete tokens from Keychain
2. Invalidate timer
3. Clear `limits` array
4. Reset status bar label to `"CC--"`
5. Call `rebuildUsageItems([])` (shows "No usage data")
6. Show login window

---

## Files

### `ClaudeUsageMonitorApp.swift`

- `@main` SwiftUI `App`
- Uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`
- `body` returns `Settings { EmptyView() }` — no main window

### `AppDelegate.swift`

- `NSObject, NSApplicationDelegate`
- Holds a `let statusBarController = StatusBarController()`
- `applicationDidFinishLaunching`: calls `NSApp.setActivationPolicy(.accessory)` then `statusBarController.setup()`
- `applicationWillTerminate`: calls `statusBarController.cleanup()`

### `UsageData.swift`

```
enum RateLimitType: String
  cases: fiveHour="five_hour", sevenDay="seven_day",
         sevenDaySonnet="seven_day_sonnet", sevenDayOpus="seven_day_opus",
         overage="overage", unknown=""
  var displayName: String
    fiveHour → "Session"
    sevenDay → "Weekly"
    sevenDaySonnet → "Sonnet Weekly"
    sevenDayOpus → "Opus Weekly"
    overage → "Extra"
    unknown → "Usage"

struct UsageLimit
  let type: RateLimitType
  let percentage: Int   // 0–100
  let resetsAt: Date?
```

### `OAuthTokens.swift`

```
struct OAuthTokens: Codable
  let accessToken: String
  let refreshToken: String?
  let expiresAt: Date
  var isExpired: Bool  →  Date().addingTimeInterval(300) >= expiresAt
```

### `OAuthError.swift`

```
enum OAuthError: LocalizedError
  cases: callbackFailed, stateMismatch, tokenExchangeFailed(String),
         noToken, cancelled, browserOpenFailed

  errorDescription:
    callbackFailed      → "OAuth callback failed."
    stateMismatch       → "Security check failed. Please try again."
    tokenExchangeFailed → "Token exchange failed: \(m)"
    noToken             → "Not logged in."
    cancelled           → "Login cancelled."
    browserOpenFailed   → "Could not open browser. Try manually opening the login URL."
```

### `KeychainManager.swift`

Singleton (`static let shared`). Uses Security framework generic-password items.

- `kSecAttrService` = `"com.claudeusagemonitor.app"`
- `kSecAttrAccount` = `"oauth-tokens"`
- `saveTokens(_:) -> Bool` — JSON-encodes, deletes old entry first, then `SecItemAdd`
- `getTokens() -> OAuthTokens?` — `SecItemCopyMatching` + JSON decode
- `deleteTokens()` — `SecItemDelete`

### `OAuthManager.swift`

`final class OAuthManager: @unchecked Sendable`, singleton.

**Hard-coded constants** (do not change):
```
clientID     = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
authorizeURL = "https://claude.ai/oauth/authorize"
tokenURL     = "https://platform.claude.com/v1/oauth/token"
scopes       = ["user:profile", "user:inference", "user:sessions:claude_code"]
```

**`login() async throws -> OAuthTokens`:**
1. Generate PKCE code verifier: 64 random bytes via `SecRandomCopyBytes`, base64url-encoded (strip `+→-`, `/→_`, `=→""`)
2. Generate code challenge: `SHA256` hash of verifier bytes, base64url-encoded (same stripping)
3. Generate state: `UUID().uuidString` with hyphens removed
4. Start `CallbackServer`, get port
5. Build authorize URL with query items (in this order): `code=true`, `client_id`, `response_type=code`, `redirect_uri`, `scope` (space-joined), `code_challenge`, `code_challenge_method=S256`, `state`
6. Open URL via `NSWorkspace.shared.open(_:)` on `MainActor`; throw `.browserOpenFailed` if returns false
7. `await server.waitForCallback()` → `(code, returnedState)`
8. Validate state == returnedState; throw `.stateMismatch` if not
9. Call `exchangeCode` passing `state` in the body (Anthropic requires it)

**`refresh(_ tokens:) async throws -> OAuthTokens`:**
- POST body: `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope` (space-joined)

**`cancelLogin()`:** calls `callbackServer?.cancel()` and nils it

**`postToken(_ body:) async throws -> OAuthTokens`:**
- POST to `tokenURL`, `Content-Type: application/json`, JSON body
- `timeoutInterval = 15`
- Decode `{ access_token, refresh_token?, expires_in? }`
- `expiresAt = Date().addingTimeInterval(TimeInterval(expires_in ?? 3600))`
- Non-200 → throw `.tokenExchangeFailed(responseString)`

### `CallbackServer.swift`

`final class CallbackServer: @unchecked Sendable`

Uses **POSIX sockets** (not `Network.framework`).

**`start() throws -> UInt16`** (synchronous):
- `socket(AF_INET, SOCK_STREAM, 0)`
- `setsockopt(SO_REUSEADDR)`
- `bind` to `127.0.0.1` port `0` (OS assigns free port)
- `listen(fd, 1)`
- `getsockname` to discover assigned port
- Returns the port

**`waitForCallback() async throws -> (code: String, state: String)`:**
- Uses `withCheckedThrowingContinuation`
- Runs `accept()` on `DispatchQueue.global(qos: .userInitiated)`
- Read up to 8191 bytes via `recv`
- Parse first line of HTTP request for `code` and `state` query params (via `URLComponents`)
- On error: send `HTTP/1.1 400 Bad Request\r\n\r\n`
- On success: send HTML success page and resume continuation
- Socket closed (cancel): resume with `.cancelled`

Success HTML response (exact):
```
HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n
<!DOCTYPE html><html><head><title>Done</title>
<style>body{font-family:system-ui;text-align:center;padding-top:80px;background:#f5f5f7}</style>
</head><body><h2>&#x2705; Login successful!</h2>
<p>You can close this tab and return to Claude Usage Monitor.</p></body></html>
```

**`cancel()`:** closes `serverFd`, sets it to `-1`

`send(_:_:)` helper: `s.withCString { Foundation.send(fd, ptr, strlen(ptr), 0) }`

`posixError(_:)` helper: `NSError(domain: NSPOSIXErrorDomain, code: Int(errno), ...)`

### `AnthropicService.swift`

`struct AnthropicService`

- `usageURL = "https://api.anthropic.com/api/oauth/usage"`
- `betaHeader = "oauth-2025-04-20"`

**`fetchUsage(tokens:) async throws -> [UsageLimit]`:**
1. If `tokens.isExpired`: refresh via `OAuthManager.shared.refresh`, save refreshed tokens to Keychain
2. GET request with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`
3. `timeoutInterval = 15`
4. 200 → parse; 401 → `.invalidToken`; 429 → `.rateLimited`; other → `.serverError(statusCode:)`

**Parsing:**
- `JSONDecoder` with `.convertFromSnakeCase`
- Custom ISO 8601 date decoder with `.withInternetDateTime | .withFractionalSeconds`
- Top-level struct: `{ fiveHour, sevenDay, sevenDaySonnet, sevenDayOpus }` — all optional `LimitInfo?`
- `LimitInfo`: `{ utilization: Double?, resetsAt: Date? }`
- Only emit a `UsageLimit` if both the field is non-nil and `utilization` is non-nil
- `percentage = Int(utilization.rounded())`
- Order: fiveHour, sevenDay, sevenDaySonnet, sevenDayOpus

```
enum AnthropicError: LocalizedError
  invalidToken   → "Session expired. Please log in again."
  invalidResponse → "Invalid response from server."
  rateLimited    → "Rate limited. Please try again later."
  serverError(Int) → "Server error: \(c)"
  decodingError  → "Failed to parse usage data."
```

### `StatusBarController.swift`

`class StatusBarController: ObservableObject`

**Properties:**
- `@Published var limits: [UsageLimit] = []`
- `@Published var refreshInterval: TimeInterval` — loaded from `UserDefaults["refreshInterval"]`, default `300`
- `private var usageMenuItems: [NSMenuItem] = []`
- `private var usageSeparator: NSMenuItem!`

**`setup()`:**
- `NSStatusBar.system.statusItem(withLength: .variableLength)`
- Button title: `"CC--"`, font: `NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)`
- Call `buildMenu()`
- If Keychain has tokens: `startAutoRefresh()` + `Task { await refreshUsage() }`
- Else: `showLoginWindow()`

**`buildMenu()`:**
- `menu.autoenablesItems = false`
- Add `usageSeparator` (usage items go above this)
- Add "Refresh Now" item, `keyEquivalent: "r"`, target self
- Add separator
- Add `NSHostingView(rootView: RefreshIntervalView(...))` in an `NSMenuItem`, frame `(0,0,240,58)`
  - The binding's setter saves to `UserDefaults["refreshInterval"]` and calls `startAutoRefresh()`
- Add separator
- Add "Log Out" item, no key equivalent, target self
- Add separator
- Add "Quit" item, `keyEquivalent: "q"`, action `NSApplication.terminate(_:)`
- Assign menu to `statusItem?.menu`

**`rebuildUsageItems(with:)`:** removes old items from menu, re-inserts new ones at `menu.index(of: usageSeparator)` in reversed order.

**`applyErrorToDisplay(_:)`:** if error is `.invalidToken`, call `showLoginWindow()`.

**`showLoginWindow()`:**
- Guard against duplicate windows (if exists, bring to front)
- Create `LoginView { ... }` with `onSuccess` closure that: closes window, nils `loginWindow`, calls `startAutoRefresh()`, fires `Task { await refreshUsage() }`
- `NSWindow(contentViewController: NSHostingController(rootView: view))`
- Title: `"Claude Usage Monitor"`, styleMask: `[.titled, .closable]`
- `setContentSize(NSSize(width: 420, height: 320))`
- `.center()`, `isReleasedWhenClosed = false`
- `makeKeyAndOrderFront(nil)`, `NSApp.activate(ignoringOtherApps: true)`

### `LoginView.swift`

SwiftUI `View`. States: `@State isLoggingIn = false`, `@State errorMessage: String?`. Prop: `let onSuccess: () -> Void`.

Layout (`VStack(spacing: 24)`, `padding(36)`, `frame(width: 420, height: 320)`):
1. `Image(systemName: "cpu")`, size 44, `.accentColor`
2. `Text("Claude Usage Monitor")`, `.title2`, `.semibold`
3. `Text("Log in with your Claude.ai account to monitor your plan usage limits.")`, `.subheadline`, `.secondary`, centered, `maxWidth: 300`
4. Error text (if set): `.caption`, `.red`, centered, `maxWidth: 320`
5. Button: when `isLoggingIn` shows `ProgressView().controlSize(.small)` + `"Waiting for browser…"`, else `"Log in with Claude.ai"`. Width `230`, `.borderedProminent`, `.large`, disabled when logging in.
6. Cancel button (only when `isLoggingIn`): `"Cancel"`, `.caption`, `.secondary`

`startLogin()`: sets `isLoggingIn = true`, calls `OAuthManager.shared.login()`, saves tokens via `KeychainManager.shared.saveTokens(_:)`, then calls `onSuccess()` on `MainActor`. On `.cancelled` error: reset `isLoggingIn`. On other errors: show `errorMessage`.

`cancel()`: `OAuthManager.shared.cancelLogin()`, `isLoggingIn = false`.

### `RefreshIntervalView.swift`

SwiftUI `View`. `@Binding var selectedInterval: TimeInterval`.

Options array (label, value): `("30s", 30)`, `("1m", 60)`, `("5m", 300)`, `("10m", 600)`.

Layout: `VStack(alignment: .leading, spacing: 4)`, `padding(.top, 6)`, `frame(width: 240)`.
- `Text("Refresh Interval")`, `system(size: 11)`, `.secondary`, `padding(.horizontal, 14)`
- `Picker("", selection: $selectedInterval)` with `.segmented` style, `.labelsHidden()`, `padding(.horizontal, 14)`, `padding(.bottom, 8)`

---

## Configuration Files

### `Info.plist`

Standard Xcode-generated plist. Required keys beyond defaults:
- `LSUIElement = true` (hides Dock icon)
- `NSPrincipalClass = NSApplication`
- All other values use `$(VARIABLE)` substitution

### `ClaudeUsageMonitor.entitlements`

Single entitlement only:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

---

## Icon Assets

`Assets.xcassets/Contents.json` — standard Xcode empty catalog JSON.

`Assets.xcassets/AppIcon.appiconset/Contents.json` — 10 entries mapping to **7 PNG files**:

| Filename             | Pixels    | Slots                               |
|----------------------|-----------|-------------------------------------|
| `icon_16x16.png`     | 16×16     | mac 16×16 @1x                       |
| `icon_32x32.png`     | 32×32     | mac 16×16 @2x **and** mac 32×32 @1x |
| `icon_64x64.png`     | 64×64     | mac 32×32 @2x                       |
| `icon_128x128.png`   | 128×128   | mac 128×128 @1x                     |
| `icon_256x256.png`   | 256×256   | mac 128×128 @2x **and** 256×256 @1x |
| `icon_512x512.png`   | 512×512   | mac 256×256 @2x **and** 512×512 @1x |
| `icon_1024x1024.png` | 1024×1024 | mac 512×512 @2x                     |

Generate from source image `claude_usage_monitor_icon.png`:
```bash
ICONSET="ClaudeUsageMonitor/Assets.xcassets/AppIcon.appiconset"
for S in 16 32 64 128 256 512 1024; do
  sips -z $S $S claude_usage_monitor_icon.png --out "$ICONSET/icon_${S}x${S}.png" > /dev/null
done
```

---

## Xcode Project (`project.pbxproj`)

Use the UUIDs below verbatim — they are referenced by the project file.

### File reference UUIDs

| File                          | FileRef UUID                 | BuildFile UUID               |
|-------------------------------|------------------------------|------------------------------|
| `AppDelegate.swift`           | `BB000001000000000000001A`   | `CC000001000000000000001A`   |
| `StatusBarController.swift`   | `BB000002000000000000001A`   | `CC000002000000000000001A`   |
| `AnthropicService.swift`      | `BB000003000000000000001A`   | `CC000003000000000000001A`   |
| `KeychainManager.swift`       | `BB000004000000000000001A`   | `CC000004000000000000001A`   |
| `LoginView.swift`             | `BB000005000000000000001A`   | `CC000005000000000000001A`   |
| `UsageData.swift`             | `BB000007000000000000001A`   | `CC000007000000000000001A`   |
| `ClaudeUsageMonitorApp.swift` | `BB000008000000000000001A`   | `CC000008000000000000001A`   |
| `Info.plist`                  | `BB000009000000000000001A`   | —                            |
| `ClaudeUsageMonitor.entitlements` | `BB00000A000000000000001A` | —                          |
| `ClaudeUsageMonitor.app`      | `BB00000B000000000000001A`   | —                            |
| `OAuthManager.swift`          | `BB00000C000000000000001A`   | `CC000009000000000000001A`   |
| `CallbackServer.swift`        | `BB00000D000000000000001A`   | `CC00000A000000000000001A`   |
| `OAuthTokens.swift`           | `BB00000E000000000000001A`   | `CC00000B000000000000001A`   |
| `OAuthError.swift`            | `56821D4B2F525A9B00C58E40`   | `56821D4C2F525A9B00C58E40`   |
| `RefreshIntervalView.swift`   | `56821D4E2F525A9B00C58E41`   | `56821D4D2F525A9B00C58E41`   |
| `Assets.xcassets`             | `56821D502F525A9B00C58E42`   | `56821D4F2F525A9B00C58E42`   |

### Group / target / config UUIDs

| Object                          | UUID                         |
|---------------------------------|------------------------------|
| Root group                      | `AA000002000000000000001A`   |
| ClaudeUsageMonitor group        | `AA000003000000000000001A`   |
| Products group                  | `AA000004000000000000001A`   |
| Native target                   | `AA000005000000000000001A`   |
| Project object                  | `AA000001000000000000001A`   |
| Sources build phase             | `DD000001000000000000001A`   |
| Frameworks build phase          | `DD000002000000000000001A`   |
| Resources build phase           | `DD000003000000000000001A`   |
| Project config list             | `FF000001000000000000001A`   |
| Target config list              | `FF000002000000000000001A`   |
| Project Debug config            | `EE000001000000000000001A`   |
| Project Release config          | `EE000002000000000000001A`   |
| Target Debug config             | `EE000003000000000000001A`   |
| Target Release config           | `EE000004000000000000001A`   |

### Key build settings

| Setting                          | Value                          |
|----------------------------------|--------------------------------|
| `PRODUCT_BUNDLE_IDENTIFIER`      | `com.claudeusagemonitor.app`   |
| `MARKETING_VERSION`              | `1.0`                          |
| `CURRENT_PROJECT_VERSION`        | `1`                            |
| `MACOSX_DEPLOYMENT_TARGET`       | `13.0`                         |
| `SWIFT_VERSION`                  | `5.0`                          |
| `ENABLE_HARDENED_RUNTIME`        | `YES`                          |
| `CODE_SIGN_STYLE`                | `Automatic`                    |
| `DEVELOPMENT_TEAM`               | `""` (empty)                   |
| `ASSETCATALOG_COMPILER_APPICON_NAME` | `AppIcon`                  |
| `GENERATE_INFOPLIST_FILE`        | `NO`                           |
| `INFOPLIST_FILE`                 | `ClaudeUsageMonitor/Info.plist`|
| `CODE_SIGN_ENTITLEMENTS`         | `ClaudeUsageMonitor/ClaudeUsageMonitor.entitlements` |
| `compatibilityVersion`           | `"Xcode 14.0"`                 |
| `objectVersion`                  | `56`                           |
| `CreatedOnToolsVersion`          | `16.0`                         |
| Debug `SWIFT_OPTIMIZATION_LEVEL` | `"-Onone"`                     |
| Release `SWIFT_COMPILATION_MODE` | `wholemodule`                  |

Sources build phase compile order:
`ClaudeUsageMonitorApp`, `AppDelegate`, `StatusBarController`, `AnthropicService`, `KeychainManager`, `LoginView`, `UsageData`, `OAuthManager`, `CallbackServer`, `OAuthError`, `RefreshIntervalView`, `OAuthTokens`

---

## Distribution Script (`build_dmg.sh`)

Builds a styled DMG for each architecture (arm64, x86_64).

```
ICON_SRC = "$(pwd)/claude_usage_monitor_icon.png"
```

Per-arch process:
1. `xcodebuild archive` with `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES OTHER_CODE_SIGN_FLAGS="--deep" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES` piped through `xcpretty 2>/dev/null || true`
2. Find `.app` in archive Products
3. Create staging dir with app + `/Applications` symlink
4. Generate `.icns` from source PNG using `sips` (10 sizes into iconset) + `iconutil`; copy into `app/Contents/Resources/AppIcon.icns`; run `/usr/bin/SetFile -a C` (ignore error)
5. `hdiutil create` UDRW 200m
6. `hdiutil attach` quiet, no autoopen
7. AppleScript Finder styling: icon view, no toolbar, no statusbar, bounds `{400, 200, 940, 540}`, icon size 100, app icon at `{130, 200}`, Applications link at `{410, 200}`
8. Detach, convert to UDZO zlib-level=9
9. Output to `dist/ClaudeUsageMonitor-{arch}.dmg`
