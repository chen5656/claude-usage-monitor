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
├── ClaudeUsageMonitor/                   ← app target folder
│   ├── ClaudeUsageMonitorApp.swift
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   ├── AnthropicService.swift
│   ├── KeychainManager.swift
│   ├── LoginView.swift
│   ├── UsageData.swift
│   ├── OAuthManager.swift
│   ├── CallbackServer.swift
│   ├── OAuthTokens.swift
│   ├── OAuthError.swift
│   ├── RefreshIntervalView.swift
│   ├── Info.plist
│   ├── ClaudeUsageMonitor.entitlements
│   └── Assets.xcassets/
│       ├── Contents.json
│       └── AppIcon.appiconset/
│           ├── Contents.json
│           └── [7 icon PNGs — see §Icon Assets]
└── ClaudeUsageMonitorTests/              ← test target folder
    ├── UsageDataTests.swift
    ├── OAuthTokensTests.swift
    ├── OAuthErrorTests.swift
    ├── AnthropicErrorTests.swift
    ├── AnthropicServiceParsingTests.swift
    ├── KeychainManagerTests.swift
    ├── CallbackServerTests.swift
    ├── OAuthManagerTests.swift
    └── StatusBarControllerTests.swift
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
5. Build `redirectURI = "http://localhost:\(port)/callback"` — **must use `localhost`, never `127.0.0.1`**, Anthropic's OAuth client rejects `127.0.0.1`
6. Build authorize URL with query items (in this order): `code=true`, `client_id`, `response_type=code`, `redirect_uri`, `scope` (space-joined), `code_challenge`, `code_challenge_method=S256`, `state`
7. Open URL via `NSWorkspace.shared.open(_:)` on `MainActor`; throw `.browserOpenFailed` if returns false
8. `await server.waitForCallback()` → `(code, returnedState)`
9. Validate state == returnedState; throw `.stateMismatch` if not
10. Call `exchangeCode` passing `state` in the body (Anthropic requires it)

**`refresh(_ tokens:) async throws -> OAuthTokens`:**
- POST body: `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope` (space-joined)

**`cancelLogin()`:** calls `callbackServer?.cancel()` and nils it

**Testable static helpers** (internal, not private — exposed for unit tests):

- `static func base64URLEncode(_ data: Data) -> String` — base64-encodes `data`, then replaces `+`→`-`, `/`→`_`, strips `=`. Used internally for both verifier and challenge.
- `static func codeChallenge(for verifier: String) -> String` — SHA256-hashes the UTF-8 bytes of `verifier` (via CryptoKit `SHA256.hash`), then calls `base64URLEncode`. Called from `login()`.

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

**Parsing** — factored into a **testable static method**:

`static func parseLimits(from data: Data) throws -> [UsageLimit]`

- `JSONDecoder` with `.convertFromSnakeCase`
- Custom ISO 8601 date decoder with `.withInternetDateTime | .withFractionalSeconds`
- Top-level struct: `{ fiveHour, sevenDay, sevenDaySonnet, sevenDayOpus }` — all optional `LimitInfo?`
- `LimitInfo`: `{ utilization: Double?, resetsAt: Date? }`
- Only emit a `UsageLimit` if the field is non-nil and `utilization` is non-nil
- `percentage = Int(utilization.rounded())`
- Order: fiveHour, sevenDay, sevenDaySonnet, sevenDayOpus

`fetchUsage` calls `AnthropicService.parseLimits(from: data)` after confirming 200 status instead of inlining the parsing logic.

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

**Testable static helpers** (internal, not private — exposed for unit tests):

- `static func formatResetString(secs: TimeInterval?) -> String` — returns the reset suffix used in usage rows.
  - `nil` → `""` (no reset info)
  - `<= 0` → `" · resetting…"`
  - `> 86400` → `" · resets in Xd Yh Zm"`
  - `> 3600` → `" · resets in Xh Ym"`
  - else → `" · resets in Xm"`

- `static func statusTitle(for limits: [UsageLimit]) -> String` — returns the status bar button label.
  - Prefers the `.fiveHour` limit; falls back to `limits.first`; returns `"CC--"` if empty
  - Format: `"CC-\(percentage)%"`

Both are called by the existing menu-building and refresh logic.

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

## Xcode Project

