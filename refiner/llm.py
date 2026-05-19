"""Anthropic call. Other providers will dispatch here in v2.

Keys live in macOS Keychain under service `penny`, account
`anthropic` (preferred). The original installation stored the key under
account `api_key`; we still read that as a fallback so existing users
don't have to re-enter their key.
"""

from __future__ import annotations

import os

import anthropic


def get_api_key(provider: str = "anthropic") -> str:
    env_var = {
        "anthropic": "ANTHROPIC_API_KEY",
        "openai": "OPENAI_API_KEY",
        "kimi": "MOONSHOT_API_KEY",
        "gemini": "GOOGLE_API_KEY",
    }.get(provider, "ANTHROPIC_API_KEY")

    if key := os.environ.get(env_var):
        return key

    try:
        import keyring
        if key := keyring.get_password("penny", provider):
            return key
        # Legacy entry from earlier versions.
        if provider == "anthropic":
            if key := keyring.get_password("penny", "api_key"):
                return key
    except Exception:
        pass

    raise RuntimeError(
        f"No API key found for {provider}. Set it in the preferences window "
        f"or export {env_var}."
    )


def refine(text: str, system_prompt: str, config: dict) -> str:
    provider = config.get("llm_provider", "anthropic")
    if provider != "anthropic":
        raise RuntimeError(
            f"Provider '{provider}' isn't wired up yet. Use 'anthropic' for now."
        )

    client = anthropic.Anthropic(api_key=get_api_key(provider))
    message = client.messages.create(
        model=config.get("model", "claude-sonnet-4-6"),
        max_tokens=config.get("max_tokens", 1024),
        system=system_prompt,
        messages=[{"role": "user", "content": text}],
        timeout=config.get("timeout_seconds", 45),
    )
    return message.content[0].text
