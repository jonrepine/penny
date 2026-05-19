# Penny

**Are you lazy? Penny is for you.**

You hold Right Option and talk. Penny types what you said. You select something
you wrote — anywhere — double-tap Right Option, pick a mode, and Penny rewrites
it cleaner. That's the whole pitch.

It's the menu-bar app that gives you Apple-style dictation that actually works,
and one-tap rewriting in every text field on your Mac, without joining anyone's
ecosystem.

---

## What Penny does

Two shortcuts. One key. Every app.

### 🎙️ Hold Right Option → dictate

Press and hold the **Right Option** key. A small "Listening" indicator appears.
Talk normally. Release the key. A "Transcribing" indicator briefly appears, and
your speech gets pasted wherever your cursor is.

Transcription runs entirely on your Mac via `faster-whisper`. Your audio never
touches the network.

### ✍️ Double-tap Right Option → refine

Select some text — *anywhere* — and double-tap **Right Option**. A small picker
appears next to your cursor. Pick a mode, your selection gets rewritten in place:

| # | Mode | What it does |
|---|------|--------------|
| 1 | Spelling only | Fix misspellings. Nothing else. |
| 2 | Grammar | Fix spelling, grammar, punctuation. Keep phrasing. |
| 3 | Improve Writing | Tighter, clearer, same meaning. Cuts filler. |
| 4 | Slack | Succinct, warm, lowercase, no sign-off. |
| 5 | Email | Polished, warm opener, ends with "Cheers,". |
| 6 | Report | Notion-formatted with headings + emojis. |
| 7 | Bullet Points | Scannable list of distinct ideas. |
| 8 | Improve Prompt | Rewrites your input as a stronger LLM prompt. |
| 9 | Custom… | Type a one-off instruction for this run. |
| 0 | Cancel | Leave the text unchanged. |

Press the digit or click the row. Esc cancels.

### Works *anywhere* you can type

This is the bit that matters. Penny is not a plugin, not a Slack app, not a
Chrome extension. It sits in your menu bar and operates on whatever text field
your cursor is in.

That means it works in:

> Cursor · VS Code · Discord · Slack · Apple Mail · Notion · Linear · Figma
> comments · Safari address bars · Notes · Messages · Spotlight · Reminders
> · Outlook · WhatsApp Desktop · ChatGPT's web UI · your terminal · anywhere
> macOS gives you a cursor.

No integrations to configure, no per-app accounts, no "connect to Penny"
buttons. **Ecosystem-agnostic, app-agnostic, input-agnostic.** If macOS lets
you type into it, Penny works there.

---

## You stay in control

Penny runs entirely on your Mac. Three things matter:

- **Dictation is fully local.** Whisper runs inside Penny's own Python venv via
  `faster-whisper`. The audio never leaves your machine.
- **Refinement only knows your API key.** When you choose to refine, Penny
  sends the selection plus the chosen system prompt directly to the LLM
  provider — Anthropic, OpenAI, or Google Gemini — authenticated with the API
  key you've stored. The provider sees the request the same way they would if
  you'd typed it into their playground. There is **no Penny server**, **no
  Penny account**, **no Penny telemetry**.
- **No phone-home.** Penny doesn't track usage, doesn't auto-update, doesn't
  call any Penny-owned endpoint. The source code on GitHub is the entire
  product.

### Great for organisations

This makes Penny easy to deploy inside a company:

- **Your AI policy is the AI policy.** Configure the team's provider key to
  point at a zero-data-retention or enterprise tier (Anthropic's no-training
  endpoint, OpenAI's enterprise zero-retention, Google's Vertex AI commercial
  terms, etc.) and that policy applies to every Penny invocation, automatically.
  There's no separate "Penny Terms of Service" layered on top of yours.
- **The API key is the only thing your provider knows about Penny.** It's the
  same data path as a developer hitting the provider's API from a terminal.
- **Auditable in a sitting.** The entire LLM call lives in `refiner/llm.py`
  (under 100 lines). The dictation path lives in `dictate/whisper-dictate`.
  Every shortcut, every prompt, every config value is in this repo.
- **Universal text upgrade.** Knowledge workers spend most of the day in five
  to fifteen text inputs across Slack, email, documents, code, tickets, calendar
  invites. Penny upgrades all of them at once, without IT having to integrate
  Penny into any of them.

If you'd like Penny rolled out at your org and need help with the policy
conversation, the code is MIT-licensed — fork it, audit it, ship it internally.

---

## Install

You need a Mac on macOS 13 (Ventura) or later, plus an API key from **Anthropic**,
**OpenAI**, or **Google Gemini** for the refinement side. Dictation needs no key
and no internet.

### 0. One-time prerequisites

Open **Terminal** (Cmd+Space → "Terminal" → Enter), and run:

```sh
xcode-select --install
```

This pulls in the Swift compiler. If it's already installed you'll see a short
message saying so — that's fine, move on.

### 1. Clone and install

Paste each of these three lines into Terminal, one at a time:

