# Penny

A tiny menu-bar app for macOS. Two shortcuts on the same key:

- **Hold Right Option (⌥) to dictate.** Penny listens to your voice, transcribes it locally on your Mac, and pastes the text wherever your cursor is.
- **Double-tap Right Option (⌥) to refine.** A small picker appears next to your cursor with options like Spelling, Slack, Email, Improve Writing, Bullet Points, and Improve Prompt. Pick one and your highlighted text is rewritten in place.

Both work in any app — your editor, your browser, Notes, Slack, anywhere.

## What you need

A Mac (anything from late 2020 onwards comfortably; macOS 13 Ventura or later), and an API key from one of **Anthropic**, **OpenAI**, or **Google Gemini** for the refinement side. The dictation side runs locally on your Mac and doesn't need any key or internet.

## Install

Open Terminal and paste these three lines, one at a time:

```sh
git clone https://github.com/jonrepine/penny.git ~/.local/penny
cd ~/.local/penny
./setup.sh
```

The installer will:

1. Set up a Python environment under `~/.penny/env`.
2. Build Penny.app and drop it in `/Applications`.
3. Register the two background services that listen for Right Option.
4. Open a small welcome window for the final permission grants.

It takes about a minute the first time, mostly because pip is downloading the dictation library.

## First-launch permissions

Penny needs three macOS permissions. The welcome window walks you through them — just click the **Grant…** button on each row.

| Permission | What it's for | Where to grant |
|---|---|---|
| Accessibility | Replacing selected text in other apps | System Settings → Privacy & Security → Accessibility |
| Input Monitoring | Listening for the Right Option key | System Settings → Privacy & Security → Input Monitoring |
| Microphone | Recording you while you hold Right Option | System Settings → Privacy & Security → Microphone |

When macOS asks, click **Allow** (or **Always Allow**). For Accessibility and Input Monitoring you may need to toggle Penny **on** in the relevant Settings pane.

## Add your API key

Click the small **P** icon in your menu bar (top right of the screen) → **Preferences…** → **AI Provider** section.

1. Choose your provider (**Anthropic**, **OpenAI**, or **Google Gemini**). The "Get an API key…" button opens the right console page in your browser.
2. Paste the key into the API Key field, click **Save key**.
3. Pick a model. Each option has a one-line description so you can choose between speed and quality.

The key is stored in the macOS Keychain. It only leaves your machine when Penny sends a refinement request to the chosen provider.

## Choose a dictation model

In **Preferences → Dictation (Whisper)** you'll see a list of Whisper models. Penny detects your RAM and picks a sensible default:

- **≥ 16 GB RAM:** Distil Large v3 — multilingual, very accurate, fast on Apple Silicon (recommended).
- **8–12 GB RAM:** Medium (English only) — high quality, ~1.5 GB.
- **6 GB RAM:** Base (English only) — light, decent for short utterances.
- **< 6 GB RAM:** Tiny (English only) — fastest, lowest accuracy.

You can change the model later. The dictation daemon automatically restarts with the new model the first time you hold Right Option after the change.

## Heads-up about the first dictation

The very first time you use a Whisper model, faster-whisper downloads it into `~/.cache/huggingface/`. The recommended Distil Large v3 is ~3 GB on first download; smaller models are 75 MB – 1.5 GB. Be on Wi-Fi the first time; every hold after that is fast.

## Daily use

- Anywhere you can type, **hold Right ⌥** while you talk, then release. The transcription gets pasted.
- Anywhere you have text selected, **double-tap Right ⌥**. The picker appears. Click a mode (or press its number key) and the selection is rewritten.

The menu-bar P icon also has **Open Log** if anything looks off, and **Quit Penny** if you want both services off.

## Updating

```sh
cd ~/.local/penny
git pull
./setup.sh
```

Your config and API key survive the update.

## Uninstall

```sh
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.penny.refiner.plist
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.penny.dictate.plist
rm -f ~/Library/LaunchAgents/com.penny.refiner.plist ~/Library/LaunchAgents/com.penny.dictate.plist
rm -rf /Applications/Penny.app ~/Applications/Penny.app
rm -rf ~/.penny ~/.local/penny
security delete-generic-password -s penny -a anthropic
```

## What's inside

- **`native/`** — Swift sources for the menu-bar app and refinement picker.
- **`dictate/whisper-dictate`** — Python script for the dictation daemon.
- **`refiner/` + `refiner_cli.py`** — Python helper that calls Anthropic.
- **`config/`** — Default settings and mode prompts.
- **`launchd/`** — LaunchAgent templates that setup.sh fills in.
- **`setup.sh`** — Installer.

## License

[MIT](LICENSE).
