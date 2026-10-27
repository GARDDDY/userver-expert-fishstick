import glob
import os
import re
import statistics as st
import sys

ORDER = ["baseline_notrace", "baseline", "pch_onetarg", "pch_general"]
BASELINE = "baseline"

HEADER = [
    "variant", "runs", "wall, s: median (min-max)", "stdev", "vs baseline",
    "CBA frontend, s", "CBA backend, s", "compiled TUs", "compile steps, s", "link steps, s",
]


def cba_times(path):
    txt = open(path).read()
    fe = float(re.search(r"Parsing \(frontend\):\s+([\d.]+) s", txt).group(1))
    be = float(re.search(r"Codegen & opts \(backend\):\s+([\d.]+) s", txt).group(1))
    n = int(re.search(r"Compilation \((\d+) times\)", txt).group(1))
    return fe, be, n


def ninja_split(path):
    kinds = {"compile": 0.0, "link": 0.0, "other": 0.0}
    for line in open(path):
        if line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) < 4:
            continue
        dur = (int(f[1]) - int(f[0])) / 1000
        out = f[3]
        if out.endswith(".o") or out.endswith(".pch"):
            kinds["compile"] += dur
        elif out.endswith(".a") or re.fullmatch(r"bench_service\w*", out.strip()):
            kinds["link"] += dur
        else:
            kinds["other"] += dur
    return kinds


def fmt(v):
    return f"{st.median(v):.1f} ({min(v):.1f}-{max(v):.1f})"


def collect(res):
    data = []
    for variant in ORDER:
        d = os.path.join(res, variant)
        walls = [float(open(p).read()) for p in sorted(glob.glob(d + "/wall_*.txt"))]
        if not walls:
            continue
        data.append({
            "variant": variant,
            "walls": walls,
            "cbas": [cba_times(p) for p in sorted(glob.glob(d + "/cba_report_*.txt"))],
            "ninja": [ninja_split(p) for p in sorted(glob.glob(d + "/ninja_log_*.txt"))],
        })
    return data


def table_cells(row, base_wall):
    walls, cbas, nin = row["walls"], row["cbas"], row["ninja"]
    sd = st.stdev(walls) if len(walls) > 1 else 0.0
    rel = f"{(st.median(walls) / base_wall - 1) * 100:+.0f}%" if base_wall else "-"
    return [
        row["variant"],
        len(walls),
        fmt(walls),
        f"{sd:.2f}",
        rel,
        fmt([c[0] for c in cbas]) if cbas else "-",
        fmt([c[1] for c in cbas]) if cbas else "-",
        cbas[0][2] if cbas else "-",
        fmt([k["compile"] for k in nin]) if nin else "-",
        fmt([k["link"] for k in nin]) if nin else "-",
    ]


def render_table(data):
    base_wall = next((st.median(r["walls"]) for r in data if r["variant"] == BASELINE), None)
    lines = ["| " + " | ".join(HEADER) + " |", "|" + "---|" * len(HEADER)]
    for row in data:
        lines.append("| " + " | ".join(str(c) for c in table_cells(row, base_wall)) + " |")
    return "\n".join(lines)


def render_walls(data):
    lines = ["Per-run wall times, s:"]
    for row in data:
        lines.append(f"- {row['variant']}: " + ", ".join(f"{w:.1f}" for w in row["walls"]))
    return "\n".join(lines)


data = collect(sys.argv[1])
print(render_table(data))
print()
print(render_walls(data))
