#!/bin/bash
# ----------------------------------------------------------------------
# Whole fpp-side-of-a-build benchmark.
#
#   usage: run-workflow-bench.sh <phase-name> <native-bin-dir>
#
# The §3 protocol measures single invocations on the largest module. That is the
# worst individual call, but it is not what a developer waits for. Building Ref
# runs 307 fpp invocations:
#
#     1 x fpp-locate-defs   (builds locs.fpp)
#   151 x fpp-depend        (per-module dependency analysis, at generate time)
#   145 x fpp-to-cpp        (autocoding)
#    10 x fpp-to-dict       (dictionary generation, via fpp_to_dict_wrapper.py)
#
# and the total is dominated by per-invocation cost across many small modules
# rather than by the one big module. This replays all of them, in dependency
# order, as a single timed unit. No C++ is compiled and CMake is not re-run;
# this is the fpp side only.
#
# The build-cache prime is done once up front and is NOT measured.
#
# Note on repeat runs: the fpp tools have no incremental or caching mode — every
# invocation recomputes and rewrites its outputs unconditionally — so replaying
# in place does not let a later run benefit from an earlier one. The stable
# run-to-run distribution in the exported JSON is the check on that.
# ----------------------------------------------------------------------
set -eu

PHASE="${1:?usage: run-workflow-bench.sh <phase> <native-bin-dir>}"
BIN="$(cd "${2:?usage: run-workflow-bench.sh <phase> <native-bin-dir>}" && pwd)"

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="/home/user/benchwork/workflow-$PHASE"
TC=/home/user/toolchains
export PATH="$BIN:$TC/hyperfine-v1.19.0-x86_64-unknown-linux-musl:/home/user/.venv/bin:$PATH"

FPRIME=/home/user/fprime
PROJECT="$FPRIME/TestDeploymentsProject"
DEPLOY="$PROJECT/Ref"
BUILD="$PROJECT/build-fprime-automatic-native"

RUNS="${RUNS:-20}"
WARMUP="${WARMUP:-3}"

command -v fpp-to-cpp | grep -q "^$BIN/" || { echo "[ERROR] PATH shadowing failed"; exit 1; }

echo "=== priming build cache (not measured) ==="
( cd "$DEPLOY" && rm -rf "$BUILD" "$PROJECT/build-artifacts" \
  && fprime-util generate -f -DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON >/dev/null 2>&1 )
# fpp_to_dict_wrapper.py reads versions/version.json, which a CMake target emits
# at *build* time rather than at generate time. Produce it here so the dict step
# can run; it is a CMake artifact, not fpp work, so it stays out of the timing.
ninja -C "$BUILD" versions/version.json >/dev/null 2>&1 \
  || echo "[warn] could not pre-generate version.json; fpp-to-dict may fail"

rm -rf "$WORK"; mkdir -p "$WORK"
REPLAY="$WORK/replay.sh"

echo "=== emitting replay script ==="
python3 - "$BUILD" "$BIN" "$REPLAY" <<'PY'
import re, shlex, sys, pathlib

build, binp, out = sys.argv[1:4]
main = pathlib.Path(build, "build.ninja").read_text()
sub  = pathlib.Path(build, "sub-build-info-cache", "build.ninja").read_text()

def grab(text, tool):
    cmds, seen = [], set()
    pat = re.escape(binp + "/" + tool) + r"(?![a-z-])(.*)"
    for m in re.finditer(pat, text):
        line = (binp + "/" + tool + m.group(1)).split(" && ")[0]
        if line not in seen:
            seen.add(line)
            cmds.append(line)
    return cmds

# fpp-to-dict is invoked through a python wrapper; capture the whole wrapper
# command line, because that is what the build actually runs.
def grab_dict(text):
    cmds, seen = [], set()
    for m in re.finditer(r"\S*fpp_to_dict_wrapper\.py(.*)", text):
        line = ("python3 " + m.group(0)).split(" && ")[0]
        if line not in seen:
            seen.add(line)
            cmds.append(line)
    return cmds

# Dependency order: locs.fpp, then per-module depend, then autocode, then dicts.
groups = [
    ("fpp-locate-defs", grab(sub, "fpp-locate-defs")),
    ("fpp-depend",      grab(sub, "fpp-depend")),
    ("fpp-to-cpp",      grab(main, "fpp-to-cpp")),
    ("fpp-to-dict",     grab_dict(main)),
]

lines = ["#!/bin/sh", "set -e"]
total = 0
for name, cmds in groups:
    lines.append(f"# ---- {name} x {len(cmds)}")
    lines += cmds
    total += len(cmds)
    print(f"  {name:18} {len(cmds)}")
pathlib.Path(out).write_text("\n".join(lines) + "\n")
print(f"  {'TOTAL':18} {total}")
PY
chmod +x "$REPLAY"

echo "=== sanity sweep ==="
sh "$REPLAY" >/dev/null || { echo "[ERROR] replay failed"; exit 1; }
echo "replay OK"

mkdir -p "$BENCH_DIR/results"
hyperfine --warmup "$WARMUP" --runs "$RUNS" \
  --command-name "fpp-whole-build-workflow" \
  --export-json "$BENCH_DIR/results/$PHASE-workflow.json" \
  "sh $REPLAY"
