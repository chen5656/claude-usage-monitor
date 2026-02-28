xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor -destination "generic/platform=macOS" build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES 2>&1 | tail -20

./build_dmg.sh 2>&1