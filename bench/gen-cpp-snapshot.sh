#!/bin/bash
# ----------------------------------------------------------------------
# Snapshot ALL C++ that fpp-to-cpp generates for the Ref project, for the
# acceptance diff (§4.3).
#
#   usage: gen-cpp-snapshot.sh <phase-name> <native-bin-dir>
#
# Rather than run a full `fprime-util build` (which compiles all of F' and takes
# far longer), this replays every fpp-to-cpp command the generated build emits
# — 145 of them, covering every module, not just the topology. That is exactly
# the set of C++ the autocoder would produce during a build, so it is the right
# artifact to diff between toolchains.
#
# Output: /home/user/cppsnap/<phase>/  (paths made relative + build-dir
# references normalised so two phases are directly comparable)
# ----------------------------------------------------------------------
set -eu

PHASE="${1:?usage: gen-cpp-snapshot.sh <phase> <native-bin-dir>}"
BIN="$(cd "${2:?usage: gen-cpp-snapshot.sh <phase> <native-bin-dir>}" && pwd)"

export PATH="$BIN:/home/user/.venv/bin:$PATH"
FPRIME=/home/user/fprime
PROJECT="$FPRIME/TestDeploymentsProject"
DEPLOY="$PROJECT/Ref"
BUILD="$PROJECT/build-fprime-automatic-native"
OUT="/home/user/cppsnap/$PHASE"

command -v fpp-to-cpp | grep -q "^$BIN/" || { echo "[ERROR] PATH shadowing failed"; exit 1; }

echo "=== priming build cache ==="
( cd "$DEPLOY" && rm -rf "$BUILD" "$PROJECT/build-artifacts" \
  && fprime-util generate -f -DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON >/dev/null 2>&1 )

rm -rf "$OUT"; mkdir -p "$OUT"

echo "=== replaying every fpp-to-cpp command into $OUT ==="
python3 - "$BUILD" "$BIN" "$OUT" <<'PY'
import re, shlex, subprocess, sys, pathlib, os

build, binp, out = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(build, "build.ninja").read_text()

cmds, seen = [], set()
for m in re.finditer(re.escape(binp + "/fpp-to-cpp") + r"(.*)", text):
    line = (binp + "/fpp-to-cpp" + m.group(1)).split(" && ")[0]
    if line in seen:
        continue
    seen.add(line)
    cmds.append(shlex.split(line))

print(f"{len(cmds)} fpp-to-cpp invocations")
fail = 0
for i, cmd in enumerate(cmds):
    d = cmd.index("-d")
    # redirect each module's output under the snapshot dir, preserving the
    # module path so phases line up file-for-file
    rel = os.path.relpath(cmd[d + 1], build)
    dest = pathlib.Path(out, rel)
    dest.mkdir(parents=True, exist_ok=True)
    cmd[d + 1] = str(dest)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fail += 1
        print(f"[FAIL {r.returncode}] {rel}: {r.stderr.strip()[:200]}")
print(f"done: {len(cmds)-fail} ok, {fail} failed")
sys.exit(1 if fail else 0)
PY

# The generated C++ embeds absolute paths and the author name; normalise so the
# diff shows real codegen differences rather than environment noise.
find "$OUT" -type f \( -name '*.cpp' -o -name '*.hpp' \) -print0 \
  | xargs -0 sed -i \
      -e "s;$FPRIME;[FPRIME];g" \
      -e 's;^// \\author .*;// \\author [user];'

echo "=== snapshot: $(find "$OUT" -type f | wc -l) files, $(du -sh "$OUT" | cut -f1) ==="