Create a standard macOS App Xcode project named `ClaudeUsageMonitor`. All 12 Swift files and `Assets.xcassets` belong to the `ClaudeUsageMonitor` app target. Add one XCTest bundle target named `ClaudeUsageMonitorTests` with the 9 test files listed in the project structure above.

### Test target build settings

| Setting | Value |
|---|---|
| `PRODUCT_NAME` | `ClaudeUsageMonitorTests` |
| `BUNDLE_LOADER` | `$(TEST_HOST)` |
| `TEST_HOST` | `$(BUILT_PRODUCTS_DIR)/ClaudeUsageMonitor.app/Contents/MacOS/ClaudeUsageMonitor` |
| `MACOSX_DEPLOYMENT_TARGET` | `13.0` |
| `SWIFT_VERSION` | `5.0` |
| `CODE_SIGN_STYLE` | `Automatic` |
| `DEVELOPMENT_TEAM` | `""` (empty) |

The test target must declare a dependency on the `ClaudeUsageMonitor` app target in `project.pbxproj`.

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

---

## Output After Generation

After creating all project files, generate two additional files in the project root:

### `README.md`

Include:
- What the app does (one paragraph)
- **How to run:** open `ClaudeUsageMonitor.xcodeproj` in Xcode and press Run, or build from the command line:
  ```bash
  xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor \
    -configuration Debug build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
- **How to update the app** (re-run with the same prompt): use `prompt/mac.md` as the prompt
- **How to create DMG distributables**: run `./build_dmg.sh` (requires `claude_usage_monitor_icon.png` in the project root)
- Features list (menu bar display, OAuth login, auto-refresh, Keychain storage)
- Requirements (macOS 13+, Xcode 16+)

### `CHANGES.md`

A plain summary of everything that was generated in this session: list each file created, its purpose in one line, and any non-obvious decisions made (e.g. why POSIX sockets instead of Network.framework, why `localhost` in redirect URI).

---

## Testing

The 9 test files below must be created verbatim inside `ClaudeUsageMonitorTests/`. Run them with:

```bash
xcodebuild test -project ClaudeUsageMonitor.xcodeproj \
  -scheme ClaudeUsageMonitorTests \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```

---

### `UsageDataTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class UsageDataTests: XCTestCase {

    // MARK: RateLimitType raw values

    func testRawValueFiveHour()       { XCTAssertEqual(RateLimitType.fiveHour.rawValue,      "five_hour") }
    func testRawValueSevenDay()       { XCTAssertEqual(RateLimitType.sevenDay.rawValue,       "seven_day") }
    func testRawValueSevenDaySonnet() { XCTAssertEqual(RateLimitType.sevenDaySonnet.rawValue, "seven_day_sonnet") }
    func testRawValueSevenDayOpus()   { XCTAssertEqual(RateLimitType.sevenDayOpus.rawValue,   "seven_day_opus") }
    func testRawValueOverage()        { XCTAssertEqual(RateLimitType.overage.rawValue,        "overage") }
    func testRawValueUnknown()        { XCTAssertEqual(RateLimitType.unknown.rawValue,        "") }

    // MARK: RateLimitType displayName

    func testDisplayNameFiveHour()       { XCTAssertEqual(RateLimitType.fiveHour.displayName,      "Session") }
    func testDisplayNameSevenDay()       { XCTAssertEqual(RateLimitType.sevenDay.displayName,       "Weekly") }
    func testDisplayNameSevenDaySonnet() { XCTAssertEqual(RateLimitType.sevenDaySonnet.displayName, "Sonnet Weekly") }
    func testDisplayNameSevenDayOpus()   { XCTAssertEqual(RateLimitType.sevenDayOpus.displayName,   "Opus Weekly") }
    func testDisplayNameOverage()        { XCTAssertEqual(RateLimitType.overage.displayName,        "Extra") }
    func testDisplayNameUnknown()        { XCTAssertEqual(RateLimitType.unknown.displayName,        "Usage") }

    // MARK: UsageLimit

    func testUsageLimitStoresValues() {
        let d = Date()
        let l = UsageLimit(type: .fiveHour, percentage: 42, resetsAt: d)
        XCTAssertEqual(l.type, .fiveHour)
        XCTAssertEqual(l.percentage, 42)
        XCTAssertEqual(l.resetsAt, d)
    }

    func testUsageLimitNilResetsAt() {
        let l = UsageLimit(type: .sevenDay, percentage: 0, resetsAt: nil)
        XCTAssertNil(l.resetsAt)
    }
}
```

---

### `OAuthTokensTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class OAuthTokensTests: XCTestCase {

    func testNotExpiredWhenFarFuture() {
        let t = OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600))
        XCTAssertFalse(t.isExpired)
    }

    func testExpiredWhenWithin5MinuteBuffer() {
        // isExpired: Date().addingTimeInterval(300) >= expiresAt → true when expiresAt < now+300
        let t = OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(200))
        XCTAssertTrue(t.isExpired)
    }

    func testExpiredWhenPast() {
        let t = OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(-1))
        XCTAssertTrue(t.isExpired)
    }

    func testExactlyAtBufferBoundaryIsExpired() {
        // expiresAt == now+300 → Date()+300 >= expiresAt is true
        let t = OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(300))
        XCTAssertTrue(t.isExpired)
    }

    func testCodableRoundTrip() throws {
        let original = OAuthTokens(accessToken: "tok", refreshToken: "ref",
                                   expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)
        XCTAssertEqual(decoded.accessToken, original.accessToken)
        XCTAssertEqual(decoded.refreshToken, original.refreshToken)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970,
                       original.expiresAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testOptionalRefreshTokenNilRoundTrip() throws {
        let t = OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: Date())
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)
        XCTAssertNil(decoded.refreshToken)
    }
}
```

---

### `OAuthErrorTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class OAuthErrorTests: XCTestCase {

    func testCallbackFailed() {
        XCTAssertEqual(OAuthError.callbackFailed.errorDescription,
                       "OAuth callback failed.")
    }

    func testStateMismatch() {
        XCTAssertEqual(OAuthError.stateMismatch.errorDescription,
                       "Security check failed. Please try again.")
    }

    func testTokenExchangeFailed() {
        XCTAssertEqual(OAuthError.tokenExchangeFailed("bad response").errorDescription,
                       "Token exchange failed: bad response")
    }

    func testNoToken() {
        XCTAssertEqual(OAuthError.noToken.errorDescription, "Not logged in.")
    }

    func testCancelled() {
        XCTAssertEqual(OAuthError.cancelled.errorDescription, "Login cancelled.")
    }

    func testBrowserOpenFailed() {
        XCTAssertEqual(OAuthError.browserOpenFailed.errorDescription,
                       "Could not open browser. Try manually opening the login URL.")
    }
}
```

---

### `AnthropicErrorTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class AnthropicErrorTests: XCTestCase {

    func testInvalidToken() {
        XCTAssertEqual(AnthropicError.invalidToken.errorDescription,
                       "Session expired. Please log in again.")
    }

    func testInvalidResponse() {
        XCTAssertEqual(AnthropicError.invalidResponse.errorDescription,
                       "Invalid response from server.")
    }

    func testRateLimited() {
        XCTAssertEqual(AnthropicError.rateLimited.errorDescription,
                       "Rate limited. Please try again later.")
    }

    func testServerError() {
        XCTAssertEqual(AnthropicError.serverError(503).errorDescription, "Server error: 503")
    }

    func testDecodingError() {
        XCTAssertEqual(AnthropicError.decodingError.errorDescription,
                       "Failed to parse usage data.")
    }
}
```

---

### `AnthropicServiceParsingTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class AnthropicServiceParsingTests: XCTestCase {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testParseAllFourLimits() throws {
        let data = json("""
        {
            "five_hour":        { "utilization": 42.0, "resets_at": "2025-01-01T12:00:00Z" },
            "seven_day":        { "utilization": 15.0, "resets_at": "2025-01-07T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 80.0, "resets_at": null },
            "seven_day_opus":   { "utilization":  5.0, "resets_at": null }
        }
        """)
        let limits = try AnthropicService.parseLimits(from: data)
        XCTAssertEqual(limits.count, 4)
        XCTAssertEqual(limits[0].type, .fiveHour);       XCTAssertEqual(limits[0].percentage, 42)
        XCTAssertEqual(limits[1].type, .sevenDay);       XCTAssertEqual(limits[1].percentage, 15)
        XCTAssertEqual(limits[2].type, .sevenDaySonnet); XCTAssertEqual(limits[2].percentage, 80)
        XCTAssertEqual(limits[3].type, .sevenDayOpus);   XCTAssertEqual(limits[3].percentage,  5)
    }

    func testParseOnlyFiveHour() throws {
        let data = json(#"{ "five_hour": { "utilization": 55.0, "resets_at": null } }"#)
        let limits = try AnthropicService.parseLimits(from: data)
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].type, .fiveHour)
        XCTAssertEqual(limits[0].percentage, 55)
    }

    func testSkipsFieldWithNilUtilization() throws {
        let data = json("""
        {
            "five_hour": { "resets_at": null },
            "seven_day": { "utilization": 30.0, "resets_at": null }
        }
        """)
        let limits = try AnthropicService.parseLimits(from: data)
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].type, .sevenDay)
    }

    func testEmptyResponseProducesNoLimits() throws {
        XCTAssertTrue(try AnthropicService.parseLimits(from: json("{}")).isEmpty)
    }

    func testRoundingUp() throws {
        let limits = try AnthropicService.parseLimits(
            from: json(#"{ "five_hour": { "utilization": 42.5, "resets_at": null } }"#))
        XCTAssertEqual(limits[0].percentage, 43)
    }

    func testRoundingDown() throws {
        let limits = try AnthropicService.parseLimits(
            from: json(#"{ "five_hour": { "utilization": 42.4, "resets_at": null } }"#))
        XCTAssertEqual(limits[0].percentage, 42)
    }

    func testResetsAtParsedCorrectly() throws {
        let limits = try AnthropicService.parseLimits(
            from: json(#"{ "five_hour": { "utilization": 50.0, "resets_at": "2025-06-15T08:30:00Z" } }"#))
        XCTAssertNotNil(limits[0].resetsAt)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: limits[0].resetsAt!)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFractionalSecondsDate() throws {
        let limits = try AnthropicService.parseLimits(
            from: json(#"{ "five_hour": { "utilization": 50.0, "resets_at": "2025-06-15T08:30:00.000Z" } }"#))
        XCTAssertNotNil(limits[0].resetsAt)
    }

    func testOutputOrderIsAlwaysFiveHourFirst() throws {
        // JSON keys in reverse order — output must follow the canonical fiveHour→sevenDay→sonnet→opus order
        let data = json("""
        {
            "seven_day_opus":   { "utilization": 1.0, "resets_at": null },
            "seven_day_sonnet": { "utilization": 2.0, "resets_at": null },
            "seven_day":        { "utilization": 3.0, "resets_at": null },
            "five_hour":        { "utilization": 4.0, "resets_at": null }
        }
        """)
        let limits = try AnthropicService.parseLimits(from: data)
        XCTAssertEqual(limits.map(\.type), [.fiveHour, .sevenDay, .sevenDaySonnet, .sevenDayOpus])
    }
}
```

---

### `KeychainManagerTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class KeychainManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainManager.shared.deleteTokens()
    }

    override func tearDown() {
        KeychainManager.shared.deleteTokens()
        super.tearDown()
    }

    private func makeTokens(access: String = "tok", refresh: String? = "ref") -> OAuthTokens {
        OAuthTokens(accessToken: access, refreshToken: refresh,
                    expiresAt: Date().addingTimeInterval(3600))
    }

    func testSaveReturnsTrueOnSuccess() {
        XCTAssertTrue(KeychainManager.shared.saveTokens(makeTokens()))
    }

    func testGetReturnsNilWhenEmpty() {
        XCTAssertNil(KeychainManager.shared.getTokens())
    }

    func testSaveAndRetrieveAccessToken() {
        _ = KeychainManager.shared.saveTokens(makeTokens(access: "access123", refresh: "refresh456"))
        XCTAssertEqual(KeychainManager.shared.getTokens()?.accessToken, "access123")
    }

    func testSaveAndRetrieveRefreshToken() {
        _ = KeychainManager.shared.saveTokens(makeTokens(access: "a", refresh: "refresh456"))
        XCTAssertEqual(KeychainManager.shared.getTokens()?.refreshToken, "refresh456")
    }

    func testSaveWithNilRefreshToken() {
        _ = KeychainManager.shared.saveTokens(makeTokens(refresh: nil))
        XCTAssertNil(KeychainManager.shared.getTokens()?.refreshToken)
    }

    func testDeleteRemovesToken() {
        _ = KeychainManager.shared.saveTokens(makeTokens())
        KeychainManager.shared.deleteTokens()
        XCTAssertNil(KeychainManager.shared.getTokens())
    }

    func testSaveOverwritesPreviousEntry() {
        _ = KeychainManager.shared.saveTokens(makeTokens(access: "first"))
        _ = KeychainManager.shared.saveTokens(makeTokens(access: "second"))
        XCTAssertEqual(KeychainManager.shared.getTokens()?.accessToken, "second")
    }

    func testDeleteWhenEmptyDoesNotCrash() {
        // setUp already called deleteTokens; calling again must not crash
        KeychainManager.shared.deleteTokens()
    }
}
```

---

### `CallbackServerTests.swift`

```swift
import XCTest
import Darwin
@testable import ClaudeUsageMonitor

final class CallbackServerTests: XCTestCase {

    // MARK: Helper — sends a raw HTTP GET using POSIX sockets

    private func sendRawHTTP(port: UInt16, path: String) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let req = "GET \(path) HTTP/1.1\r\nHost: localhost\r\n\r\n"
        req.withCString { _ = Foundation.send(fd, $0, strlen($0), 0) }
    }

    // MARK: Tests

    func testStartReturnsValidPort() throws {
        let server = CallbackServer()
        let port = try server.start()
        XCTAssertGreaterThan(port, 0)
        server.cancel()
    }

    func testCancelAfterStartDoesNotCrash() throws {
        let server = CallbackServer()
        _ = try server.start()
        server.cancel() // must not throw or crash
    }

    func testWaitForCallbackParsesCodeAndState() async throws {
        let server = CallbackServer()
        let port = try server.start()
        Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            self.sendRawHTTP(port: port, path: "/callback?code=authCode123&state=stateXYZ")
        }
        let (code, state) = try await server.waitForCallback()
        XCTAssertEqual(code, "authCode123")
        XCTAssertEqual(state, "stateXYZ")
    }

    func testWaitForCallbackIgnoresExtraParams() async throws {
        let server = CallbackServer()
        let port = try server.start()
        Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            self.sendRawHTTP(port: port,
                             path: "/callback?foo=bar&code=mycode&state=mystate&extra=ignored")
        }
        let (code, state) = try await server.waitForCallback()
        XCTAssertEqual(code, "mycode")
        XCTAssertEqual(state, "mystate")
    }

    func testCancelCausesWaitToThrowCancelled() async throws {
        let server = CallbackServer()
        _ = try server.start()
        Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            server.cancel()
        }
        do {
            _ = try await server.waitForCallback()
            XCTFail("Expected OAuthError.cancelled to be thrown")
        } catch let e as OAuthError {
            guard case .cancelled = e else {
                XCTFail("Expected .cancelled, got \(e)")
                return
            }
        }
    }
}
```

---

### `OAuthManagerTests.swift`

```swift
import XCTest
import CryptoKit
@testable import ClaudeUsageMonitor

final class OAuthManagerTests: XCTestCase {

    // MARK: base64URLEncode

    func testBase64URLEncodeNoPlusSign() {
        // Encode all 256 byte values and verify no '+' appears
        let allBytes = Data((0...255).map { UInt8($0) })
        XCTAssertFalse(OAuthManager.base64URLEncode(allBytes).contains("+"))
    }

    func testBase64URLEncodeNoSlash() {
        let allBytes = Data((0...255).map { UInt8($0) })
        XCTAssertFalse(OAuthManager.base64URLEncode(allBytes).contains("/"))
    }

    func testBase64URLEncodeNoPadding() {
        let allBytes = Data((0...255).map { UInt8($0) })
        XCTAssertFalse(OAuthManager.base64URLEncode(allBytes).contains("="))
    }

    func testBase64URLEncodeKnownValue() {
        // 0xFB → standard base64 "+w==" → base64url "-w"
        XCTAssertEqual(OAuthManager.base64URLEncode(Data([0xFB])), "-w")
    }

    func testBase64URLEncodeRandomBytesAreURLSafe() {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, 64, &bytes)
        let result = OAuthManager.base64URLEncode(Data(bytes))
        XCTAssertFalse(result.contains("+"))
        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.contains("="))
    }

    // MARK: codeChallenge

    func testCodeChallengeMatchesSHA256() {
        let verifier = "test-verifier-string"
        let expected = OAuthManager.base64URLEncode(
            Data(SHA256.hash(data: Data(verifier.utf8)))
        )
        XCTAssertEqual(OAuthManager.codeChallenge(for: verifier), expected)
    }

    func testCodeChallengeIsURLSafe() {
        let challenge = OAuthManager.codeChallenge(for: "any verifier 12345")
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    func testCodeChallengeLength() {
        // SHA256 → 32 bytes → base64url (no padding) → 43 chars
        XCTAssertEqual(OAuthManager.codeChallenge(for: "verifier").count, 43)
    }

    func testCodeChallengeIsDeterministic() {
        let v = "same-verifier"
        XCTAssertEqual(OAuthManager.codeChallenge(for: v), OAuthManager.codeChallenge(for: v))
    }

    // MARK: cancelLogin

    func testCancelLoginWhenIdleDoesNotCrash() {
        OAuthManager.shared.cancelLogin()
    }
}
```

---

### `StatusBarControllerTests.swift`

```swift
import XCTest
@testable import ClaudeUsageMonitor

