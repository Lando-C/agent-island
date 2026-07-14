# Browser Web Bridge

The browser bridge is optional. It lets an unpacked Chrome/Chromium extension
send minimal status frames for ChatGPT, Claude, and Codex web pages to the Agent
Island app running on the same Mac.

## Trust boundary

- The app listens only on `127.0.0.1:27583`.
- Every request requires a random per-install bearer token stored locally at
  `~/.agent-island/web-bridge-token` with owner-only permissions.
- The extension sends only engine name, page-derived session key, title, phase,
  and URL path. It does not send page text, prompts, replies, tool input, or
  cookies.
- Web-page state is a DOM heuristic. Agent Island labels it `网页桥接`; it is
  not equivalent to a CLI Hook or an app transcript confirmation.

## Install the extension

1. Start Agent Island and open **Settings > Diagnostics**.
2. Click **Copy Web Bridge Token**.
3. Open `chrome://extensions`, enable Developer mode, and choose **Load
   unpacked**.
4. Select `extensions/agent-island-web-bridge` from this checkout, or the
   `WebBridgeExtension` folder packaged inside the app bundle.
5. Open the extension's **Options**, paste the token, and save.
6. Open a supported ChatGPT, Claude, or Codex page. The Browser Web Bridge row
   in Diagnostics shows its last successful event.

This is intentionally an unpacked developer extension until it is reviewed and
published through the relevant browser extension stores. It can be removed at
any time from the browser's extension manager.
