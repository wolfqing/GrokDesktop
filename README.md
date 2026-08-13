# Grok Desktop

Native macOS SwiftUI client for [Grok Build](https://x.ai/build). The window follows [grok.com](https://grok.com/) layout and settings; the engine is your local `grok` CLI over ACP.

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

Grok Desktop does **not** ship the `grok` binary. It looks on `PATH`, `~/.local/bin/grok`, and `~/.grok/bin/grok`.

## Build

Command Line Tools are enough. Xcode.app is not required.

```bash
cd GrokDesktop
swift build -c release
./scripts/bundle.sh
open "dist/Grok Desktop.app"
```

Dev loop:

```bash
swift run GrokDesktop
swift run GrokDesktopSmoke
```

This machine only needs Command Line Tools. There is no XCTest target.

## Layout

- Left: new session, search, Imagine, live agents, history (from `~/.grok/sessions`)
- Center: grok.com-style conversation + pill composer (Fast / Auto / Expert / Heavy)
- Right inspector: Plan, diffs, timeline, workflows (opens when needed)
- Settings: appearance, account, behavior, extensions — reads `~/.grok/config.toml`

## License

Apache-2.0. See [LICENSE](LICENSE).

Grok, Grok Build, and grok.com are trademarks of their owners.