final class StatusBarControllerTests: XCTestCase {

    // MARK: formatResetString

    func testNilSecs() {
        XCTAssertEqual(StatusBarController.formatResetString(secs: nil), "")
    }

    func testZeroSecsIsResetting() {
        XCTAssertEqual(StatusBarController.formatResetString(secs: 0), " · resetting…")
    }

    func testNegativeSecsIsResetting() {
        XCTAssertEqual(StatusBarController.formatResetString(secs: -60), " · resetting…")
    }

    func testMinutesOnly() {
        XCTAssertEqual(StatusBarController.formatResetString(secs: 150), " · resets in 2m")
    }

    func testLessThanOneMinute() {
        // 45 seconds → 0m
        XCTAssertEqual(StatusBarController.formatResetString(secs: 45), " · resets in 0m")
    }

    func testExactlyOneHour() {
        XCTAssertEqual(StatusBarController.formatResetString(secs: 3600), " · resets in 1h 0m")
    }

    func testHoursAndMinutes() {
        // 2h 30m = 9000s
        XCTAssertEqual(StatusBarController.formatResetString(secs: 9000), " · resets in 2h 30m")
    }

    func testExactlyOneDay() {
        XCTAssertEqual(StatusBarController.formatResetString(secs: 86400), " · resets in 1d 0h 0m")
    }

