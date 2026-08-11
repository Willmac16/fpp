#!/bin/bash
# ----------------------------------------------------------------------
# Build the benchmark corpus from a real F' build.
#
#   usage: prep-corpus.sh <native-bin-dir>
#
# Runs `fprime-util generate` against the Ref deployment and then harvests the
# *verbatim* fpp-depend and fpp-to-cpp command lines that the F' build emits for
# the deployment topology module (Ref/Top) — the largest single fpp invocation
# in the build. Using the build's own command lines means the benchmark measures
# what F' actually asks the tools to do, rather than a hand-rolled file list.
#
# Harvested commands are stored with two placeholders:
#   @TOOL@  -> replaced by the phase's native binary
#   @WORK@  -> replaced by a per-phase scratch output dir, so measured runs
#              never write into (or benefit from) the F' build cache
#
# Run ONCE, from the baseline phase. Every later phase reuses the result
# unchanged, which is what "same corpus every phase" requires.
#
# NOTE: locs.fpp uses paths relative to its own location in the build tree, so
# the corpus deliberately references it in place. run-bench.sh therefore
# regenerates the build cache before measuring.
# ----------------------------------------------------------------------
set -eu

BIN="$(cd "${1:?usage: prep-corpus.sh <native-bin-dir>}" && pwd)"
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$BENCH_DIR/corpus"

export PATH="$BIN:/home/user/.venv/bin:$PATH"

FPRIME=/home/user/fprime
PROJECT="$FPRIME/TestDeploymentsProject"
DEPLOY="$PROJECT/Ref"
BUILD="$PROJECT/build-fprime-automatic-native"

command -v fpp-depend | grep -q "^$BIN/" || { echo "[ERROR] PATH shadowing failed: $(command -v fpp-depend)"; exit 1; }

rm -rf "$CORPUS"; mkdir -p "$CORPUS"

echo "=== generating Ref build cache (source of the corpus) ==="
cd "$DEPLOY"
rm -rf "$BUILD" "$PROJECT/build-artifacts"
# FPRIME_SKIP_TOOLS_VERSION_CHECK: a source-built fpp reports a git SHA as its
# version, which can never equal the pinned fprime-fpp version. See OBSTACLES.md.
fprime-util generate -f -DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON 2>&1 | tail -5

echo "=== harvesting verbatim command lines for Ref/Top ==="
python3 - "$BUILD" "$CORPUS" "$BIN" <<'PY'
import re, sys, shlex, pathlib

build, corpus, binp = sys.argv[1], sys.argv[2], sys.argv[3]

def harvest(ninja, tool, must_contain):
    text = pathlib.Path(ninja).read_text()
    best = None
    for m in re.finditer(re.escape(binp + "/" + tool) + r"(.*)", text):
        line = (binp + "/" + tool + m.group(1))
        # ninja escapes '$' and wraps commands; cut at the first shell separator
        line = line.split(" && ")[0].split(" > ")[0]
        if must_contain in line:
            if best is None or len(line) > len(best):
                best = line
    if best is None:
        raise SystemExit(f"[ERROR] no {tool} command containing {must_contain} in {ninja}")
    return shlex.split(best)

# fpp-to-cpp for the topology module
tocpp = harvest(f"{build}/build.ninja", "fpp-to-cpp", "Ref/Top")
# redirect -d output into the scratch dir
i = tocpp.index("-d")
tocpp[i+1] = "@WORK@/tocpp"
tocpp[0] = "@TOOL@/fpp-to-cpp"

# fpp-depend for the topology module
dep = harvest(f"{build}/sub-build-info-cache/build.ninja", "fpp-depend", "Ref/Top")
for flag in ("-d", "-m", "-f", "-g", "-i", "-u"):
    j = dep.index(flag)
    dep[j+1] = "@WORK@/depend/" + pathlib.Path(dep[j+1]).name
dep[0] = "@TOOL@/fpp-depend"

for name, cmd in (("cmd-to-cpp.txt", tocpp), ("cmd-depend.txt", dep)):
    pathlib.Path(corpus, name).write_text(" ".join(shlex.quote(a) for a in cmd) + "\n")
    print(f"{name}: {len(cmd)} args")

# record corpus scale for the report
imports = [a for a in tocpp if "," in a and a.endswith(".fpp")]
n_imports = len(imports[0].split(",")) if imports else 0
srcs = [a for a in tocpp if a.endswith(".fpp") and "," not in a]
pathlib.Path(corpus, "scale.txt").write_text(
    f"topology module: Ref/Top\n"
    f"fpp-to-cpp sources: {len(srcs)}\n"
    f"fpp-to-cpp imports (-i): {n_imports}\n"
)
print(f"sources={len(srcs)} imports={n_imports}")
PY

# Small single file for the per-invocation startup measurement. Must be
# self-contained (fpp-check must succeed on it alone) or the measurement dies on
# the first warmup run. Fw/Com/Com.fpp is a real fprime model file, 11 lines.
cp "$FPRIME/Fw/Com/Com.fpp" "$CORPUS/small.fpp"
"$BIN/fpp-check" "$CORPUS/small.fpp" >/dev/null 2>&1 \
  || { echo "[ERROR] small.fpp is not self-contained; fpp-check fails on it"; exit 1; }

echo "=== corpus ==="
cat "$CORPUS/scale.txt"
echo "small.fpp: $(wc -l < "$CORPUS/small.fpp") lines"
echo "locs.fpp:  $(wc -l < "$BUILD/locs.fpp") locate directives (referenced in place)"
