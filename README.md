# Grok Desktop

Native macOS SwiftUI client for [Grok Build](https://x.ai/build). The window follows [grok.com](https://grok.com/) layout and settings; the engine is your local `grok` CLI over ACP.

**This entire app was built with [Grok Build](https://x.ai/build) on Grok 4.6** — every screen, the ACP client, settings, and release scripts. No other coding agent or AI IDE was used.

This is a community client. It is not an official xAI / SpaceXAI product.

## What you need

1. macOS 14+
2. Official Grok Build CLI (`grok --version`)
3. A signed-in grok.com account (`grok login`) or `XAI_API_KEY`

Install the CLI:

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
grok login
```

Grok Desktop does **not** ship the `grok` binary. It looks on `PATH`, `~/.local/bin/grok`, `~/.grok/bin/grok`, `/opt/homebrew/bin/grok`, and `/usr/local/bin/grok`.

## Build

Command Line Tools are enough. Xcode.app is not required.

```bash
cd GrokDesktop
swift build -c release
./scripts/bundle.sh
open "dist/Grok Desktop.app"
```

Unsigned builds may need a right-click → Open the first time.

Release zip (unsigned unless you have a Developer ID):

```bash
./scripts/release.sh
# ./scripts/release.sh --publish   # also creates GitHub release v0.1.10
```

Notarization needs a Developer ID Application certificate and a stored notary profile:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials "notarytool-profile" --apple-id "you@apple.com" --team-id TEAMID --password "app-specific-password"
export NOTARY_PROFILE="notarytool-profile"
./scripts/release.sh --publish
```

This machine currently has no Developer ID identity, so local zips stay unsigned.

Dev loop:

```bash
swift run GrokDesktop
swift run GrokDesktopSmoke
```

This machine only needs Command Line Tools. There is no XCTest target.

## Layout

- Top of the sidebar: Chat | Build. Chat embeds grok.com. Build is the local CLI session.
- Build left: new session, search, Imagine, live agents, history (from `~/.grok/sessions`)
- Build center: conversation with Markdown, clickable links/files, and compact CLI-style tool lines. Live work sits above the composer and leaves when the turn ends.
- Build right inspector: only the live pieces — context, tasks, Plan, diffs
- Settings: appearance, account, behavior, extensions — reads `~/.grok/config.toml`

## License

Apache-2.0. See [LICENSE](LICENSE).

Grok, Grok Build, and grok.com are trademarks of their owners.
