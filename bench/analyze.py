#!/usr/bin/env python3
"""
Turn hyperfine JSON exports into the REPORT.md table (§3).

Reports median and p95 (not means) plus the full distribution summary, because
the benchmark host is a shared cloud VM with a high noise floor — see
OBSTACLES.md O-9.

usage: analyze.py <results-dir> [baseline-phase]
"""
import json, sys, pathlib, statistics

RESULTS = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "results")
BASE = sys.argv[2] if len(sys.argv) > 2 else "baseline"

TOOLS = [
    ("depend", "fpp-depend (full model)"),
    ("to-cpp", "fpp-to-cpp (full model)"),
    ("check-small", "fpp-check (single small file)"),
    ("generate", "fprime-util generate (cold)"),
]

def pct(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)

def load(phase, tool):
    f = RESULTS / f"{phase}-{tool}.json"
    if not f.exists():
        return None
    times = json.loads(f.read_text())["results"][0]["times"]
    return {
        "n": len(times),
        "median": statistics.median(times),
        "p95": pct(times, 0.95),
        "min": min(times),
        "max": max(times),
        "stdev": statistics.stdev(times) if len(times) > 1 else 0.0,
    }

phases = sorted({p.name.rsplit("-", 1)[0].replace("-check", "@check")
                 for p in RESULTS.glob("*.json")})
# recover phase names properly: filename is <phase>-<tool>.json
phases = []
for p in RESULTS.glob("*.json"):
    for key, _ in TOOLS:
        if p.name.endswith(f"-{key}.json"):
            ph = p.name[: -len(f"-{key}.json")]
            if ph not in phases:
                phases.append(ph)
order = [BASE] + [p for p in sorted(phases) if p != BASE]

def fmt(v):
    if v is None:
        return "—"
    return f"{v*1000:.1f} ms" if v < 1 else f"{v:.3f} s"

rows = []
for key, label in TOOLS:
    base = load(BASE, key)
    for ph in order:
        d = load(ph, key)
        if d is None:
            continue
        if ph == BASE or base is None:
            delta = "—" if ph == BASE else "n/a"
        else:
            change = (d["median"] - base["median"]) / base["median"] * 100
            delta = f"{change:+.1f}%"
        rows.append((label, ph, fmt(d["median"]), fmt(d["p95"]),
                     fmt(d["min"]), fmt(d["max"]),
                     f"{d['stdev']/d['median']*100:.0f}%", delta, d["n"]))

print("| Tool | Phase | Median | p95 | Min | Max | σ/median | Δ vs baseline | n |")
print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
prev = None
for r in rows:
    tool = r[0] if r[0] != prev else ""
    prev = r[0]
    print(f"| {tool} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | {r[7]} | {r[8]} |")
