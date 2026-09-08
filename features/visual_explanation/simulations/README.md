# Simulations

> Status: 🚫 deferred

- **Input:** parameters
- **Output:** interactive simulation (physics, engineering, math, chemistry, mechanics, thermo, fluids, circuits, electronics, structural, stats, economics)

## JSON shape

Input: `{ "domain": "physics", "type": "projectile", "parameters": { "velocity": 20, "angle": 45, "gravity": 9.81 } }` (`gravity` optional, default 9.81)
Output: `{ "simulation": { "domain": "physics", "state": { "t": [...], "x": [...], "y": [...] }, "summary": { "range": 40.77, "max_height": 10.19, "time_of_flight": 2.88 } } }`

## Notes

**Honesty note on scope:** the original feature description claims coverage of physics, engineering, math, chemistry, mechanics, thermo, fluids, circuits, electronics, structural, stats, and economics simulations — that breadth is **not attempted**; it would mean a different real numerical model per domain, dozens of them. This implements exactly **one** real, physically-correct simulation as a genuine proof-of-concept: projectile motion under gravity (`domain: "physics"`, `type: "projectile"`) — real kinematics (`x(t) = v·cos(θ)·t`, `y(t) = v·sin(θ)·t - ½gt²`), not a placeholder. Any other domain/type combination raises `ValueError` naming what's actually supported, rather than returning fabricated simulation data for a domain nothing here models.

- Tested against exact analytic projectile-motion formulas for `v=20, angle=45°, g=9.81`: `range=40.77m`, `max_height=10.19m`, `time_of_flight=2.88s` — all matched precisely. Unsupported domain/type correctly rejected with a clear error rather than silently returning something.
