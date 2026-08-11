#!/bin/bash
# ----------------------------------------------------------------------
# FPP benchmark protocol runner (see REPORT.md §3)
#
#   usage: run-bench.sh <phase-name> <native-bin-dir>
#
# Measures with hyperfine (>=3 warmup, >=20 runs, full distribution exported):
#   1. fpp-depend  over the full model      (verbatim F' command, Ref/Top)
#   2. fpp-to-cpp  over the full model      (verbatim F' command, Ref/Top)
#   3. fpp-check   on a single small file   (per-invocation startup cost)
#   4. cold `fprime-util generate`          (purged build cache every run)
#
# The phase's native bin dir goes FIRST on PATH so it shadows the pip-installed
# fprime-fpp shims in the venv (acceptance criterion §4).
# ----------------------------------------------------------------------
set -u

PHASE="${1:?usage: run-bench.sh <phase-name> <native-bin-dir>}"
BIN="$(cd "${2:?usage: run-bench.sh <phase-name> <native-bin-dir>}" && pwd)"

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$BENCH_DIR/corpus"
WORK="/home/user/benchwork/$PHASE"

TC=/home/user/toolchains
export PATH="$BIN:$TC/hyperfine-v1.19.0-x86_64-unknown-linux-musl:/home/user/.venv/bin:$PATH"

FPRIME=/home/user/fprime
PROJECT="$FPRIME/TestDeploymentsProject"
DEPLOY="$PROJECT/Ref"
BUILD="$PROJECT/build-fprime-automatic-native"

# Protocol minimum is 3 warmup / 20 runs. The fpp tool measurements use 100 runs
# because this host has a heavy right tail (see OBSTACLES.md O-9) and a 20-run
# median is too coarse to separate the deltas we care about. `generate` stays at
# 20 (protocol minimum) because each run costs ~13 s.
WARMUP="${WARMUP:-3}"
RUNS="${RUNS:-100}"
GEN_RUNS="${GEN_RUNS:-20}"
GEN_WARMUP="${GEN_WARMUP:-3}"

for f in "$CORPUS/cmd-depend.txt" "$CORPUS/cmd-to-cpp.txt" "$CORPUS/small.fpp"; do
  test -f "$f" || { echo "[ERROR] missing $f — run prep-corpus.sh first"; exit 1; }
done

echo "=== phase=$PHASE bin=$BIN ==="
command -v fpp-check | grep -q "^$BIN/" || { echo "[ERROR] PATH shadowing failed: $(command -v fpp-check)"; exit 1; }
echo "fpp-check -> $(command -v fpp-check)"
fpp-check --help 2>&1 | head -1

rm -rf "$WORK"; mkdir -p "$WORK/depend" "$WORK/tocpp"

# The corpus references locs.fpp and generated config .fpp files in the build
# tree by path, so the build cache must exist before measuring. Unmeasured.
echo "=== priming build cache (not measured) ==="
( cd "$DEPLOY" && rm -rf "$BUILD" "$PROJECT/build-artifacts" \
  && fprime-util generate -f -DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON >/dev/null 2>&1 ) \
  || { echo "[ERROR] priming generate failed"; exit 1; }

subst() { sed -e "s;@TOOL@;$BIN;g" -e "s;@WORK@;$WORK;g" "$1"; }
CMD_DEPEND="$(subst "$CORPUS/cmd-depend.txt")"
CMD_TOCPP="$(subst "$CORPUS/cmd-to-cpp.txt")"

# sanity: each command must actually succeed once before we time it
echo "=== sanity run ==="
eval "$CMD_DEPEND" > "$WORK/depend-stdout.txt" || { echo "[ERROR] fpp-depend failed"; exit 1; }
eval "$CMD_TOCPP" || { echo "[ERROR] fpp-to-cpp failed"; exit 1; }
echo "fpp-to-cpp produced $(find "$WORK/tocpp" -type f | wc -l) files"

# ---------------------------------------------------------------- 1. depend
hyperfine --warmup "$WARMUP" --runs "$RUNS" \
  --command-name "fpp-depend" \
  --prepare "rm -rf $WORK/depend && mkdir -p $WORK/depend" \
  --export-json "$BENCH_DIR/results/$PHASE-depend.json" \
  "$CMD_DEPEND > $WORK/depend-stdout.txt" || exit 1

# ---------------------------------------------------------------- 2. to-cpp
hyperfine --warmup "$WARMUP" --runs "$RUNS" \
  --command-name "fpp-to-cpp" \
  --prepare "rm -rf $WORK/tocpp && mkdir -p $WORK/tocpp" \
  --export-json "$BENCH_DIR/results/$PHASE-to-cpp.json" \
  "$CMD_TOCPP" || exit 1

# ---------------------------------------------------------------- 3. startup
# --shell=none here: this measurement IS the per-invocation startup cost, and a
# shell spawn (~2 ms) would be a material fraction of it. The other measurements
# keep the shell because they need redirection/prepare and are ~1 s, where the
# same overhead is noise.
hyperfine --warmup "$WARMUP" --runs "$RUNS" --shell=none \
  --command-name "fpp-check-small" \
  --export-json "$BENCH_DIR/results/$PHASE-check-small.json" \
  "$BIN/fpp-check $CORPUS/small.fpp" || exit 1

# ---------------------------------------------------------------- 4. generate
if [ "${SKIP_GENERATE:-0}" != "1" ]; then
  hyperfine --warmup "$GEN_WARMUP" --runs "$GEN_RUNS" \
    --command-name "fprime-util-generate-cold" \
    --prepare "rm -rf $BUILD $PROJECT/build-artifacts" \
    --export-json "$BENCH_DIR/results/$PHASE-generate.json" \
    "cd $DEPLOY && fprime-util generate -f -DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON" || exit 1
fi

echo "=== phase $PHASE complete ==="
