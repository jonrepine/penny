"""Load learned style rules and inject them into a base mode prompt.

Rules live at `~/.penny/style-rules.json` keyed by mode id (as string):

    {
      "4": {
        "rules": ["Sentences start lowercase, no period", ...],
        "deleted_rules": [...],
        "extracted_at": "2026-05-19T14:22:11Z",
        "examples_hash": "sha256:..."
      }
    }

The injection format is the template at config/style-rules.fragment.txt
shipped by the prompt engineer. We replace `{rules}` with a bullet list
of the user's rules, then append the result to the mode's base prompt.

When no rules exist for a mode, the base prompt is returned untouched.
"""

from __future__ import annotations

import json
import os
from typing import Any

USER_RULES_PATH = os.path.expanduser("~/.penny/style-rules.json")


def _fragment_path() -> str:
    candidates = [
        os.path.expanduser("~/.penny/style-rules.fragment.txt"),
        os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "config",
            "style-rules.fragment.txt",
        ),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return ""


def _load_rules(mode: int) -> list[str]:
    try:
        with open(USER_RULES_PATH, encoding="utf-8") as fh:
            data: dict[str, Any] = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return []

    entry = data.get(str(mode))
    if not entry:
        return []

    raw_rules = entry.get("rules") or []
    deleted = set(entry.get("deleted_rules") or [])
    return [rule.strip() for rule in raw_rules if rule.strip() and rule.strip() not in deleted]


def inject(base_prompt: str, mode: int) -> str:
    """Append the style-rules block to `base_prompt` if rules exist for
    `mode`. Returns the base prompt unchanged when no rules apply."""
    rules = _load_rules(mode)
    if not rules:
        return base_prompt

    fragment_path = _fragment_path()
    if not fragment_path:
        return base_prompt

    try:
        with open(fragment_path, encoding="utf-8") as fh:
            template = fh.read()
    except OSError:
        return base_prompt

    bulleted = "\n".join(f"- {rule}" for rule in rules)
    fragment = template.replace("{rules}", bulleted)
    return base_prompt + fragment