```sh
git clone https://github.com/jonrepine/penny.git ~/.local/penny
cd ~/.local/penny
./setup.sh
```

The installer takes a minute or two. It:

1. Creates a Python virtual environment at `~/.penny/env` and installs deps.
2. Compiles `Penny.app` and copies it into `/Applications` (falls back to
   `~/Applications` if you don't have admin rights).
3. Signs the bundle with a stable identifier so future updates keep your
   macOS permissions.
4. Registers two LaunchAgents so Penny starts at login and respawns if it
   crashes.
5. Opens a small welcome window for the final permission grants.

### 2. Grant macOS permissions

Penny needs three permissions, all in **System Settings → Privacy & Security**:

| Permission | What it's for |
|---|---|
| Accessibility | Replacing selected text in other apps; reading the focused text field. |
| Input Monitoring | Listening for the Right Option key globally. |
| Microphone | Recording you while you hold Right Option to dictate. |

The welcome window has a **Grant…** button for each of the three. Click each
button — Penny will open the right pane of System Settings and surface its
own toggle. Flip Penny **on** (you may need to enter your Mac password). Then
come back to the welcome window; the row's status dot will turn green within
a couple of seconds.

> ⚠️ If a row stays red after toggling, toggle Penny **off and back on**
> in that pane. macOS sometimes leaves the toggle visually on while the
> underlying permission is invalidated.

### 3. Add your API key

Click the small **P** icon in your menu bar (top right corner of the screen) →
**Preferences…**.

In the **AI Provider** section:

1. Pick a provider: **Anthropic**, **OpenAI**, or **Google Gemini**.
2. Click **Get an API key for this provider →** to open the provider's
   console in your browser. Generate a key, copy it.
3. Paste it into the API Key field, click **Save key**.
4. Pick a model. Each option has a one-liner explaining the speed / quality /
   cost trade-off. The first option in each list is the recommended default.

The key is stored only in macOS Keychain. It leaves your machine when you
refine text — and only then, only to the provider you chose.

### 4. (Optional) Pick a dictation model

In **Preferences → Dictation (Whisper)** you'll see five Whisper model options.
Penny detects your RAM on first launch and picks a sensible default. You can
change it any time:

- **≥ 16 GB RAM:** *Distil Large v3* — multilingual, very accurate, fast on
  Apple Silicon. Recommended. ~3 GB on first download.
- **8 GB – 12 GB RAM:** *Medium (English only)* — high quality, ~1.5 GB.
- **6 GB RAM:** *Base (English only)* — light, decent for short utterances.
- **< 6 GB RAM:** *Tiny (English only)* — fastest, lowest accuracy.

The first time you hold Right Option after picking a model, faster-whisper
downloads it into `~/.cache/huggingface/`. Be on Wi-Fi the first time; every
hold after that is instant.

### 5. Use it

You're done. Open any app with a text field:

- **Hold Right Option** → talk → release → text appears.
- **Select text → double-tap Right Option** → pick a mode → text gets rewritten.

The **P** menu bar icon also has **Open Log** if anything looks off, and
**Quit Penny** if you want both services off.

---

## Configuration

Click the **P** menu bar icon → **Preferences…**. Sections:

- **Status** — green/red dots for each macOS permission Penny needs.
- **AI Provider** — provider, model, API key. Per-provider keys; switch
  between providers without re-pasting.
- **Dictation (Whisper)** — which transcription model to use; auto-restarts
  the dictation daemon when you change it.
- **General** — max tokens, request timeout, history limit, toast toggles.
- **Modes** — add, edit, delete refinement modes. Each mode is a name plus
  a system prompt. The Custom and Cancel rows are locked so you can't break
  the picker.

Your settings live in `~/.penny/config.json` and `~/.penny/modes.json`. They
survive updates.

---

## Updating

```sh
cd ~/.local/penny
git pull
./setup.sh
```

Your config, modes, and API keys all survive the update. The first launch
after an update may briefly ask you to re-grant Accessibility / Input
Monitoring if the binary's signature changed.

## Uninstalling

```sh
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.penny.refiner.plist 2>/dev/null
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.penny.dictate.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.penny.refiner.plist ~/Library/LaunchAgents/com.penny.dictate.plist
rm -rf /Applications/Penny.app ~/Applications/Penny.app
rm -rf ~/.penny ~/.local/penny
for account in anthropic openai gemini; do
  security delete-generic-password -s penny -a "$account" 2>/dev/null
done
```

## What's inside

- `native/` — Swift sources for the menu-bar app, picker, preferences,
  onboarding, overlays.
- `dictate/whisper-dictate` — Python dictation daemon.
- `refiner/` + `refiner_cli.py` — Python helper for the LLM refinement call.
- `config/` — Default settings and mode prompts shipped with the repo.
- `launchd/` — LaunchAgent templates that `setup.sh` fills in.
- `setup.sh` — The installer. Idempotent; safe to re-run.

## License

[MIT](LICENSE). Fork it, ship it, take it to work.
