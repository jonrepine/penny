"""LLM dispatch for the supported providers.

Provider and model come from the user config. API keys come from the
process environment, set by the Swift app when it spawns this subprocess.
We deliberately do NOT read the macOS Keychain from Python: doing so
forces every refinement to trigger an "Always Allow" prompt for the
Python interpreter, separately from the prompt for Penny.app. By letting
Swift own Keychain and pass the key through `env`, the user only has to
approve Keychain access once, for Penny itself.
"""

from __future__ import annotations

import os


_ENV_VARS = {
    "anthropic": "ANTHROPIC_API_KEY",
    "openai":    "OPENAI_API_KEY",
    "gemini":    "GOOGLE_API_KEY",
}


def refine(text: str, system_prompt: str, config: dict) -> str:
    """Single chat completion against the configured provider."""
    return refine_with_provider(text, system_prompt, config)


def refine_with_provider(text: str, system_prompt: str, config: dict) -> str:
    """Internal alias used by both `refine` (refinement) and the extraction
    path. Identical behaviour today; split out so the call sites read
    clearly and so we can pin a higher max_tokens for extraction later if
    we want."""
    provider = config.get("llm_provider", "anthropic")
    model = config.get("model", "")
    max_tokens = int(config.get("max_tokens", 1024))
    timeout = int(config.get("timeout_seconds", 45))

    api_key = _get_api_key(provider)

    if provider == "anthropic":
        return _call_anthropic(text, system_prompt, model, api_key, max_tokens, timeout)
    if provider == "openai":
        return _call_openai(text, system_prompt, model, api_key, max_tokens, timeout)
    if provider == "gemini":
        return _call_gemini(text, system_prompt, model, api_key, max_tokens, timeout)

    raise RuntimeError(f"Unknown provider: {provider}")


# ── Per-provider implementations ──────────────────────────────────────────────

def _call_anthropic(text, system_prompt, model, api_key, max_tokens, timeout):
    import anthropic

    client = anthropic.Anthropic(api_key=api_key)
    message = client.messages.create(
        model=model or "claude-sonnet-4-6",
        max_tokens=max_tokens,
        system=system_prompt,
        messages=[{"role": "user", "content": text}],
        timeout=timeout,
    )
    return message.content[0].text


def _call_openai(text, system_prompt, model, api_key, max_tokens, timeout):
    from openai import OpenAI

    client = OpenAI(api_key=api_key, timeout=timeout)
    response = client.chat.completions.create(
        model=model or "gpt-4o",
        max_tokens=max_tokens,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": text},
        ],
    )
    return response.choices[0].message.content or ""


def _call_gemini(text, system_prompt, model, api_key, max_tokens, timeout):
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model=model or "gemini-2.5-flash",
        contents=text,
        config=types.GenerateContentConfig(
            system_instruction=system_prompt,
            max_output_tokens=max_tokens,
        ),
    )
    return response.text or ""


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_api_key(provider: str) -> str:
    env_var = _ENV_VARS.get(provider)
    if not env_var:
        raise RuntimeError(f"Unknown provider: {provider}")

    key = os.environ.get(env_var)
    if not key:
        raise RuntimeError(
            f"No {env_var} set. Open Penny → Preferences → AI Provider "
            f"and add your {provider.capitalize()} API key."
        )
    return key