    func testDaysHoursMinutes() {
        // 5d 3h 2m = 5*86400 + 3*3600 + 2*60 = 442920s
        XCTAssertEqual(StatusBarController.formatResetString(secs: 442920), " · resets in 5d 3h 2m")
    }

    // MARK: statusTitle

    func testStatusTitlePrefersFiveHour() {
        let limits = [
            UsageLimit(type: .fiveHour, percentage: 42, resetsAt: nil),
            UsageLimit(type: .sevenDay,  percentage: 15, resetsAt: nil)
        ]
        XCTAssertEqual(StatusBarController.statusTitle(for: limits), "CC-42%")
    }

    func testStatusTitleFallsBackToFirstLimit() {
        let limits = [UsageLimit(type: .sevenDay, percentage: 33, resetsAt: nil)]
        XCTAssertEqual(StatusBarController.statusTitle(for: limits), "CC-33%")
    }

    func testStatusTitleEmptyLimitsReturnsDash() {
        XCTAssertEqual(StatusBarController.statusTitle(for: []), "CC--")
    }

    func testStatusTitle100Percent() {
        let limits = [UsageLimit(type: .fiveHour, percentage: 100, resetsAt: nil)]
        XCTAssertEqual(StatusBarController.statusTitle(for: limits), "CC-100%")
    }

    func testStatusTitle0Percent() {
        let limits = [UsageLimit(type: .fiveHour, percentage: 0, resetsAt: nil)]
        XCTAssertEqual(StatusBarController.statusTitle(for: limits), "CC-0%")
    }

    func testStatusTitleSkipsNonFiveHourToFindFiveHour() {
        // fiveHour not first in array — still must be selected
        let limits = [
            UsageLimit(type: .sevenDay,  percentage: 99, resetsAt: nil),
            UsageLimit(type: .fiveHour,  percentage: 7,  resetsAt: nil)
        ]
        XCTAssertEqual(StatusBarController.statusTitle(for: limits), "CC-7%")
    }
}
```
