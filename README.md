# agy-statusline

An enhanced multi-line status line for [Antigravity CLI (agy)](https://gemini.google.com/) that adds repo name, git branch info, model + effort level, cost tracking, rate limits, and token usage — grouped by category across four lines.

## Features

- Shows current repo name with a folder icon
- GitButler support: displays active GitButler branches when on `gitbutler/workspace`
- Falls back to regular git branch display when not using GitButler
- Shows current model name with its effort level (color-coded) and a thinking-mode indicator when extended thinking is on
- Cost tracking: self-contained session and daily cost tracking in your local currency (no external dependencies)
- Rate limit progress bar (5-hour window with time remaining, color-coded green/yellow/red)
- Falls back to session duration display when rate limit data isn't available
- Context window progress bar and token usage display
- Auto-updates from `main` once per day

## Status Line Example

```
📂 xylem · 🤖 Gemini 1.5 Pro · ⚡ high · 🤔
🌿 gb/feature-a, gb/feature-b, gb/feature-c + 2 more
💸 A$1.21 session · 💰 A$4.00 today · ⏱️ ██░░░░░░░░ 23% 4h0m left
💭 █░░░░░░░░░ 11% ctx · 🧠 45k in / 12k out
```

Each line groups related information:

| Line | Purpose | Contents |
|------|---------|----------|
| 1 | **Identity + Model** | 📂 Repo name · 🤖 Model · ⚡ Effort · 🤔 Thinking flag |
| 2 | **Branches** | 🌿/🔀 Branch (or as many GitButler branches as fit + `+ N more`) |
| 3 | **Spend & limits** | 💸 Session cost · 💰 Daily cost · ⏱️ Rate limit bar |
| 4 | **Technical** | 💭 Context usage bar · 🧠 Token counts |

The branches line uses the full terminal width: it shows as many full branch names as fit (comma-separated), then ` + N more` for the rest. A single long name is truncated with `…`.

### Icons

| Icon | Meaning |
|------|---------|
| 📂 | Repository name |
| 🌿 | GitButler active branch(es) |
| 🔀 | Regular git branch (when not using GitButler) |
| 🤖 | Current model |
| ⚡ | Effort level (`low` dim, `medium` plain, `high` yellow, `xhigh`/`max` red) |
| 🤔 | Extended thinking is enabled (hidden when off) |
| 💸 | Session cost (local currency) |
| 💰 | Daily cost (local currency) |
| ⏱️ | 5-hour rate limit (progress bar + time remaining) |
| 💭 | Context window usage (progress bar) |
| 🧠 | Token counts (input / output) |

Progress bars are color-coded: green (<70%), yellow (70-89%), red (90%+).

## Install

```bash
curl -sSL https://raw.githubusercontent.com/gordonbeeming/agy-statusline/main/install.sh | bash
```

This will:
1. Copy `statusline.sh` to `~/.gemini/antigravity-cli/scripts/`
2. Print instructions for updating your `~/.gemini/antigravity-cli/settings.json`

After running the installer, add this to your `~/.gemini/antigravity-cli/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.gemini/antigravity-cli/scripts/statusline.sh"
}
```

## Dependencies

- [jq](https://jqlang.github.io/jq/) — for parsing JSON input and GitButler output
- [bc](https://www.gnu.org/software/bc/) — for floating-point calculations in the status line
- [GitButler CLI](https://docs.gitbutler.com/cli-overview) (`but`) — optional, for GitButler branch display

## Currency Configuration

You can customize the local currency shown in the status line by setting the `STATUSLINE_CURRENCY` environment variable (e.g. `USD`, `AUD`, `GBP`, `EUR`, `NZD`, `CAD`, `JPY`). It defaults to `AUD`. Exchange rates are fetched from Open Exchange Rates (Open ER) API and cached locally for 24 hours to prevent network overhead.

## Auto-Updates

The installed script checks once per day for updates from the `main` branch of this repo. The check runs in the background so it never slows down the status line.
