"""
Interactive 3D — generates a 3D model (GLB).

INPUT (JSON) — what this engine receives:
{
    "shape": "sphere",              // cube | sphere
    "params": {"radius": 1.0},      // shape-specific
    "output_path": "model.glb"      // optional
}

OUTPUT (JSON) — what this engine returns:
{
    "model": "<path to generated glb file>",
    "format": "glb"
}

Status: deferred / optional

HONESTY NOTE / interpretation choice: the original skeleton's input
("model": "<geometry data>") doesn't specify a geometry format — there's no
established "geometry data" JSON convention to parse. This implementation
instead supports a small set of basic parametric primitives (cube, sphere)
built directly as real, valid, loadable glTF/GLB geometry via pygltflib —
genuine 3D output for the achievable case, not an attempt at general mesh
import/generation from arbitrary "geometry data" (which was never a
concretely specified format to begin with).
"""
from __future__ import annotations

import struct
from typing import Any

import numpy as np
from pygltflib import (
    GLTF2, Scene, Node, Mesh, Primitive, Attributes,
    Buffer, BufferView, Accessor,
    ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER, FLOAT, UNSIGNED_INT, VEC3, SCALAR,
)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"shape": "cube" | "sphere", "params"?: dict, "output_path"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    shape: str = kwargs["shape"]
    params: dict = kwargs.get("params", {})
    output_path: str = kwargs.get("output_path", f"{shape}.glb")

    if shape == "cube":
        vertices, indices = _cube_geometry(params.get("size", 1.0))
    elif shape == "sphere":
        vertices, indices = _sphere_geometry(params.get("radius", 1.0), params.get("segments", 16))
    else:
        raise ValueError(f"unsupported shape: {shape!r} (only 'cube' and 'sphere' are implemented)")

    _write_glb(vertices, indices, output_path)
    return {"model": output_path, "format": "glb"}


# --- private helpers ---


def _cube_geometry(size: float) -> tuple[np.ndarray, np.ndarray]:
    h = size / 2
    vertices = np.array(
        [
            [-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h],
            [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h],
        ],
        dtype=np.float32,
    )
    indices = np.array(
        [
            0, 1, 2, 0, 2, 3,  # back
            4, 6, 5, 4, 7, 6,  # front
            0, 4, 5, 0, 5, 1,  # bottom
            3, 2, 6, 3, 6, 7,  # top
            0, 3, 7, 0, 7, 4,  # left
            1, 5, 6, 1, 6, 2,  # right
        ],
        dtype=np.uint32,
    )
    return vertices, indices


def _sphere_geometry(radius: float, segments: int) -> tuple[np.ndarray, np.ndarray]:
    """Standard UV-sphere: rings of latitude x segments of longitude."""
    vertices = []
    for lat in range(segments + 1):
        theta = lat * np.pi / segments
        for lon in range(segments + 1):
            phi = lon * 2 * np.pi / segments
            x = radius * np.sin(theta) * np.cos(phi)
            y = radius * np.cos(theta)
            z = radius * np.sin(theta) * np.sin(phi)
            vertices.append([x, y, z])
    vertices = np.array(vertices, dtype=np.float32)

    indices = []
    for lat in range(segments):
        for lon in range(segments):
            a = lat * (segments + 1) + lon
            b = a + segments + 1
            indices.extend([a, b, a + 1, b, b + 1, a + 1])
    indices = np.array(indices, dtype=np.uint32)

    return vertices, indices


def _write_glb(vertices: np.ndarray, indices: np.ndarray, output_path: str) -> None:
    vertex_bytes = vertices.tobytes()
    index_bytes = indices.tobytes()
    # glTF requires each bufferView to start at a 4-byte-aligned offset
    padding = b"\x00" * ((4 - len(vertex_bytes) % 4) % 4)
    binary_blob = vertex_bytes + padding + index_bytes

    gltf = GLTF2(
        scene=0,
        scenes=[Scene(nodes=[0])],
        nodes=[Node(mesh=0)],
        meshes=[Mesh(primitives=[Primitive(attributes=Attributes(POSITION=0), indices=1)])],
        accessors=[
            Accessor(
                bufferView=0, componentType=FLOAT, count=len(vertices), type=VEC3,
                min=vertices.min(axis=0).tolist(), max=vertices.max(axis=0).tolist(),
            ),
            Accessor(bufferView=1, componentType=UNSIGNED_INT, count=len(indices), type=SCALAR),
        ],
        bufferViews=[
            BufferView(buffer=0, byteOffset=0, byteLength=len(vertex_bytes), target=ARRAY_BUFFER),
            BufferView(
                buffer=0, byteOffset=len(vertex_bytes) + len(padding), byteLength=len(index_bytes),
                target=ELEMENT_ARRAY_BUFFER,
            ),
        ],
        buffers=[Buffer(byteLength=len(binary_blob))],
    )
    gltf.set_binary_blob(binary_blob)
    gltf.save_binary(output_path)


if __name__ == "__main__":
    import asyncio
    from pathlib import Path

    async def demo() -> None:
        for shape, params in [("cube", {"size": 2.0}), ("sphere", {"radius": 1.5, "segments": 16})]:
            result = await run(shape=shape, params=params, output_path=f"scratch_3d_{shape}.glb")
            path = Path(result["model"])
            print(result, "exists:", path.exists(), "size:", path.stat().st_size if path.exists() else 0)
            path.unlink(missing_ok=True)

    asyncio.run(demo())
