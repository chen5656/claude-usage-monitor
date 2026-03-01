# Privacy Policy

**Last Updated: March 1, 2026**

This Privacy Policy describes how **Claude Usage Monitor** ("the App") handles your data. The App is a utility designed for macOS that displays your Claude.ai usage limits in the menu bar.

## 1. Data Collection and Usage

### Personal Information
The App **does not collect, store, or transmit any personal information**. We do not collect your name, email address, physical address, or any other personally identifiable information (PII).

### Authentication Data (OAuth Tokens)
To function, the App requires access to your Claude.ai account via OAuth. 
- **Storage**: When you log in, the App receives authentication tokens (access and refresh tokens) from Anthropic. These tokens are stored securely and exclusively in your local **macOS Keychain** using the `KeychainManager`.
- **Usage**: These tokens are used solely to authenticate requests to the Anthropic API (`api.anthropic.com`) to retrieve your usage limits.
- **Exposure**: Tokens are never logged in plaintext, never sent to any server other than Anthropic's official API, and never shared with third parties.

### Usage Data
The App periodically fetches your current usage limits (e.g., remaining message count, reset time) from Anthropic. 
- This data is used only to update the display in your macOS menu bar. 
- This data is not stored permanently or shared with any third party.

## 2. Third-Party Services

The App communicates directly with **Anthropic, PBC**. Your use of Claude.ai is subject to Anthropic's own privacy policy and terms of service. The App does not integrate any other third-party analytics, advertising, or tracking libraries.

## 3. Data Retention and Deletion

- **Local Data**: Authentication tokens remain in your macOS Keychain until you explicitly log out within the App or manually delete the Keychain entry.
- **Logging Out**: Selecting "Log Out" in the App menu will immediately delete the stored tokens from your macOS Keychain.

## 4. Security

We take the security of your authentication data seriously. The App uses standard security practices, including:
- **Keychain Storage**: Leveraging macOS's built-in secure storage for sensitive tokens.
- **OAuth with PKCE**: Implementing Proof Key for Code Exchange (PKCE) to ensure secure authentication flows.
- **Local Loopback**: Using a local server only for the OAuth callback process.

## 5. Changes to This Policy

We may update our Privacy Policy from time to time. Any changes will be posted on this page with an updated "Last Updated" date.

## 6. Contact Information

If you have any questions, suggestions, or wish to report an issue regarding this Privacy Policy or the App, please visit our GitHub repository:

**Chen5656**  
GitHub Issues: [https://github.com/chen5656/claude-usage-monitor/issues](https://github.com/chen5656/claude-usage-monitor/issues)
