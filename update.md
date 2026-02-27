The project is built and working. 

  How it works:
  1. First launch shows a login window to enter and validate the Anthropic API key (stored in Keychain)
  2. Menu bar shows CC-42% — token usage within the current rate-limit window
  3. Dropdown shows: usage %, token counts, reset time, Refresh Now, Settings, Quit
  4. Auto-refreshes every 10 min (configurable: 30s / 1m / 5m / 10m)
  5. On error: shows --% ⚠ and never crashes

  Build command:
  xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor \
    -configuration Debug build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

  Open ClaudeUsageMonitor.xcodeproj in Xcode to run/archive and distribute.

