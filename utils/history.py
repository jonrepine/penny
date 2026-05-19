import json
import os
from datetime import datetime

HISTORY_PATH = os.path.expanduser("~/.penny/history.json")


def save_entry(original: str, refined: str, mode, config: dict) -> None:
    entries = _load()
    entries.insert(0, {
        "timestamp": datetime.now().isoformat(),
        "mode": str(mode),
        "original": original,
        "refined": refined,
    })
    limit = config.get("history_limit", 50)
    entries = entries[:limit]
    os.makedirs(os.path.dirname(HISTORY_PATH), exist_ok=True)
    with open(HISTORY_PATH, "w") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)


def get_last_original() -> str | None:
    entries = _load()
    return entries[0].get("original") if entries else None


def _load() -> list:
    try:
        with open(HISTORY_PATH) as f:
            return json.load(f)
    except Exception:
        return []
