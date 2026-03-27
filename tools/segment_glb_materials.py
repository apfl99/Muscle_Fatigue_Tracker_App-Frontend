#!/usr/bin/env python3
"""
Create a multi-material variant of our GLB for model-viewer tinting.

Why:
- Current GLB ships with a single unnamed material for all meshes.
- model-viewer scene-graph API exposes materials by name, so we need
  per-region materials to tint different body parts independently.

What this script does:
- Reads an input GLB (glTF JSON + BIN).
- Clones the base material into multiple named materials.
- Rewrites mesh primitive `material` indices by node/mesh name mapping.
- Writes out a new GLB with updated JSON chunk + original BIN chunk.

Note:
- This does NOT modify geometry buffers. Only JSON metadata changes.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


@dataclass(frozen=True)
class GlbChunks:
    json_bytes: bytes
    bin_bytes: Optional[bytes]


def _read_glb(path: str) -> GlbChunks:
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"Not a GLB file: magic={magic!r}")
    if version != 2:
        raise ValueError(f"Unsupported GLB version: {version}")
    if length != len(data):
        raise ValueError(f"GLB length mismatch: header={length} actual={len(data)}")

    offset = 12
    json_chunk = None
    bin_chunk = None
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_len]
        offset += chunk_len
        if chunk_type == b"JSON":
            json_chunk = chunk
        elif chunk_type == b"BIN\x00":
            bin_chunk = chunk

    if json_chunk is None:
        raise ValueError("Missing JSON chunk")
    return GlbChunks(json_bytes=json_chunk, bin_bytes=bin_chunk)


def _pad4(b: bytes) -> bytes:
    pad = (4 - (len(b) % 4)) % 4
    return b + (b" " * pad)


def _write_glb(path: str, json_bytes: bytes, bin_bytes: Optional[bytes]) -> None:
    json_bytes = _pad4(json_bytes)
    chunks = []
    chunks.append(struct.pack("<I4s", len(json_bytes), b"JSON") + json_bytes)
    if bin_bytes is not None:
        bin_bytes = _pad4(bin_bytes)
        chunks.append(struct.pack("<I4s", len(bin_bytes), b"BIN\x00") + bin_bytes)
    body = b"".join(chunks)
    header = struct.pack("<4sII", b"glTF", 2, 12 + len(body))
    with open(path, "wb") as f:
        f.write(header)
        f.write(body)


def _material_name_for_muscle(muscle_code: str) -> str:
    return {
        "chest": "Material_Chest",
        "quadriceps": "Material_Quads",
        "glutes": "Material_Glutes",
        "calves": "Material_Calves",
        "latissimus": "Material_Lats",
        "erector_spinae": "Material_LowerBack",
        "rectus_abdominis": "Material_Abs",
        "obliques": "Material_Obliques",
        "lateral_deltoid": "Material_Shoulders",
        "upper_arm_region": "Material_UpperArms",
        "forearm_region": "Material_Forearms",
        "trapezius": "Material_Neck",
    }.get(muscle_code, f"Material_{muscle_code}")


def _muscle_code_for_node_name(node_name: str) -> Optional[str]:
    n = (node_name or "").lower()
    if "chest" in n:
        return "chest"
    if "thigh" in n:
        return "quadriceps"
    if "butt" in n:
        return "glutes"
    if "fore_arms" in n or "fore arms" in n or "forearm" in n:
        return "forearm_region"
    if "leg" in n or "ankle" in n or "feet" in n:
        return "calves"
    if "upper_arms" in n or "upper arms" in n:
        return "upper_arm_region"
    if "shoulder" in n:
        return "lateral_deltoid"
    if "abdomen" in n:
        return "rectus_abdominis"
    if "lower_abdomen" in n or "lower abdomen" in n:
        return "obliques"
    if n.endswith("_back") or "back" in n:
        # Prefer to separate lower back if possible.
        if "lower_back" in n or "lower back" in n:
            return "erector_spinae"
        return "latissimus"
    if "neck" in n:
        return "trapezius"
    return None


def _build_muscle_materials(gltf: dict) -> Tuple[dict, Dict[str, int]]:
    materials = gltf.get("materials") or []
    if not materials:
        raise ValueError("GLTF has no materials; cannot clone base material")

    base_material = dict(materials[0])
    base_material["name"] = base_material.get("name") or "Material_Base"
    new_materials: List[dict] = [base_material]
    muscle_to_index: Dict[str, int] = {}

    # We may discover muscle codes via nodes. We create materials lazily later.
    gltf["materials"] = new_materials
    return gltf, muscle_to_index


def _ensure_material_for_muscle(gltf: dict, muscle_to_index: Dict[str, int], muscle_code: str) -> int:
    if muscle_code in muscle_to_index:
        return muscle_to_index[muscle_code]

    materials: List[dict] = gltf.get("materials") or []
    base = dict(materials[0])
    base["name"] = _material_name_for_muscle(muscle_code)
    materials.append(base)
    idx = len(materials) - 1
    muscle_to_index[muscle_code] = idx
    gltf["materials"] = materials
    return idx


def _rewrite_mesh_materials(gltf: dict) -> dict:
    nodes = gltf.get("nodes") or []
    meshes = gltf.get("meshes") or []

    gltf, muscle_to_index = _build_muscle_materials(gltf)

    # For each node with a mesh, decide muscle code then rewrite mesh primitives.
    for node in nodes:
        mesh_idx = node.get("mesh")
        if mesh_idx is None:
            continue
        if not (0 <= int(mesh_idx) < len(meshes)):
            continue
        muscle_code = _muscle_code_for_node_name(node.get("name") or "")
        if muscle_code is None:
            continue

        material_idx = _ensure_material_for_muscle(gltf, muscle_to_index, muscle_code)
        mesh = meshes[int(mesh_idx)]
        primitives = mesh.get("primitives") or []
        for prim in primitives:
            prim["material"] = material_idx

    gltf["meshes"] = meshes
    return gltf


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    chunks = _read_glb(args.input)
    json_text = chunks.json_bytes.decode("utf-8").rstrip("\x00")
    gltf = json.loads(json_text)

    gltf = _rewrite_mesh_materials(gltf)

    out_json = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    _write_glb(args.output, out_json, chunks.bin_bytes)

    # Basic reporting
    mats = gltf.get("materials") or []
    mat_names = [m.get("name") for m in mats]
    print(f"Wrote: {args.output}")
    print(f"materials={len(mats)} names={mat_names}")


if __name__ == "__main__":
    main()

