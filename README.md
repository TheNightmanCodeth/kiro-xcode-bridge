# kiro-bridge

Makes Amazon Kiro appear as a native Xcode Coding Intelligence provider. Select Kiro models in the Xcode model picker the same way you would ChatGPT or Claude — responses stream directly into the chat window, and your usage counts against your Kiro subscription.

```
Xcode 26 Intelligence
        │  /v1/models, /v1/chat/completions (SSE)
        ▼
kiro-bridge  (localhost:7077)
        │  Bearer token
        ▼
Kiro backend  (q.{region}.amazonaws.com)
```

## Requirements

- macOS 14+
- Xcode 26 with Intelligence enabled
- A Kiro account (free Builder ID, Pro, or enterprise IAM Identity Center)

## Quick start

**If you have Kiro CLI installed and are already logged in:**

```bash
cd ~/Code/MyProject
kiro-bridge
```

The bridge reads your existing Kiro CLI credentials automatically — no extra login needed.

**If you have a Kiro API key** (Pro/Pro+/Power):

```bash
export KIRO_API_KEY="your-key-here"
kiro-bridge --project ~/Code/MyProject
```

**First-time login (no Kiro CLI):**

```bash
kiro-bridge --login
# Opens browser with a device code — log in once, credentials are cached
```

**Enterprise (IAM Identity Center):**

```bash
kiro-bridge --start-url https://my-org.awsapps.com/start --region us-east-1
```

## Xcode setup

After the bridge is running, register it once in Xcode:

1. **Xcode → Settings → Intelligence**
2. Click **+** → **Locally Hosted**
3. Set **Port** to `7077` and **Description** to `Kiro`
4. Select a model from the picker — `claude-sonnet-4.5` is a good default

## Install

```bash
bash Scripts/install.sh
```

This builds a release binary and copies it to `/usr/local/bin/kiro-bridge`.

## Auto-start on login

```bash
# Edit the plist first — replace YOURUSERNAME with your macOS username
sed -i '' "s/YOURUSERNAME/$USER/" Scripts/com.kiro-bridge.plist

cp Scripts/com.kiro-bridge.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.kiro-bridge.plist
```

Logs are written to `/tmp/kiro-bridge.log` and `/tmp/kiro-bridge.err`.

To stop: `launchctl unload ~/Library/LaunchAgents/com.kiro-bridge.plist`

## Options

```
USAGE: kiro-bridge [OPTIONS]

OPTIONS:
  --port <port>          Port for Xcode to connect to (default: 7077)
  --region <region>      AWS region for the Kiro backend (default: us-east-1)
  --project <path>       Xcode project root, for .kiro/steering/ files
                         (default: current directory)
  --api-key <key>        Kiro API key. Also reads KIRO_API_KEY env var.
  --start-url <url>      IAM Identity Center start URL for enterprise SSO login
  --login                Force re-login even if cached credentials exist
  --verbose              Print auth and request details to stderr
```

## Steering rules

The bridge injects `.kiro/steering/*.md` files as a system prompt prefix on every request, the same way Kiro IDE does. Place rules in:

- `~/.kiro/steering/` — applied to all projects
- `<project>/.kiro/steering/` — applied to requests from that project

Files with `inclusion: manual` in their YAML front matter are skipped. All others are included automatically. Changes take effect on the next request without restarting the bridge.

## Authentication chain

On startup the bridge checks credentials in this order, using the first match:

| Priority | Source | When it's used |
|---|---|---|
| 1 | `KIRO_API_KEY` env var | Pro/Pro+/Power API keys |
| 2 | kiro-cli SQLite (`~/Library/Application Support/kiro-cli/data.sqlite3`) | Already logged into Kiro CLI |
| 3 | SSO cache (`~/.aws/sso/cache/*.json`) | Kiro IDE or previous bridge login |
| 4 | Bridge token cache (`~/.aws/sso/cache/kiro-bridge-token.json`) | Previous `--login` session |
| 5 | Interactive device code flow | First-time login with no cached credentials |

Tokens are refreshed automatically before they expire. On a 401/403 from the Kiro API, the bridge forces an immediate refresh.

## Available models

At startup the bridge calls the Kiro API to fetch the models available to your account. The startup banner prints the active list:

```
Models:  auto, claude-sonnet-4.5, claude-sonnet-4, claude-haiku-4.5
```

Free and Pro plans typically include `claude-sonnet-4.5`, `claude-sonnet-4`, `claude-haiku-4.5`, and `auto`. Higher-tier plans may include additional models (Opus, extended context variants, etc.). The `auto` model lets Kiro pick the best model for each request.

If the API call fails (e.g. when using a static API key), the bridge falls back to checking whether kiro-cli is installed and can list models, then finally to a built-in fallback list.

## Building from source

```bash
swift build                        # debug
swift build -c release             # release
swift test                         # run tests
```

Requires Swift 6.0+ (ships with Xcode 26).
