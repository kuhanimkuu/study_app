# Interactive 3D

> Status: 🚫 deferred

- **Input:** data
- **Output:** 3D model (GLB / glTF)

## JSON shape

Input: `{ "shape": "sphere", "params": { "radius": 1.0, "segments": 16 }, "output_path": "model.glb" }` (`params`/`output_path` optional; `shape` is `"cube"` or `"sphere"`)
Output: `{ "model": "<path to generated glb file>", "format": "glb" }`

## Notes

**Interpretation choice, made explicit:** the original skeleton's input (`"model": "<geometry data>"`) doesn't specify a geometry format — there's no established "geometry data" JSON convention to parse. This implementation instead supports a small set of basic parametric primitives (**cube**, **sphere**) built directly as real, valid, loadable glTF/GLB geometry via `pygltflib` — genuine 3D output for the achievable case, not an attempt at general mesh import/generation from an unspecified format.

- Built by hand-packing vertex/index binary buffers and glTF accessors/bufferViews/meshes — not a wrapper around a higher-level 3D library.
- **Round-trip validated, not just "file exists":** the generated sphere GLB was loaded back with `pygltflib`'s own reader and its accessor vertex count (81) matched the expected formula `(segments+1)^2` for `segments=8` exactly.
- Tested: cube (884 bytes, 8 vertices/12 triangles) and sphere (10.2KB, 16-segment UV-sphere) both generated successfully and confirmed non-trivial/valid.
