#!/usr/bin/env python3
"""JSON CLI used by the native macOS daemon."""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from refiner.llm import refine
from refiner.prompts import get_prompt
from utils.history import save_entry


USER_CONFIG_PATH = os.path.expanduser("~/.penny/config.json")
DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "config",
    "config.json",
)

DEFAULT_CONFIG = {
    "llm_provider": "anthropic",
    "model": "claude-sonnet-4-6",
    "max_tokens": 1024,
    "timeout_seconds": 45,
    "save_history": True,
    "history_limit": 50,
}


def load_config() -> dict:
    config = DEFAULT_CONFIG.copy()
    for path in (DEFAULT_CONFIG_PATH, USER_CONFIG_PATH):
        try:
            with open(path, encoding="utf-8") as fh:
                config.update(json.load(fh))
        except FileNotFoundError:
            pass
        except Exception:
            pass
    return config


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        text = payload["text"]
        mode = int(payload["mode"])
        custom_prompt = payload.get("custom_prompt")

        if custom_prompt:
            system_prompt = custom_prompt
        else:
            system_prompt = get_prompt(mode)
        if not system_prompt:
            raise RuntimeError(f"No prompt configured for mode {mode}")

        config = load_config()
        refined = refine(text, system_prompt, config)
        if config.get("save_history"):
            save_entry(text, refined, mode, config)

        print(json.dumps({"ok": True, "text": refined}))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
