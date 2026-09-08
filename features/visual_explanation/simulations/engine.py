"""
Simulations — interactive simulations (physics, engineering, chemistry,
mechanics, thermo, fluids, circuits, electronics, structural, stats, economics).

INPUT (JSON) — what this engine receives:
{
    "domain": "physics",
    "type": "projectile",
    "parameters": {"velocity": 20, "angle": 45, "gravity": 9.81}
}

OUTPUT (JSON) — what this engine returns:
{
    "simulation": {
        "domain": "physics",
        "state": {"t": [0.0, 0.1, ...], "x": [0.0, 1.4, ...], "y": [0.0, 1.3, ...]},
        "summary": {"range": 40.77, "max_height": 10.19, "time_of_flight": 2.88}
    }
}

Status: deferred / optional

HONESTY NOTE ON SCOPE: the original feature description claims coverage of
"physics, engineering, math, chemistry, mechanics, thermo, fluids,
circuits, electronics, structural, stats, economics" — that breadth is not
attempted; it would mean a different real numerical model per domain
(dozens of them). This implements exactly ONE real, physically-correct
simulation — projectile motion under gravity (`domain: "physics"`,
`type: "projectile"`) — as a genuine, testable proof-of-concept, not a
token stub. Any other domain/type combination raises `ValueError` naming
what's actually supported, rather than returning fabricated "simulation"
data for a domain nothing here actually models.
"""
from __future__ import annotations

import math
from typing import Any


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"domain": str, "type": str, "parameters": dict}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    domain: str = kwargs["domain"]
    sim_type: str = kwargs["type"]
    parameters: dict = kwargs["parameters"]

    if domain == "physics" and sim_type == "projectile":
        return _projectile_motion(parameters)

    raise ValueError(
        f"unsupported domain/type: {domain!r}/{sim_type!r}, only "
        "domain='physics', type='projectile' is implemented"
    )


# --- private helpers ---


def _projectile_motion(parameters: dict) -> dict:
    velocity: float = parameters["velocity"]
    angle_deg: float = parameters["angle"]
    gravity: float = parameters.get("gravity", 9.81)

    angle_rad = math.radians(angle_deg)
    vx = velocity * math.cos(angle_rad)
    vy = velocity * math.sin(angle_rad)

    time_of_flight = 2 * vy / gravity
    max_height = (vy**2) / (2 * gravity)
    horizontal_range = (velocity**2) * math.sin(2 * angle_rad) / gravity

    num_points = 100
    t_values, x_values, y_values = [], [], []
    for i in range(num_points + 1):
        t = time_of_flight * i / num_points
        t_values.append(t)
        x_values.append(vx * t)
        y_values.append(max(0.0, vy * t - 0.5 * gravity * t**2))

    return {
        "simulation": {
            "domain": "physics",
            "state": {"t": t_values, "x": x_values, "y": y_values},
            "summary": {"range": horizontal_range, "max_height": max_height, "time_of_flight": time_of_flight},
        }
    }


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        result = await run(domain="physics", type="projectile", parameters={"velocity": 20, "angle": 45})
        summary = result["simulation"]["summary"]
        print(f"range={summary['range']:.2f}m max_height={summary['max_height']:.2f}m time_of_flight={summary['time_of_flight']:.2f}s")
        print(f"points generated: {len(result['simulation']['state']['t'])}")

        try:
            await run(domain="chemistry", type="reaction", parameters={})
        except ValueError as e:
            print(f"unsupported domain correctly rejected: {e}")

    asyncio.run(demo())
