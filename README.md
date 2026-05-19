# Penny

**Are you lazy? Penny is for you.**

Hold Right Option and talk → Penny types what you said. Select text anywhere
→ double-tap Right Option → pick a mode → Penny rewrites it in place.

That's it. Menu-bar app, no ecosystem, works in every text field on your Mac.

---

## What Penny does

Two shortcuts, one key, every app.

- **Hold Right Option → dictate.** Penny shows a "Listening" indicator while
  you talk, transcribes locally via `faster-whisper` when you release, pastes
  the text where your cursor is. Audio never leaves your Mac.
- **Double-tap Right Option → refine.** A picker pops next to your cursor
  with 9 modes — Spelling, Grammar, Improve Writing, Slack, Email, Report,
  Bullet Points, Improve Prompt, Custom — plus Cancel. Pick one, your
  selection gets rewritten in place.

It works in Cursor, VS Code, Discord, Slack, Mail, Notion, Linear, Safari,
Notes, your terminal — anywhere macOS gives you a cursor. Nothing to integrate,
no per-app accounts, no plugins. **Ecosystem-, app-, and input-agnostic.**

> ### 🔑 Two independent tools that play well together
>
> **Refine works on *any* text you've selected on your Mac.** You don't have
> to dictate first. Emails you typed by hand, code comments, Slack drafts,
> things you pasted in from somewhere else — select it, double-tap Right
> Option, pick a mode, done.
>
> Dictation is just one fast way to *get* text into a field. Refine makes any
> text better, no matter where it came from. Use either, both, or one without
> the other.

---

## You stay in control

- **Dictation is local.** Whisper runs in Penny's own Python venv. Your audio
  never touches the network.
- **Refinement uses your key, nothing else.** Penny sends the selection +
  system prompt directly to your chosen provider (Anthropic, OpenAI, or Gemini)
  with the API key you've stored in macOS Keychain. No Penny server, no Penny
  account, no Penny telemetry.

### Great for organisations

Point the provider key at your company's zero-data-retention or enterprise
tier (Anthropic's no-training endpoint, OpenAI Enterprise, Vertex AI, etc.) and
that policy applies to every Penny invocation — same data path as your devs
already use. The whole LLM call is `refiner/llm.py` (< 100 lines); audit in a
sitting, fork it, ship it internally. MIT-licensed.

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
