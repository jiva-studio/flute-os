"""LLM post-processing for fluteos-ptt.

Backend (endpoint, api shape, model, token cap) is per-mode configuration; the
key is a systemd credential read at runtime. Nothing here is hardcoded, so a
downstream user can point a mode at a different model or a proxy without
touching this file.

Raw HTTP rather than a vendor SDK: `endpoint` is an option, so the daemon must
speak whatever URL it is given, and the request shape below is the only one it
needs.
"""
import httpx

from .config import ConfigError


class LlmUnconfigured(RuntimeError):
    """No API key for this mode's LLM backend.

    Distinct from a request failure: it means the machine was never given the
    key, so the user gets "not configured" rather than a network error, and
    plain dictation keeps working.
    """


def process_with_llm(text: str, prompt: str, llm: dict, api_key: str | None) -> str:
    """Send the transcript to the configured LLM and return its reply."""
    if not api_key:
        raise LlmUnconfigured(
            "no API key for this mode's LLM backend "
            "(set features.fluteos.ptt.llm.apiKeyFile)"
        )

    api = llm.get("api")
    if api != "anthropic":
        raise ConfigError(
            f"unsupported llm.api {api!r}; this build implements the Anthropic "
            "Messages shape only (point llm.endpoint at a compatible proxy if "
            "needed)"
        )

    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/json",
        "anthropic-version": "2023-06-01",
    }

    payload = {
        "model": llm["model"],
        "max_tokens": llm["maxTokens"],
        "messages": [
            {
                "role": "user",
                "content": f"{prompt}\n\n{text}",
            }
        ],
    }

    with httpx.Client(timeout=30.0) as client:
        response = client.post(llm["endpoint"], headers=headers, json=payload)
        response.raise_for_status()
        result = response.json()

    # Pick the first text block rather than content[0]: current models return
    # thinking blocks ahead of the answer (empty-texted by default), so indexing
    # blindly yields a KeyError or an empty rewrite.
    for block in result.get("content") or []:
        if block.get("type") == "text" and block.get("text"):
            return block["text"].strip()

    # Nothing usable came back; leave the dictated text as-is rather than
    # replacing what the user said with an empty string.
    return text
