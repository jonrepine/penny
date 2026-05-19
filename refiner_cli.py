#!/usr/bin/env python3
"""JSON CLI used by the native macOS daemon.

Two subcommands selected via the JSON `action` field on stdin:

  {"action": "refine", "text": "...", "mode": 1}
  {"action": "extract_rules", "mode": 4, "mode_name": "Slack",
   "mode_intent": "succinct · warm · lowercase",
   "examples": ["...", "..."]}

For backwards-compat, omitting `action` defaults to refine.
"""

import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from refiner.llm import refine, refine_with_provider
from refiner.prompts import get_prompt
from refiner.style_rules import inject as inject_style_rules
from utils.history import save_entry


USER_CONFIG_PATH = os.path.expanduser("~/.penny/config.json")
DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "config",
    "config.json",
)
USER_RULES_PATH = os.path.expanduser("~/.penny/style-rules.json")
EXTRACTION_PROMPT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "config",
    "style-extraction.prompt.txt",
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


# ── refine action ─────────────────────────────────────────────────────────────

def do_refine(payload: dict) -> dict:
    text = payload["text"]
    mode = int(payload["mode"])
    custom_prompt = payload.get("custom_prompt")

    if custom_prompt:
        system_prompt = custom_prompt
    else:
        system_prompt = get_prompt(mode)
        if not system_prompt:
            raise RuntimeError(f"No prompt configured for mode {mode}")
        system_prompt = inject_style_rules(system_prompt, mode)

    config = load_config()
    refined = refine(text, system_prompt, config)
    if config.get("save_history"):
        save_entry(text, refined, mode, config)
    return {"ok": True, "text": refined}


# ── extract_rules action ──────────────────────────────────────────────────────

def do_extract_rules(payload: dict) -> dict:
    """Run the engineer-supplied extraction prompt over the user's examples
    and write the resulting rules to ~/.penny/style-rules.json. Preserves
    any user-edited or user-deleted rules already in that file."""
    mode = int(payload["mode"])
    examples = [e.strip() for e in payload.get("examples") or [] if e and e.strip()]
    if not examples:
        raise RuntimeError("Need at least one example to extract rules.")

    try:
        with open(EXTRACTION_PROMPT_PATH, encoding="utf-8") as fh:
            system_prompt = fh.read()
    except OSError as exc:
        raise RuntimeError(f"Extraction prompt not found: {exc}")

    user_message = json.dumps({
        "mode_id": mode,
        "mode_name": payload.get("mode_name", ""),
        "mode_intent": payload.get("mode_intent", ""),
        "mode_base_prompt": payload.get("mode_base_prompt", ""),
        "examples": examples,
    }, ensure_ascii=False, indent=2)

    config = load_config()
    raw = refine_with_provider(user_message, system_prompt, config)
    rules = _parse_rules_json(raw)

    # Merge with existing entry, filtering out anything the user has deleted.
    existing = _read_rules_file()
    entry = existing.get(str(mode), {}) or {}
    deleted = set(entry.get("deleted_rules") or [])
    rules = [r for r in rules if r not in deleted]

    entry["rules"] = rules
    entry["extracted_at"] = _now_iso()
    entry["examples_hash"] = _hash_examples(examples)
    existing[str(mode)] = entry
    _write_rules_file(existing)

    return {"ok": True, "rules": rules, "extracted_at": entry["extracted_at"]}


def _parse_rules_json(raw: str) -> list[str]:
    """The extraction prompt mandates a JSON array of strings, but models
    occasionally produce nested unescaped double quotes inside the values
    (e.g. `"opener like "hey", "morning""`). This parser tries strict
    JSON first, then a line-based fallback that recovers the rules even
    when the surrounding JSON is malformed."""
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].startswith("```"):
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()

    try:
        value = json.loads(cleaned)
        if isinstance(value, list):
            return _normalise_rules(value)
    except json.JSONDecodeError:
        pass

    # Fallback: model produced a JSON-like array but with bad inner quotes.
    # Pull out anything between top-level commas that lives inside outer
    # double quotes, ignoring everything else.
    recovered = _recover_rules_loose(cleaned)
    if recovered:
        return _normalise_rules(recovered)

    raise RuntimeError(f"Extraction returned non-list / unparseable: {raw!r}")


def _normalise_rules(value: list) -> list[str]:
    return [str(rule).strip() for rule in value if str(rule).strip()][:10]


def _recover_rules_loose(text: str) -> list[str]:
    """Best-effort recovery when the model returned `["foo", "bar"]` with
    unescaped inner double quotes. We split by `",` then trim leading and
    trailing junk to get the raw rule strings."""
    body = text.strip()
    if body.startswith("["):
        body = body[1:]
    if body.endswith("]"):
        body = body[:-1]

    # Split between rule entries. Each entry is wrapped in `"..."`, so a
    # `",\s*"` boundary is a strong rule separator even with inner quotes.
    import re
    parts = re.split(r'"\s*,\s*"', body.strip())
    rules: list[str] = []
    for part in parts:
        clean = part.strip().strip('"').strip()
        if clean:
            rules.append(clean)
    return rules


def _read_rules_file() -> dict:
    try:
        with open(USER_RULES_PATH, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return {}


def _write_rules_file(data: dict) -> None:
    os.makedirs(os.path.dirname(USER_RULES_PATH), exist_ok=True)
    with open(USER_RULES_PATH, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)


def _hash_examples(examples: list[str]) -> str:
    h = hashlib.sha256("\n---\n".join(examples).encode("utf-8")).hexdigest()
    return f"sha256:{h[:16]}"


def _now_iso() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ── entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    try:
        payload = json.load(sys.stdin)
        action = payload.get("action", "refine")
        if action == "refine":
            result = do_refine(payload)
        elif action == "extract_rules":
            result = do_extract_rules(payload)
        else:
            raise RuntimeError(f"Unknown action: {action}")
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
