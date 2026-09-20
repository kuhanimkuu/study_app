"""
Hosted-tier pricing — provider cost + markup + infra surcharge, tracked as
three separate, auditable line items (not blended into one opaque number)
per the user's explicit instruction that Study OS's own server/hosting
cost must be visible and independently adjustable alongside the provider's
raw usage cost, not folded silently into the markup.

Provider prices are USD per 1,000,000 tokens, input and output priced
separately (the standard shape every provider's own pricing page uses).
Sourced from each provider's public pricing page — provider pricing
changes over time, so this table is a real, named staleness risk:
re-check against the provider's current pricing page before relying on it
for real billing, don't assume it's still current.
Last checked: 2026-09-20.

Deliberately scoped to exactly the three models
features/model_router/engine.py's DEFAULT_MODEL_NAMES uses — the hosted
tier does not let a caller pick an arbitrary model/override (see
core/model_config.py's resolve_model_config_async), so every hosted-tier
generation is guaranteed to hit a known price, never the "unpriced model"
gap this file's ValueError below guards against.
"""
from __future__ import annotations

from ...core.config import get_settings

# USD per 1,000,000 tokens: (input_price, output_price)
_PROVIDER_PRICES_USD_PER_MILLION: dict[str, dict[str, tuple[float, float]]] = {
    "anthropic": {
        "claude-sonnet-5": (3.00, 15.00),
    },
    "openai": {
        "gpt-4o-mini": (0.15, 0.60),
    },
    "deepseek": {
        "deepseek-chat": (0.27, 1.10),
    },
}


def _round_cents(usd: float) -> int:
    # Round-half-up rather than truncate — a real nonzero cost should never
    # round down to a free 0-cent charge.
    return int(usd * 100 + 0.5)


def _apply_percent(cents: int, percent: float) -> int:
    return int(cents * percent / 100 + 0.5)


def provider_cost_cents(provider: str, model_name: str, input_tokens: int, output_tokens: int) -> int:
    try:
        input_price, output_price = _PROVIDER_PRICES_USD_PER_MILLION[provider][model_name]
    except KeyError as exc:
        raise ValueError(
            f"no known price for provider={provider!r} model_name={model_name!r} — "
            "add it to _PROVIDER_PRICES_USD_PER_MILLION before offering it on the "
            "hosted tier (silently charging $0 for a real provider call is not safe)"
        ) from exc
    usd = (input_tokens * input_price + output_tokens * output_price) / 1_000_000
    return _round_cents(usd)


def compute_charge(provider: str, model_name: str, input_tokens: int, output_tokens: int) -> dict:
    """The amount actually debited from a user's wallet for one hosted-tier
    generation. markup/infra percentages come from Settings (server/core/
    config.py) so they're adjustable without a code change."""
    settings = get_settings()
    base = provider_cost_cents(provider, model_name, input_tokens, output_tokens)
    markup = _apply_percent(base, settings.hosted_markup_percent)
    infra = _apply_percent(base, settings.hosted_infra_surcharge_percent)
    return {
        "provider_cost_cents": base,
        "markup_cents": markup,
        "infra_surcharge_cents": infra,
        "total_cents": base + markup + infra,
    }
