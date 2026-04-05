#!/usr/bin/env python3
"""Classify LOS/NLOS for Track23 scenarios from JSON and export CSV.

Rules
-----
1) geometric_class:
   - LOS: direct Tx->Rx segment does not intersect any object AABB.
   - NLOS: intersects one or more objects.

2) material_class (6.5 GHz simple penetration rule):
   - If any hit material is metal/concrete -> NLOS (hard blocker).
   - Else compute penetration loss = sum(alpha_db_per_m[material] * inside_length_m).
   - LOS if loss <= threshold_db (default 3.0 dB), otherwise NLOS.
"""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# 6.5 GHz reference values from current project baseline discussions.
ALPHA_DB_PER_M: Dict[str, float] = {
    "concrete": 142.0,
    "glass": 28.0,
    "wood": 41.0,
    "metal": 1.0e6,  # treat as effectively opaque
}

HARD_BLOCK_MATERIALS = {"metal", "concrete"}
PENETRATION_THRESHOLD_DB = 3.0


@dataclass
class HitInfo:
    name: str
    material: str
    inside_length_m: float


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def segment_box_inside_length(p0: Tuple[float, float, float],
                              p1: Tuple[float, float, float],
                              bmin: Tuple[float, float, float],
                              bmax: Tuple[float, float, float],
                              eps: float = 1e-12) -> float:
    """Return segment length inside an AABB (axis-aligned box)."""
    d = [p1[i] - p0[i] for i in range(3)]
    tmin = 0.0
    tmax = 1.0

    for i in range(3):
        if abs(d[i]) < eps:
            if p0[i] < bmin[i] or p0[i] > bmax[i]:
                return 0.0
            continue

        inv_d = 1.0 / d[i]
        t1 = (bmin[i] - p0[i]) * inv_d
        t2 = (bmax[i] - p0[i]) * inv_d
        if t1 > t2:
            t1, t2 = t2, t1

        tmin = max(tmin, t1)
        tmax = min(tmax, t2)
        if tmin > tmax:
            return 0.0

    seg_len = ((d[0] ** 2) + (d[1] ** 2) + (d[2] ** 2)) ** 0.5
    inside = max(0.0, tmax - tmin) * seg_len
    return inside


def classify_point(tx: Tuple[float, float, float],
                   rx: Tuple[float, float, float],
                   objects: List[dict]) -> Tuple[str, str, float, List[HitInfo], str]:
    hits: List[HitInfo] = []

    for obj in objects:
        origin = obj["origin"]
        size = obj["size"]
        bmin = (float(origin[0]), float(origin[1]), float(origin[2]))
        bmax = (
            float(origin[0]) + float(size[0]),
            float(origin[1]) + float(size[1]),
            float(origin[2]) + float(size[2]),
        )
        inside_len = segment_box_inside_length(tx, rx, bmin, bmax)
        if inside_len > 1e-9:
            hits.append(
                HitInfo(
                    name=str(obj.get("name", "")),
                    material=str(obj.get("material", "unknown")).lower(),
                    inside_length_m=inside_len,
                )
            )

    geometric_class = "NLOS" if hits else "LOS"

    hard_block = any(h.material in HARD_BLOCK_MATERIALS for h in hits)
    total_loss = 0.0
    for h in hits:
        alpha = ALPHA_DB_PER_M.get(h.material, 0.0)
        total_loss += alpha * h.inside_length_m

    if hard_block:
        material_class = "NLOS"
        reason = "hard_block_material"
    else:
        material_class = "LOS" if total_loss <= PENETRATION_THRESHOLD_DB else "NLOS"
        reason = "penetration_threshold"

    return geometric_class, material_class, total_loss, hits, reason


def scenario_to_rows(scene: dict, src_json: Path) -> List[dict]:
    scenario_id = str(scene.get("id", "")).upper()
    tx = tuple(float(v) for v in scene["tx"]["pos"])
    points = scene["rx"]["points"]
    objects = scene.get("objects", [])

    rows: List[dict] = []
    for idx, p in enumerate(points, start=1):
        rx = (float(p[0]), float(p[1]), float(p[2]))
        gcls, mcls, loss_db, hits, reason = classify_point(tx, rx, objects)

        hit_objects = ";".join(h.name for h in hits)
        hit_materials = ";".join(h.material for h in hits)
        hit_inside_lengths_m = ";".join(f"{h.inside_length_m:.4f}" for h in hits)

        rows.append(
            {
                "scenario": scenario_id,
                "source_json": src_json.name,
                "rx_index": idx,
                "tag_id": f"T{idx}",
                "x_m": f"{rx[0]:.3f}",
                "y_m": f"{rx[1]:.3f}",
                "z_m": f"{rx[2]:.3f}",
                "geometric_class": gcls,
                "material_class": mcls,
                "penetration_loss_db": f"{loss_db:.3f}",
                "criterion": reason,
                "num_hits": len(hits),
                "hit_objects": hit_objects,
                "hit_materials": hit_materials,
                "inside_lengths_m": hit_inside_lengths_m,
            }
        )
    return rows


def write_csv(path: Path, rows: List[dict]) -> None:
    if not rows:
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)


def main() -> None:
    base_dir = Path(__file__).resolve().parent
    json_paths = [
        base_dir / "track23_scenario_a.json",
        base_dir / "track23_scenario_b.json",
        base_dir / "track23_scenario_c.json",
    ]

    all_rows: List[dict] = []
    for jp in json_paths:
        scene = load_json(jp)
        rows = scenario_to_rows(scene, jp)
        all_rows.extend(rows)

        out_csv = base_dir / f"{jp.stem}_los_nlos.csv"
        write_csv(out_csv, rows)

    combined_csv = base_dir / "track23_all_scenarios_los_nlos.csv"
    write_csv(combined_csv, all_rows)

    summary_lines = [
        "LOS/NLOS classification summary",
        f"threshold_db={PENETRATION_THRESHOLD_DB}",
        "alpha_db_per_m=" + json.dumps(ALPHA_DB_PER_M, ensure_ascii=False),
    ]
    for scenario in ("A", "B", "C"):
        rows = [r for r in all_rows if r["scenario"] == scenario]
        g_los = sum(1 for r in rows if r["geometric_class"] == "LOS")
        g_nlos = sum(1 for r in rows if r["geometric_class"] == "NLOS")
        m_los = sum(1 for r in rows if r["material_class"] == "LOS")
        m_nlos = sum(1 for r in rows if r["material_class"] == "NLOS")
        summary_lines.append(
            f"Scenario {scenario}: geometric LOS={g_los}, geometric NLOS={g_nlos}, material LOS={m_los}, material NLOS={m_nlos}"
        )

    (base_dir / "los_nlos_summary.txt").write_text("\n".join(summary_lines), encoding="utf-8")
    print("Done. CSV files and summary were created in:")
    print(str(base_dir))


if __name__ == "__main__":
    main()
