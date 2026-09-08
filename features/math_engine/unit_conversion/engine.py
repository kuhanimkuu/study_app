"""
Unit conversion — converts a value between units.

INPUT (JSON) — what this engine receives:
{
    "value": 100,
    "from_unit": "km",
    "to_unit": "miles"
}

OUTPUT (JSON) — what this engine returns:
{
    "value": 62.137,
    "from_unit": "km",
    "to_unit": "miles"
}

Status: later phase
Built on pint — a real, mature unit-conversion library (handles hundreds of
units, dimensional-analysis errors, temperature's affine offset, etc.), not
a hand-rolled conversion table.
"""
from __future__ import annotations

from typing import Any

import pint

_ureg = pint.UnitRegistry()


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"value": number, "from_unit": str, "to_unit": str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    value = kwargs["value"]
    from_unit: str = kwargs["from_unit"]
    to_unit: str = kwargs["to_unit"]

    quantity = _ureg.Quantity(value, from_unit)  # Quantity(), not value * ureg(unit) — the
    converted = quantity.to(to_unit)              # latter breaks on offset units like degF/degC

    return {"value": converted.magnitude, "from_unit": from_unit, "to_unit": to_unit}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        for value, frm, to in [
            (100, "km", "miles"),
            (32, "degF", "degC"),
            (1, "hour", "seconds"),
            (5, "kg", "lb"),
        ]:
            result = await run(value=value, from_unit=frm, to_unit=to)
            print(f"{value} {frm} = {result['value']:.4g} {to}")

    asyncio.run(demo())
