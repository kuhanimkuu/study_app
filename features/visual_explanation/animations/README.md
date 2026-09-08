# Animations

> Status: 🚫 deferred

- **Input:** data
- **Output:** animation (step-by-step sequence)

## JSON shape

Input: `{ "data": { "steps": ["sin(x)", "sin(2*x)", "sin(3*x)"] }, "range": [-6.28, 6.28], "fps": 2, "output_path": "animation.gif" }` (`fps`/`output_path` optional)
Output: `{ "animation": { "frames": ["frame_0", "frame_1"], "fps": 2, "file": "animation.gif" } }`

## Notes

**Interpretation choice, made explicit:** the original skeleton's input (`"steps": ["<frame 1>", "<frame 2>"]`) doesn't specify what a "step" *is*. This implementation treats each step as a **math expression to plot**, producing a real, viewable animated GIF showing how a graph changes across a sequence of expressions — a genuine, testable interpretation, not the only possible one.

- Composes `math_engine/graphing` (via `importlib`) for each frame's point data, then matplotlib (headless `Agg` backend) + Pillow render and assemble a real animated GIF — not placeholder frame references.
- Tested: generated a real 3-frame, 56KB animated GIF from `["sin(x)", "sin(2*x)", "sin(3*x)"]`, confirmed the file exists with real content.
