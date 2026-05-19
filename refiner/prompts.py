"""Mode + prompt lookup, loaded from the user's modes.json.

The Swift daemon writes to `~/.penny/modes.json` from the preferences
window. We read it here. Defaults are bundled at `<repo>/config/modes.default.json`
and copied into place on first install.
"""

from __future__ import annotations

import json
import os
from typing import Any

USER_MODES_PATH = os.path.expanduser("~/.penny/modes.json")
DEFAULT_MODES_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "config",
    "modes.default.json",
)


def _load_modes() -> list[dict[str, Any]]:
    for path in (USER_MODES_PATH, DEFAULT_MODES_PATH):
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                return json.load(fh)
    return []


def _mode_by_id(mode_id: int) -> dict[str, Any] | None:
    for mode in _load_modes():
        if int(mode.get("id", -1)) == mode_id:
            return mode
    return None


def get_prompt(mode: int) -> str:
    entry = _mode_by_id(mode)
    return entry.get("prompt", "") if entry else ""


def get_mode_name(mode: int) -> str:
    entry = _mode_by_id(mode)
    return entry.get("name", "Custom") if entry else "Custom"


# Back-compat for any caller that still imports MODE_NAMES / PROMPTS.
MODE_NAMES = {int(m["id"]): m["name"] for m in _load_modes()}
PROMPTS = {int(m["id"]): m["prompt"] for m in _load_modes() if m.get("prompt")}
