# Claude Usage Monitor

Agent runbook for `claude-usage-monitor` (macOS app).

## What This App Does
- Shows Claude usage limits in the macOS menu bar.
- Displays percentage + reset window for available limits.
- Uses Claude OAuth login and stores session tokens in Keychain.

## Build (Agent Steps)
Requirements:
- macOS 13+
- Xcode command line tools / `xcodebuild`

Build command:
```bash
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected result:
- Build succeeds with no compile errors.

Optional packaging:
```bash
./build_dmg.sh
```
Creates:
- `dist/ClaudeUsageMonitor-arm64.dmg`
- `dist/ClaudeUsageMonitor-x86_64.dmg`

## Install (Agent/User Steps)
From DMG:
1. Open the generated `.dmg`.
2. Drag `Claude Usage Monitor.app` to `Applications`.
3. Launch app from `Applications`.

From build output:
1. Locate built `.app` in Xcode DerivedData/build output.
2. Move app to `Applications`.
3. Launch app.

## Use (Agent/User Steps)
1. Launch app.
2. If not logged in, click `Log in with Claude.ai`.
3. Browser opens Claude OAuth page.
4. After success, app updates menu bar text like `CC-42%`.
5. Open menu bar item to:
   - Refresh now
   - Change auto-refresh interval
   - Use quick-copy command shortcuts
   - Log out

## Keychain Password Prompts

On first launch (and occasionally after token refresh), macOS may show a prompt:
> "Claude Usage Monitor wants to use your confidential information stored in ... in your keychain."

**Why it happens:** The app is distributed unsigned. macOS Keychain ties trusted access to an app's code signature. Without a stable signature, macOS cannot remember that it has already granted access and prompts again each session.

**How many prompts to expect:**
- Fresh (non-expired) token: 1 prompt on startup
- Expired token that needs refresh: up to 2 prompts (1 read + 1 write)

**How to avoid it entirely:** Click **Always Allow** on the first prompt. If macOS still prompts repeatedly, it means the app binary has changed (e.g. rebuilt from source) and its identity no longer matches the stored grant. Click **Always Allow** once more after each rebuild.

For a permanent fix, build and sign with an Apple Developer certificate:
```bash
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor \
  -configuration Release build \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```
A signed build is trusted by Keychain indefinitely and will never prompt again.

## Why It Is Safe/Secure
- OAuth tokens are stored only in macOS Keychain (`KeychainManager`).
- Tokens are not written to plaintext files.
- OAuth uses PKCE with `code_verifier` and `code_challenge`.
- OAuth callback is local loopback (`http://localhost:<port>/callback`).
- App only calls Anthropic OAuth/token and usage endpoints.

Security-relevant files:
- `ClaudeUsageMonitor/KeychainManager.swift`
- `ClaudeUsageMonitor/OAuthManager.swift`
- `ClaudeUsageMonitor/CallbackServer.swift`

## How Data Is Fetched
Flow:
1. `StatusBarController` starts refresh cycle.
2. `AnthropicService.fetchUsage()` checks token expiry.
3. If expired, `OAuthManager.refresh()` refreshes token.
4. App calls `GET https://api.anthropic.com/api/oauth/usage` with bearer token.
5. Parses usage keys (`five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus`).
6. Updates menu bar title and menu details.

Data-fetch files:
- `ClaudeUsageMonitor/StatusBarController.swift`
- `ClaudeUsageMonitor/AnthropicService.swift`
- `ClaudeUsageMonitor/UsageData.swift`

## Agent Guardrails
- Keep token storage in Keychain only.
- Do not add plaintext token logging.
- Preserve OAuth callback + PKCE behavior.
- Preserve usage parsing for current supported keys.
- Keep menu bar app behavior (accessory app, no Dock icon).
